
import 'package:isar_plus/isar_plus.dart';
import 'package:fiscora/core/sync/outbox_operation.dart';
import 'package:uuid/uuid.dart';

import 'package:fiscora/features/expenses/models/expense_model.dart';
import 'package:fiscora/core/sync/collections/expense_collection.dart';
import 'package:fiscora/core/sync/collections/budget_collection.dart';
import 'package:fiscora/core/sync/collections/category_rule_collection.dart';
import 'package:fiscora/core/sync/collections/category_collection.dart';
import 'package:fiscora/features/categories/models/category.dart';
import 'package:fiscora/features/categories/services/category_registry.dart';
import 'package:fiscora/features/categories/services/category_resolver.dart';
import 'package:fiscora/core/sync/isar_database.dart';
import 'package:fiscora/core/sync/sync_engine.dart';
import 'package:fiscora/core/sync/sync_metadata.dart';
import 'package:fiscora/core/repositories/i_expense_repository.dart';
import 'package:fiscora/core/services/account_balances.dart';

class IsarExpenseRepository implements IExpenseRepository {
  Isar get _isar => IsarDatabase.instance.isar;
  final _uuid = const Uuid();

  @override
  Stream<List<Expense>> watchExpenses() {
    // Return a stream that watches all changes on expenses (excluding deleted ones)
    return _isar.expenseCollections
        .where()
        .isDeletedEqualTo(false)
        .sortByDateDesc()
        .watch(fireImmediately: true)
        .map((list) => list.map((e) => e.toDomain()).toList());
  }

  @override
  Future<Set<String>> getAllExpenseIds() async {
    final ids = _isar.expenseCollections.where().clientIdProperty().findAll();
    return ids.toSet();
  }

  @override
  Future<List<Expense>> findExpensesNear({
    required double amount,
    required DateTime date,
    Duration window = const Duration(minutes: 3),
  }) async {
    return _isar.expenseCollections
        .where()
        .amountBetween(amount - 0.001, amount + 0.001)
        .and()
        .dateBetween(date.subtract(window), date.add(window))
        .findAll()
        .map((e) => e.toDomain())
        .toList();
  }

  @override
  Future<void> addExpense(Expense expense) async {
    await _isar.writeAsync((isar) {
      final existing = isar.expenseCollections
          .where()
          .clientIdEqualTo(expense.id)
          .findFirst();
      if (existing != null) {
        return;
      }

      final newId = isar.expenseCollections.autoIncrement();
      final col = ExpenseCollection.fromDomain(
        _withNames(isar, expense),
        syncStatus: SyncStatus.pendingCreate,
        dirty: true,
      )..id = newId;

      isar.expenseCollections.put(col);
      SyncEngine.enqueue(
        isar: isar,
        entityType: 'expense',
        clientId: col.clientId,
        operationType: 'create',
        payload: col.toSyncJson(),
      );

      // Balances are derived from transactions; recompute in the same write.
      AccountBalances.recomputeAll(isar);
    });

    // Trigger sync in background
    SyncEngine.instance.triggerSync();
  }

  @override
  Future<void> updateExpense(Expense expense) async {
    await _isar.writeAsync((isar) {
      final existing = isar.expenseCollections
          .where()
          .clientIdEqualTo(expense.id)
          .findFirst();

      if (existing != null) {
        final col = ExpenseCollection.fromDomain(
          _withNames(isar, expense),
          serverId: existing.serverId,
          serverUpdatedAt: existing.serverUpdatedAt,
          syncStatus: existing.serverId == null ? SyncStatus.pendingCreate : SyncStatus.pendingUpdate,
          // version stays the last server version seen; the server uses it to
          // detect edits made elsewhere in the meantime.
          version: existing.version,
          dirty: true,
        )..id = existing.id;

        isar.expenseCollections.put(col);
        AccountBalances.recomputeAll(isar);
        SyncEngine.enqueue(
          isar: isar,
          entityType: 'expense',
          clientId: col.clientId,
          operationType: existing.serverId == null ? 'create' : 'update',
          payload: col.toSyncJson(),
        );
      }
    });

    SyncEngine.instance.triggerSync();
  }

  @override
  Future<void> approveExpenses(List<String> ids) async {
    if (ids.isEmpty) return;
    await _isar.writeAsync((isar) {
      for (final id in ids) {
        final col = isar.expenseCollections.where().clientIdEqualTo(id).findFirst();
        if (col == null || !col.needsReview || col.isDeleted) continue;
        col
          ..needsReview = false
          ..dirty = true
          ..syncStatus = col.serverId == null ? SyncStatus.pendingCreate.name : SyncStatus.pendingUpdate.name
          ..updatedAt = DateTime.now().toUtc();
        isar.expenseCollections.put(col);
        SyncEngine.enqueue(
          isar: isar,
          entityType: 'expense',
          clientId: id,
          operationType: col.serverId == null ? 'create' : 'update',
          payload: col.toSyncJson(),
        );
      }
    });
    SyncEngine.instance.triggerSync();
  }

