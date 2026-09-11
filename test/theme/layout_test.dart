import 'package:boardhop/theme/layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('content column follows the window up to the wide cap', () {
    expect(ContentColumn.widthFor(400), 400);
    expect(ContentColumn.widthFor(840), 840);
    // Grows with the window, keeping a margin on each side.
    expect(ContentColumn.widthFor(900), 852);
    expect(ContentColumn.widthFor(1032), 984);
    // iPad Pro 13" in landscape beside the rail: capped at the wide value.
    expect(ContentColumn.widthFor(1264), ContentColumn.wide);
    expect(ContentColumn.widthFor(2000), ContentColumn.wide);
  });

  Future<void> pump(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: const [
              SideBySide(start: [Text('start')], end: [Text('end')]),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('side by side sits in two columns when wide', (tester) async {
    await pump(tester, 1200);
    final start = tester.getTopLeft(find.text('start'));
    final end = tester.getTopLeft(find.text('end'));
    expect(start.dy, end.dy);
    expect(end.dx, greaterThan(start.dx + 400));
  });

  testWidgets('side by side stacks when narrow', (tester) async {
    await pump(tester, 600);
    final start = tester.getTopLeft(find.text('start'));
    final end = tester.getTopLeft(find.text('end'));
    expect(start.dx, end.dx);
    expect(end.dy, greaterThan(start.dy));
  });
}
