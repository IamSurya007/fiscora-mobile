import 'package:flutter_test/flutter_test.dart';
import 'package:fiscora/features/investments/screens/add_investment_sheet.dart';

void main() {
  test('SIP compounds monthly: 10k x 120 months at 12% is about 23.23L', () {
    final v = investmentMaturityValue(type: 'SIP', monthly: 10000, months: 120, annualRatePct: 12);
    expect(v, closeTo(2323390, 100));
  });
  test('zero rate returns the amount deposited', () {
    expect(investmentMaturityValue(type: 'SIP', monthly: 1000, months: 12, annualRatePct: 0), 12000);
  });
  test('adding months clamps to the end of the month', () {
    expect(addMonthsClamped(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    expect(addMonthsClamped(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
    expect(addMonthsClamped(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
  });
}
