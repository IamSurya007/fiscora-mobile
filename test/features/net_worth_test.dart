import 'package:flutter_test/flutter_test.dart';
import 'package:fiscora/features/accounts/models/account_model.dart';
import 'package:fiscora/features/networth/models/net_worth.dart';

Account account(String id, AccountType type, double balance, {bool archived = false}) => Account(
      id: id,
      name: id,
      type: type,
      currentBalance: balance,
      colorValue: 0,
      isArchived: archived,
      createdAt: DateTime(2026),
    );

void main() {
  test('offline net worth is non-card balances minus card balances owed', () {
    final nw = NetWorthSummary.fromAccounts([
      account('bank', AccountType.bank_account, 10000),
      account('cash', AccountType.cash, 500),
      account('card', AccountType.credit_card, 2500),
      account('old', AccountType.bank_account, 9999, archived: true),
    ]);
    expect(nw.assets, 10500);
    expect(nw.liabilities, 2500);
    expect(nw.netWorth, 8000);
    expect(nw.isLocal, isTrue);
    expect(nw.accounts.where((l) => l.isLiability).map((l) => l.id), ['card']);
  });

  test('parses the API summary and history', () {
    final nw = NetWorthSummary.fromJson({
      'assets': 1000,
      'liabilities': 200.5,
      'netWorth': 799.5,
      'breakdown': {
        'byType': {'bank': 1000, 'creditCards': 200.5},
        'accounts': [
          {'id': 'a', 'name': 'HDFC', 'type': 'bank', 'side': 'asset', 'value': 1000},
          {'id': 'c', 'name': 'Card', 'type': 'credit_card', 'side': 'liability', 'value': 200.5},
        ],
        'investments': [],
        'loans': [],
      },
    });
    expect(nw.netWorth, 799.5);
    expect(nw.byType['creditCards'], 200.5);
    expect(nw.accounts.last.isLiability, isTrue);
    expect(nw.isLocal, isFalse);

    final p = NetWorthPoint.fromJson({'date': '2026-11-15', 'netWorth': 5, 'live': true});
    expect(p.date, '2026-11-15');
    expect(p.live, isTrue);
  });

  test('tolerates a missing breakdown', () {
    final nw = NetWorthSummary.fromJson({'assets': 1, 'liabilities': 0, 'netWorth': 1, 'breakdown': null});
    expect(nw.accounts, isEmpty);
    expect(nw.byType, isEmpty);
  });
}
