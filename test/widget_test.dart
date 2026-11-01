import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/main.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/home_screen.dart';
import 'package:heizungstrainer/screens/live_view_screen.dart';

void main() {
  testWidgets('App renders title text', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ECLProvider(),
        child: const HeizungstrainerApp(),
      ),
    );

    expect(find.textContaining('Heizungstrainer'), findsWidgets);
    expect(find.textContaining('ECL 310'), findsWidgets);
  });

  testWidgets('MainShell uses IndexedStack to maintain tab state', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ECLProvider(),
        child: const MaterialApp(
          home: MainShell(),
        ),
      ),
    );

    // Initial tab: HomeScreen is active and visible
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(IndexedStack), findsOneWidget);

    // Tab 'Live': the live view exists only while its tab is open (it polls)
    expect(find.byType(LiveViewScreen, skipOffstage: false), findsNothing);
    await tester.tap(find.text('Live'));
    await tester.pump();
    expect(find.byType(LiveViewScreen), findsOneWidget);

    // Switch to 'Urlaub'
    await tester.tap(find.text('Urlaub'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
    expect(find.textContaining('Urlaub & Abwesenheit'), findsOneWidget);
    expect(find.byType(LiveViewScreen, skipOffstage: false), findsNothing);

    // Switch to tab 2 ('Vergleich')
    await tester.tap(find.text('Vergleich'));
    await tester.pumpAndSettle();

    // With IndexedStack, HomeScreen is preserved in the tree with state maintained
    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
    expect(find.text('Community-Vergleich'), findsOneWidget);

    // Switch to tab 'Backup'
    await tester.tap(find.text('Backup'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
    expect(find.text('Backup'), findsWidgets);
  });
}
