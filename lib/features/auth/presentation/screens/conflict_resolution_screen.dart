import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar_plus/isar_plus.dart';

import 'package:fiscora/core/constants/app_colors.dart';
import 'package:fiscora/core/constants/app_text_styles.dart';
import 'package:fiscora/core/sync/collections/conflict_record.dart';
import 'package:fiscora/core/sync/collections/expense_collection.dart';
import 'package:fiscora/core/sync/collections/loan_collection.dart';
import 'package:fiscora/core/sync/collections/investment_collection.dart';
import 'package:fiscora/core/sync/collections/budget_collection.dart';
import 'package:fiscora/core/sync/collections/category_rule_collection.dart';
import 'package:fiscora/core/sync/collections/account_collection.dart';
import 'package:fiscora/core/sync/collections/category_collection.dart';
import 'package:fiscora/core/sync/isar_database.dart';
import 'package:fiscora/core/sync/sync_engine.dart';
import 'package:fiscora/core/sync/sync_metadata.dart';

class ConflictResolutionScreen extends ConsumerWidget {
  const ConflictResolutionScreen({super.key});

  Isar get _isar => IsarDatabase.instance.isar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Text('Sync Conflicts', style: AppTextStyles.h2),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.primaryNavy),
      ),
      body: StreamBuilder<List<ConflictRecord>>(
        stream: _isar.conflictRecords.where().watch(fireImmediately: true),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final conflicts = snapshot.data ?? [];
          if (conflicts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.incomeGreen.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppColors.incomeGreen,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('All Synced Up!', style: AppTextStyles.h2),
                  const SizedBox(height: 8),
                  Text(
                    'No conflicts found. Your data is consistent.',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: conflicts.length,
            itemBuilder: (context, index) {
              final conflict = conflicts[index];
              return _ConflictCard(conflict: conflict);
            },
          );
        },
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  final ConflictRecord conflict;

  const _ConflictCard({required this.conflict});

  @override
  Widget build(BuildContext context) {
    final typeName = conflict.entityType.toUpperCase();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.expenseRed.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.sync_problem_rounded, color: AppColors.expenseRed),
        ),
        title: Text('$typeName Conflict', style: AppTextStyles.h3),
        subtitle: Text(
          'ID: ${conflict.clientId.substring(0, 8)}...',
          style: AppTextStyles.caption,
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.mutedText),
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: AppColors.pageBackground,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (context) => _ConflictDetailsSheet(conflict: conflict),
          );
        },
      ),
    );
  }
}

class _ConflictDetailsSheet extends StatelessWidget {
  final ConflictRecord conflict;

  const _ConflictDetailsSheet({required this.conflict});

  Isar get _isar => IsarDatabase.instance.isar;

