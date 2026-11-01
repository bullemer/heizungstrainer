import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/models/ecl_parameter.dart';
import 'package:heizungstrainer/screens/connection_screen.dart';
import 'package:heizungstrainer/screens/live_view_screen.dart';
import 'package:heizungstrainer/services/heating_curve_model.dart';
import 'package:heizungstrainer/screens/home_screen.dart';
import 'package:heizungstrainer/screens/holiday_screen.dart';
import 'package:heizungstrainer/screens/community_screen.dart';
import 'package:heizungstrainer/screens/backup_screen.dart';
import 'package:heizungstrainer/screens/settings_screen.dart';
import 'package:heizungstrainer/screens/config_check_screen.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final width in [320.0, 360.0]) {
    for (final scale in [1.0, 1.3]) {
      for (final screen in const <Widget>[
        ConnectionScreen(), HomeScreen(), HolidayScreen(), CommunityScreen(),
        BackupScreen(), SettingsScreen(), ConfigCheckScreen(), LiveViewScreen(),
      ]) {
        testWidgets('${screen.runtimeType} at $width / text $scale', (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final previousErrorHandler = FlutterError.onError;
          FlutterError.onError = (details) {
            FlutterError.dumpErrorToConsole(details, forceReport: true);
            previousErrorHandler?.call(details);
          };
          final p = ECLProvider(autoLoadDatabase: false);
          await tester.pump();
          if (screen is! ConnectionScreen) {
            p.setConnectedForTesting(ip: 'Simulation');
            p.setReadingForTesting(ECLRegisters.outdoorTemp, 7.5);
            p.setReadingForTesting(ECLRegisters.flowTemp, 46);
            p.setReadingForTesting(ECLRegisters.returnTemp, 36);
            p.setReadingForTesting(ECLRegisters.hotWaterTemp, 52);
            p.setReadingForTesting(ECLRegisters.roomTargetTemp, 20);
            p.setReadingForTesting(ECLRegisters.heatingCurveShift, 0);
            p.setReadingForTesting(ECLRegisters.curveSlope, danfossFactoryCurve.slope);
            for (var i = 0; i < ECLRegisters.curvePoints.length; i++) {
              p.setReadingForTesting(ECLRegisters.curvePoints[i], danfossFactoryCurve.flowTemps[i]);
            }
          }
          await tester.pumpWidget(ChangeNotifierProvider.value(
            value: p,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: screen,
            ),
          ));
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          // Exercise lazy content below the fold as well.
          final scrolls = find.byType(Scrollable);
          if (scrolls.evaluate().isNotEmpty) {
            for (var i = 0; i < 8; i++) {
              await tester.drag(scrolls.first, const Offset(0, -550));
              await tester.pump(const Duration(milliseconds: 300));
              expect(tester.takeException(), isNull);
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
          p.dispose();
        });
      }
    }
  }
}
