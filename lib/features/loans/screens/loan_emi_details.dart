import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../models/loan_model.dart';

/// EMI summary, repayment progress, amortisation schedule and repayment log
/// shown inside an expanded loan card. Renders nothing for a plain loan with
/// no repayments.
class LoanEmiDetails extends StatefulWidget {
  final Loan loan;
  const LoanEmiDetails({super.key, required this.loan});

  @override
  State<LoanEmiDetails> createState() => _LoanEmiDetailsState();
}

class _LoanEmiDetailsState extends State<LoanEmiDetails> {
  bool _showSchedule = false;
  bool _showRepayments = false;

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    final schedule = loan.schedule;
    if (schedule.isEmpty && loan.repayments.isEmpty) {
      return const SizedBox.shrink();
    }
    final fmt = NumberFormat('#,##,###');
    final fmt2 = NumberFormat('#,##,##0.00');
    final accent = loan.type == 'given' ? AppColors.incomeGreen : AppColors.expenseRed;
    final next = loan.nextEmi;
    final paidInstalments = next == null ? schedule.length : next.month - 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (schedule.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _stat('EMI', '₹${fmt2.format(loan.effectiveEmi)}')),
              Expanded(child: _stat('Tenure', '${schedule.length} months')),
              Expanded(child: _stat('Rate', '${loan.interestRate}%')),
            ],
          ),
        ],
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: loan.repaidFraction,
            minHeight: 6,
            backgroundColor: AppColors.inputFill,
            valueColor: AlwaysStoppedAnimation(accent),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Paid ₹${fmt.format(loan.totalPaid)}', style: AppTextStyles.caption),
            Text('Remaining ₹${fmt.format(loan.outstanding)}', style: AppTextStyles.caption),
          ],
        ),
        if (schedule.isNotEmpty)
          _toggle(
            'Schedule · $paidInstalments of ${schedule.length} paid',
            _showSchedule,
            () => setState(() => _showSchedule = !_showSchedule),
          ),
        if (_showSchedule && schedule.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: AppColors.inputFill,
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: schedule.length + 1,
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return _row('#', 'Due', 'EMI', 'Interest', 'Balance', header: true);
                }
                final r = schedule[i - 1];
                final isNext = next != null && r.month == next.month;
                final isPaid = next == null || r.month < next.month;
                return _row(
                  '${r.month}',
                  DateFormat('d MMM yy').format(r.dueDate),
                  fmt.format(r.emi),
                  fmt.format(r.interest),
                  fmt.format(r.balance),
                  muted: isPaid,
                  highlight: isNext,
                );
              },
            ),
          ),
        if (loan.repayments.isNotEmpty)
          _toggle(
            'Repayments (${loan.repayments.length})',
            _showRepayments,
            () => setState(() => _showRepayments = !_showRepayments),
          ),
        if (_showRepayments)
          for (final r in [...loan.repayments]..sort((a, b) => b.date.compareTo(a.date)))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Text(DateFormat('d MMM yyyy').format(r.date), style: AppTextStyles.caption),
                  if (r.note.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(r.note,
                          style: AppTextStyles.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ] else
                    const Spacer(),
                  Text('₹${fmt2.format(r.amount)}',
                      style: AppTextStyles.caption.copyWith(
                          color: AppColors.primaryNavy, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
      ],
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 2),
          Text(value, style: AppTextStyles.h3.copyWith(fontSize: 13)),
        ],
      );

  Widget _toggle(String label, bool open, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Text(label,
                  style: AppTextStyles.caption.copyWith(
                      color: AppColors.primaryNavy, fontWeight: FontWeight.w600)),
              const Spacer(),
              Icon(
                open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: AppColors.mutedText,
              ),
            ],
          ),
        ),
      );

  Widget _row(String n, String due, String emi, String interest, String balance,
      {bool header = false, bool muted = false, bool highlight = false}) {
    final style = AppTextStyles.caption.copyWith(
      fontSize: 11,
      fontWeight: header || highlight ? FontWeight.w700 : null,
      color: highlight
          ? AppColors.accent
          : muted
              ? AppColors.mutedText
              : AppColors.primaryNavy,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 24, child: Text(n, style: style)),
          Expanded(flex: 3, child: Text(due, style: style)),
          Expanded(flex: 3, child: Text(emi, style: style, textAlign: TextAlign.right)),
          Expanded(flex: 3, child: Text(interest, style: style, textAlign: TextAlign.right)),
          Expanded(flex: 4, child: Text(balance, style: style, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
