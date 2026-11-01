import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/settings_screen.dart';

/// The settings with every brand's config card must fit a 411 dp phone
/// (dropdowns used to overflow by 50–70 px).
void main() {
  for (final id in ['generic_modbus', 'bosch_buderus_ems', 'viessmann_vicare', 'vaillant_ebusd', 'weishaupt_wem', 'nibe_modbus']) {
    testWidgets('settings fit 411 dp with $id selected', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(411 * 2.625, 12000);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);
      final provider = ECLProvider(autoLoadDatabase: false);
      await provider.setSelectedController(id);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: ChangeNotifierProvider<ECLProvider>.value(value: provider, child: const SettingsScreen()),
      ));
      await tester.pumpAndSettle();
      // overflow errors fail the test by themselves
      await tester.pumpWidget(const SizedBox.shrink());
      provider.dispose();
    });
  }
}
