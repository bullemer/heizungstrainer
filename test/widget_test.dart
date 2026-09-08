import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/main.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';
import 'package:heizungstrainer/screens/home_screen.dart';

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

    // Switch to tab 1 ('Urlaub')
    await tester.tap(find.text('Urlaub'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
    expect(find.textContaining('Urlaub & Abwesenheit'), findsOneWidget);

    // Switch to tab 2 ('Vergleich')
    await tester.tap(find.text('Vergleich'));
    await tester.pumpAndSettle();

    // With IndexedStack, HomeScreen is preserved in the tree with state maintained
    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
    expect(find.text('Community Vergleich'), findsOneWidget);

    // Switch to tab 3 ('Sicherungen')
    await tester.tap(find.text('Sicherungen'));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
    expect(find.text('Sicherungen'), findsWidgets);
  });
}
