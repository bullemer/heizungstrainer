import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:heizungstrainer/main.dart';
import 'package:heizungstrainer/providers/ecl_provider.dart';

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
}
