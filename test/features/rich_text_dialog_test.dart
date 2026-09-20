import 'dart:async';

import 'package:boardhop/core/display_cutout.dart';
import 'package:boardhop/features/work_items/form/controls/rich_text_control.dart';
import 'package:boardhop/theme/boardhop_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/duo_display.dart';

/// The rich text editor's dialog goes through `showBoardhopDialog` like
/// every other dialog in the app, so a fold puts it on one half — and
/// moves it there if the fold happens while it is open (research/23 §9.13).
///
/// Markdown throughout: the HTML side of the editor is a WebView, which a
/// widget test cannot host, and the dialog around it is the same either
/// way.
void main() {
  late BuildContext pageContext;

  Future<ValueNotifier<DisplayRegions>> pump(
    WidgetTester tester, {
    required DisplayRegions regions,
  }) async {
    tester.view.physicalSize = Duo.wide;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(right: 84, bottom: 34);
    addTearDown(tester.view.reset);
    final live = ValueNotifier<DisplayRegions>(regions);
    addTearDown(live.dispose);
    await tester.pumpWidget(
      ValueListenableBuilder<DisplayRegions>(
        valueListenable: live,
        builder: (context, value, _) => Duo.scope(
          window: Duo.wide,
          regions: value,
          barEdge: BarEdge.trailing,
          child: MaterialApp(
            theme: BoardhopTheme.light(),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  pageContext = context;
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return live;
  }

  void open() => unawaited(
    openRichTextEditor(
      pageContext,
      title: 'Description',
      content: '# hello',
      format: 'markdown',
    ),
  );

  testWidgets('opens on one half of a folded display', (tester) async {
    await pump(tester, regions: Duo.folded(Duo.wideBand));
    open();
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(Dialog));
    // The trailing half, the fallback for a whole-page opener, and clear
    // of the system's 84 pt bar column on that edge.
    expect(box.left, greaterThanOrEqualTo(Duo.creaseLine));
    expect(box.right, lessThanOrEqualTo(951 - 84));
  });

  testWidgets('spans the window when nothing is folded', (tester) async {
    await pump(tester, regions: Duo.flat(Duo.wideBand));
    open();
    await tester.pumpAndSettle();
    final box = tester.getRect(find.byType(Dialog));
    expect(box.left, lessThan(Duo.creaseLine));
    expect(box.right, greaterThan(Duo.creaseLine));
  });

  testWidgets('moves to a half when the display folds under it', (
    tester,
  ) async {
    final live = await pump(tester, regions: Duo.flat(Duo.wideBand));
    open();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Dialog)).left, lessThan(Duo.creaseLine));

    live.value = Duo.folded(Duo.wideBand);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byType(Dialog)).left,
      greaterThanOrEqualTo(Duo.creaseLine),
    );
    // The editor itself was never rebuilt from scratch — the same widget
    // instance is handed back on every rebuild, which is what keeps the
    // WebView alive on a device (research/23 §9.12, F3).
    expect(find.byType(RichTextEditor), findsOneWidget);
  });
}
