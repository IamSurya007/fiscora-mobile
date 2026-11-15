import '../../accounts/models/account_model.dart';

double _num(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

/// One row of the breakdown (an account, investment or loan).
class NetWorthLine {
  final String id;
  final String name;
  final String type;
  final bool isLiability;
  final double value;

  const NetWorthLine({
    required this.id,
    required this.name,
    required this.type,
    required this.isLiability,
    required this.value,
  });

  factory NetWorthLine.fromJson(Map<String, dynamic> json) => NetWorthLine(
        id: json['id']?.toString() ?? '',
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? '',
        isLiability: json['side'] == 'liability',
        value: _num(json['value']),
      );
}

/// Current net worth. [isLocal] means it was derived on the device from
/// account balances only (offline), so investments and loans are missing.
class NetWorthSummary {
  final double assets;
  final double liabilities;
  final double netWorth;
  final Map<String, double> byType;
  final List<NetWorthLine> accounts;
  final List<NetWorthLine> investments;
  final List<NetWorthLine> loans;
  final bool isLocal;

  const NetWorthSummary({
    required this.assets,
    required this.liabilities,
    required this.netWorth,
    this.byType = const {},
    this.accounts = const [],
    this.investments = const [],
    this.loans = const [],
    this.isLocal = false,
  });

  factory NetWorthSummary.fromJson(Map<String, dynamic> json) {
    final b = (json['breakdown'] as Map?)?.cast<String, dynamic>() ?? const {};
    List<NetWorthLine> lines(String key) => ((b[key] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => NetWorthLine.fromJson(m.cast<String, dynamic>()))
        .toList();
    final byType = <String, double>{};
    ((b['byType'] as Map?) ?? const {}).forEach((k, v) => byType[k.toString()] = _num(v));
    return NetWorthSummary(
      assets: _num(json['assets']),
      liabilities: _num(json['liabilities']),
      netWorth: _num(json['netWorth']),
      byType: byType,
      accounts: lines('accounts'),
      investments: lines('investments'),
      loans: lines('loans'),
    );
  }

  /// Offline fallback: non-card balances minus card balances owed.
  factory NetWorthSummary.fromAccounts(List<Account> accounts) {
    double assets = 0, liabilities = 0;
    final lines = <NetWorthLine>[];
    for (final a in accounts.where((a) => !a.isArchived)) {
      if (a.isCreditCard) {
        liabilities += a.currentBalance;
      } else {
        assets += a.currentBalance;
      }
      lines.add(NetWorthLine(
        id: a.id,
        name: a.name,
        type: a.type.name,
        isLiability: a.isCreditCard,
        value: a.currentBalance,
      ));
    }
    return NetWorthSummary(
      assets: assets,
      liabilities: liabilities,
      netWorth: assets - liabilities,
      accounts: lines,
      isLocal: true,
    );
  }
}

/// One day on the trend line ('YYYY-MM-DD', IST).
class NetWorthPoint {
  final String date;
  final double netWorth;
  final bool live;

  const NetWorthPoint({required this.date, required this.netWorth, this.live = false});

  factory NetWorthPoint.fromJson(Map<String, dynamic> json) => NetWorthPoint(
        date: json['date']?.toString() ?? '',
        netWorth: _num(json['netWorth']),
        live: json['live'] == true,
      );
}

/// What the API returned: current figures plus history (oldest first).
class NetWorthData {
  final NetWorthSummary current;
  final List<NetWorthPoint> history;

  const NetWorthData({required this.current, required this.history});
}
