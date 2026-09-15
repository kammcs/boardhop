import 'package:boardhop/features/diagnostics/wiki_probe/wiki_probe_page.dart';
import 'package:boardhop/features/wiki/widgets/wiki_markdown.dart';
import 'package:boardhop/features/wiki/widgets/wiki_source_page.dart';
import 'package:boardhop/features/wiki/widgets/wiki_tree_view.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wiki probe draws the hub's furniture on canned data, with no network,
/// no account and no repository — which is what makes it openable on a
/// simulator for the light/dark and dynamic-type checks.
void main() {
  Future<void> pump(WidgetTester tester, {Brightness? brightness}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? BoardhopTheme.dark()
            : BoardhopTheme.light(),
        home: const WikiProbePage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('it draws the tree, the recents and the reader', (tester) async {
    await pump(tester);

    expect(find.byType(WikiRecentsStrip), findsOneWidget);
    expect(find.byType(WikiTreeTile), findsWidgets);
    expect(find.byType(WikiMarkdown), findsOneWidget);
    // Expanded along the selected path (K1).
    expect(find.text('Boardhop'), findsWidgets);
    expect(find.text('Links'), findsWidgets);
    // The non-conformant row is listed and cannot be opened.
    expect(find.text('Pushed page'), findsOneWidget);
    expect(
      find.text('Not readable: the file name has a space'),
      findsOneWidget,
    );
  });

  testWidgets('the contents sheet is the page\'s h1–h3', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Contents'));
    await tester.pumpAndSettle();

    expect(find.text('Contents'), findsOneWidget);
    expect(find.text('Second heading'), findsWidgets);
    // h4 is out of the sheet (K9).
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.text('Fourth heading, not in the contents sheet'),
      ),
      findsNothing,
    );
  });

  testWidgets('Show source opens the raw markdown', (tester) async {
    await pump(tester);

    await tester.tap(find.byTooltip('Show source'));
    await tester.pumpAndSettle();

    expect(find.byType(WikiSourcePage), findsOneWidget);
  });

  testWidgets('it draws in dark too', (tester) async {
    await pump(tester, brightness: Brightness.dark);

    expect(find.byType(WikiMarkdown), findsOneWidget);
  });
}
