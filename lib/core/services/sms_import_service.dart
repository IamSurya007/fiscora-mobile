import '../../features/accounts/models/account_model.dart';
import '../../features/categories/models/category.dart';
import '../../features/categories/services/category_resolver.dart';
import '../../features/categories/services/merchant_categorizer.dart';
import '../../features/expenses/models/expense_model.dart';
import '../repositories/i_account_repository.dart';
import '../repositories/i_expense_repository.dart';
import 'sms_account_resolver.dart';
import 'sms_dedup.dart';
import 'sms_parser_service.dart';

/// Turns parsed SMS into expenses. Shared by the inbox scan and live
/// auto-capture so both use the same id, duplicate check and categorisation.
class SmsImportService {
  final IExpenseRepository _expenseRepo;
  final IAccountRepository _accountRepo;

  SmsImportService(this._expenseRepo, this._accountRepo);

  /// Drops SMS that are already stored (including ones the user deleted) and
  /// repeats within [txns].
  Future<List<ParsedSms>> filterNew(List<ParsedSms> txns) async {
    final existingIds = await _expenseRepo.getAllExpenseIds();
    final seen = <String>{};
    final result = <ParsedSms>[];
    for (final txn in txns) {
      final key = txn.dedupKey;
      if (!seen.add(key)) continue;
      if (await _isDuplicate(txn, existingIds)) continue;
      result.add(txn);
    }
    return result;
  }

  Future<bool> _isDuplicate(ParsedSms txn, Set<String> existingIds) async {
    if (existingIds.contains(txn.dedupKey) || existingIds.contains(txn.legacyKey)) {
      return true;
    }
    // Rows saved by older builds used an id derived from the (receive) time,
    // amount and merchant, which cannot be recomputed from the inbox exactly.
    // Treat a nearby row with the same amount as a duplicate only when its
    // id proves it came from that legacy SMS scheme; genuine repeat payments
    // (two ₹20 chais) have different v2 ids and are kept.
    final signed = txn.isDebit ? txn.amount : -txn.amount;
    final near = await _expenseRepo.findExpensesNear(amount: signed, date: txn.date);
    return near.any(_isLegacySmsRow);
  }

  static bool _isLegacySmsRow(Expense e) {
    final ms = e.date.millisecondsSinceEpoch;
    final amount = e.amount.abs();
    return e.id == SmsDedup.legacyKey(dateMs: ms, amount: amount, merchant: e.merchant) ||
        e.id == SmsDedup.legacyKeyWithPrefix('spendly', dateMs: ms, amount: amount, merchant: e.merchant);
  }

  /// Category for [txn]: the user's merchant rule, then the keyword table,
  /// then the default for debits/credits.
  Future<({CategorySelection selection, bool fromRule})> categorize(ParsedSms txn) async {
    final rule = await _expenseRepo.getMerchantRule(txn.merchant);
    if (rule != null) return (selection: rule, fromRule: true);
    final guessed = MerchantCategorizer.categorize(txn.merchant);
    return (
      selection: guessed ?? CategoryResolver.defaultFor(isCredit: !txn.isDebit),
      fromRule: false,
    );
  }

  /// Saves [txn] unless it is a duplicate. Returns the saved expense, or null.
  Future<Expense?> import(ParsedSms txn, {required String note}) async {
    final existingIds = await _expenseRepo.getAllExpenseIds();
    if (await _isDuplicate(txn, existingIds)) return null;

    final accountId = await SmsAccountResolver(_accountRepo).resolveAccountId(txn);
    final (:selection, :fromRule) = await categorize(txn);

    // A credit card bill payment shows up twice: a debit SMS from the bank and
    // a "payment received" SMS from the card. It is one transfer, not spend
    // plus income, so link the two instead of recording both.
    final cardPayment = await _matchCardPayment(txn, accountId);
    if (cardPayment.skip) return null;
    if (cardPayment.upgraded != null) return cardPayment.upgraded;
    final isCardPayment = cardPayment.toCardId != null || cardPayment.cardSide;

    final expense = Expense(
      id: txn.dedupKey,
      amount: txn.isDebit ? txn.amount : -txn.amount,
      category: '',
      categoryId: isCardPayment ? 'transfers' : selection.categoryId,
      subcategoryId: isCardPayment ? 'transfers.self' : selection.subcategoryId,
      transferAccountId: cardPayment.toCardId ?? '',
      isCountedAsSpend: !isCardPayment,
      note: note,
      date: txn.date,
      method: txn.accountType == AccountType.credit_card
          ? 'card'
          : (txn.accountType == AccountType.cash ? 'cash' : 'upi'),
      source: 'sms',
      merchant: txn.merchant,
      accountId: accountId,
      createdAt: DateTime.now(),
    );

    await _expenseRepo.addExpense(expense);
    return expense;
  }

  static final _cardPaymentWords = RegExp(
    r'\b(?:credit card|card bill|cc bill|cc payment|card payment|payment towards (?:your )?card)\b',
    caseSensitive: false,
  );
  static const _pairWindow = Duration(days: 5);

  /// Recognises both halves of a card bill payment (see [import]).
  Future<({bool skip, Expense? upgraded, String? toCardId, bool cardSide})> _matchCardPayment(
    ParsedSms txn,
    String accountId,
  ) async {
    const none = (skip: false, upgraded: null, toCardId: null, cardSide: false);
    final accounts = await _accountRepo.getAccounts();
    final cards = accounts.where((a) => a.isCreditCard).toList();
    if (cards.isEmpty) return none;

    final from = accounts.where((a) => a.id == accountId).firstOrNull;
    final isCardAccount = from?.isCreditCard ?? txn.accountType == AccountType.credit_card;

    // Card side: money received on the card account.
    if (!txn.isDebit && isCardAccount) {
      final near = await _expenseRepo.findExpensesNear(amount: txn.amount, date: txn.date, window: _pairWindow);
      final alreadyPaid = near.any((e) => e.transferAccountId == accountId);
      if (alreadyPaid) return (skip: true, upgraded: null, toCardId: null, cardSide: false);
      return (skip: false, upgraded: null, toCardId: null, cardSide: true);
    }

    // Bank side: a debit that mentions paying a card.
    if (!txn.isDebit || isCardAccount || !_cardPaymentWords.hasMatch(txn.body)) return none;
    final mentioned = cards.where((c) {
      final last4 = RegExp(r'(\d{4})').allMatches(c.name).map((m) => m.group(1)).toSet();
      return last4.any((d) => d != null && txn.body.contains(d));
    }).toList();
    final card = mentioned.length == 1 ? mentioned.first : (cards.length == 1 ? cards.first : null);
    if (card == null) return none;

    // The card's "payment received" SMS came first: turn it into the full transfer.
    final near = await _expenseRepo.findExpensesNear(amount: -txn.amount, date: txn.date, window: _pairWindow);
    final cardHalf = near
        .where((e) => e.accountId == card.id && e.transferAccountId.isEmpty && e.categoryId == 'transfers')
        .firstOrNull;
    if (cardHalf != null) {
      final upgraded = cardHalf.copyWith(
        amount: txn.amount,
        accountId: accountId,
        transferAccountId: card.id,
        isCountedAsSpend: false,
      );
      await _expenseRepo.updateExpense(upgraded);
      return (skip: false, upgraded: upgraded, toCardId: card.id, cardSide: false);
    }
    return (skip: false, upgraded: null, toCardId: card.id, cardSide: false);
  }
}
