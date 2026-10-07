import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heizungstrainer/models/live_snapshot.dart';
import 'package:heizungstrainer/widgets/a247_diagram.dart';

void main() {
  testWidgets('preview', (tester) async {
    const dir = '/home/carsten/development/flutter/bin/cache/artifacts/material_fonts';
    final l = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(File('$dir/Roboto-Regular.ttf').readAsBytesSync())))
      ..addFont(Future.value(ByteData.sublistView(File('$dir/Roboto-Bold.ttf').readAsBytesSync())))
      ..addFont(Future.value(ByteData.sublistView(File('$dir/Roboto-Medium.ttf').readAsBytesSync())));
    await l.load();
    tester.view.physicalSize = const Size(2000, 1300);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    final snap = LiveSnapshot(
      at: DateTime(2026, 10, 8, 1, 5), spec: LiveViewSpec.a247,
      sensors: {1: 13.1, 2: null, 3: 26.45, 4: 31.53, 5: 25.89, 6: 50.33, 7: null, 8: 47.45},
      references: {3: 10.0, 5: 22.5, 2: 40.0, 4: 10.0, 6: 55.0},
      triacs: [false, true, false, true, false, false], relays: [true, false, false, false, false, false],
      controllerTime: DateTime(2026, 10, 8, 1, 5));
    await tester.pumpWidget(MaterialApp(home: Scaffold(backgroundColor: const Color(0xFF2A2A32),
      body: Center(child: RepaintBoundary(child: Container(color: const Color(0xFF2A2A32), width: 1000, child: A247Diagram(snapshot: snap)))))));
    await tester.pumpAndSettle();
    await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('/tmp/claude-1000/-home-carsten/4df24419-c246-44db-8c68-249daba836c5/scratchpad/golden/a247.png'));
  });
}
