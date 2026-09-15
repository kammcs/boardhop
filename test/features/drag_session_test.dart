import 'package:boardhop/features/boards/widgets/drag_session.dart';
import 'package:boardhop/features/boards/widgets/kanban_board.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dragScrollDelta', () {
    test('is zero away from both edges', () {
      expect(DragSession.dragScrollDelta(300, 0, 800), 0);
    });

    test('pulls back near the start of the band and forward near the end', () {
      expect(DragSession.dragScrollDelta(0, 0, 800), -DragSession.maxSpeed);
      expect(DragSession.dragScrollDelta(800, 0, 800), DragSession.maxSpeed);
      expect(
        DragSession.dragScrollDelta(32, 0, 800),
        -DragSession.maxSpeed / 2,
      );
    });

    test('the band starts below the header, not at the top', () {
      // 60 is inside the header + edge band when the header is 52 high.
      expect(DragSession.dragScrollDelta(60, 52, 800), lessThan(0));
      expect(DragSession.dragScrollDelta(120, 52, 800), 0);
    });
  });

  group('boardHeaderHeight', () {
    Future<double> measure(WidgetTester tester, TextScaler scaler) async {
      late double value;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: scaler),
          child: Builder(
            builder: (context) {
              value = boardHeaderHeight(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return value;
    }

    testWidgets('follows the text scaler and stops at 3x', (tester) async {
      expect(await measure(tester, TextScaler.noScaling), kBoardHeaderHeight);
      expect(
        await measure(tester, const TextScaler.linear(1.3)),
        closeTo(kBoardHeaderHeight * 1.3, 0.01),
      );
      expect(
        await measure(tester, const TextScaler.linear(5)),
        kBoardHeaderHeight * 3,
      );
    });
  });

  group('kanbanColumnWidth', () {
    test('most of a phone, capped for a tablet', () {
      expect(kanbanColumnWidth(400), 320);
      expect(kanbanColumnWidth(200), 240);
      expect(kanbanColumnWidth(1200), 320);
    });

    test('the cap follows the text scale, up to 1.6x', () {
      expect(kanbanColumnWidth(1200, textScale: 1.3), closeTo(416, 0.01));
      expect(kanbanColumnWidth(1200, textScale: 3), closeTo(512, 0.01));
      // A smaller-than-normal scale never shrinks the cap.
      expect(kanbanColumnWidth(1200, textScale: 0.8), 320);
    });
  });
}
