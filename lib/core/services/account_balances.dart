import 'package:isar_plus/isar_plus.dart';

import '../../features/accounts/models/account_model.dart';
import '../sync/collections/account_collection.dart';
import '../sync/collections/expense_collection.dart';

/// Balances are derived, never pushed: currentBalance = openingBalance + the
/// effect of every live transaction on the account. Phones used to push an
/// absolute balance and the last write won, so two devices adding expenses at
/// once lost one of them. Mirrors fiscora-api/src/accounts/account-balance.ts.
///
/// `amount` > 0 is money out of `accountId`, < 0 is money in. A transfer also
/// names `transferAccountId`, which receives the money. A credit card's balance
/// is the amount owed: a purchase raises it, a bill payment into it lowers it.
class AccountBalances {
  AccountBalances._();

  static double effectOn(
    AccountCollection account, {
    required double amount,
    required String accountId,
    required String transferAccountId,
  }) {
    final debitSign = account.type == AccountType.credit_card.name ? 1.0 : -1.0;
    final ids = {account.clientId, if (account.serverId != null) account.serverId!};
    var effect = 0.0;
    if (ids.contains(accountId)) effect += debitSign * amount;
    if (transferAccountId.isNotEmpty && ids.contains(transferAccountId)) {
      effect -= debitSign * amount;
    }
    return effect;
  }

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  static double _effects(AccountCollection account, List<ExpenseCollection> txs) {
    var sum = 0.0;
    for (final t in txs) {
      sum += effectOn(account,
          amount: t.amount, accountId: t.accountId, transferAccountId: t.transferAccountId);
    }
    return sum;
  }

  static List<ExpenseCollection> _liveTransactions(Isar isar) =>
      isar.expenseCollections.where().isDeletedEqualTo(false).findAll();

  /// Recomputes every account's balance. Call inside an Isar write. Accounts
  /// that predate derived balances get an opening balance worked back from
  /// their stored balance, so the figure the user sees does not change. This
  /// is local bookkeeping: it never marks the account dirty or queues a push.
  static void recomputeAll(Isar isar) {
    final accounts = isar.accountCollections.where().findAll();
    if (accounts.isEmpty) return;
    final txs = _liveTransactions(isar);
    for (final account in accounts) {
      final effects = _effects(account, txs);
      var changed = false;
      if (account.openingBalance == null) {
        account.openingBalance = _round2(account.currentBalance - effects);
        changed = true;
      }
      final balance = _round2(account.openingBalance! + effects);
      if (balance != account.currentBalance) {
        account.currentBalance = balance;
        changed = true;
      }
      if (changed) isar.accountCollections.put(account);
    }
  }

  /// Opening balance that makes [account] show [targetBalance] now
  /// ("Adjust balance" / editing the balance field). Call inside an Isar write.
  static double openingForTarget(Isar isar, AccountCollection account, double targetBalance) {
    return _round2(targetBalance - _effects(account, _liveTransactions(isar)));
  }
}
