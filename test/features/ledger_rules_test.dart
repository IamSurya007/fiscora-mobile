import 'package:flutter_test/flutter_test.dart';
import 'package:fiscora/features/expenses/models/expense_model.dart';
import 'package:fiscora/features/expenses/models/ledger_rules.dart';

Expense tx(double amount, String categoryId, {bool counted = true}) => Expense(
      id: 'x',
      amount: amount,
      category: categoryId,
      categoryId: categoryId,
      note: '',
      date: DateTime(2026, 11, 14),
      method: 'upi',
      source: 'manual',
      merchant: '',
      createdAt: DateTime(2026, 11, 14),
      isCountedAsSpend: counted,
    );

void main() {
  test('debits are spend, credits are income', () {
    expect(tx(500, 'food').countsAsSpend, isTrue);
    expect(tx(-50000, 'income').countsAsIncome, isTrue);
  });

  test('transfers are neither spend nor income', () {
    expect(tx(5000, 'transfers').countsAsSpend, isFalse);
    expect(tx(-5000, 'transfers').countsAsIncome, isFalse);
    expect(tx(2000, 'transfers.self').isTransfer, isTrue);
  });

  test('the spend flag excludes debits but not credits', () {
    expect(tx(500, 'food', counted: false).countsAsSpend, isFalse);
    expect(tx(-500, 'income', counted: false).countsAsIncome, isTrue);
  });
}
