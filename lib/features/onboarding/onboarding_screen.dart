import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/providers/repository_providers.dart';
import '../../core/services/privacy_service.dart';
import '../accounts/services/account_providers.dart';
import '../expenses/screens/sms_scan_sheet.dart';

/// First run: what Fiscora reads and why, the SMS permission with that
/// context, an optional scan of past bank SMS, and a check of the accounts it
/// found with their real balances. New users used to land on an empty Home
/// with no explanation and no permission prompt.
class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _consented = false;
  bool _isAdult = false;
  bool _smsGranted = false;

  void _next() {
    if (_page >= 2) {
      widget.onDone();
      return;
    }
    _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  /// Records consent on the server without holding up onboarding; a failure
  /// is retried on the next launch.
  void _acceptPrivacy() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      unawaited(PrivacyService(ref.read(syncApiClientProvider)).recordConsent(uid));
    }
    _next();
  }

  Future<void> _askSms() async {
    final status = await Permission.sms.request();
    if (!mounted) return;
    setState(() => _smsGranted = status.isGranted);
    if (status.isGranted) {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const SmsScanSheet(),
      );
      if (mounted) _next();
    } else if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screenPadding, AppSpacing.md, AppSpacing.screenPadding, 0),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i <= _page ? AppColors.primaryNavy : AppColors.borderLight,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  _privacyPage(),
                  _smsPage(),
                  const _AccountsPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _privacyPage() {
    return _Step(
      icon: Icons.verified_user_rounded,
      title: 'Your money, your data',
      body: const [
        'Fiscora reads bank and card SMS to record transactions for you. Each message is parsed on this phone; '
            'only the transaction details (amount, date, merchant, account) are synced to your Fiscora account.',
        'Personal messages and OTPs are never uploaded. Fiscora shows no ads, offers no loans, and never sells your data.',
        'You can export or delete everything from Profile at any time.',
      ],
      footer: Column(
        children: [
          CheckboxListTile(
            value: _consented,
            onChanged: (v) => setState(() => _consented = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('I agree to Fiscora processing my transaction data as described above.',
                style: AppTextStyles.bodySmall),
          ),
          CheckboxListTile(
            value: _isAdult,
            onChanged: (v) => setState(() => _isAdult = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('I confirm I am 18 years of age or older.', style: AppTextStyles.bodySmall),
          ),
          _PrimaryButton(label: 'Continue', onPressed: _consented && _isAdult ? _acceptPrivacy : null),
        ],
      ),
    );
  }

  Widget _smsPage() {
    return _Step(
      icon: Icons.sms_rounded,
      title: 'Capture transactions automatically',
      body: const [
        'Allow SMS access and Fiscora records new bank and UPI transactions as they arrive. '
            'They land in a review inbox so you can confirm or fix each one.',
        'You can also import your recent bank SMS now to start with a full picture.',
      ],
      footer: Column(
        children: [
          _PrimaryButton(
            label: _smsGranted ? 'Import recent SMS' : 'Allow SMS access',
            onPressed: _askSms,
          ),
          TextButton(onPressed: _next, child: const Text("Not now, I'll add transactions myself")),
        ],
      ),
    );
  }
}

/// Accounts found (from SMS or added manually), with their balance today.
/// Entering the real balance sets the starting point; later transactions keep
/// it up to date.
class _AccountsPage extends ConsumerWidget {
  const _AccountsPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? const [];
    final fmt = NumberFormat('#,##,###.##');
    final state = context.findAncestorStateOfType<_OnboardingScreenState>();

    return _Step(
      icon: Icons.account_balance_wallet_rounded,
      title: accounts.isEmpty ? 'Add your accounts later' : 'Check your balances',
      body: [
        accounts.isEmpty
            ? 'No accounts yet. They are created automatically from your bank SMS, or you can add them from Home.'
            : 'Tap an account to enter its balance today (for a card, the amount you owe).',
      ],
      content: accounts.isEmpty
          ? null
          : Column(
              children: [
                for (final a in accounts)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(a.type.icon, color: Color(a.colorValue)),
                    title: Text(a.name, style: AppTextStyles.h3),
                    trailing: Text('₹${fmt.format(a.currentBalance)}', style: AppTextStyles.labelBold),
                    onTap: () async {
                      final controller = TextEditingController(text: a.currentBalance.toStringAsFixed(2));
                      final value = await showDialog<double>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(a.isCreditCard ? 'Amount owed on ${a.name}' : 'Balance of ${a.name}'),
                          content: TextField(
                            controller: controller,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(prefixText: '₹ '),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, double.tryParse(controller.text.replaceAll(',', ''))),
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      );
                      controller.dispose();
                      if (value != null) {
                        await ref.read(accountNotifierProvider.notifier).updateAccountBalance(a.id, value);
                      }
                    },
                  ),
              ],
            ),
      footer: _PrimaryButton(label: 'Start using Fiscora', onPressed: () => state?._next()),
    );
  }
}

class _Step extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> body;
  final Widget? content;
  final Widget footer;

  const _Step({required this.icon, required this.title, required this.body, this.content, required this.footer});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: AppSpacing.lg),
                Icon(icon, size: 44, color: AppColors.accent),
                const SizedBox(height: AppSpacing.md),
                Text(title, style: AppTextStyles.h1),
                const SizedBox(height: AppSpacing.md),
                for (final p in body) ...[
                  Text(p, style: AppTextStyles.bodyMedium.copyWith(height: 1.5)),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (content != null) ...[const SizedBox(height: AppSpacing.sm), content!],
              ],
            ),
          ),
          footer,
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _PrimaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.cardRadius)),
        ),
        child: Text(label, style: AppTextStyles.buttonText),
      ),
    );
  }
}
