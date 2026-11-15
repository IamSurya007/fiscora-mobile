import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/providers/repository_providers.dart';

/// One expected payment: a detected subscription/recurring charge, a credit
/// card bill (from the card's due day) or a loan due date.
class UpcomingBill {
  final String kind; // recurring | card | loan
  final String name;
  final double amount;
  final DateTime dueDate;
  final String? cadence;

  UpcomingBill.fromJson(Map<String, dynamic> j)
      : kind = j['kind'] as String? ?? 'recurring',
        name = j['name'] as String? ?? '',
        amount = (j['amount'] as num? ?? 0).toDouble(),
        dueDate = DateTime.parse(j['dueDate'] as String),
        cadence = j['cadence'] as String?;
}

/// Bills are worked out on the server from the full history, so this needs a
/// connection; offline the screen says so instead of showing a stale guess.
final upcomingBillsProvider = FutureProvider.autoDispose<List<UpcomingBill>>((ref) async {
  final dio = ref.read(syncApiClientProvider).dio;
  final res = await dio.get('/bills/upcoming', queryParameters: {'days': 45});
  final list = (res.data as List).cast<Map<String, dynamic>>();
  return list.map(UpcomingBill.fromJson).toList();
});

class UpcomingBillsScreen extends ConsumerWidget {
  const UpcomingBillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(upcomingBillsProvider);
    final fmt = NumberFormat('#,##,###');

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Text('Upcoming bills', style: AppTextStyles.h2),
        backgroundColor: AppColors.pageBackground,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(upcomingBillsProvider.future),
        child: bills.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
          error: (_, __) => ListView(children: const [
            Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Text(
                "Couldn't load bills. Check your connection and pull to refresh.",
                textAlign: TextAlign.center,
              ),
            ),
          ]),
          data: (list) {
            if (list.isEmpty) {
              return ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Text(
                    'Nothing due in the next 45 days. Subscriptions show up here once Fiscora has seen '
                    'them a few times; add a due day to your credit cards to see card bills.',
                    style: AppTextStyles.caption,
                    textAlign: TextAlign.center,
                  ),
                ),
              ]);
            }
            final total = list.fold(0.0, (s, b) => s + b.amount);
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding, AppSpacing.sm, AppSpacing.screenPadding, AppSpacing.md),
                  child: Text('₹${fmt.format(total)} due in the next 45 days', style: AppTextStyles.h3),
                ),
                for (final b in list)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.inputFill,
                      child: Icon(
                        switch (b.kind) {
                          'card' => Icons.credit_card_rounded,
                          'loan' => Icons.handshake_rounded,
                          _ => Icons.autorenew_rounded,
                        },
                        color: AppColors.primaryNavy,
                      ),
                    ),
                    title: Text(b.name, style: AppTextStyles.h3),
                    subtitle: Text(
                      [
                        DateFormat('EEE, d MMM').format(b.dueDate),
                        if (b.kind == 'card') 'card bill',
                        if (b.kind == 'loan') 'loan due',
                        if (b.cadence != null) b.cadence!,
                      ].join(' · '),
                      style: AppTextStyles.caption,
                    ),
                    trailing: Text('₹${fmt.format(b.amount)}', style: AppTextStyles.labelBold),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
