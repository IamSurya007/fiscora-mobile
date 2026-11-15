import 'package:isar_plus/isar_plus.dart';
import '../../../../features/accounts/models/account_model.dart';
import '../sync_metadata.dart';

part 'account_collection.g.dart';

@collection
class AccountCollection with SyncMetadataMixin {
  int id = 0;

  late String name;
  late String type;
  late String institution;
  /// Derived locally: openingBalance + effects of live transactions
  /// (see core/services/account_balances.dart). Never pushed as the truth.
  late double currentBalance;

  /// Balance before any recorded transaction; null until first computed.
  double? openingBalance;
  late double creditLimit;
  int? statementDay;
  int? dueDay;
  late int colorValue;
  late String iconName;
  late bool isArchived;
  late DateTime createdAt;

  AccountCollection();

  factory AccountCollection.fromDomain(
    Account account, {
    String? serverId,
    DateTime? serverUpdatedAt,
    SyncStatus syncStatus = SyncStatus.pendingCreate,
    int version = 1,
    bool dirty = true,
    bool isDeleted = false,
  }) {
    final col = AccountCollection()
      ..name = account.name
      ..type = account.type.name
      ..institution = account.institution
      ..currentBalance = account.currentBalance
      ..openingBalance = account.openingBalance
      ..creditLimit = account.creditLimit
      ..statementDay = account.statementDay
      ..dueDay = account.dueDay
      ..colorValue = account.colorValue
      ..iconName = account.iconName
      ..isArchived = account.isArchived
      ..createdAt = account.createdAt;

    col.clientId = account.id;
    col.serverId = serverId;
    col.serverUpdatedAt = serverUpdatedAt;
    col.syncStatus = syncStatus.name;
    col.version = version;
    col.dirty = dirty;
    col.isDeleted = isDeleted;
    col.updatedAt = DateTime.now().toUtc();
    return col;
  }

  Account toDomain() {
    return Account(
      id: clientId,
      name: name,
      type: AccountType.values.firstWhere(
        (t) => t.name == type,
        orElse: () => AccountType.bank_account,
      ),
      institution: institution,
      currentBalance: currentBalance,
      openingBalance: openingBalance,
      creditLimit: creditLimit,
      statementDay: statementDay,
      dueDay: dueDay,
      colorValue: colorValue,
      iconName: iconName,
      isArchived: isArchived,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toSyncJson() {
    return {
      'name': name,
      'type': type,
      'institution': institution,
      // The server derives the balance; it only needs openingBalance. The
      // current figure is still sent for servers older than that change.
      if (openingBalance != null) 'openingBalance': openingBalance,
      'currentBalance': currentBalance,
      'current_balance': currentBalance,
      'creditLimit': creditLimit,
      'credit_limit': creditLimit,
      'statementDay': statementDay,
      'dueDay': dueDay,
      'colorValue': colorValue,
      'color_value': colorValue,
      'iconName': iconName,
      'icon_name': iconName,
      'isArchived': isArchived,
      'is_archived': isArchived,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}
