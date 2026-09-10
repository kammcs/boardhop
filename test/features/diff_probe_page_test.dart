import 'package:boardhop/features/diagnostics/diff_probe/diff_probe_page.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('diff probe renders the fixture and the live controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 2856);
    tester.view.devicePixelRatio = 3.2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: BoardhopTheme.light(), home: const DiffProbePage()),
    );
    // initState schedules the fixture load after the first frame.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.textContaining('sample.dart'), findsOneWidget);
    expect(find.text('/// Generated fixture for spike F5.'), findsOneWidget);

    await tester.tap(find.text('Live PR'));
    await tester.pump();
    expect(find.text('Load'), findsOneWidget);
    final org = tester.getSize(find.widgetWithText(TextField, 'Org'));
    expect(org.width, greaterThan(100));
    expect(tester.takeException(), isNull);
  });
}
