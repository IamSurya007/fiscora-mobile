import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/providers/repository_providers.dart';

/// Month in review from the API: totals vs last month, the categories that
/// moved most and the biggest purchases (same rules as the web page).
final monthReviewProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, month) async {
  final dio = ref.read(syncApiClientProvider).dio;
  final res = await dio.get('/insights/month-review', queryParameters: {'month': month});
  return Map<String, dynamic>.from(res.data as Map);
});

class MonthReviewScreen extends ConsumerStatefulWidget {
  const MonthReviewScreen({super.key});

  @override
  ConsumerState<MonthReviewScreen> createState() => _MonthReviewScreenState();
}

class _MonthReviewScreenState extends ConsumerState<MonthReviewScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final _fmt = NumberFormat('#,##,###');

  String get _key => DateFormat('yyyy-MM').format(_month);
  String _inr(num v) => '₹${_fmt.format(v.abs())}';

  String _change(num? pct) {
    if (pct == null) return 'no data last month';
    return '${pct > 0 ? '▲' : pct < 0 ? '▼' : ''} ${pct.abs()}% vs last month';
  }

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(monthReviewProvider(_key));
    final isCurrent = _month.year == DateTime.now().year && _month.month == DateTime.now().month;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Text('Month in review', style: AppTextStyles.h2),
        backgroundColor: AppColors.pageBackground,
        elevation: 0,
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              ),
              Text(DateFormat('MMMM yyyy').format(_month), style: AppTextStyles.h3),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: isCurrent ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              ),
            ],
          ),
          Expanded(
            child: review.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
              error: (_, __) => const Center(child: Text("Couldn't load the review. Check your connection.")),
              data: (r) {
                final spent = (r['spent'] as num? ?? 0);
                final income = (r['income'] as num? ?? 0);
                final net = (r['net'] as num? ?? 0);
                final up = r['biggestUp'] as Map?;
                final down = r['biggestDown'] as Map?;
                final cats = (r['topCategories'] as List? ?? const []).cast<Map>();
                final biggest = (r['biggest'] as List? ?? const []).cast<Map>();
                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.screenPadding),
                  children: [
                    _stat('Spent', _inr(spent), _change(r['spentChangePct'] as num?), AppColors.expenseRed),
                    _stat('Income', _inr(income), _change(r['incomeChangePct'] as num?), AppColors.incomeGreen),
                    _stat(
                      'Saved',
                      '${net < 0 ? '-' : ''}${_inr(net)}',
                      r['savingsRate'] == null ? 'no income recorded' : '${r['savingsRate']}% of income',
                      net >= 0 ? AppColors.incomeGreen : AppColors.expenseRed,
                    ),
                    if (up != null)
                      _note('${up['name']} went up the most: ${_inr(up['spent'] as num)} '
                          '(${_inr(up['change'] as num)} more).'),
                    if (down != null)
                      _note('${down['name']} dropped the most: ${_inr(down['spent'] as num)} '
                          '(${_inr(down['change'] as num)} less).'),
                    const SizedBox(height: AppSpacing.md),
                    Text('Top categories', style: AppTextStyles.h3),
                    for (final c in cats)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${c['name']}'),
                        trailing: Text(_inr(c['spent'] as num), style: AppTextStyles.labelBold),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    Text('Biggest purchases', style: AppTextStyles.h3),
                    for (final b in biggest)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${b['merchant']}'),
                        subtitle: Text('${b['date']} · ${b['category']}', style: AppTextStyles.caption),
                        trailing: Text(_inr(b['amount'] as num), style: AppTextStyles.labelBold),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, String sub, Color color) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppTextStyles.label)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value, style: AppTextStyles.h2.copyWith(color: color)),
                  Text(sub, style: AppTextStyles.caption),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Text(text, style: AppTextStyles.bodyMedium),
      );
}
