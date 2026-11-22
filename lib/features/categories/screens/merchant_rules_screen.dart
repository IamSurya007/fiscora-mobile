import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../expenses/services/expense_providers.dart';
import '../models/category.dart';
import '../services/category_providers.dart';
import '../widgets/category_icon.dart';
import '../widgets/category_picker_sheet.dart';

/// The merchant -> category rules Fiscora has learned. They used to be saved
/// silently (from "Update All" or picking a category for a merchant) with no
/// way to see or undo them.
class MerchantRulesScreen extends ConsumerWidget {
  const MerchantRulesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(merchantRulesProvider);
    final registry = ref.watch(categoryRegistryProvider);

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Text('Merchant rules', style: AppTextStyles.h2),
        backgroundColor: AppColors.pageBackground,
        elevation: 0,
      ),
      body: rulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (e, _) => Center(child: Text('Could not load rules: $e', style: AppTextStyles.bodySmall)),
        data: (rules) {
          if (rules.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'No rules yet. When you recategorise a merchant and choose "Update All", '
                  'Fiscora remembers it here for future transactions.',
                  style: AppTextStyles.caption,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: rules.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final rule = rules[i];
              final leaf = registry.leaf(rule.selection.categoryId, rule.selection.subcategoryId);
              return Dismissible(
                key: ValueKey('rule-${rule.merchant}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: AppColors.expenseRed,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                ),
                onDismissed: (_) =>
                    ref.read(expenseNotifierProvider.notifier).deleteMerchantRule(rule.merchant),
                child: ListTile(
                  leading: CategoryIcon(category: leaf, size: 36),
                  title: Text(rule.merchant, style: AppTextStyles.h3),
                  subtitle: Text(
                    registry.label(rule.selection.categoryId, rule.selection.subcategoryId),
                    style: AppTextStyles.caption,
                  ),
                  trailing: const Icon(Icons.edit_rounded, size: 18, color: AppColors.mutedText),
                  onTap: () => _change(context, ref, rule.merchant, rule.selection),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _change(
    BuildContext context,
    WidgetRef ref,
    String merchant,
    CategorySelection current,
  ) async {
    final picked = await showCategoryPicker(context, initial: current);
    if (picked == null) return;
    final notifier = ref.read(expenseNotifierProvider.notifier);
    await notifier.setMerchantRule(merchant, picked);
    // Keep existing transactions from this merchant consistent with the rule.
    await notifier.updateExpensesCategory(merchant, picked);
  }
}
