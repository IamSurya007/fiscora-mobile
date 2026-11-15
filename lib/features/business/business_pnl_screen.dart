import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/providers/repository_providers.dart';

/// One expense category of the business P&L.
class PnlCategory {
  final String categoryId;
  final String name;
  final double total;
  final int count;
  const PnlCategory(this.categoryId, this.name, this.total, this.count);
}

/// Business profit and loss as computed by the API (GET /business/pnl).
class BusinessPnl {
  final double revenue;
  final double expenses;
  final double netProfit;
  final double ownerDraws;
  final double owedToYou;
  final List<PnlCategory> expensesByCategory;

  const BusinessPnl({
    required this.revenue,
    required this.expenses,
    required this.netProfit,
    required this.ownerDraws,
    required this.owedToYou,
    required this.expensesByCategory,
  });

  static double _n(Object? v) => (v as num?)?.toDouble() ?? 0;

  factory BusinessPnl.fromJson(Map<String, dynamic> json) => BusinessPnl(
        revenue: _n(json['revenue']),
        expenses: _n(json['expenses']),
        netProfit: _n(json['netProfit']),
        ownerDraws: _n(json['ownerDraws']),
        owedToYou: _n(json['owedToYou']),
        expensesByCategory: [
          for (final c in (json['expensesByCategory'] as List? ?? const []).cast<Map>())
            PnlCategory(
              '${c['categoryId'] ?? ''}',
              '${c['category'] ?? c['categoryId'] ?? 'Other'}',
              _n(c['total']),
              (c['count'] as num?)?.toInt() ?? 0,
            ),
        ],
      );
}

final businessPnlProvider =
    FutureProvider.autoDispose.family<BusinessPnl, String>((ref, month) async {
  final dio = ref.read(syncApiClientProvider).dio;
  final res = await dio.get('/business/pnl', queryParameters: {'month': month});
  return BusinessPnl.fromJson(Map<String, dynamic>.from(res.data as Map));
});

/// Business P&L for a month: revenue, expenses by category, net profit, what
/// you drew out and what the business owes you.
class BusinessPnlScreen extends ConsumerStatefulWidget {
  const BusinessPnlScreen({super.key});

  @override
  ConsumerState<BusinessPnlScreen> createState() => _BusinessPnlScreenState();
}

class _BusinessPnlScreenState extends ConsumerState<BusinessPnlScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final _fmt = NumberFormat('#,##,###');

  String get _key => DateFormat('yyyy-MM').format(_month);
  String _inr(num v) => '${v < 0 ? '-' : ''}₹${_fmt.format(v.abs().round())}';

  @override
  Widget build(BuildContext context) {
    final pnl = ref.watch(businessPnlProvider(_key));
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Text('Business', style: AppTextStyles.h2),
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
                onPressed: isCurrent
                    ? null
                    : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              ),
            ],
          ),
          Expanded(
            child: pnl.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
              error: (_, __) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.mutedText),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        "You're offline or the server can't be reached. The business P&L needs a connection.",
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(businessPnlProvider(_key)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (p) => RefreshIndicator(
                onRefresh: () => ref.refresh(businessPnlProvider(_key).future),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.screenPadding),
                  children: [
                    _row('Revenue', p.revenue, bold: true, color: AppColors.incomeGreen),
                    const SizedBox(height: AppSpacing.sm),
                    Text('Expenses', style: AppTextStyles.h3),
                    if (p.expensesByCategory.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: Text('No business expenses this month', style: AppTextStyles.caption),
                      ),
                    for (final c in p.expensesByCategory) _row(c.name, c.total),
                    _row('Total expenses', p.expenses, bold: true, color: AppColors.expenseRed),
                    const Divider(),
                    _row('Net profit', p.netProfit,
                        bold: true,
                        color: p.netProfit >= 0 ? AppColors.incomeGreen : AppColors.expenseRed),
                    const Divider(),
                    _row('Owner draws', p.ownerDraws),
                    Text('Moved from business to personal accounts', style: AppTextStyles.caption),
                    const SizedBox(height: AppSpacing.sm),
                    _row('Owed to you by the business', p.owedToYou),
                    Text('Business expenses you paid from personal accounts',
                        style: AppTextStyles.caption),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, double value, {bool bold = false, Color? color}) {
    final style = bold ? AppTextStyles.labelBold : AppTextStyles.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(_inr(value), style: style.copyWith(color: color)),
        ],
      ),
    );
  }
}
