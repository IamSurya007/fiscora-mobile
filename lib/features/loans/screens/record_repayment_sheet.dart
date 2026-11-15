import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/providers/repository_providers.dart';
import '../../accounts/services/account_providers.dart';
import '../../expenses/models/expense_model.dart';
import '../models/loan_model.dart';
import '../services/loan_providers.dart';

/// Category for a repayment recorded as a transaction: an EMI paid out for a
/// loan you took, money received back for one you gave.
({String categoryId, String subcategoryId}) repaymentCategory(String loanType) =>
    loanType == 'taken'
        ? (categoryId: 'finance', subcategoryId: 'finance.loan_emi')
        : (categoryId: 'income', subcategoryId: 'income.received');

/// Adds [repayment] to [loan]'s log; the loan becomes paid once nothing is
/// outstanding.
Loan applyRepayment(Loan loan, LoanRepayment repayment) {
  final updated = loan.copyWith(repayments: [...loan.repayments, repayment]);
  return updated.outstanding <= 0 ? updated.copyWith(status: 'paid') : updated;
}

class RecordRepaymentSheet extends ConsumerStatefulWidget {
  final Loan loan;
  const RecordRepaymentSheet({super.key, required this.loan});

  @override
  ConsumerState<RecordRepaymentSheet> createState() =>
      _RecordRepaymentSheetState();
}

class _RecordRepaymentSheetState extends ConsumerState<RecordRepaymentSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
  bool _alsoRecordTransaction = true;
  String? _accountId;

  @override
  void initState() {
    super.initState();
    final loan = widget.loan;
    final suggested = loan.nextEmi?.emi ?? loan.outstanding;
    final capped = suggested > loan.outstanding ? loan.outstanding : suggested;
    if (capped > 0) {
      _amountController.text = capped == capped.roundToDouble()
          ? capped.toInt().toString()
          : capped.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.accent,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) return;
    final loan = widget.loan;
    final note = _noteController.text.trim();
    final day = DateTime(_date.year, _date.month, _date.day);
    final repayment = LoanRepayment(
      id: const Uuid().v4(),
      date: day,
      amount: amount,
      note: note,
    );

    final accounts = ref.read(accountsStreamProvider).valueOrNull ?? [];
    final accountId = _accountId ??
        (accounts.isNotEmpty ? accounts.first.id : 'default_bank');

    Navigator.pop(context);
    await ref
        .read(loanNotifierProvider.notifier)
        .updateLoan(applyRepayment(loan, repayment));

    if (_alsoRecordTransaction) {
      final cat = repaymentCategory(loan.type);
      final isTaken = loan.type == 'taken';
      await ref.read(expenseRepositoryProvider).addExpense(Expense(
            id: const Uuid().v4(),
            // Positive = money out (EMI paid), negative = money in.
            amount: isTaken ? amount : -amount,
            category: '',
            categoryId: cat.categoryId,
            subcategoryId: cat.subcategoryId,
            note: note.isNotEmpty
                ? note
                : '${isTaken ? 'Repayment to' : 'Repayment from'} ${loan.name}',
            date: _date,
            merchant: loan.name,
            accountId: accountId,
            createdAt: DateTime.now(),
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final loan = widget.loan;
    final fmt = NumberFormat('#,##,##0.##');
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? [];
    final selectedId = _accountId ??
        (accounts.isNotEmpty ? accounts.first.id : null);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.md,
        AppSpacing.screenPadding,
        bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Record Repayment', style: AppTextStyles.h2),
            const SizedBox(height: 4),
            Text(
              '${loan.name} · ₹${fmt.format(loan.outstanding)} outstanding',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Amount ₹', style: AppTextStyles.label),
            const SizedBox(height: AppSpacing.xs),
            _input(_amountController, '0',
                const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: AppSpacing.sm),
            Text('Note', style: AppTextStyles.label),
            const SizedBox(height: AppSpacing.xs),
            _input(_noteController, 'Optional', TextInputType.text),
            const SizedBox(height: AppSpacing.sm),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.inputFill,
                  borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 16, color: AppColors.primaryNavy),
                    const SizedBox(width: 8),
                    Text(
                      'Paid on ${DateFormat('d MMM yyyy').format(_date)}',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.primaryNavy),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              value: _alsoRecordTransaction,
              onChanged: (v) =>
                  setState(() => _alsoRecordTransaction = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.primaryNavy,
              title: Text('Also record as a transaction',
                  style: AppTextStyles.bodyMedium),
              subtitle: Text(
                loan.type == 'taken'
                    ? 'Adds an expense (Loan EMI)'
                    : 'Adds income (Received from People)',
                style: AppTextStyles.caption,
              ),
            ),
            if (_alsoRecordTransaction && accounts.isNotEmpty) ...[
              Text('Account', style: AppTextStyles.label),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in accounts)
                    ChoiceChip(
                      label: Text(a.name),
                      selected: a.id == selectedId,
                      onSelected: (_) => setState(() => _accountId = a.id),
                      selectedColor: AppColors.primaryNavy.withValues(alpha: 0.12),
                      labelStyle: AppTextStyles.label.copyWith(
                        color: a.id == selectedId
                            ? AppColors.primaryNavy
                            : AppColors.mutedText,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryNavy,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  ),
                ),
                child: Text('Save Repayment', style: AppTextStyles.buttonText),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(TextEditingController c, String hint, TextInputType type) {
    return TextField(
      controller: c,
      keyboardType: type,
      style: AppTextStyles.bodyMedium,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyles.caption,
        filled: true,
        fillColor: AppColors.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
          borderSide: const BorderSide(color: AppColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }
}
