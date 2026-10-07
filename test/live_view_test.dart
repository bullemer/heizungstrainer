import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/models/live_snapshot.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/live_view_screen.dart';
import 'package:heizungstrainer/services/activity_log_service.dart';
import 'package:heizungstrainer/widgets/a247_diagram.dart';

/// Values read live from the user's A247.1 on 2026-10-08 (matches the
/// Danfoss portal): outputs Tr2 + Tr4 on, all relays off; limiter words
/// [2, 0x8000, 0, 0].
LiveSnapshot realSnapshot() => LiveSnapshot(
      at: DateTime(2026, 10, 8, 1, 5),
      spec: LiveViewSpec.a247,
      sensors: {1: 13.1, 2: null, 3: 26.45, 4: 31.53, 5: 25.89, 6: 50.33, 7: null, 8: 47.45},
      references: {3: 10.0, 5: 22.5, 2: 40.0, 4: 10.0, 6: 55.0},
      triacs: [false, true, false, true, false, false],
      relays: List.filled(6, false),
      circuitMode: const {1: 1, 2: 2},
      circuitStatus: const {1: 2, 2: 2},
      limiter: const [2, 0x8000, 0, 0],
      controllerTime: DateTime(2026, 10, 8, 1, 5),
    );

class _FakeProvider extends ECLProvider {
  _FakeProvider(this.snap)
      : super(logService: ActivityLogService(enablePersistence: false, enableRemoteDispatch: false), autoLoadDatabase: false);
  final LiveSnapshot? snap;
  int reads = 0;
  @override
  Future<LiveSnapshot?> readLiveSnapshot() async {
    reads++;
    return snap;
  }
}

void main() {
  test('A247 spec: reference registers per circuit', () {
    expect(LiveViewSpec.referenceAddress(1, 3), 11252); // PNU 11253 S3 reference
    expect(LiveViewSpec.referenceAddress(2, 6), 12255); // PNU 12256 S6 reference
    expect(LiveViewSpec.forApplication('A247.1 v4.00').hasDiagram, isTrue);
    expect(LiveViewSpec.forApplication('A266.1').hasDiagram, isFalse);
  });

  test('outputs and limiter flags decode like the Danfoss view', () {
    final s = realSnapshot();
    expect(s.p1 || s.p2 || s.p3, isFalse);
    expect(s.m1, ValveMotion.closing); // Tr2
    expect(s.m2, ValveMotion.closing); // Tr4
    expect(s.alarmOutput, isFalse);
    expect(s.limiterTexts, ['Rücklaufbegrenzung senkt den Sollwert', 'Sommerabschaltung aktiv (Heizgrenze)']);
    expect(LiveSnapshot.sensorFromRaw(19200), isNull);
    expect(LiveSnapshot.sensorFromRaw(2645), 26.45);
    expect(eclStatusLabel(2), 'Komfort');
  });

  testWidgets('screen shows diagram, values and outputs', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.resetPhysicalSize);
    final provider = _FakeProvider(realSnapshot());
    await tester.pumpWidget(ChangeNotifierProvider<ECLProvider>.value(
      value: provider,
      child: const MaterialApp(home: LiveViewScreen(refreshInterval: Duration(hours: 1))),
    ));
    await tester.pump();
    expect(find.byType(A247Diagram), findsOneWidget);
    expect(find.text('Vorlauf Heizung'), findsOneWidget);
    expect(find.text('26.5 °C'), findsOneWidget); // S3, rounded like Danfoss
    expect(find.text('22.5 °C'), findsOneWidget); // S5 target
    expect(find.text('Heizungspumpe'), findsOneWidget);
    expect(find.text('schließt'), findsNWidgets(2));
    expect(find.text('• Sommerabschaltung aktiv (Heizgrenze)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });

  testWidgets('no data → message instead of a diagram', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final provider = _FakeProvider(null);
    await tester.pumpWidget(ChangeNotifierProvider<ECLProvider>.value(
      value: provider,
      child: const MaterialApp(home: LiveViewScreen(refreshInterval: Duration(hours: 1))),
    ));
    await tester.pump();
    expect(find.textContaining('Keine Live-Daten'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    provider.dispose();
  });
}
