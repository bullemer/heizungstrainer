import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:heizungstrainer/app_version.dart';
import 'package:heizungstrainer/services/play_store.dart';
import 'package:in_app_review/in_app_review.dart';

/// What kind of feedback the user sends.
enum FeedbackKind {
  praise('Lob', 'praise'),
  idea('Idee / Wunsch', 'idea'),
  problem('Problem', 'problem');

  const FeedbackKind(this.label, this.code);
  final String label;
  final String code;
}

/// Sends in-app feedback to the backoffice (Fehlerberichte list, severity =
/// kind) and asks Play for a rating at a good moment.
class FeedbackService {
  static const String endpoint = 'https://bo.heizungstrainer.de/api/v1/feedback/bug';
  static const String forumUrl = 'https://heizungstrainer.de/forum/';

  // Same app key as diagnostics (backoffice APP_INGEST_KEY).
  static const String _appKey = 'ht_backoffice_secret_2026';

  static const String _writesKey = 'ht_review_successful_writes';
  static const String _firstUseKey = 'ht_review_first_use';
  static const String _lastAskedKey = 'ht_review_last_asked';

  /// Successful writes before the first rating request.
  static const int writesBeforeAsking = 3;
  static const Duration minUsage = Duration(days: 3);
  static const Duration askAgainAfter = Duration(days: 120);

  final FlutterSecureStorage _storage;
  final Map<String, String>? _memory;
  final InAppReview? _review;
  final bool _reviewEnabled;

  FeedbackService({
    FlutterSecureStorage? storage,
    Map<String, String>? inMemoryStorage,
    @visibleForTesting InAppReview? review,
    bool? reviewEnabled,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _memory = inMemoryStorage,
        _review = review ?? (inMemoryStorage == null ? InAppReview.instance : null),
        _reviewEnabled = reviewEnabled ?? isPlayBuild;

  /// Builds the backoffice payload (bug-report schema).
  static Map<String, dynamic> buildPayload({
    required FeedbackKind kind,
    required String message,
    String? email,
    String? controllerBrand,
    String? controllerModel,
  }) {
    final text = message.trim();
    final firstLine = text.split('\n').first;
    final title = firstLine.length > 80 ? '${firstLine.substring(0, 80)}…' : firstLine;
    final mail = email?.trim();
    return {
      'title': 'App-Feedback (${kind.label}): $title',
      'description': text,
      'controller_brand': controllerBrand,
      'controller_model': controllerModel,
      'app_version': '$appVersionLabel${isPlayBuild ? ' Play' : ''}',
      'os_platform': _platformLabel(),
      'user_email': (mail == null || mail.isEmpty) ? null : mail,
      'severity': 'feedback_${kind.code}',
    };
  }

  static String _platformLabel() {
    final label = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    return label.length > 64 ? label.substring(0, 64) : label;
  }

  /// Sends feedback; returns null on success or a German error message.
  Future<String?> send({
    required FeedbackKind kind,
    required String message,
    String? email,
    String? controllerBrand,
    String? controllerModel,
  }) async {
    if (message.trim().length < 3) return 'Bitte schreib uns ein paar Worte.';
    final payload = buildPayload(
      kind: kind,
      message: message,
      email: email,
      controllerBrand: controllerBrand,
      controllerModel: controllerModel,
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(Uri.parse(endpoint));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set('X-API-Key', _appKey);
      request.add(utf8.encode(jsonEncode(payload)));
      final response = await request.close().timeout(const Duration(seconds: 15));
      await response.drain<void>();
      if (response.statusCode >= 200 && response.statusCode < 300) return null;
      return 'Senden fehlgeschlagen (HTTP ${response.statusCode}). Bitte später erneut versuchen.';
    } catch (e) {
      debugPrint('[FeedbackService] send failed: $e');
      return 'Keine Verbindung zum Server. Bitte Internetverbindung prüfen.';
    } finally {
      client.close(force: true);
    }
  }

  // ── Play rating prompt ──────────────────────────────────────────────

  Future<String?> _read(String key) async =>
      _memory != null ? _memory[key] : _storage.read(key: key);

  Future<void> _write(String key, String value) async {
    if (_memory != null) {
      _memory[key] = value;
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  /// Call after a write the controller confirmed. Asks Play for a rating
  /// after a few successful writes and some days of use, at most every
  /// [askAgainAfter]. Returns true if the rating dialog was requested
  /// (Play decides whether it actually shows).
  Future<bool> recordSuccessfulWrite({DateTime? now}) async {
    final t = now ?? DateTime.now();
    try {
      final firstUse = DateTime.tryParse(await _read(_firstUseKey) ?? '');
      if (firstUse == null) await _write(_firstUseKey, t.toIso8601String());
      final writes = (int.tryParse(await _read(_writesKey) ?? '') ?? 0) + 1;
      await _write(_writesKey, '$writes');

      if (!_reviewEnabled || _review == null) return false;
      if (writes < writesBeforeAsking) return false;
      if (firstUse == null || t.difference(firstUse) < minUsage) return false;
      final lastAsked = DateTime.tryParse(await _read(_lastAskedKey) ?? '');
      if (lastAsked != null && t.difference(lastAsked) < askAgainAfter) return false;
      if (!await _review.isAvailable()) return false;

      await _write(_lastAskedKey, t.toIso8601String());
      await _review.requestReview();
      return true;
    } catch (e) {
      debugPrint('[FeedbackService] review prompt skipped: $e');
      return false;
    }
  }

  /// Opens the Play Store page (Play build only).
  Future<void> openStoreListing() async {
    await (_review ?? InAppReview.instance).openStoreListing();
  }
}
