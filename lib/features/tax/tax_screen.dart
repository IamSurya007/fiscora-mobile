import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/providers/repository_providers.dart';

/// "2026-27" for the IST financial year (1 Apr – 31 Mar) containing [now].
String fyOf(DateTime now) {
  final ist = now.toUtc().add(const Duration(hours: 5, minutes: 30));
  final start = ist.month >= 4 ? ist.year : ist.year - 1;
  return '$start-${((start + 1) % 100).toString().padLeft(2, '0')}';
}

/// Tax summary for an FY from the API (estimates; see fiscora-api src/tax).
final taxSummaryProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, fy) async {
  final dio = ref.read(syncApiClientProvider).dio;
  final res = await dio.get('/tax/summary', queryParameters: {'fy': fy});
  return Map<String, dynamic>.from(res.data as Map);
});

class TaxScreen extends ConsumerWidget {
  const TaxScreen({super.key});

  static final _fmt = NumberFormat('#,##,###');
  static String _inr(num v) => '₹${_fmt.format(v.round())}';

  Color _levelColor(String? level) => switch (level) {
        'exceeded' => AppColors.expenseRed,
        'warning' => Colors.orange.shade700,
        _ => AppColors.incomeGreen,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fy = fyOf(DateTime.now());
    final summary = ref.watch(taxSummaryProvider(fy));

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Text('Tax helper · FY $fy', style: AppTextStyles.h2),
        backgroundColor: AppColors.pageBackground,
        elevation: 0,
      ),
      body: summary.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("You're offline or the server couldn't be reached. The tax summary needs a connection.",
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                TextButton(onPressed: () => ref.invalidate(taxSummaryProvider(fy)), child: const Text('Retry')),
              ],
            ),
          ),
        ),
        data: (s) {
          final receipts = Map<String, dynamic>.from(s['receipts'] as Map? ?? const {});
          final setAside = Map<String, dynamic>.from(s['setAside'] as Map? ?? const {});
          final adv = Map<String, dynamic>.from(s['advanceTax'] as Map? ?? const {});
          final tds = Map<String, dynamic>.from(s['tds'] as Map? ?? const {});
          final meters = (s['meters'] as List? ?? const []).cast<Map>();
          final schedule = (adv['schedule'] as List? ?? const []).cast<Map>();
          final next = adv['next'] as Map?;
          final presumptive = s['presumptiveIncome'] as num?;
          final annual = (adv['estimatedAnnualTax'] as num? ?? 0);
          final cashShare = (receipts['cashShare'] as num? ?? 0) * 100;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(taxSummaryProvider(fy)),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Text(
                    'Estimates only, not tax advice. Verify on incometax.gov.in / cbic-gst.gov.in or with your CA.',
                    style: AppTextStyles.caption,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                _stat('Gross business receipts', _inr(receipts['gross'] as num? ?? 0),
                    '${receipts['count'] ?? 0} receipts · cash ${cashShare.toStringAsFixed(1)}%'),
                _stat(
                  'Presumptive income (est.)',
                  presumptive == null ? '—' : _inr(presumptive),
                  presumptive == null ? 'Regular regime' : 'Section ${s['regime']}',
                ),
                _stat('Set aside for tax', _inr(setAside['amount'] as num? ?? 0), '${setAside['percent'] ?? 20}% of receipts'),
                _stat('TDS deducted', _inr(tds['total'] as num? ?? 0), 'Check against Form 26AS / AIS'),
                const SizedBox(height: AppSpacing.md),
                Text('Thresholds', style: AppTextStyles.h3),
                const SizedBox(height: AppSpacing.sm),
                for (final m in meters)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m['label']}', style: AppTextStyles.label),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: ((m['percent'] as num? ?? 0) / 100).clamp(0, 1).toDouble(),
                          color: _levelColor(m['level'] as String?),
                          backgroundColor: AppColors.borderLight,
                          minHeight: 6,
                        ),
                        const SizedBox(height: 4),
                        Text('${m['percent']}% · ${_inr(m['value'] as num? ?? 0)} of ${_inr(m['limit'] as num? ?? 0)}',
                            style: AppTextStyles.caption),
                        if (m['message'] != null)
                          Text('${m['message']}',
                              style: AppTextStyles.caption.copyWith(color: _levelColor(m['level'] as String?))),
                      ],
                    ),
                  ),
                Text('Advance tax', style: AppTextStyles.h3),
                Text(
                  adv['presumptiveRule'] == true
                      ? 'Presumptive (44AD/44ADA): you may pay 100% by 15 March.'
                      : 'Regular instalments: 15% / 45% / 75% / 100%.',
                  style: AppTextStyles.caption,
                ),
                Text('Estimated tax for the year: ${_inr(annual)}', style: AppTextStyles.caption),
                for (final d in schedule)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      next != null && next['date'] == d['date'] ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: AppColors.accent,
                    ),
                    title: Text(DateFormat('d MMM yyyy').format(DateTime.parse('${d['date']}'))),
                    subtitle: Text('${d['cumulativePercent']}% cumulative'),
                    trailing: Text(_inr(annual * (d['cumulativePercent'] as num) / 100), style: AppTextStyles.labelBold),
                  ),
                const SizedBox(height: AppSpacing.md),
                Text('Edit your tax profile and download the CSV for your CA on the web app.', style: AppTextStyles.caption),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value, String sub) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Expanded(child: Text(label, style: AppTextStyles.label)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(value, style: AppTextStyles.h2),
                  Text(sub, style: AppTextStyles.caption),
                ],
              ),
            ],
          ),
        ),
      );
}
