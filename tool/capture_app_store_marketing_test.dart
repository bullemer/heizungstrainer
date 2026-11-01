// Renders the real app widgets with demo data (as with a connected Danfoss
// ECL, so the curve editor and schedule card are visible) and writes the
// screens plus the rectangles of the interesting parts for
// tool/compose_app_store_screenshots.py.
//
// HEIZUNG_SCREENSHOT_FONT_DIR=<flutter>/bin/cache/artifacts/material_fonts \
//   flutter test tool/capture_app_store_marketing_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:heizungstrainer/main.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/models/week_schedule.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/holiday_screen.dart';
import 'package:heizungstrainer/screens/home_screen.dart';
import 'package:heizungstrainer/screens/live_view_screen.dart';
import 'package:heizungstrainer/services/database_service.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';

/// Demo values, shown like a connected ECL (curve editor, schedule card).
class _ShowcaseProvider extends ECLProvider {
  _ShowcaseProvider(DatabaseService db) : super(databaseService: db, autoLoadDatabase: false);
  @override
  bool get supportsControllerSchedule => true;
}

const _pixelRatio = 3.0;

void main() {
  testWidgets('render App Store showcase screens', (tester) async {
    final fontDir = Platform.environment['HEIZUNG_SCREENSHOT_FONT_DIR'];
    expect(fontDir, isNotNull, reason: 'Provide the Roboto fonts; never ship Ahem test-font screenshots.');
    final roboto = FontLoader('Roboto');
    for (final w in ['Regular', 'Medium', 'Bold']) {
      roboto.addFont(Future.value(ByteData.sublistView(File('$fontDir/Roboto-$w.ttf').readAsBytesSync())));
    }
    await roboto.load();
    for (final entry in {
      'MaterialIcons': '$fontDir/MaterialIcons-Regular.otf',
      'DejaVu Sans': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      'Noto Color Emoji': '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(File(entry.value).readAsBytesSync())))).load();
    }
    tester.view.devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // ignore: invalid_use_of_visible_for_testing_member
    FlutterSecureStorage.setMockInitialValues({});

    final p = (await tester.runAsync(() async {
      sqfliteFfiInit();
      final db = DatabaseService(preOpenedDb: await databaseFactoryFfi.openDatabase(inMemoryDatabasePath));
      final p = _ShowcaseProvider(db);
      await p.reloadSettings();
      await p.setBuildingProfile(const BuildingProfile(HeatingSystem.radiator, BuildingAge.from1990to2000));
      await p.setSelectedBillingProvider('none');
      await p.setAnnualHeatingKwh(9000);
      await p.startSimulation();
      return p;
    }))!;
    // A typical working week: warm mornings and evenings, weekend all day.
    p
      ..setReadingForTesting(ECLRegisters.savingRoomTemp, 17)
      ..setReadingForTesting(ECLRegisters.circuitMode, 1)
      ..setControllerScheduleForTesting(WeekSchedule([
        for (var d = 0; d < 7; d++)
          d < 5
              ? const [SchedulePeriod(600, 800), SchedulePeriod(1600, 2230), SchedulePeriod.unused]
              : const [SchedulePeriod(700, 2300), SchedulePeriod.unused, SchedulePeriod.unused],
      ]));

    final out = Directory('build/app-store/raw')..createSync(recursive: true);
    final rects = <String, dynamic>{};
    final boundary = GlobalKey();

    Future<void> app(Widget home) async {
      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ChangeNotifierProvider<ECLProvider>.value(
          value: p,
          child: Builder(builder: (context) {
            final base = const HeizungstrainerApp().build(context) as MaterialApp;
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: base.locale,
              supportedLocales: base.supportedLocales,
              localizationsDelegates: base.localizationsDelegates,
              theme: base.theme!.copyWith(
                textTheme: base.theme!.textTheme.apply(fontFamilyFallback: const ['Noto Color Emoji', 'DejaVu Sans']),
              ),
              home: home,
            );
          }),
        ),
      ));
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> capture(String name, Map<String, Finder> parts) async {
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      rects[name] = {
        for (final e in parts.entries)
          e.key: () {
            final r = tester.getRect(e.value.first);
            return [r.left, r.top, r.right, r.bottom].map((v) => (v * _pixelRatio).round()).toList();
          }(),
      };
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: _pixelRatio);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        File('${out.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
        image.dispose();
      });
    }

    // Start page, tall enough to show every card at once.
    tester.view.physicalSize = const Size(1320, 9000);
    await app(const HomeScreen());
    await capture('home', {
      'curve': find.byKey(const Key('heatingCurveCard')),
      'schedule': find.byKey(const Key('controllerScheduleCard')),
    });

    // Curve editor with a change previewed.
    tester.view.physicalSize = const Size(1320, 2868);
    await app(const HomeScreen());
    await tester.ensureVisible(find.byKey(const Key('editCurve')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('editCurve')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('curveFlatter')));
    await tester.tap(find.byKey(const Key('curveFlatter')));
    await tester.pump();
    await capture('curve_editor', {'dialog': find.byType(AlertDialog)});
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(1320, 4400);
    await app(const LiveViewScreen(refreshInterval: Duration(hours: 1)));
    await tester.pump(const Duration(seconds: 1));
    await capture('live', {'diagram': find.byKey(const Key('liveDiagram'))});

    tester.view.physicalSize = const Size(1320, 4400);
    await app(const HolidayScreen());
    await capture('holiday', {'table': find.byKey(const Key('seasonalSavings'))});

    File('${out.path}/rects.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rects));
    await tester.pumpWidget(const SizedBox.shrink());
    p.dispose();
    await tester.runAsync(p.databaseService.close);
  });
}
