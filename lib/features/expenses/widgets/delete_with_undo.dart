import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/expense_model.dart';
import '../services/expense_providers.dart';

/// Ids swiped away for deletion but still undoable. Lists hide them at once;
/// the real delete waits for the undo snackbar to close, because once a delete
/// reaches the server it is final (a later edit can't bring the row back).
final pendingDeleteIdsProvider = StateProvider<Set<String>>((ref) => {});

/// Deletes [expense] with a few seconds to undo.
Future<void> deleteWithUndo(BuildContext context, WidgetRef ref, Expense expense) async {
  final messenger = ScaffoldMessenger.of(context);
  final pending = ref.read(pendingDeleteIdsProvider.notifier);
  final notifier = ref.read(expenseNotifierProvider.notifier);

  pending.update((s) => {...s, expense.id});
  var undone = false;
  messenger.hideCurrentSnackBar();
  await messenger
      .showSnackBar(
        SnackBar(
          content: const Text('Transaction deleted'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(label: 'UNDO', onPressed: () => undone = true),
        ),
      )
      .closed;

  if (!undone) await notifier.deleteExpense(expense.id);
  pending.update((s) => {...s}..remove(expense.id));
}

/// Red "Delete" background for a swipe-to-delete row.
Widget deleteSwipeBackground() => Container(
      color: const Color(0xFFC0293E),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, color: Colors.white),
          SizedBox(width: 6),
          Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
