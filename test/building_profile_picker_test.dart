import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';
import 'package:heizungstrainer/widgets/building_profile_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('top card: pick floor heating 1990–2000, shown afterwards', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final provider = ECLProvider(autoLoadDatabase: false);

    Widget app() => MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: provider,
              builder: (_, __) => BuildingProfileCard(provider: provider),
            ),
          ),
        );
    await tester.pumpWidget(app());
    expect(find.textContaining('Noch nicht festgelegt'), findsOneWidget);

    await tester.tap(find.byKey(const Key('buildingProfileCard')));
    await tester.pumpAndSettle();
    // all systems and age classes are offered
    for (final s in HeatingSystem.values) {
      expect(find.byKey(Key('system_${s.name}')), findsOneWidget);
    }
    for (final a in BuildingAge.values) {
      expect(find.byKey(Key('age_${a.name}')), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('system_floor')));
    await tester.tap(find.byKey(const Key('age_from1990to2000')));
    await tester.pumpAndSettle();
    expect(find.textContaining('30–40 °C'), findsOneWidget);
    await tester.tap(find.byKey(const Key('saveBuildingProfile')));
    await tester.pumpAndSettle();

    expect(provider.buildingProfile!.system, HeatingSystem.floor);
    expect(provider.isFloorHeating, isTrue);
    expect(find.text('Fußbodenheizung · Baujahr/Standard 1990–2000'), findsOneWidget);
  });
}
