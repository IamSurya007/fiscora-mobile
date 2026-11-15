import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../accounts/services/account_providers.dart';
import '../models/net_worth.dart';

/// Net worth and history from the API, or null when it cannot be reached
/// (offline, signed out, server error). Invalidate to refresh.
final netWorthRemoteProvider = FutureProvider<NetWorthData?>((ref) async {
  final dio = ref.read(syncApiClientProvider).dio;
  try {
    final results = await Future.wait([
      dio.get('/networth'),
      dio.get('/networth/history', queryParameters: {'days': 365}),
    ]);
    final current = NetWorthSummary.fromJson(
      (results[0].data as Map).cast<String, dynamic>(),
    );
    final history = ((results[1].data as List?) ?? const [])
        .whereType<Map>()
        .map((m) => NetWorthPoint.fromJson(m.cast<String, dynamic>()))
        .toList();
    return NetWorthData(current: current, history: history);
  } catch (e) {
    debugPrint('Could not load net worth: $e');
    return null;
  }
});

/// Locally derivable net worth (sum of account balances on this device).
final localNetWorthProvider = Provider<NetWorthSummary>((ref) {
  final accounts = ref.watch(accountsStreamProvider).valueOrNull ?? const [];
  return NetWorthSummary.fromAccounts(accounts);
});
