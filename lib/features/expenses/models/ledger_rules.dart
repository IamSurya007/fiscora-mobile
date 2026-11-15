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
