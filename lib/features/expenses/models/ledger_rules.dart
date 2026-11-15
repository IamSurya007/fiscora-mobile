import '../../categories/data/category_taxonomy.g.dart';
import '../../categories/models/category.dart';
import 'expense_model.dart';

/// Parent ids of the system categories whose kind is "transfer".
final Set<String> _transferParents = {
  for (final c in systemCategories)
    if (c.kind == CategoryKind.transfer && c.parentId == null) c.id,
};

/// The same rules the API uses (fiscora-api/src/utils/ledger.ts), so the app and
/// the web dashboard show the same totals for the same month.
extension LedgerRules on Expense {
  /// Moving money between your own accounts (or to cash) is neither spend nor income.
  bool get isTransfer => _transferParents.contains(categoryId.split('.').first);

  /// Debits that count towards spending and budgets.
  bool get countsAsSpend => amount > 0 && isCountedAsSpend && !isTransfer;

  /// Credits count as income whatever the spend flag says (that flag only affects debits).
  bool get countsAsIncome => amount < 0 && !isTransfer;

  /// Business-scope entries are kept out of personal totals and budgets.
  bool get isPersonal => scope != 'business';

  /// Spend that counts towards personal totals and budgets (business excluded).
  bool get countsAsPersonalSpend => countsAsSpend && isPersonal;

  /// Income that counts towards personal totals (business revenue excluded).
  bool get countsAsPersonalIncome => countsAsIncome && isPersonal;
}

/// Scope a new transaction gets when none is chosen: business accounts file
/// as business, personal and mixed accounts default to personal.
String defaultScopeFor(String? ownership) =>
    ownership == 'business' ? 'business' : 'personal';

/// Whether the add/edit form should offer a Personal/Business toggle.
bool showsScopeToggle(String? ownership) =>
    ownership == 'business' || ownership == 'mixed';

/// Mirrors budgetParts in fiscora-api/src/utils/ledger.ts: the parent-category
/// amounts of a transaction that count in [month]'s budgets. Split
/// transactions count in each of their categories; spread ones count 1/n in
/// each of n months from the month paid. Balances are unaffected.
extension BudgetParts on Expense {
  Map<String, double> budgetPartsFor(DateTime month) {
    if (!countsAsPersonalSpend) return const {};
    final n = spreadMonths < 1 ? 1 : spreadMonths;
    final index = (month.year - date.year) * 12 + (month.month - date.month);
    if (index < 0 || index >= n) return const {};
    final share = amount / n;
    final lines = splits.where((l) => l.amount > 0).toList();
    if (lines.isEmpty) return {categoryId.split('.').first: share};
    final total = lines.fold(0.0, (s, l) => s + l.amount);
    final out = <String, double>{};
    for (final l in lines) {
      final parent = l.categoryId.split('.').first;
      out[parent] = (out[parent] ?? 0) + share * l.amount / total;
    }
    return out;
  }
}
