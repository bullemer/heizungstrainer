import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/connection_screen.dart';
import 'package:heizungstrainer/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  // Play reviewers and users without hardware must be able to reach the
  // simulation from the start page.
  testWidgets('not connected: Demo button on the start page starts the simulation',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final provider = ECLProvider(autoLoadDatabase: false);
    expect(provider.isConnected, isFalse);

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pump();

    final demo = find.byKey(const ValueKey('home_start_demo'));
    expect(demo, findsOneWidget);
    await tester.tap(demo);
    await tester.pump(const Duration(seconds: 3));

    expect(provider.isConnected, isTrue);
    expect(provider.isSimulatedController, isTrue);
    expect(find.byKey(const ValueKey('home_start_demo')), findsNothing);
    provider.disconnect();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('fresh install: connection screen offers the demo', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final provider = ECLProvider(autoLoadDatabase: false);

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: provider,
      child: const MaterialApp(home: ConnectionScreen()),
    ));
    await tester.pump();

    final demo = find.byKey(const Key('startpage_demo_button'));
    await tester.ensureVisible(demo);
    await tester.tap(demo);
    await tester.pump(const Duration(seconds: 3));
    expect(provider.isSimulatedController, isTrue);
    expect(provider.isConnected, isTrue);
    provider.disconnect();
    await tester.pump(const Duration(seconds: 1));
  });
}
