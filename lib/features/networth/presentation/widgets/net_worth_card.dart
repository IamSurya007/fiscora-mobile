import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../services/networth_providers.dart';
import '../screens/net_worth_screen.dart';
import 'net_worth_sparkline.dart';

String formatRupees(double v) {
  final s = '₹${NumberFormat('#,##,###').format(v.abs())}';
  return v < 0 ? '-$s' : s;
}

/// Home card: current net worth with a sparkline of the server history.
/// Offline it shows the sum of local account balances and no chart.
class NetWorthCard extends ConsumerWidget {
  const NetWorthCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(netWorthRemoteProvider);
    final local = ref.watch(localNetWorthProvider);
    final data = remote.valueOrNull;
    final summary = data?.current ?? local;
    final history = data?.history ?? const [];
    final color = summary.netWorth >= 0 ? AppColors.incomeGreen : AppColors.expenseRed;

    String? subtitle;
    if (remote.isLoading && data == null) {
      subtitle = 'Updating…';
    } else if (data == null) {
      subtitle = 'Offline · accounts on this device only';
    } else if (history.length >= 2) {
      final change = history.last.netWorth - history.first.netWorth;
      subtitle = '${change >= 0 ? '+' : '-'}${formatRupees(change.abs())} since ${_shortDate(history.first.date)}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, AppSpacing.md, AppSpacing.screenPadding, 0),
      child: Material(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          onTap: () {
            // Retry the server figures if the last attempt failed (offline).
            if (data == null && !remote.isLoading) ref.invalidate(netWorthRemoteProvider);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NetWorthScreen()),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Net worth', style: AppTextStyles.label),
                      const SizedBox(height: 4),
                      Text(formatRupees(summary.netWorth), style: AppTextStyles.h2),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle, style: AppTextStyles.caption),
                      ],
                    ],
                  ),
                ),
                if (data != null && history.length >= 2)
                  SizedBox(
                    width: 110,
                    child: NetWorthSparkline(points: history, color: color, height: 44),
                  ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.chevron_right_rounded, color: AppColors.mutedText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _shortDate(String ymd) {
  final d = DateTime.tryParse(ymd);
  return d == null ? ymd : DateFormat('d MMM').format(d);
}
