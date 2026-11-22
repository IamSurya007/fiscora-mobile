import 'package:flutter_test/flutter_test.dart';
import 'package:fiscora/features/business/business_pnl_screen.dart';

void main() {
  test('parses the API P&L response', () {
    final p = BusinessPnl.fromJson({
      'from': '2026-11',
      'to': '2026-11',
      'revenue': 50000,
      'expenses': 12000.5,
      'expensesByCategory': [
        {'categoryId': 'work', 'category': 'Work', 'total': 12000.5, 'count': 3},
      ],
      'netProfit': 37999.5,
      'ownerDraws': 20000,
      'owedToYou': 1500,
      'months': [],
    });
    expect(p.revenue, 50000);
    expect(p.expenses, 12000.5);
    expect(p.netProfit, 37999.5);
    expect(p.ownerDraws, 20000);
    expect(p.owedToYou, 1500);
    expect(p.expensesByCategory.single.name, 'Work');
    expect(p.expensesByCategory.single.count, 3);
  });

  test('missing fields default to zero', () {
    final p = BusinessPnl.fromJson({});
    expect(p.revenue, 0);
    expect(p.expensesByCategory, isEmpty);
  });
}
