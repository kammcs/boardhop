import 'package:boardhop/features/diagnostics/board_probe/board_probe_data.dart';
import 'package:boardhop/features/diagnostics/frame_stats.dart';
import 'package:boardhop/features/diagnostics/board_probe/hand_rolled_board.dart';
import 'package:boardhop/features/diagnostics/board_probe/probe_widgets.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoardData', () {
    test('generate is deterministic and spreads cards over five columns', () {
      final a = BoardData.generate(cards: 200);
      final b = BoardData.generate(cards: 200);
      expect(a.cardCount, 200);
      expect(a.columns.length, 5);
      expect(a.columns.every((c) => c.cards.isNotEmpty), isTrue);
      for (var i = 0; i < 5; i++) {
        expect(
          a.columns[i].cards.map((c) => c.id),
          orderedEquals(b.columns[i].cards.map((c) => c.id)),
        );
      }
    });

    test('move uses the post-removal index convention', () {
      final data = BoardData.generate(cards: 50);
      final source = data.columns[0].cards.toList();
      final target = data.columns[1].cards.toList();
      final moved = data.move(
        fromColumn: 0,
        fromIndex: 0,
        toColumn: 1,
        toIndex: 2,
      );
      expect(moved.card.id, source[0].id);
      expect(data.columns[0].cards.length, source.length - 1);
      expect(data.columns[1].cards[2].id, source[0].id);
      expect(data.columns[1].cards[1].id, target[1].id);
      expect(data.columns[1].cards[3].id, target[2].id);
      expect(data.locate(moved.card), (1, 2));
    });

    test('move within a column and to the end clamps the index', () {
      final data = BoardData.generate(cards: 50);
      final ids = data.columns[0].cards.map((c) => c.id).toList();
      data.move(fromColumn: 0, fromIndex: 0, toColumn: 0, toIndex: 999);
      expect(data.columns[0].cards.last.id, ids.first);
      expect(data.columns[0].cards.first.id, ids[1]);
    });
  });

  group('FrameWindow', () {
    FrameTiming timing(int buildMs, int rasterMs) => FrameTiming(
      vsyncStart: 0,
      buildStart: 0,
      buildFinish: buildMs * 1000,
      rasterStart: buildMs * 1000,
      rasterFinish: (buildMs + rasterMs) * 1000,
      rasterFinishWallTime: (buildMs + rasterMs) * 1000,
    );

    test('flags a frame when either thread blows the budget', () {
      final w = FrameWindow()
        ..add(timing(2, 3))
        ..add(timing(20, 3))
        ..add(timing(2, 30))
        ..add(timing(40, 40));
      const budget = Duration(microseconds: 16667);
      expect(w.frames, 4);
      expect(w.janky(budget), 3);
      expect(w.janky(budget * 2), 1);
      expect(w.buildMax, 40);
      expect(w.rasterMax, 40);
      expect(w.summary(budget), contains('janky 3 (75.0%)'));
    });
  });

  group('HandRolledBoard', () {
    testWidgets('long-press drag moves a card into the next column', (
      tester,
    ) async {
      final data = BoardData.generate(cards: 60);
      final moves = <CardMove>[];
      var starts = 0;
      var ends = 0;
      final hooks = BoardProbeHooks(
        onDragStart: () => starts++,
        onDragEnd: () => ends++,
        onMove: moves.add,
      );
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(body: HandRolledBoard(data: data, hooks: hooks)),
        ),
      );
      final first = data.columns[0].cards.first;
      final firstFinder = find.text('${first.type} ${first.id}');
      expect(firstFinder, findsOneWidget);
      final targetTitle = data.columns[1].cards[1];
      final targetFinder = find.text(
        '${targetTitle.type} ${targetTitle.id}',
      );
      expect(targetFinder, findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(firstFinder),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.moveTo(tester.getCenter(targetFinder));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(starts, 1);
      expect(ends, 1);
      expect(moves.single.fromColumn, 0);
      expect(moves.single.toColumn, 1);
      expect(data.locate(first)?.$1, 1);
    });
  });
}
