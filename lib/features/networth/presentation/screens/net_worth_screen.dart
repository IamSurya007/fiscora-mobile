import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../models/net_worth.dart';
import '../../services/networth_providers.dart';
import '../widgets/net_worth_card.dart' show formatRupees;
import '../widgets/net_worth_sparkline.dart';

const _typeLabels = {
  'bank': 'Bank accounts',
  'cash': 'Cash',
  'wallet': 'Wallets',
  'other': 'Other accounts',
  'investments': 'Investments',
  'loansGiven': 'Loans given',
  'creditCards': 'Credit cards',
  'loansTaken': 'Loans taken',
};
const _assetKeys = ['bank', 'cash', 'wallet', 'other', 'investments', 'loansGiven'];
const _liabilityKeys = ['creditCards', 'loansTaken'];

/// Net worth with a trend chart and the assets/liabilities breakdown.
class NetWorthScreen extends ConsumerWidget {
  const NetWorthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(netWorthRemoteProvider);
    final local = ref.watch(localNetWorthProvider);
    final data = remote.valueOrNull;
    final summary = data?.current ?? local;
    final history = data?.history ?? const <NetWorthPoint>[];
    final color = summary.netWorth >= 0 ? AppColors.incomeGreen : AppColors.expenseRed;

    final assetLines = [
      ...summary.accounts.where((l) => !l.isLiability),
      ...summary.investments,
      ...summary.loans.where((l) => !l.isLiability),
    ];
    final liabilityLines = [
      ...summary.accounts.where((l) => l.isLiability),
      ...summary.loans.where((l) => l.isLiability),
    ];

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('Net worth'),
        backgroundColor: AppColors.pageBackground,
        elevation: 0,
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () => ref.refresh(netWorthRemoteProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          children: [
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Net worth', style: AppTextStyles.label),
                  const SizedBox(height: 4),
                  Text(
                    formatRupees(summary.netWorth),
                    style: AppTextStyles.balanceLarge.copyWith(color: color),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(child: _Stat('Assets', summary.assets, AppColors.incomeGreen)),
                      Expanded(child: _Stat('Liabilities', summary.liabilities, AppColors.expenseRed)),
                    ],
                  ),
                  if (summary.isLocal) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      remote.isLoading
                          ? 'Loading full figures…'
                          : 'Offline: showing account balances on this device. Investments, loans and history need a connection.',
                      style: AppTextStyles.caption,
                    ),
                  ],
                  if (history.length >= 2) ...[
                    const SizedBox(height: AppSpacing.md),
                    NetWorthSparkline(points: history, color: color, height: 140, interactive: true),
                    const SizedBox(height: 4),
                    Text(
                      '${history.length} days of history',
                      style: AppTextStyles.caption,
                    ),
                  ] else if (data != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'A trend appears after a few daily snapshots.',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ],
              ),
            ),
            if (summary.byType.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('By type', style: AppTextStyles.h3),
                    const SizedBox(height: AppSpacing.sm),
                    for (final k in [..._assetKeys, ..._liabilityKeys])
                      if ((summary.byType[k] ?? 0) != 0)
                        _Row(_typeLabels[k] ?? k, summary.byType[k]!, _liabilityKeys.contains(k)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            _Section('Assets', assetLines, false),
            const SizedBox(height: AppSpacing.md),
            _Section('Liabilities', liabilityLines, true),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: child,
      );
}

class _Stat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _Stat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          Text(formatRupees(value), style: AppTextStyles.labelBold.copyWith(color: color)),
        ],
      );
}

class _Row extends StatelessWidget {
  final String label;
  final double value;
  final bool liability;
  const _Row(this.label, this.value, this.liability);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTextStyles.bodyMedium)),
            Text(
              formatRupees(value),
              style: AppTextStyles.labelBold.copyWith(
                color: liability ? AppColors.expenseRed : AppColors.primaryNavy,
              ),
            ),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final List<NetWorthLine> lines;
  final bool liability;
  const _Section(this.title, this.lines, this.liability);

  @override
  Widget build(BuildContext context) => _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.h3),
            const SizedBox(height: AppSpacing.sm),
            if (lines.isEmpty)
              Text('None', style: AppTextStyles.caption)
            else
              for (final l in lines) _Row(l.name, l.value, liability),
          ],
        ),
      );
}
