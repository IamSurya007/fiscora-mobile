import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../sync/sync_api_client.dart';

/// Version of the privacy notice shown in onboarding. Bump when it changes.
const consentVersion = 'v1';

/// Grievance officer published by the API (DPDP).
class GrievanceContact {
  final String? name;
  final String? email;
  const GrievanceContact({this.name, this.email});
}

/// DPDP data-principal actions: record consent, download data, delete account.
class PrivacyService {
  final SyncApiClient api;
  PrivacyService(this.api);

  /// Marker file holding the uid whose consent has not reached the server yet.
  static Future<File> _pendingFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/consent_pending');
  }

  /// Sends the onboarding consent. Never throws: a failure leaves a marker so
  /// [retryPendingConsent] sends it on the next launch.
  Future<void> recordConsent(String uid) async {
    try {
      await (await _pendingFile()).writeAsString(uid, flush: true);
    } catch (e) {
      debugPrint('Could not store pending consent: $e');
    }
    await retryPendingConsent(uid);
  }

  /// Sends a consent left pending by an earlier failed attempt for [uid].
  Future<void> retryPendingConsent(String uid) async {
    try {
      final file = await _pendingFile();
      if (!await file.exists()) return;
      if ((await file.readAsString()).trim() != uid) {
        await file.delete();
        return;
      }
      await api.dio.post('/users/me/consent', data: {'version': consentVersion, 'isAdult': true});
      await file.delete();
    } catch (e) {
      debugPrint('Consent not recorded yet, will retry next launch: $e');
    }
  }

  /// True when the server has no consent for the current notice version
  /// (existing users skipped onboarding, or the notice changed). False when
  /// offline, so the prompt never blocks using the app.
  Future<bool> needsConsent() async {
    try {
      final res = await api.dio.get('/users/me');
      final data = res.data;
      return data is Map && data['consentVersion'] != consentVersion;
    } catch (_) {
      return false;
    }
  }

  /// Downloads everything the server stores for the user and opens the share
  /// sheet with it as a JSON file.
  Future<void> exportMyData() async {
    final res = await api.dio.get('/users/me/export');
    final json = const JsonEncoder.withIndent('  ').convert(res.data);
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final filePath = '${tempDir.path}/Fiscora_MyData_$timestamp.json';
    await File(filePath).writeAsString(json, flush: true);
    await Share.shareXFiles(
      [XFile(filePath, mimeType: 'application/json')],
      subject: 'My Fiscora data',
    );
  }

  /// Permanently deletes the account and all its data on the server.
  Future<void> deleteAccount() async {
    await api.dio.delete('/users/me');
  }

  Future<GrievanceContact?> grievanceContact() async {
    final res = await api.dio.get('/privacy/contact');
    final officer = (res.data as Map?)?['grievanceOfficer'] as Map?;
    if (officer == null) return null;
    return GrievanceContact(name: officer['name'] as String?, email: officer['email'] as String?);
  }
}