  @override
  Widget build(BuildContext context) {
    final local = jsonDecode(conflict.localPayloadJson) as Map<String, dynamic>;
    final server = jsonDecode(conflict.serverPayloadJson) as Map<String, dynamic>;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resolve ${conflict.entityType.toUpperCase()} Conflict',
                  style: AppTextStyles.h2,
                ),
                const SizedBox(height: 4),
                Text(
                  'Record Client ID: ${conflict.clientId}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _PayloadColumn(
                      title: 'Local Changes',
                      subtitle: 'Modified on this device',
                      payload: local,
                      color: AppColors.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PayloadColumn(
                      title: 'Server Version',
                      subtitle: 'Saved on other devices',
                      payload: server,
                      color: AppColors.incomeGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _resolve(context, useLocal: true),
                    child: Text('Keep Local', style: AppTextStyles.buttonText),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.incomeGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _resolve(context, useLocal: false),
                    child: Text('Keep Server'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(BuildContext context, {required bool useLocal}) async {
    final server = jsonDecode(conflict.serverPayloadJson) as Map<String, dynamic>;

    await _isar.write((isar) {
      if (useLocal) {
        // Keep local: push it again on top of the server's current version,
        // so the server accepts it instead of reporting the same conflict.
        _setLocalStatus(isar, conflict.entityType, conflict.clientId, SyncStatus.pendingUpdate,
            baseVersion: server['__serverVersion'] as int?);
      } else {
        // Keep server: apply the server's full record (all fields and types).
        SyncEngine.instance.applyConflictServerCopy(conflict.entityType, conflict.clientId, server);
      }

      // Delete the conflict record now that it is resolved
      isar.conflictRecords.delete(conflict.id);
    });

    if (context.mounted) {
      Navigator.pop(context);
    }

    // Trigger synchronization to push local resolution or pull updates
    SyncEngine.instance.triggerSync();
  }

  void _setLocalStatus(Isar isar, String entityType, String clientId, SyncStatus status, {int? baseVersion}) {
    if (entityType == 'expense') {
      final res = isar.expenseCollections.where().clientIdEqualTo(clientId).findFirst();
      if (res != null) {
        res.syncStatus = status.name;
        if (baseVersion != null) res.version = baseVersion;
        res.dirty = true;
        res.updatedAt = DateTime.now().toUtc();
        isar.expenseCollections.put(res);
        SyncEngine.enqueue(
          isar: isar,
          entityType: entityType,
          clientId: clientId,
          operationType: res.serverId == null ? 'create' : 'update',
          payload: res.toSyncJson(),
        );
      }
    } else if (entityType == 'loan') {
      final res = isar.loanCollections.where().clientIdEqualTo(clientId).findFirst();
      if (res != null) {
        res.syncStatus = status.name;
        if (baseVersion != null) res.version = baseVersion;
        res.dirty = true;
        res.updatedAt = DateTime.now().toUtc();
        isar.loanCollections.put(res);
        SyncEngine.enqueue(
          isar: isar,
          entityType: entityType,
          clientId: clientId,
          operationType: res.serverId == null ? 'create' : 'update',
          payload: res.toSyncJson(),
        );
      }
    } else if (entityType == 'investment') {
      final res = isar.investmentCollections.where().clientIdEqualTo(clientId).findFirst();
      if (res != null) {
        res.syncStatus = status.name;
        if (baseVersion != null) res.version = baseVersion;
        res.dirty = true;
        res.updatedAt = DateTime.now().toUtc();
        isar.investmentCollections.put(res);
        SyncEngine.enqueue(
          isar: isar,
          entityType: entityType,
          clientId: clientId,
          operationType: res.serverId == null ? 'create' : 'update',
          payload: res.toSyncJson(),
        );
      }
    } else if (entityType == 'budget') {
      final res = isar.budgetCollections.where().clientIdEqualTo(clientId).findFirst();
      if (res != null) {
        res.syncStatus = status.name;
        if (baseVersion != null) res.version = baseVersion;
        res.dirty = true;
        res.updatedAt = DateTime.now().toUtc();
        isar.budgetCollections.put(res);
        SyncEngine.enqueue(
          isar: isar,
          entityType: entityType,
          clientId: clientId,
          operationType: res.serverId == null ? 'create' : 'update',
          payload: res.toSyncJson(),
        );
      }
    } else if (entityType == 'category_rule') {
      final res = isar.categoryRuleCollections.where().clientIdEqualTo(clientId).findFirst();
      if (res != null) {
        res.syncStatus = status.name;
        if (baseVersion != null) res.version = baseVersion;
        res.dirty = true;
        res.updatedAt = DateTime.now().toUtc();
        isar.categoryRuleCollections.put(res);
        SyncEngine.enqueue(
          isar: isar,
          entityType: entityType,
          clientId: clientId,
          operationType: res.serverId == null ? 'create' : 'update',
          payload: res.toSyncJson(),
        );
      }
    } else if (entityType == 'account' || entityType == 'category') {
      // These were missing, so "Keep local" deleted the conflict and pushed nothing.
      final SyncMetadataMixin? res = entityType == 'account'
          ? isar.accountCollections.where().clientIdEqualTo(clientId).findFirst()
          : isar.categoryCollections.where().clientIdEqualTo(clientId).findFirst();
      if (res != null) {
        res.syncStatus = status.name;
        if (baseVersion != null) res.version = baseVersion;
        res.dirty = true;
        res.updatedAt = DateTime.now().toUtc();
        final Map<String, dynamic> payload;
        if (res is AccountCollection) {
          isar.accountCollections.put(res);
          payload = res.toSyncJson();
        } else {
          final cat = res as CategoryCollection;
          isar.categoryCollections.put(cat);
          payload = cat.toSyncJson();
        }
        SyncEngine.enqueue(
          isar: isar,
          entityType: entityType,
          clientId: clientId,
          operationType: res.serverId == null ? 'create' : 'update',
          payload: payload,
        );
      }
    }
  }

}

class _PayloadColumn extends StatelessWidget {
  final String title;
  final String subtitle;
  final Map<String, dynamic> payload;
  final Color color;

  const _PayloadColumn({
    required this.title,
    required this.subtitle,
    required this.payload,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.h3.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(subtitle, style: AppTextStyles.caption),
          const Divider(height: 16),
          ...payload.entries.where((e) => e.key != 'clientId' && e.key != 'id' && e.key != 'userId' && e.key != 'version').map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.key.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.mutedText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.value?.toString() ?? 'N/A',
                    style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
