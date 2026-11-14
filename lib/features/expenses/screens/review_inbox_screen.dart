import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/transaction_tile.dart';
import '../models/expense_model.dart';
import '../services/expense_providers.dart';
import 'add_expense_sheet.dart';

/// Auto-captured transactions waiting for a decision. Swipe right to keep,
/// swipe left to delete, tap to fix the amount, category or account.
/// Recategorising offers "Update All", which also clears every matching
/// capture from this list and remembers the merchant for next time.
/// Ids swiped away for deletion but still undoable. The real delete waits for
/// the undo snackbar to close: once a delete reaches the server it is final.
final _pendingDeleteProvider = StateProvider<Set<String>>((ref) => {});

class ReviewInboxScreen extends ConsumerWidget {
  const ReviewInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(_pendingDeleteProvider);
    final queue = ref.watch(reviewQueueProvider).where((e) => !hidden.contains(e.id)).toList();
    final notifier = ref.read(expenseNotifierProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Text('To review (${queue.length})', style: AppTextStyles.h2),
        backgroundColor: AppColors.pageBackground,
        elevation: 0,
        actions: [
          if (queue.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Approve all?'),
                    content: Text('Keep all ${queue.length} captured transactions as they are.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve all')),
                    ],
                  ),
                );
                if (ok == true) await notifier.approveExpenses(queue.map((e) => e.id).toList());
              },
              child: const Text('Approve all'),
            ),
        ],
      ),
      body: queue.isEmpty
          ? const _EmptyInbox()
          : ListView.separated(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              itemCount: queue.length + 1,
              separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenPadding, AppSpacing.sm, AppSpacing.screenPadding, AppSpacing.md),
                    child: Text(
                      'Swipe right to keep, left to delete. Tap to change anything.',
                      style: AppTextStyles.caption,
                    ),
                  );
                }
                final expense = queue[i - 1];
                return _ReviewItem(expense: expense);
              },
            ),
    );
  }
}

class _ReviewItem extends ConsumerWidget {
  final Expense expense;
  const _ReviewItem({required this.expense});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(expenseNotifierProvider.notifier);
    return Dismissible(
      key: ValueKey('review-${expense.id}'),
      background: _swipeBackground(
        color: AppColors.incomeGreen,
        icon: Icons.check_rounded,
        label: 'Keep',
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _swipeBackground(
        color: AppColors.expenseRed,
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        alignment: Alignment.centerRight,
      ),
      onDismissed: (direction) async {
        final messenger = ScaffoldMessenger.of(context);
        if (direction == DismissDirection.startToEnd) {
          await notifier.approveExpenses([expense.id]);
          return;
        }
        final pending = ref.read(_pendingDeleteProvider.notifier);
        pending.update((s) => {...s, expense.id});
        var undone = false;
        final closed = messenger
            .showSnackBar(
              SnackBar(
                content: const Text('Transaction deleted'),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(label: 'UNDO', onPressed: () => undone = true),
              ),
            )
            .closed;
        await closed;
        if (undone) {
          pending.update((s) => {...s}..remove(expense.id));
        } else {
          await notifier.deleteExpense(expense.id);
        }
      },
      child: TransactionTile(
        expense: expense,
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => AddExpenseSheet(expense: expense),
        ),
      ),
    );
  }

  Widget _swipeBackground({
    required Color color,
    required IconData icon,
    required String label,
    required Alignment alignment,
  }) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.labelBold.copyWith(color: Colors.white)),
        ],
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_rounded, size: 48, color: AppColors.mutedText),
            const SizedBox(height: AppSpacing.md),
            Text('All caught up', style: AppTextStyles.h3),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'New SMS transactions appear here for a quick check.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
