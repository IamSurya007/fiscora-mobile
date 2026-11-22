// Pure EMI maths for loans (reducing balance).
// Mirrors fiscora-api src/loans/emi.ts — keep the two in step.

import 'dart:math' as math;

double _round2(double v) => (v * 100).roundToDouble() / 100;

/// One logged repayment against a loan.
class LoanRepayment {
  final String id;
  final DateTime date;
  final double amount;
  final String note;

  const LoanRepayment({
    required this.id,
    required this.date,
    required this.amount,
    this.note = '',
  });

  factory LoanRepayment.fromJson(Map<String, dynamic> json) {
    final rawDate = json['date'];
    DateTime date;
    if (rawDate is DateTime) {
      date = rawDate;
    } else {
      date = DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();
    }
    return LoanRepayment(
      id: json['id']?.toString() ?? '',
      date: DateTime(date.year, date.month, date.day),
      amount: (json['amount'] is num)
          ? (json['amount'] as num).toDouble()
          : double.tryParse(json['amount']?.toString() ?? '') ?? 0,
      note: json['note']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': formatDateOnly(date),
        'amount': amount,
        'note': note,
      };
}

/// One instalment of an amortisation schedule.
class EmiScheduleRow {
  /// 1-based instalment number.
  final int month;
  final DateTime dueDate;
  final double emi;
  final double interest;
  final double principal;

  /// Balance left after this instalment.
  final double balance;

  const EmiScheduleRow({
    required this.month,
    required this.dueDate,
    required this.emi,
    required this.interest,
    required this.principal,
    required this.balance,
  });
}

/// "YYYY-MM-DD" of a calendar date.
String formatDateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Monthly instalment: P·r·(1+r)^n / ((1+r)^n − 1), r = annual% / 1200;
/// r = 0 → P / n.
double computeEmi(double principal, double annualRatePercent, int tenureMonths) {
  if (principal <= 0 || tenureMonths <= 0) return 0;
  final r = annualRatePercent / 1200;
  if (r <= 0) return _round2(principal / tenureMonths);
  final f = math.pow(1 + r, tenureMonths).toDouble();
  return _round2(principal * r * f / (f - 1));
}

/// Due date of instalment [index] (0-based), day clamped to the month's end.
DateTime emiDueDate(DateTime start, int index, [int? dayOfMonth]) {
  final day = (dayOfMonth != null && dayOfMonth > 0) ? dayOfMonth : start.day;
  final total = (start.month - 1) + index;
  final year = start.year + total ~/ 12;
  final month = total % 12 + 1;
  final daysInMonth = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, math.min(day, daysInMonth));
}

/// Amortisation schedule. [emiOverride] replaces the computed EMI; a larger
/// EMI closes the loan early, and the last row always absorbs rounding (or
/// any remainder) so the balance ends at exactly 0.
List<EmiScheduleRow> buildSchedule({
  required double principal,
  required double annualRatePercent,
  required int tenureMonths,
  required DateTime startDate,
  int? dayOfMonth,
  double? emiOverride,
}) {
  if (principal <= 0 || tenureMonths <= 0) return const [];
  final r = annualRatePercent / 1200;
  final emi = (emiOverride != null && emiOverride > 0)
      ? _round2(emiOverride)
      : computeEmi(principal, annualRatePercent, tenureMonths);
  final rows = <EmiScheduleRow>[];
  var balance = _round2(principal);
  for (var i = 0; i < tenureMonths && balance > 0; i++) {
    final interest = _round2(balance * (r > 0 ? r : 0));
    var principalPart = _round2(emi - interest);
    var rowEmi = emi;
    if (i == tenureMonths - 1 || principalPart >= balance) {
      principalPart = balance;
      rowEmi = _round2(interest + balance);
    }
    balance = _round2(balance - principalPart);
    rows.add(EmiScheduleRow(
      month: i + 1,
      dueDate: emiDueDate(startDate, i, dayOfMonth),
      emi: rowEmi,
      interest: interest,
      principal: principalPart,
      balance: balance,
    ));
  }
  return rows;
}

double totalRepaid(List<LoanRepayment> repayments) =>
    _round2(repayments.fold(0.0, (s, r) => s + r.amount));

/// First instalment not yet covered by [paid] (repayments are applied to
/// instalments in order), or null when every instalment is covered.
EmiScheduleRow? nextDueRow(List<EmiScheduleRow> schedule, double paid) {
  var cumulative = 0.0;
  for (final row in schedule) {
    cumulative = _round2(cumulative + row.emi);
    if (cumulative > paid + 0.005) return row;
  }
  return null;
}

double scheduleTotal(List<EmiScheduleRow> schedule) =>
    _round2(schedule.fold(0.0, (s, r) => s + r.emi));
