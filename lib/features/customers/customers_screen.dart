import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/providers/repository_providers.dart';

/// A customer in the business credit ledger (udhaar). [balance] is
/// sum(gave) - sum(got): positive means they owe you.
class Party {
  final String id;
  final String name;
  final String? phone;
  final String? gstin;
  final double balance;

  const Party({required this.id, required this.name, this.phone, this.gstin, required this.balance});

  factory Party.fromJson(Map<String, dynamic> j) => Party(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String?,
        gstin: j['gstin'] as String?,
        balance: switch (j['balance']) {
          num n => n.toDouble(),
          String s => double.tryParse(s) ?? 0,
          _ => 0,
        },
      );
}

/// Total the customers owe you (ignores advances).
double totalReceivable(List<Party> parties) =>
    parties.fold(0.0, (s, p) => p.balance > 0 ? s + p.balance : s);

/// The ledger lives on the server (no offline copy), so this needs a connection.
final partiesProvider = FutureProvider.autoDispose<List<Party>>((ref) async {
  final dio = ref.read(syncApiClientProvider).dio;
  final res = await dio.get('/parties');
  final list = (res.data as List).cast<Map<String, dynamic>>();
  return list.map(Party.fromJson).toList();
});

String _apiMessage(Object e, String fallback) {
  if (e is DioException) {
    final msg = e.response?.data is Map ? (e.response!.data as Map)['message'] : null;
    if (msg is String) return msg;
    if (msg is List && msg.isNotEmpty) return msg.first.toString();
    if (e.response == null) return "You're offline. Connect to the internet and try again.";
  }
  return fallback;
}

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  Future<void> _remind(BuildContext context, WidgetRef ref, Party p) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await ref.read(syncApiClientProvider).dio.get('/parties/${p.id}/reminder');
      final message = (res.data as Map)['message'] as String;
      await Clipboard.setData(ClipboardData(text: message));
      messenger.showSnackBar(SnackBar(
        content: Text('Reminder copied. Paste it in WhatsApp to +91 ${p.phone}.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_apiMessage(e, 'Could not create the reminder.'))));
    }
  }

  Future<void> _addCustomer(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile (optional)', prefixText: '+91 '),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    final n = name.text.trim();
    final ph = phone.text.trim();
    name.dispose();
    phone.dispose();
    if (ok != true || n.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(syncApiClientProvider).dio.post('/parties', data: {
        'name': n,
        if (ph.isNotEmpty) 'phone': ph,
      });
      ref.invalidate(partiesProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_apiMessage(e, 'Could not add the customer.'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parties = ref.watch(partiesProvider);
    final fmt = NumberFormat('#,##,##0.##', 'en_IN');

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Text('Customers', style: AppTextStyles.h2),
        backgroundColor: AppColors.pageBackground,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        onPressed: () => _addCustomer(context, ref),
        tooltip: 'Add customer',
        child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(partiesProvider.future),
        child: parties.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
          error: (_, __) => ListView(children: const [
            Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Text(
                "Couldn't load customers. You may be offline. Check your connection and pull to refresh.",
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
                    'No customers yet. Add the people you give goods or credit to, and track what they owe you.',
                    style: AppTextStyles.caption,
                    textAlign: TextAlign.center,
                  ),
                ),
              ]);
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenPadding, AppSpacing.sm, AppSpacing.screenPadding, AppSpacing.md),
                  child: Text('You will get ₹${fmt.format(totalReceivable(list))}', style: AppTextStyles.h3),
                ),
                for (final p in list)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.inputFill,
                      child: Text(
                        p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                        style: AppTextStyles.labelBold.copyWith(color: AppColors.primaryNavy),
                      ),
                    ),
                    title: Text(p.name, style: AppTextStyles.h3),
                    subtitle: Text(
                      p.balance > 0
                          ? 'You will get ₹${fmt.format(p.balance)}'
                          : p.balance < 0
                              ? 'Advance ₹${fmt.format(-p.balance)}'
                              : 'Settled',
                      style: AppTextStyles.caption.copyWith(
                        color: p.balance > 0
                            ? AppColors.incomeGreen
                            : p.balance < 0
                                ? AppColors.expenseRed
                                : AppColors.mutedText,
                      ),
                    ),
                    trailing: (p.balance > 0 && p.phone != null)
                        ? IconButton(
                            tooltip: 'Copy WhatsApp reminder',
                            icon: const Icon(Icons.chat_rounded, color: AppColors.incomeGreen),
                            onPressed: () => _remind(context, ref, p),
                          )
                        : null,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
