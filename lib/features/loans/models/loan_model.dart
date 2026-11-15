import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/emi.dart';

export '../domain/emi.dart' show LoanRepayment, EmiScheduleRow;

class Loan {
  final String id;
  final String type; // taken | given
  final String name;
  final double principal;
  final double total;
  final double interestRate;
  final DateTime? repaymentDate;
  final String status; // active | paid | overdue
  final String notes;
  final DateTime createdAt;

  /// EMI loan: repaid in monthly instalments on a reducing balance.
  final bool isEmi;

  /// Override EMI; null means the computed one is used.
  final double? emiAmount;
  final int? tenureMonths;

  /// Due date of the first instalment.
  final DateTime? emiStartDate;

  /// Day of month instalments fall on (clamped to month end); null = day of
  /// [emiStartDate].
  final int? emiDayOfMonth;

  /// Repayment log.
  final List<LoanRepayment> repayments;

  const Loan({
    required this.id,
    required this.type,
    required this.name,
    required this.principal,
    required this.total,
    this.interestRate = 0.0,
    this.repaymentDate,
    this.status = 'active',
    this.notes = '',
    required this.createdAt,
    this.isEmi = false,
    this.emiAmount,
    this.tenureMonths,
    this.emiStartDate,
    this.emiDayOfMonth,
    this.repayments = const [],
  });

  factory Loan.fromJson(Map<String, dynamic> json, String docId) {
    DateTime? parseOptDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    DateTime parseDate(dynamic val) {
      return parseOptDate(val) ?? DateTime.now();
    }

    return Loan(
      id: docId,
      type: (json['type'] as String? ?? 'given').toLowerCase(),
      name: json['name'] as String? ?? '',
      principal: (json['principal'] as num? ?? 0).toDouble(),
      total: (json['total'] as num? ?? 0).toDouble(),
      interestRate: (json['interestRate'] as num?)?.toDouble() ??
          (json['interest_rate'] as num?)?.toDouble() ??
          0.0,
      repaymentDate: parseOptDate(json['repaymentDate'] ?? json['repayment_date']),
      status: (json['status'] as String? ?? 'active').toLowerCase(),
      notes: json['notes'] as String? ?? '',
      createdAt: parseDate(json['createdAt']),
      isEmi: json['isEmi'] == true,
      emiAmount: (json['emiAmount'] as num?)?.toDouble(),
      tenureMonths: (json['tenureMonths'] as num?)?.toInt(),
      emiStartDate: parseOptDate(json['emiStartDate']),
      emiDayOfMonth: (json['emiDayOfMonth'] as num?)?.toInt(),
      repayments: parseRepayments(json['repayments']),
    );
  }

  /// Repayment log from a decoded JSON list (anything else -> empty).
  static List<LoanRepayment> parseRepayments(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => LoanRepayment.fromJson(Map<String, dynamic>.from(m)))
        .where((r) => r.amount > 0)
        .toList();
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'name': name,
        'principal': principal,
        'total': total,
        'interestRate': interestRate,
        'repaymentDate':
            repaymentDate != null ? Timestamp.fromDate(repaymentDate!) : null,
        'status': status,
        'notes': notes,
        'createdAt': Timestamp.fromDate(createdAt),
        'isEmi': isEmi,
        'emiAmount': emiAmount,
        'tenureMonths': tenureMonths,
        'emiStartDate': emiStartDate != null ? formatDateOnly(emiStartDate!) : null,
        'emiDayOfMonth': emiDayOfMonth,
        'repayments': repayments.map((r) => r.toJson()).toList(),
      };

  Loan copyWith({
    String? id,
    String? type,
    String? name,
    double? principal,
    double? total,
    double? interestRate,
    DateTime? repaymentDate,
    String? status,
    String? notes,
    DateTime? createdAt,
    bool? isEmi,
    double? Function()? emiAmount,
    int? tenureMonths,
    DateTime? emiStartDate,
    int? emiDayOfMonth,
    List<LoanRepayment>? repayments,
  }) {
    return Loan(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      principal: principal ?? this.principal,
      total: total ?? this.total,
      interestRate: interestRate ?? this.interestRate,
      repaymentDate: repaymentDate ?? this.repaymentDate,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      isEmi: isEmi ?? this.isEmi,
      emiAmount: emiAmount != null ? emiAmount() : this.emiAmount,
      tenureMonths: tenureMonths ?? this.tenureMonths,
      emiStartDate: emiStartDate ?? this.emiStartDate,
      emiDayOfMonth: emiDayOfMonth ?? this.emiDayOfMonth,
      repayments: repayments ?? this.repayments,
    );
  }

  /// Amortisation schedule; empty unless this is an EMI loan with a tenure
  /// and start date.
  List<EmiScheduleRow> get schedule {
    if (!isEmi || tenureMonths == null || emiStartDate == null) return const [];
    return buildSchedule(
      principal: principal,
      annualRatePercent: interestRate,
      tenureMonths: tenureMonths!,
      startDate: emiStartDate!,
      dayOfMonth: emiDayOfMonth,
      emiOverride: emiAmount,
    );
  }

  /// The monthly instalment in effect (override or computed), 0 if not EMI.
  double get effectiveEmi {
    if (!isEmi || tenureMonths == null) return 0;
    if (emiAmount != null && emiAmount! > 0) return emiAmount!;
    return computeEmi(principal, interestRate, tenureMonths!);
  }

  double get totalPaid => totalRepaid(repayments);

  /// What is payable over the loan's life: the schedule's sum for EMI loans,
  /// otherwise [currentTotal].
  double get totalPayable {
    final rows = schedule;
    if (rows.isNotEmpty) return scheduleTotal(rows);
    return currentTotal;
  }

  /// Still to be repaid (never negative).
  double get outstanding {
    final left = totalPayable - totalPaid;
    return left > 0 ? left : 0;
  }

  /// 0..1 share of [totalPayable] already repaid.
  double get repaidFraction {
    final payable = totalPayable;
    if (payable <= 0) return 0;
    return (totalPaid / payable).clamp(0.0, 1.0);
  }

  /// The next instalment not covered by the repayments, or null.
  EmiScheduleRow? get nextEmi => nextDueRow(schedule, totalPaid);

  double get currentTotal {
    if (status == 'paid') return total;
    if (interestRate <= 0.0) return principal;
    final days = DateTime.now().difference(createdAt).inDays;
    if (days <= 0) return principal;
    return principal * (1.0 + (interestRate / 100.0) * (days / 365.0));
  }

  /// Next date money is due: the next EMI for EMI loans, else [repaymentDate].
  DateTime? get nextDueDate => isEmi ? nextEmi?.dueDate : repaymentDate;

  int? get daysRemaining {
    final due = nextDueDate;
    if (due == null) return null;
    return due.difference(DateTime.now()).inDays;
  }

  bool get isOverdue {
    final due = nextDueDate;
    if (due == null) return false;
    // An instalment is overdue only after its due day has passed.
    final cutoff = isEmi ? due.add(const Duration(days: 1)) : due;
    return DateTime.now().isAfter(cutoff) && status == 'active';
  }
}
