import 'package:flutter_test/flutter_test.dart';
import 'package:heizungstrainer/models/license_info.dart';
import 'package:heizungstrainer/services/feedback_service.dart';
import 'package:heizungstrainer/services/license_service.dart';
import 'package:in_app_review/in_app_review.dart';

class _FakeReview implements InAppReview {
  int requests = 0;
  bool available = true;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async => requests++;

  @override
  Future<void> openStoreListing({String? appStoreId, String? microsoftStoreId}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Free launch phase', () {
    test('everything unlocked and install marked as early adopter', () async {
      final storage = <String, String>{};
      final service = LicenseService(inMemoryStorage: storage, freeLaunch: true);
      expect(service.isPro, isTrue, reason: 'unlocked even before init');
      await service.init();
      expect(service.isPro, isTrue);
      expect(service.canWriteParameters, isTrue);
      expect(service.isEarlyAdopter, isTrue);
      expect(service.currentInfo.source, LicenseSource.earlyAdopter);
      expect(storage['ht_early_adopter_since'], isNotNull);
    });

    test('early adopter keeps Pro after the launch phase ends', () async {
      final storage = <String, String>{};
      await LicenseService(inMemoryStorage: storage, freeLaunch: true).init();

      final later = LicenseService(inMemoryStorage: storage);
      await later.init();
      expect(later.isFreeLaunch, isFalse);
      expect(later.isPro, isTrue);
      expect(later.canWriteParameters, isTrue);
      expect(later.currentTier, LicenseTier.pro);
      expect(later.currentInfo.source, LicenseSource.earlyAdopter);
    });

    test('new install after the launch phase is Free', () async {
      final service = LicenseService(inMemoryStorage: {});
      await service.init();
      expect(service.isPro, isFalse);
      expect(service.isEarlyAdopter, isFalse);
    });

    test('mark is set once and keeps its original date', () async {
      final storage = {'ht_early_adopter_since': '2026-10-08T10:00:00.000'};
      final service = LicenseService(inMemoryStorage: storage, freeLaunch: true);
      await service.init();
      expect(service.earlyAdopterSince, DateTime(2026, 10, 8, 10));
    });

    test('removing a licence key does not remove early-adopter Pro', () async {
      final storage = <String, String>{};
      await LicenseService(inMemoryStorage: storage, freeLaunch: true).init();
      final later = LicenseService(inMemoryStorage: storage);
      await later.init();
      await later.revokeLicense();
      expect(later.isPro, isTrue);
    });
  });

  group('Feedback', () {
    test('payload matches the backoffice bug schema', () {
      final p = FeedbackService.buildPayload(
        kind: FeedbackKind.idea,
        message: '  Bitte Warmwasser-Zeitprogramm\nund mehr  ',
        email: ' a@b.de ',
        controllerBrand: 'Danfoss',
        controllerModel: 'ECL Comfort 310',
      );
      expect(p['title'], 'App-Feedback (Idee / Wunsch): Bitte Warmwasser-Zeitprogramm');
      expect(p['description'], 'Bitte Warmwasser-Zeitprogramm\nund mehr');
      expect(p['user_email'], 'a@b.de');
      expect(p['severity'], 'feedback_idea');
      expect((p['severity'] as String).length, lessThanOrEqualTo(32));
      expect((p['os_platform'] as String).length, lessThanOrEqualTo(64));
      expect(p['app_version'], isNotEmpty);
    });

    test('empty email is sent as null, long first line is cut', () {
      final p = FeedbackService.buildPayload(
        kind: FeedbackKind.problem,
        message: 'x' * 300,
        email: '  ',
      );
      expect(p['user_email'], isNull);
      expect((p['title'] as String).length, lessThan(255));
    });

    test('too short message is rejected without network', () async {
      final s = FeedbackService(inMemoryStorage: {}, reviewEnabled: false);
      expect(await s.send(kind: FeedbackKind.praise, message: ' ok'), isNotNull);
    });

    test('rating asked after 3 writes and 3 days, then not again for 120 days', () async {
      final review = _FakeReview();
      final s = FeedbackService(inMemoryStorage: {}, review: review, reviewEnabled: true);
      final day0 = DateTime(2026, 10, 8);
      expect(await s.recordSuccessfulWrite(now: day0), isFalse);
      expect(await s.recordSuccessfulWrite(now: day0), isFalse);
      expect(await s.recordSuccessfulWrite(now: day0), isFalse, reason: 'too early');
      final day4 = day0.add(const Duration(days: 4));
      expect(await s.recordSuccessfulWrite(now: day4), isTrue);
      expect(review.requests, 1);
      expect(await s.recordSuccessfulWrite(now: day4.add(const Duration(days: 30))), isFalse);
      expect(await s.recordSuccessfulWrite(now: day4.add(const Duration(days: 121))), isTrue);
      expect(review.requests, 2);
    });

    test('no rating prompt outside the Play build', () async {
      final review = _FakeReview();
      final s = FeedbackService(inMemoryStorage: {}, review: review, reviewEnabled: false);
      for (var i = 0; i < 5; i++) {
        await s.recordSuccessfulWrite(now: DateTime(2026, 10, 8).add(Duration(days: i * 2)));
      }
      expect(review.requests, 0);
    });
  });
}
