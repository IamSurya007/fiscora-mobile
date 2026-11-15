import 'package:flutter_test/flutter_test.dart';
import 'package:fiscora/features/loans/domain/emi.dart';
import 'package:fiscora/features/loans/models/loan_model.dart';
import 'package:fiscora/features/loans/screens/record_repayment_sheet.dart';

void main() {
  group('computeEmi', () {
    test('reducing-balance EMI', () {
      expect(computeEmi(100000, 12, 12), closeTo(8884.88, 0.001));
      expect(computeEmi(500000, 8.5, 60), closeTo(10258.27, 0.001));
    });
    test('zero rate splits evenly; bad inputs give 0', () {
      expect(computeEmi(12000, 0, 12), 1000);
      expect(computeEmi(0, 10, 12), 0);
      expect(computeEmi(1000, 10, 0), 0);
    });
  });

  test('due dates clamp to the month end', () {
    expect(emiDueDate(DateTime(2026, 1, 31), 0), DateTime(2026, 1, 31));
    expect(emiDueDate(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    expect(emiDueDate(DateTime(2026, 1, 31), 2), DateTime(2026, 3, 31));
    expect(emiDueDate(DateTime(2027, 12, 15), 1, 5), DateTime(2028, 1, 5));
    expect(emiDueDate(DateTime(2028, 1, 10), 1, 30), DateTime(2028, 2, 29));
  });

  group('buildSchedule', () {
    test('ends at exactly zero, matching the TS implementation', () {
      final rows = buildSchedule(
        principal: 100000,
        annualRatePercent: 12,
        tenureMonths: 12,
        startDate: DateTime(2026, 1, 5),
      );
      expect(rows, hasLength(12));
      expect(rows.first.emi, 8884.88);
      expect(rows.first.interest, 1000);
      expect(rows.first.principal, 7884.88);
      expect(rows.first.balance, 92115.12);
      expect(rows.last.balance, 0);
      expect(rows.last.dueDate, DateTime(2026, 12, 5));
      final principalSum = rows.fold(0.0, (s, r) => s + r.principal);
      expect(principalSum, closeTo(100000, 0.01));
      expect((rows.last.emi - 8884.88).abs(), lessThan(0.1));
    });
    test('a larger override EMI closes the loan early', () {
      final rows = buildSchedule(
        principal: 12000,
        annualRatePercent: 0,
        tenureMonths: 12,
        startDate: DateTime(2026, 1, 1),
        emiOverride: 5000,
      );
      expect(rows.map((r) => r.emi), [5000, 5000, 2000]);
      expect(rows.last.balance, 0);
    });
    test('a small override EMI leaves the remainder in the last row', () {
      final rows = buildSchedule(
        principal: 12000,
        annualRatePercent: 0,
        tenureMonths: 3,
        startDate: DateTime(2026, 1, 1),
        emiOverride: 1000,
      );
      expect(rows.map((r) => r.emi), [1000, 1000, 10000]);
    });
  });

  group('Loan EMI getters', () {
    Loan emiLoan(List<LoanRepayment> repayments) => Loan(
          id: 'l1',
          type: 'taken',
          name: 'Car',
          principal: 12000,
          total: 12000,
          createdAt: DateTime(2026, 1, 1),
          isEmi: true,
          tenureMonths: 12,
          emiStartDate: DateTime(2026, 1, 10),
          repayments: repayments,
        );

    test('outstanding, progress and next due follow repayments', () {
      final loan = emiLoan([
        LoanRepayment(id: 'a', date: DateTime(2026, 1, 10), amount: 1000),
        LoanRepayment(id: 'b', date: DateTime(2026, 2, 10), amount: 500),
      ]);
      expect(loan.effectiveEmi, 1000);
      expect(loan.totalPayable, 12000);
      expect(loan.outstanding, 10500);
      expect(loan.repaidFraction, closeTo(0.125, 1e-9));
      expect(loan.nextEmi?.dueDate, DateTime(2026, 2, 10));
      expect(loan.nextDueDate, DateTime(2026, 2, 10));
    });

    test('fully repaid has no next due', () {
      final loan = emiLoan([LoanRepayment(id: 'a', date: DateTime(2026, 1, 1), amount: 12000)]);
      expect(loan.outstanding, 0);
      expect(loan.nextEmi, isNull);
    });

    test('non-EMI loans keep the plain repayment date and total', () {
      final loan = Loan(
        id: 'l2',
        type: 'given',
        name: 'Rahul',
        principal: 1000,
        total: 1000,
        createdAt: DateTime.now(),
        repaymentDate: DateTime(2030, 1, 1),
        repayments: [LoanRepayment(id: 'a', date: DateTime(2026, 1, 1), amount: 400)],
      );
      expect(loan.schedule, isEmpty);
      expect(loan.outstanding, 600);
      expect(loan.nextDueDate, DateTime(2030, 1, 1));
    });

    test('repayments round-trip through JSON', () {
      final parsed = Loan.parseRepayments([
        {'id': 'x', 'date': '2026-03-05', 'amount': 250, 'note': 'cash'},
        {'id': 'bad', 'date': '2026-03-05', 'amount': 0},
        'junk',
      ]);
      expect(parsed, hasLength(1));
      expect(parsed.first.date, DateTime(2026, 3, 5));
      expect(parsed.first.toJson(), {'id': 'x', 'date': '2026-03-05', 'amount': 250.0, 'note': 'cash'});
    });
  });

  group('recording a repayment', () {
    final loan = Loan(
      id: 'l3',
      type: 'taken',
      name: 'Bike',
      principal: 3000,
      total: 3000,
      createdAt: DateTime(2026, 1, 1),
      isEmi: true,
      tenureMonths: 3,
      emiStartDate: DateTime(2026, 2, 1),
    );

    test('appends to the log and stays active while money is outstanding', () {
      final after = applyRepayment(loan, LoanRepayment(id: 'a', date: DateTime(2026, 2, 1), amount: 1000));
      expect(after.repayments, hasLength(1));
      expect(after.status, 'active');
      expect(after.nextEmi?.month, 2);
    });

    test('marks the loan paid when nothing is outstanding', () {
      final after = applyRepayment(loan, LoanRepayment(id: 'a', date: DateTime(2026, 2, 1), amount: 3000));
      expect(after.status, 'paid');
    });

    test('uses system categories for the linked transaction', () {
      expect(repaymentCategory('taken'), (categoryId: 'finance', subcategoryId: 'finance.loan_emi'));
      expect(repaymentCategory('given'), (categoryId: 'income', subcategoryId: 'income.received'));
    });
  });
}
