import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_shell.dart';
import 'core/models/user_profile.dart';
import 'core/providers/repository_providers.dart';
import 'core/services/seed_service.dart';
import 'core/sync/sync_engine.dart';
import 'features/categories/services/category_providers.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/data/repository/auth_repository_impl.dart';
import 'features/ai_chat/providers/rag_chat_provider.dart';
import 'core/sync/isar_database.dart';
import 'core/sync/collections/user_profile_collection.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:isar_plus/isar_plus.dart';
import 'core/services/push_service.dart';
import 'core/services/privacy_service.dart';
import 'features/onboarding/onboarding_screen.dart';

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = FirebaseAuth.instance.currentUser;
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data ?? currentUser;
        if (user != null) {
          return _AuthenticatedApp(
            key: ValueKey(user.uid),
            user: user,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

/// Handles post-auth setup (user profile + seeding) before showing AppShell.
/// Uses [ConsumerStatefulWidget] so it can read repository providers.
class _AuthenticatedApp extends ConsumerStatefulWidget {
  final User user;
  const _AuthenticatedApp({super.key, required this.user});

  @override
  ConsumerState<_AuthenticatedApp> createState() => _AuthenticatedAppState();
}

void resetAuthSetup() {
  _AuthenticatedAppState._completedSetupUid = null;
}

/// Drops in-memory per-user state (AI chat and its history).
void _resetUserScopedProviders(WidgetRef ref) {
  ref.invalidate(ragChatNotifierProvider);
  ref.invalidate(chatHistoryProvider);
}

/// Signs out and wipes everything this device holds for the user. Sync is
/// suspended first so a pending debounced sync can't repopulate the database.
Future<void> signOutAndClearLocalData(WidgetRef ref) async {
  resetAuthSetup();
  try {
    await SyncEngine.instance.suspend();
  } on StateError {
    // Sync engine never initialised; nothing to stop.
  }
  await PushService.instance.unregister();
  await IsarDatabase.clearAll();
  _resetUserScopedProviders(ref);
  await AuthRepositoryImpl().signOut();
}

/// The local database is not partitioned by user. If it holds another
/// account's profile (the session ended without the Profile sign-out, e.g. a
/// revoked token), wipe it so this user never sees, or uploads, that data.
Future<void> _wipeIfOwnedByAnotherUser(String uid) async {
  final isar = IsarDatabase.instance.isar;
  final others = await isar.userProfileCollections
      .where()
      .not()
      .uidEqualTo(uid)
      .count();
  if (others > 0) await IsarDatabase.clearAll();
}

class _AuthenticatedAppState extends ConsumerState<_AuthenticatedApp> {
  late bool _ready;
  bool _needsOnboarding = false;
  static String? _completedSetupUid;

  @override
  void initState() {
    super.initState();
    if (_completedSetupUid == widget.user.uid) {
      _ready = true;
    } else {
      _ready = false;
      _setup();
    }
  }

  Future<void> _setup() async {
    try {
      await _runSetup();
    } catch (e, st) {
      // Never leave an offline-first app stuck on the splash screen.
      debugPrint('Post-auth setup failed: $e\n$st');
    }
    _completedSetupUid = widget.user.uid;
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _runSetup() async {
    // Refresh the token for the API client; offline launches continue without it.
    try {
      await widget.user.getIdToken();
    } catch (e) {
      debugPrint('Token refresh failed (offline?): $e');
    }

    await _wipeIfOwnedByAnotherUser(widget.user.uid);
    _resetUserScopedProviders(ref);

    // Read repos via Riverpod — injected through repository_providers.dart.
    final userRepo = ref.read(userRepositoryProvider);
    final expenseRepo = ref.read(expenseRepositoryProvider);
    final loanRepo = ref.read(loanRepositoryProvider);
    final investmentRepo = ref.read(investmentRepositoryProvider);

    // Ensure the user document exists in the backing store.
    await userRepo.ensureUserProfile(UserProfile(
      uid: widget.user.uid,
      name: widget.user.displayName ?? '',
      email: widget.user.email ?? '',
      photoUrl: widget.user.photoURL ?? '',
    ));

    // Initialize Sync Engine
    final syncClient = ref.read(syncApiClientProvider);
    SyncEngine.init(syncClient);
    SyncEngine.instance.resume();

    // Give records that only carry an old category name their category ids.
    // Idempotent and cheap once done.
    await ref.read(categoryRepositoryProvider).migrateLegacyCategories();

    // Seed demo data once (no-op on subsequent launches).
    await SeedService(
      userRepo: userRepo,
      expenseRepo: expenseRepo,
      loanRepo: loanRepo,
      investmentRepo: investmentRepo,
    ).seedIfNeeded();
    
    // Trigger initial pull/push sync in background
    SyncEngine.instance.triggerSync();

    // First run on this device: onboarding, unless this account already has
    // data here (existing users upgrading skip it).
    final userRepoForOnboarding = ref.read(userRepositoryProvider);
    if (!await userRepoForOnboarding.isOnboarded(widget.user.uid)) {
      final hasData = (await expenseRepo.getAllExpenseIds()).isNotEmpty;
      if (hasData) {
        await userRepoForOnboarding.markOnboarded(widget.user.uid);
      } else {
        _needsOnboarding = true;
      }
    }

    // Budget alerts and reminders from the server (not awaited: the prompt
    // must not hold the splash screen).
    unawaited(PushService.instance.register(syncClient));

    // Consent from onboarding that failed to reach the server last time.
    unawaited(PrivacyService(syncClient).retryPendingConsent(widget.user.uid));
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const _SplashScreen();
    if (_needsOnboarding) {
      return OnboardingScreen(onDone: () async {
        await ref.read(userRepositoryProvider).markOnboarded(widget.user.uid);
        if (mounted) setState(() => _needsOnboarding = false);
      });
    }
    return AppShell(user: widget.user);
  }
}

// ─────────────────────────────────────────────
// Splash shown while Firebase initialises / seeding runs
// ─────────────────────────────────────────────

/// Shown while post-sign-in setup runs. Continues the native launch screen
/// (same navy and logo), then eases in the wordmark and a slim progress bar
/// so the hand-off from the system splash is seamless.
class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> with SingleTickerProviderStateMixin {
  static const _navy = Color(0xFF0A2540);
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final logoScale = Tween(begin: 1.0, end: 0.86)
        .animate(CurvedAnimation(parent: _c, curve: const Interval(0, 0.6, curve: Curves.easeOutCubic)));
    final textFade = CurvedAnimation(parent: _c, curve: const Interval(0.35, 1, curve: Curves.easeOut));

    return Scaffold(
      backgroundColor: _navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: reduceMotion ? const AlwaysStoppedAnimation(0.86) : logoScale,
              child: Image.asset('assets/images/splash_logo.png', width: 220, height: 220),
            ),
            FadeTransition(
              opacity: reduceMotion ? const AlwaysStoppedAnimation(1.0) : textFade,
              child: Column(
                children: [
                  const Text(
                    'Fiscora',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your money, in one place',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        color: const Color(0xFF007BFF),
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
