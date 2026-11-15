import 'package:fiscora/features/customers/customers_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses parties from the API, including string balances', () {
    final a = Party.fromJson({'id': 'a', 'name': 'Ravi', 'phone': '9876543210', 'gstin': null, 'balance': 1250.5});
    final b = Party.fromJson({'id': 'b', 'name': 'Meena', 'balance': '-300'});
    final c = Party.fromJson({'id': 'c', 'name': 'Arjun'});
    expect(a.balance, 1250.5);
    expect(a.phone, '9876543210');
    expect(b.balance, -300);
    expect(b.phone, isNull);
    expect(c.balance, 0);
  });

  test('total receivable ignores advances', () {
    final parties = [
      const Party(id: 'a', name: 'A', balance: 1000),
      const Party(id: 'b', name: 'B', balance: -400),
      const Party(id: 'c', name: 'C', balance: 250),
    ];
    expect(totalReceivable(parties), 1250);
    expect(totalReceivable(const []), 0);
  });
}
