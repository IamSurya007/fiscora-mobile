import 'package:isar_plus/isar_plus.dart';

import 'package:fiscora/features/accounts/models/account_model.dart';
import 'package:fiscora/core/sync/collections/account_collection.dart';
import 'package:fiscora/core/sync/isar_database.dart';
import 'package:fiscora/core/sync/sync_engine.dart';
import 'package:fiscora/core/sync/sync_metadata.dart';
import 'package:fiscora/core/repositories/i_account_repository.dart';
import 'package:fiscora/core/services/account_balances.dart';

class IsarAccountRepository implements IAccountRepository {
  Isar get _isar => IsarDatabase.instance.isar;

  @override
  Stream<List<Account>> watchAccounts() {
    return _isar.accountCollections
        .where()
        .isDeletedEqualTo(false)
        .watch(fireImmediately: true)
        .map((list) => list.where((a) => !a.isArchived).map((a) => a.toDomain()).toList());
  }

  @override
  Future<List<Account>> getAccounts() async {
    final list = _isar.accountCollections
        .where()
        .isDeletedEqualTo(false)
        .findAll();
    return list.where((a) => !a.isArchived).map((a) => a.toDomain()).toList();
  }

  @override
  Future<Account?> getAccount(String id) async {
    final col = _isar.accountCollections
        .where()
        .clientIdEqualTo(id)
        .findFirst();
    return col?.toDomain();
  }

  @override
  Future<void> addAccount(Account account) async {
    await _isar.writeAsync((isar) {
      final existing = isar.accountCollections
          .where()
          .clientIdEqualTo(account.id)
          .findFirst();
      if (existing != null) return;

      final newId = isar.accountCollections.autoIncrement();
      final col = AccountCollection.fromDomain(
        account,
        syncStatus: SyncStatus.pendingCreate,
        dirty: true,
      )..id = newId;
      // The entered balance is what the user sees now, including any
      // transactions already recorded against this account id.
      col.openingBalance ??= AccountBalances.openingForTarget(isar, col, account.currentBalance);

      isar.accountCollections.put(col);
      SyncEngine.enqueue(
        isar: isar,
        entityType: 'account',
        clientId: col.clientId,
        operationType: 'create',
        payload: col.toSyncJson(),
      );
    });

    SyncEngine.instance.triggerSync();
  }

  @override
  Future<void> updateAccount(Account account) async {
    await _isar.writeAsync((isar) {
      final existing = isar.accountCollections
          .where()
          .clientIdEqualTo(account.id)
          .findFirst();

      if (existing != null) {
        // Name/type/colour edits never touch the balance: a form opened before
        // an SMS import would otherwise write back a stale figure. Balance
        // changes go through updateAccountBalance.
        final col = AccountCollection.fromDomain(
          account,
          serverId: existing.serverId,
          serverUpdatedAt: existing.serverUpdatedAt,
          syncStatus: existing.serverId == null ? SyncStatus.pendingCreate : SyncStatus.pendingUpdate,
          version: existing.version,
          dirty: true,
        )
          ..id = existing.id
          ..openingBalance = existing.openingBalance
          ..currentBalance = existing.currentBalance;

        isar.accountCollections.put(col);
        SyncEngine.enqueue(
          isar: isar,
          entityType: 'account',
          clientId: col.clientId,
          operationType: existing.serverId == null ? 'create' : 'update',
          payload: col.toSyncJson(),
        );
      }
    });

    SyncEngine.instance.triggerSync();
  }

  @override
  Future<void> updateAccountBalance(String id, double newBalance) async {
    await _isar.writeAsync((isar) {
      final existing = isar.accountCollections
          .where()
          .clientIdEqualTo(id)
          .findFirst();

      if (existing != null) {
        // "Set balance to X" moves the opening balance; the balance stays derived.
        existing.openingBalance = AccountBalances.openingForTarget(isar, existing, newBalance);
        existing.currentBalance = newBalance;
        existing.dirty = true;
        existing.syncStatus = existing.serverId == null ? SyncStatus.pendingCreate.name : SyncStatus.pendingUpdate.name;
        existing.updatedAt = DateTime.now().toUtc();

        isar.accountCollections.put(existing);
        SyncEngine.enqueue(
          isar: isar,
          entityType: 'account',
          clientId: id,
          operationType: existing.serverId == null ? 'create' : 'update',
          payload: existing.toSyncJson(),
        );
      }
    });

    SyncEngine.instance.triggerSync();
  }

  @override
  Future<void> adjustAccountBalance(String id, double delta) async {
    if (delta == 0) return;

    await _isar.writeAsync((isar) {
      final existing = isar.accountCollections
          .where()
          .clientIdEqualTo(id)
          .findFirst();

      if (existing != null) {
        existing.openingBalance = (existing.openingBalance ?? existing.currentBalance) + delta;
        existing.currentBalance += delta;
        existing.dirty = true;
        existing.syncStatus = existing.serverId == null ? SyncStatus.pendingCreate.name : SyncStatus.pendingUpdate.name;
        existing.updatedAt = DateTime.now().toUtc();

        isar.accountCollections.put(existing);
        SyncEngine.enqueue(
          isar: isar,
          entityType: 'account',
          clientId: id,
          operationType: existing.serverId == null ? 'create' : 'update',
          payload: existing.toSyncJson(),
        );
      }
    });

    SyncEngine.instance.triggerSync();
  }

  @override
  Future<void> deleteAccount(String id) async {
    await _isar.writeAsync((isar) {
      final existing = isar.accountCollections
          .where()
          .clientIdEqualTo(id)
          .findFirst();

      if (existing != null) {
        // Keep a tombstone even if never acknowledged (see deleteExpense).
        existing.isDeleted = true;
        existing.dirty = true;
        existing.syncStatus = SyncStatus.pendingDelete.name;
        existing.updatedAt = DateTime.now().toUtc();
        isar.accountCollections.put(existing);

        SyncEngine.enqueue(
          isar: isar,
          entityType: 'account',
          clientId: id,
          operationType: 'delete',
          payload: {},
        );
      }
    });

    SyncEngine.instance.triggerSync();
  }

  @override
  Future<void> seedDefaultAccountsIfNeeded() async {
    // Accounts should only be created from SMS parsing or manual user creation.
    return;
  }
}
