import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/services/alert_center.dart';
import 'package:heizungstrainer/widgets/alerts_panel.dart';

void main() {
  group('AlertCenter', () {
    test('conditions stay until resolved, events until acknowledged', () async {
      final store = <String, String>{};
      final c = AlertCenter(inMemoryStorage: store);
      await c.raise(key: 'alarm_3', severity: AlertSeverity.error, title: 'A', message: 'm', isCondition: true);
      await c.raise(key: 'ext_1', severity: AlertSeverity.info, title: 'E', message: 'm');
      expect(c.unacknowledgedCount, 2);

      // repeated condition does not add a new badge
      await c.acknowledge('alarm_3');
      await c.raise(key: 'alarm_3', severity: AlertSeverity.error, title: 'A', message: 'm', isCondition: true);
      expect(c.unacknowledgedCount, 1);
      expect(c.alerts, hasLength(2));

      await c.acknowledge('ext_1');
      expect(c.alerts.map((a) => a.key), ['alarm_3']);

      // persisted
      final again = AlertCenter(inMemoryStorage: store);
      await again.load();
      expect(again.alerts.single.key, 'alarm_3');
      expect(again.alerts.single.acknowledged, isTrue);

      await c.resolve('alarm_3');
      expect(c.alerts, isEmpty);
    });

    test('acknowledgeAll removes events, keeps active conditions', () async {
      final c = AlertCenter(inMemoryStorage: {});
      await c.raise(key: 'sensor_x', severity: AlertSeverity.error, title: 'S', message: 'm', isCondition: true);
      await c.raise(key: 'lost_1', severity: AlertSeverity.error, title: 'L', message: 'm');
      await c.acknowledgeAll();
      expect(c.alerts.map((a) => a.key), ['sensor_x']);
      expect(c.unacknowledgedCount, 0);
    });
  });

  test('provider: controller alarm becomes an alert and clears with the alarm', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final provider = ECLProvider(
      logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false),
      autoLoadDatabase: false,
    );
    await provider.processAlarmMask(1 << 4); // alarm 5
    expect(provider.alerts.alerts.single.key, 'alarm_5');
    expect(provider.alerts.alerts.single.isCondition, isTrue);
    await provider.processAlarmMask(0);
    expect(provider.alerts.alerts, isEmpty);
    provider.dispose();
  });

  testWidgets('panel lists alerts and acknowledges them', (tester) async {
    final c = AlertCenter(inMemoryStorage: {});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AlertsPanel(alerts: c))));
    expect(find.text('Keine aktiven Meldungen'), findsOneWidget);

    await tester.runAsync(() => c.raise(
        key: 'alarm_2', severity: AlertSeverity.error, title: 'Regler-Alarm 2', message: 'x', isCondition: true));
    await tester.runAsync(() => c.raise(
        key: 'ext_9', severity: AlertSeverity.info, title: 'Außerhalb der App geändert', message: 'Spar 25 → 18 °C'));
    await tester.pump();
    expect(find.text('Aktive Meldungen (2, 2 neu)'), findsOneWidget);
    expect(find.text('aktiv'), findsOneWidget);

    await tester.tap(find.byKey(const Key('alertAck_ext_9')));
    await tester.pump();
    expect(find.text('Spar 25 → 18 °C'), findsNothing);
    expect(find.text('Aktive Meldungen (1, 1 neu)'), findsOneWidget);
    expect(ECLRegisters.sensorParameters, isNotEmpty);
  });
}
