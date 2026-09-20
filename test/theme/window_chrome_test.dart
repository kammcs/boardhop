import 'package:boardhop/core/display_cutout.dart';
import 'package:boardhop/theme/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/duo_display.dart';

/// The wrapper above the router (`MaterialApp.builder`) that gives every
/// route **outside** the project shell the two things the shell gives its
/// own pages: the corner-adapted clearance and the crease padding
/// (research/23 §9.13).
void main() {
  /// Pumps a page under a [WindowChrome] and answers with the
  /// `MediaQuery.padding` that page is given. [shell] mirrors what
  /// `ProjectShell` does — take the raw padding back — so the same pose
  /// can be read from both sides of the wrapper.
  Future<EdgeInsets> pump(
    WidgetTester tester, {
    required Size window,
    required EdgeInsets insets,
    DisplayRegions? regions,
    BarEdge barEdge = BarEdge.unspecified,
    EdgeInsets corner = EdgeInsets.zero,
    bool shell = false,
  }) async {
    tester.view.physicalSize = window;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(
      left: insets.left,
      top: insets.top,
      right: insets.right,
      bottom: insets.bottom,
    );
    addTearDown(tester.view.reset);
    late EdgeInsets seen;
    final page = Builder(
      builder: (context) {
        seen = MediaQuery.paddingOf(context);
        return const SizedBox.expand();
      },
    );
    await tester.pumpWidget(
      Duo.scope(
        window: window,
        regions: regions,
        barEdge: barEdge,
        cornerInsets: corner,
        child: MaterialApp(
          builder: (context, child) =>
              WindowChrome(child: child ?? const SizedBox.shrink()),
          home: shell
              ? Builder(
                  builder: (context) =>
                      WindowChrome.unwrap(context, child: page),
                )
              : page,
        ),
      ),
    );
    // `CreasePadding` reads the band through the box's own transform, which
    // the first layout has not written yet (research/23 §9.10).
    await tester.pump();
    return seen;
  }

  group('outside the shell', () {
    testWidgets('a route takes the corner clearance on the leading edge', (
      tester,
    ) async {
      final padding = await pump(
        tester,
        window: Duo.wide,
        insets: Duo.wideInsets,
        barEdge: BarEdge.trailing,
        corner: Duo.wideCorner,
      );
      // 16 pt where iOS reports zero and the display is curved all the
      // same; the trailing 84 is the system's own bar column, untouched.
      expect(padding, const EdgeInsets.fromLTRB(16, 0, 84, 34));
    });

    testWidgets('the corner goes on the side away from the bar', (
      tester,
    ) async {
      final padding = await pump(
        tester,
        window: Duo.wide,
        insets: const EdgeInsets.fromLTRB(84, 0, 0, 34),
        barEdge: BarEdge.leading,
        corner: const EdgeInsets.fromLTRB(84, 0, 16, 34),
      );
      expect(padding, const EdgeInsets.fromLTRB(84, 0, 16, 34));
    });

    testWidgets('nothing changes where iOS asks for no vertical bar', (
      tester,
    ) async {
      // Every phone and tablet: the corner-adapted region answers there
      // too, and taking it would move every page in the app sideways for
      // a curve the layout has always cleared.
      final padding = await pump(
        tester,
        window: Duo.wide,
        insets: Duo.wideInsets,
        corner: Duo.wideCorner,
      );
      expect(padding, Duo.wideInsets);
    });

    testWidgets('a horizontal crease pads the page clear of the fold', (
      tester,
    ) async {
      final padding = await pump(
        tester,
        window: Duo.tall,
        insets: Duo.tallInsets,
        regions: Duo.folded(Duo.tallBand),
        barEdge: BarEdge.unspecified,
      );
      // The band's near edge: content at rest, and anything anchored to
      // the bottom, stops above the fold.
      expect(padding.bottom, closeTo(Duo.tall.height - Duo.tallBand.top, 0.5));
      expect(padding.top, Duo.tallInsets.top);
    });

    testWidgets('a flat display is left exactly as it was', (tester) async {
      final padding = await pump(
        tester,
        window: Duo.tall,
        insets: Duo.tallInsets,
        regions: Duo.flat(Duo.tallBand),
      );
      expect(padding, Duo.tallInsets);
    });
  });

  group('inside the shell', () {
    testWidgets('the corner is not taken twice', (tester) async {
      final padding = await pump(
        tester,
        window: Duo.wide,
        insets: Duo.wideInsets,
        barEdge: BarEdge.trailing,
        corner: Duo.wideCorner,
        shell: true,
      );
      // The shell insets its own pages from these numbers; the wrapper's
      // 16 pt would have moved the rail's column and the fade with it.
      expect(padding, Duo.wideInsets);
    });

    testWidgets('the crease padding is the shell\'s own to add', (
      tester,
    ) async {
      final padding = await pump(
        tester,
        window: Duo.tall,
        insets: Duo.tallInsets,
        regions: Duo.folded(Duo.tallBand),
        shell: true,
      );
      expect(padding, Duo.tallInsets);
    });
  });
}
