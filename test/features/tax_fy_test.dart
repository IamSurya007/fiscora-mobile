import 'package:flutter_test/flutter_test.dart';
import 'package:fiscora/features/tax/tax_screen.dart';

void main() {
  test('FY starts at 1 April 00:00 IST', () {
    expect(fyOf(DateTime.utc(2026, 3, 31, 18, 29)), '2025-26');
    expect(fyOf(DateTime.utc(2026, 3, 31, 18, 30)), '2026-27');
    expect(fyOf(DateTime.utc(2027, 1, 15)), '2026-27');
    expect(fyOf(DateTime.utc(2099, 6, 1)), '2099-00');
  });
}
