// Render the actual app widgets with demo data; no device or private account needed.
// HEIZUNG_SCREENSHOT_FONT=/path/to/Roboto-Regular.ttf flutter test tool/capture_store_screenshots_test.dart
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
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/home_screen.dart';
import 'package:heizungstrainer/screens/live_view_screen.dart';
import 'package:heizungstrainer/screens/holiday_screen.dart';
import 'package:heizungstrainer/screens/backup_screen.dart';
import 'package:heizungstrainer/services/database_service.dart';

void main() {
  testWidgets('capture current demo screens at 1080 x 1920', (tester) async {
    final fontPath = Platform.environment['HEIZUNG_SCREENSHOT_FONT'];
    expect(fontPath, isNotNull, reason: 'Provide Roboto; never ship Ahem test-font screenshots.');
    final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File(fontPath!).readAsBytesSync())));
    await loader.load();
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/home/carsten/development/flutter';
    for (final entry in {
      'MaterialIcons': '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      'DejaVu Sans': '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      'Noto Color Emoji': '/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf',
    }.entries) {
      final font = FontLoader(entry.key)..addFont(Future.value(ByteData.sublistView(File(entry.value).readAsBytesSync())));
      await font.load();
    }
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // This file is an explicitly invoked Flutter test outside test/.
    // ignore: invalid_use_of_visible_for_testing_member
    FlutterSecureStorage.setMockInitialValues({});
    final p = (await tester.runAsync(() async {
      sqfliteFfiInit();
      final db = DatabaseService(preOpenedDb: await databaseFactoryFfi.openDatabase(inMemoryDatabasePath));
      final p = ECLProvider(databaseService: db, autoLoadDatabase: false);
      await p.reloadSettings();
      await p.startSimulation();
      return p;
    }))!;
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: ChangeNotifierProvider<ECLProvider>.value(value: p, child: Builder(builder: (context) {
        final app = const HeizungstrainerApp().build(context) as MaterialApp;
        // flutter_tester has no Android system font fallback. Supply the
        // equivalent symbol/emoji fonts explicitly for this renderer only.
        return MaterialApp(
          navigatorKey: app.navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: app.theme!.copyWith(textTheme: app.theme!.textTheme.apply(
            fontFamilyFallback: const ['Noto Color Emoji', 'DejaVu Sans'],
          )),
          home: app.home,
        );
      })),
    ));
    await tester.pump(const Duration(seconds: 1));
    final output = Directory('build/play-release/screenshots')..createSync(recursive: true);
    Future<void> capture(String name) async {
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2.5);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        File('${output.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
        image.dispose();
      });
    }
    await capture('01_zuhause_demo');
    final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
    for (final entry in <String, Widget>{
      '03_anlage_live_demo': const LiveViewScreen(),
      '04_urlaub_demo': const HolidayScreen(),
      '05_sicherungen_demo': const BackupScreen(),
    }.entries) {
      navigator.push(MaterialPageRoute<void>(builder: (_) => entry.value));
      await tester.pump(const Duration(seconds: 1));
      await capture(entry.key);
      navigator.pop();
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpWidget(const SizedBox.shrink());
    p.dispose();
    await tester.runAsync(p.databaseService.close);
  });
}
