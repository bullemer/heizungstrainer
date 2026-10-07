import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/settings_transfer_service.dart';
import 'package:heizungstrainer/widgets/settings_transfer_card.dart';

Map<String, String> _phone() => {
      'selected_controller_id': 'danfoss_ecl_310',
      'ecl_controller_ip': '192.168.188.133',
      'selected_billing_id': 'brunata_hamburg',
      'building_reference': '{"system":"floor","age":"after2010"}',
      'annual_heating_kwh': '10578',
      'brunata_price_per_kwh': '0.132',
      'brunata_portal_url': 'https://portal.example',
      'ecl_controller_backups': jsonEncode([
        {'id': 'b1', 'name': 'Winter'},
      ]),
      'ecl_holiday_plans': jsonEncode([
        {'id': 'h1', 'title': 'Ostsee'},
      ]),
      'viessmann_config': jsonEncode({'host': '10.0.0.5', 'apiToken': 'tok-123', 'circuit': '0'}),
      'bosch_buderus_ems_config': jsonEncode(
          {'host': '10.0.0.6', 'gatewayPassword': 'gw', 'privatePassword': 'pp', 'port': 80}),
      // never exported:
      'brunata_username': 'mieter@example.de',
      'brunata_password': 'geheim',
      'ecl_license_info': '{"tier":"pro"}',
      'ht_early_adopter_since': '2026-10-07',
      'beta_write_enabled_nibe_modbus': 'true',
      'ht_review_successful_writes': '5',
    };

void main() {
  group('SettingsTransferService', () {
    test('export contains settings but no credentials, licence or consent', () async {
      final service = SettingsTransferService(inMemoryStorage: _phone());
      final raw = await service.exportJson(appVersion: '1.2.0 (Build 12)', now: DateTime(2026, 10, 8));
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final values = json['values'] as Map<String, dynamic>;

      expect(json['format'], SettingsTransferService.format);
      expect(values['ecl_controller_ip'], '192.168.188.133');
      expect(values['brunata_price_per_kwh'], '0.132');
      expect(values.keys, contains('ecl_holiday_plans'));
      for (final secret in [
        'brunata_username',
        'brunata_password',
        'ecl_license_info',
        'ht_early_adopter_since',
        'beta_write_enabled_nibe_modbus',
        'ht_review_successful_writes',
      ]) {
        expect(values.containsKey(secret), isFalse, reason: secret);
      }
      expect(raw, isNot(contains('geheim')));
      expect(raw, isNot(contains('tok-123')));
      expect(raw, isNot(contains('mieter@example.de')));
      final bosch = jsonDecode(values['bosch_buderus_ems_config'] as String) as Map;
      expect(bosch['gatewayPassword'], '');
      expect(bosch['privatePassword'], '');
      expect(bosch['host'], '10.0.0.6');
    });

    test('export → import on a fresh install restores the settings', () async {
      final raw = await SettingsTransferService(inMemoryStorage: _phone()).exportJson(appVersion: 'x');
      final fresh = <String, String>{};
      final result = await SettingsTransferService(inMemoryStorage: fresh).importJson(raw);

      expect(result.ignored, isEmpty);
      expect(fresh['selected_controller_id'], 'danfoss_ecl_310');
      expect(fresh['building_reference'], _phone()['building_reference']);
      expect(fresh.containsKey('brunata_password'), isFalse);
      expect(jsonDecode(fresh['viessmann_config']!)['apiToken'], '');
    });

    test('import keeps existing secrets and merges lists by id', () async {
      final raw = await SettingsTransferService(inMemoryStorage: _phone()).exportJson(appVersion: 'x');
      final target = <String, String>{
        'viessmann_config': jsonEncode({'host': 'old', 'apiToken': 'keep-me'}),
        'ecl_controller_backups': jsonEncode([
          {'id': 'b0', 'name': 'Lokal'},
          {'id': 'b1', 'name': 'alt'},
        ]),
      };
      await SettingsTransferService(inMemoryStorage: target).importJson(raw);

      final vic = jsonDecode(target['viessmann_config']!) as Map;
      expect(vic['host'], '10.0.0.5');
      expect(vic['apiToken'], 'keep-me');
      final backups = (jsonDecode(target['ecl_controller_backups']!) as List).cast<Map>();
      expect(backups.map((b) => b['id']), unorderedEquals(['b0', 'b1']));
      expect(backups.firstWhere((b) => b['id'] == 'b1')['name'], 'Winter');
    });

    test('import ignores keys that are not importable', () async {
      final target = <String, String>{};
      final result = await SettingsTransferService(inMemoryStorage: target).importJson(jsonEncode({
        'format': SettingsTransferService.format,
        'formatVersion': 1,
        'values': {
          'ht_early_adopter_since': '2026-01-01',
          'ecl_license_info': '{"tier":"pro"}',
          'beta_write_enabled_nibe_modbus': 'true',
          'annual_heating_kwh': '9000',
        },
      }));
      expect(result.imported, ['annual_heating_kwh']);
      expect(result.ignored, hasLength(3));
      expect(target.keys, ['annual_heating_kwh']);
    });

    test('rejects foreign files and newer formats', () async {
      final s = SettingsTransferService(inMemoryStorage: {});
      expect(() => s.importJson('kein json'), throwsA(isA<SettingsFormatException>()));
      expect(() => s.importJson('{"format":"other"}'), throwsA(isA<SettingsFormatException>()));
      expect(
        () => s.importJson(jsonEncode({'format': SettingsTransferService.format, 'formatVersion': 99, 'values': {}})),
        throwsA(isA<SettingsFormatException>()),
      );
    });
  });

  group('SettingsTransferCard', () {
    testWidgets('export saves a file, import applies it', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final provider = ECLProvider(
        logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false),
        autoLoadDatabase: false,
      );
      final storage = _phone();
      String? savedName;
      String? savedContent;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SettingsTransferCard(
            provider: provider,
            service: SettingsTransferService(inMemoryStorage: storage),
            saveFile: (name, content) async {
              savedName = name;
              savedContent = content;
              return true;
            },
            pickFile: () async => savedContent,
          ),
        ),
      ));

      await tester.tap(find.byKey(const ValueKey('settings_export')));
      await tester.pumpAndSettle();
      expect(savedName, startsWith('heizungstrainer-einstellungen-'));
      expect(savedContent, isNot(contains('geheim')));
      expect(find.text('Einstellungen gespeichert (ohne Passwörter).'), findsOneWidget);

      storage.remove('ecl_controller_ip');
      await tester.tap(find.byKey(const ValueKey('settings_import')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Datei wählen'));
      await tester.pumpAndSettle();
      expect(find.text('Einstellungen übernommen'), findsOneWidget);
      expect(storage['ecl_controller_ip'], '192.168.188.133');

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });
  });
}