  @override
  Future<void> deleteExpense(String id) async {
    await _isar.writeAsync((isar) {
      final existing = isar.expenseCollections
          .where()
          .clientIdEqualTo(id)
          .findFirst();
      if (existing == null) return;

      // Always keep a tombstone and tell the server, even if this record was
      // never acknowledged. Hard-deleting unsynced rows let them come back:
      // the create may already have reached the server (response lost), and
      // SMS import uses existing ids to skip messages the user deleted.
      existing.isDeleted = true;
      existing.dirty = true;
      existing.syncStatus = SyncStatus.pendingDelete.name;
      existing.updatedAt = DateTime.now().toUtc();
      isar.expenseCollections.put(existing);

      SyncEngine.enqueue(
        isar: isar,
        entityType: 'expense',
        clientId: id,
        operationType: 'delete',
        payload: {},
      );
      AccountBalances.recomputeAll(isar);
    });

    SyncEngine.instance.triggerSync();
  }

  @override
  Future<Map<String, Map<String, dynamic>>> getBudgetForMonth(String month) async {
    final budgets = _isar.budgetCollections
        .where()
        .monthEqualTo(month)
        .isDeletedEqualTo(false)
        .findAll();

    final Map<String, Map<String, dynamic>> results = {};
    for (final b in budgets) {
      results[b.category] = {
        'limit': b.amountLimit,
        'spent': 0.0, // populated by UI provider calculations
      };
    }
    return results;
  }

  @override
  Future<void> setBudgetForMonth(
    String month,
    Map<String, Map<String, dynamic>> categories,
  ) async {
    await _isar.writeAsync((isar) {
      // Find all existing budgets for this month
      final existingBudgets = isar.budgetCollections
          .where()
          .monthEqualTo(month)
          .findAll();

      final existingMap = {for (var b in existingBudgets) b.category: b};

      // Upsert new budgets
      for (final entry in categories.entries) {
        final category = entry.key;
        final limit = (entry.value['limit'] as num? ?? 0.0).toDouble();

        final existing = existingMap[category];
        if (existing != null) {
          if (existing.amountLimit != limit || existing.isDeleted) {
            existing.amountLimit = limit;
            existing.isDeleted = false;
            existing.dirty = true;
            existing.syncStatus = existing.serverId == null ? SyncStatus.pendingCreate.name : SyncStatus.pendingUpdate.name;
            existing.updatedAt = DateTime.now().toUtc();

            isar.budgetCollections.put(existing);
            SyncEngine.enqueue(
              isar: isar,
              entityType: 'budget',
              clientId: existing.clientId,
              operationType: existing.serverId == null ? 'create' : 'update',
              payload: existing.toSyncJson(),
            );
          }
        } else {
          final clientId = _uuid.v4();
          final newId = isar.budgetCollections.autoIncrement();
          final newCol = BudgetCollection.create(
            clientId: clientId,
            month: month,
            category: category,
            amountLimit: limit,
            syncStatus: SyncStatus.pendingCreate,
            dirty: true,
          )..id = newId;

          isar.budgetCollections.put(newCol);
          SyncEngine.enqueue(
            isar: isar,
            entityType: 'budget',
            clientId: clientId,
            operationType: 'create',
            payload: newCol.toSyncJson(),
          );
        }
      }

      // Soft delete omitted budgets
      for (final existing in existingBudgets) {
        if (!categories.containsKey(existing.category) && !existing.isDeleted) {
          if (existing.serverId == null) {
            isar.budgetCollections.delete(existing.id);
            final ops = isar.outboxOperations.where().clientIdEqualTo(existing.clientId).findAll();
            for (final op in ops) {
              isar.outboxOperations.delete(op.id);
            }
          } else {
            existing.isDeleted = true;
            existing.dirty = true;
            existing.syncStatus = SyncStatus.pendingDelete.name;
            existing.updatedAt = DateTime.now().toUtc();

            isar.budgetCollections.put(existing);
            SyncEngine.enqueue(
              isar: isar,
              entityType: 'budget',
              clientId: existing.clientId,
              operationType: 'delete',
              payload: {},
            );
          }
        }
      }
    });

    SyncEngine.instance.triggerSync();
  }


  /// Fills category ids (from a legacy name if needed) and refreshes the
  /// denormalised display names from the user's categories.
  Expense _withNames(Isar isar, Expense e) {
    var expense = e;
    if (expense.categoryId.isEmpty) {
      final sel = CategoryResolver.fromLegacyName(expense.category, isCredit: expense.amount < 0);
      expense = expense.copyWith(categoryId: sel.categoryId, subcategoryId: sel.subcategoryId);
    }
    final r = _registry(isar).resolve(
      expense.categoryId,
      expense.subcategoryId,
      isCredit: expense.amount < 0,
    );
    return expense.copyWith(
      categoryId: r.parent.id,
      subcategoryId: r.sub?.id ?? '',
      category: r.parent.name,
      subcategory: r.sub?.name ?? '',
    );
  }

  CategoryRegistry _registry(Isar isar) => CategoryRegistry(
        isar.categoryCollections
            .where()
            .isDeletedEqualTo(false)
            .findAll()
            .map((c) => c.toDomain())
            .toList(),
      );

