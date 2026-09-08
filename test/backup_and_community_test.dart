import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/models/brunata_chart.dart';
import 'package:heizungstrainer/models/brunata_meter_data.dart';
import 'package:heizungstrainer/models/configuration_backup.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/backup_screen.dart';
import 'package:heizungstrainer/screens/community_screen.dart';
import 'package:heizungstrainer/services/backup_service.dart';

void main() {
  group('ConfigurationBackup Model Tests', () {
    test('serializes and deserializes snapshot accurately', () {
      final now = DateTime(2026, 9, 7, 20, 0);
      final backup = ConfigurationBackup(
        id: 'test_backup_1',
        name: 'Winteroptimierung 2026',
        timestamp: now,
        heatingCurveShift: -1.0,
        roomTarget: 20.5,
        outdoorTemp: -4.2,
        flowTemp: 52.3,
        returnTemp: 38.1,
        note: 'Starker Frost - Vorlauf abgesenkt',
      );

      final json = backup.toJson();
      final restored = ConfigurationBackup.fromJson(json);

      expect(restored.id, 'test_backup_1');
      expect(restored.name, 'Winteroptimierung 2026');
      expect(restored.timestamp, now);
      expect(restored.heatingCurveShift, -1.0);
      expect(restored.roomTarget, 20.5);
      expect(restored.outdoorTemp, -4.2);
      expect(restored.flowTemp, 52.3);
      expect(restored.returnTemp, 38.1);
      expect(restored.note, 'Starker Frost - Vorlauf abgesenkt');
      expect(restored.isPreset, false);
    });

    test('encodes and decodes lists of backups', () {
      final list = [
        ConfigurationBackup(
          id: 'b1',
          name: 'Backup 1',
          timestamp: DateTime(2026, 1, 1),
          heatingCurveShift: 0.0,
        ),
        ConfigurationBackup(
          id: 'b2',
          name: 'Backup 2',
          timestamp: DateTime(2026, 2, 1),
          heatingCurveShift: -2.0,
        ),
      ];

      final encoded = ConfigurationBackup.encodeList(list);
      final decoded = ConfigurationBackup.decodeList(encoded);

      expect(decoded.length, 2);
      expect(decoded[0].id, 'b1');
      expect(decoded[1].id, 'b2');
      expect(decoded[1].heatingCurveShift, -2.0);
    });

    test('provides factory presets with valid values', () {
      final presets = ConfigurationBackup.presets;
      expect(presets, isNotEmpty);
      expect(presets.any((p) => p.heatingCurveShift == 0.0), isTrue);
      expect(presets.any((p) => p.heatingCurveShift == -2.0), isTrue);
      expect(presets.every((p) => p.isPreset), isTrue);
    });
  });

  group('BackupService Tests', () {
    test('saves, retrieves, and deletes backups in memory', () async {
      final mem = <String, String>{};
      final service = BackupService(inMemoryStorage: mem);

      expect(await service.getBackups(), isEmpty);

      final b1 = ConfigurationBackup(
        id: 'test-1',
        name: 'Snapshot 1',
        timestamp: DateTime(2026, 3, 1),
        heatingCurveShift: 0.0,
      );
      final b2 = ConfigurationBackup(
        id: 'test-2',
        name: 'Snapshot 2',
        timestamp: DateTime(2026, 3, 2),
        heatingCurveShift: -1.0,
      );

      await service.saveBackup(b1);
      await service.saveBackup(b2);

      final backups = await service.getBackups();
      expect(backups.length, 2);
      // Sorted newest first
      expect(backups.first.id, 'test-2');

      await service.deleteBackup('test-1');
      final remaining = await service.getBackups();
      expect(remaining.length, 1);
      expect(remaining.first.id, 'test-2');

      await service.clearBackups();
      expect(await service.getBackups(), isEmpty);
    });
  });

  group('BrunataMeterData Tests', () {
    test('demo data contains complete community and building charts', () {
      final demo = BrunataMeterData.demo();

      expect(demo.consumedKwh, greaterThan(0));
      expect(demo.currentBillingPeriodCost, greaterThan(0));
      expect(demo.hasDetail, isTrue);
      expect(demo.charts.length, greaterThanOrEqualTo(3));

      // Must contain building comparison charts
      final liegenschaft =
          demo.charts.where((c) => c.source.contains('liegenschaft'));
      expect(liegenschaft, isNotEmpty);

      // Must contain monthly chart
      final monthly = demo.charts.where((c) => c.source == 'month_heizung');
      expect(monthly, isNotEmpty);
    });

    test('copyWithPrice updates estimated costs accurately', () {
      final demo = BrunataMeterData.demo();
      final updated = demo.copyWithPrice(0.15);

      expect(updated.pricePerKwh, 0.15);
      expect(updated.currentBillingPeriodCost, demo.consumedKwh * 0.15);
      expect(updated.consumedKwh, demo.consumedKwh);
    });

    test('calculateCommunityComparisonPercentage computes accurate diff for demo charts', () {
      final demo = BrunataMeterData.demo();
      final diff = calculateCommunityComparisonPercentage(demo.charts);
      expect(diff, isNotNull);
      expect(diff, closeTo(-22.1, 0.1));
    });

    test('calculateCommunityComparisonPercentage handles real scraped Brunata Hamburg structure', () {
      final realCharts = [
        const BrunataChart(
          source: 'liegenschaft_heizung',
          title: 'Liegenschaftsvergleich Heizung',
          subtitle: 'Ausgewählter Abrechnungszeitraum: 01.01.2026 - 31.12.2026',
          unit: 'Verbrauch in kWh je m²',
          categories: ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'],
          series: [
            BrunataChartSeries(
              name: 'Durchschnitt der Liegenschaft',
              values: [10.197, 8.497, 5.187, 3.81, 2.492, 1.835, 1.75, 1.789, 1.705, 4.548, 6.824, 9.098],
              extrapolated: [false, false, false, false, false, false, false, false, true, true, true, true],
            ),
            BrunataChartSeries(
              name: 'Carsten Bullemer',
              values: [6.911, 7.726, 5.841, 4.798, 3.229, 1.786, 1.412, 1.703, 1.641, 4.382, 6.573, 8.764],
              extrapolated: [false, false, false, false, false, false, false, false, true, true, true, true],
            ),
          ],
        ),
      ];

      final diff = calculateCommunityComparisonPercentage(realCharts);
      expect(diff, isNotNull);
      // Carsten: 33.406 vs Avg: 35.559 -> (33.406 - 35.559) / 35.559 = -6.05%
      expect(diff!, lessThan(0));
      expect(diff, closeTo(-6.0, 0.2));
    });

    test('BrunataMeterData.fromJson auto-recomputes communityComparisonPercentage if 0.0 and charts exist', () {
      final demo = BrunataMeterData.demo();
      final json = demo.toJson();
      json['communityComparisonPercentage'] = 0.0;

      final restored = BrunataMeterData.fromJson(json);
      expect(restored.communityComparisonPercentage, closeTo(-22.1, 0.1));
    });

    test('hasWarmWater returns false when apartment has no hot water meters', () {
      final dataNoHotWater = BrunataMeterData(
        currentBillingPeriodCost: 804.25,
        consumedKwh: 6434,
        communityComparisonPercentage: -6.0,
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 12, 31),
        pricePerKwh: 0.125,
        heatingYtdActual: 6434,
        heatingProjection: 10548,
        warmWaterYtdActual: 0,
        warmWaterProjection: 0,
        charts: const [],
      );

      expect(dataNoHotWater.hasWarmWater, isFalse);
    });

    test('hasWarmWater returns true when warm water data is available', () {
      final demo = BrunataMeterData.demo();
      expect(demo.hasWarmWater, isTrue);
    });
  });

  group('Widget Tests for P2 Screens', () {
    testWidgets('BackupScreen displays presets and active status card',
        (tester) async {
      final provider = ECLProvider();
      final backupService = BackupService(inMemoryStorage: {});

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: BackupScreen(backupService: backupService),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Sicherungen'), findsOneWidget);
      expect(find.text('Aktiver Regler-Status'), findsOneWidget);
      expect(find.text('Vordefinierte Profile'), findsOneWidget);
      expect(find.textContaining('Werkseinstellung'), findsOneWidget);
      expect(find.textContaining('Eco-Sparbetrieb'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });

    testWidgets('CommunityScreen renders un-synced state when data is null',
        (tester) async {
      final provider = ECLProvider();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: CommunityScreen(),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Community Vergleich'), findsOneWidget);
      expect(find.text('Noch keine Abrechnungsdaten'), findsOneWidget);
      expect(find.textContaining('Synchronisiere die Verbrauchsdaten'),
          findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });

    testWidgets(
        'CommunityScreen renders benchmark, weather note and charts when data present',
        (tester) async {
      final provider = ECLProvider();
      provider.setBrunataDataForTesting(BrunataMeterData.demo());

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: const MaterialApp(
            home: CommunityScreen(),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('Community Vergleich'), findsOneWidget);
      expect(find.text('Liegenschafts-Effizienz'), findsOneWidget);
      expect(find.textContaining('Witterungsbereinigt nach VDI 3807'),
          findsOneWidget);
      expect(find.text('Heizung'), findsOneWidget);
      // "Warmwasser" appears both in summary card and filter chip
      expect(find.text('Warmwasser'), findsNWidgets(2));
      expect(find.text('Alle'), findsOneWidget);
      expect(find.text('Liegenschaft'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });
  });
}