  @override
  Stream<List<({String merchant, CategorySelection selection})>> watchMerchantRules() {
    return _isar.categoryRuleCollections
        .where()
        .isDeletedEqualTo(false)
        .sortByMerchant()
        .watch(fireImmediately: true)
        .map((rows) => [
              for (final r in rows)
                if (r.categoryId.isNotEmpty)
                  (merchant: r.merchant, selection: CategorySelection(r.categoryId, r.subcategoryId)),
            ]);
  }

  @override
  Future<void> deleteMerchantRule(String merchant) async {
    await _isar.writeAsync((isar) {
      final rule = isar.categoryRuleCollections
          .where()
          .merchantEqualTo(merchant.trim(), caseSensitive: false)
          .findFirst();
      if (rule == null || rule.isDeleted) return;
      rule
        ..isDeleted = true
        ..dirty = true
        ..syncStatus = SyncStatus.pendingDelete.name
        ..updatedAt = DateTime.now().toUtc();
      isar.categoryRuleCollections.put(rule);
      SyncEngine.enqueue(
        isar: isar,
        entityType: 'category_rule',
        clientId: rule.clientId,
        operationType: 'delete',
        payload: {},
      );
    });
    SyncEngine.instance.triggerSync();
  }

  @override
  Future<void> setMerchantRule(String merchant, CategorySelection selection) async {
    final trimmed = merchant.trim();
    if (trimmed.isEmpty || selection.categoryId.isEmpty) return;

    await _isar.writeAsync((isar) {
      final parentName = _registry(isar).categoryOrFallback(selection.categoryId).name;
      final existing = isar.categoryRuleCollections
          .where()
          .merchantEqualTo(trimmed, caseSensitive: false)
          .findFirst();

      if (existing != null) {
        if (existing.categoryId != selection.categoryId ||
            existing.subcategoryId != selection.subcategoryId ||
            existing.isDeleted) {
          existing
            ..category = parentName
            ..categoryId = selection.categoryId
            ..subcategoryId = selection.subcategoryId
            ..isDeleted = false
            ..dirty = true
            ..syncStatus = existing.serverId == null
                ? SyncStatus.pendingCreate.name
                : SyncStatus.pendingUpdate.name
            ..updatedAt = DateTime.now().toUtc();

          isar.categoryRuleCollections.put(existing);
          SyncEngine.enqueue(
            isar: isar,
            entityType: 'category_rule',
            clientId: existing.clientId,
            operationType: existing.serverId == null ? 'create' : 'update',
            payload: existing.toSyncJson(),
          );
        }
      } else {
        final clientId = _uuid.v4();
        final newCol = CategoryRuleCollection.create(
          clientId: clientId,
          merchant: trimmed,
          category: parentName,
          categoryId: selection.categoryId,
          subcategoryId: selection.subcategoryId,
          syncStatus: SyncStatus.pendingCreate,
          dirty: true,
        )..id = isar.categoryRuleCollections.autoIncrement();

        isar.categoryRuleCollections.put(newCol);
        SyncEngine.enqueue(
          isar: isar,
          entityType: 'category_rule',
          clientId: clientId,
          operationType: 'create',
          payload: newCol.toSyncJson(),
        );
      }
    });

    SyncEngine.instance.triggerSync();
  }

  @override
  Future<CategorySelection?> getMerchantRule(String merchant) async {
    final trimmed = merchant.trim();
    if (trimmed.isEmpty) return null;

    final rule = _isar.categoryRuleCollections
        .where()
        .merchantEqualTo(trimmed, caseSensitive: false)
        .isDeletedEqualTo(false)
        .findFirst();
    if (rule == null) return null;
    if (rule.categoryId.isEmpty) return CategoryResolver.fromLegacyName(rule.category);
    return CategorySelection(rule.categoryId, rule.subcategoryId);
  }

  @override
  Future<void> updateExpensesCategory(String merchant, CategorySelection selection) async {
    if (merchant.trim().isEmpty) return;

    await _isar.writeAsync((isar) {
      final registry = _registry(isar);
      final expenses = isar.expenseCollections
          .where()
          .merchantEqualTo(merchant.trim(), caseSensitive: false)
          .isDeletedEqualTo(false)
          .findAll();

      for (final exp in expenses) {
        final r = registry.resolve(selection.categoryId, selection.subcategoryId, isCredit: exp.amount < 0);
        exp
          ..categoryId = r.parent.id
          ..subcategoryId = r.sub?.id ?? ''
          ..category = r.parent.name
          ..subcategory = r.sub?.name ?? ''
          // "Apply to similar" is a review decision for every matching capture.
          ..needsReview = false
          ..dirty = true
          ..syncStatus = exp.serverId == null ? SyncStatus.pendingCreate.name : SyncStatus.pendingUpdate.name
          ..updatedAt = DateTime.now().toUtc();

        isar.expenseCollections.put(exp);
        SyncEngine.enqueue(
          isar: isar,
          entityType: 'expense',
          clientId: exp.clientId,
          operationType: exp.serverId == null ? 'create' : 'update',
          payload: exp.toSyncJson(),
        );
      }
    });

    SyncEngine.instance.triggerSync();
  }
}
