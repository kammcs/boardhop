import 'package:boardhop/features/shared/dismiss_keyboard_on_drag.dart';
import 'package:boardhop/features/work_items/widgets/work_item_actions.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kelly, 2026-09-14: the keyboard goes away when a comment is posted, and a
/// swipe down the list puts it away while writing.
void main() {
  bool fieldHasFocus(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus;

  testWidgets('a posted comment takes the keyboard with it', (tester) async {
    final posted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: CommentComposer(
            onSubmit: (text) async {
              posted.add(text);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'ship it');
    await tester.pumpAndSettle();
    expect(fieldHasFocus(tester), isTrue);

    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(posted, ['ship it']);
    expect(fieldHasFocus(tester), isFalse);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );
  });

  testWidgets('a failed post keeps the text and the keyboard', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: CommentComposer(onSubmit: (_) async => false),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'offline?');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(fieldHasFocus(tester), isTrue);
    expect(find.text('offline?'), findsOneWidget);
  });

  testWidgets('dragging a list under DismissKeyboardOnDrag unfocuses', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: DismissKeyboardOnDrag(
            child: ListView(
              children: [
                TextField(focusNode: node),
                for (var i = 0; i < 40; i++) ListTile(title: Text('row $i')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.showKeyboard(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);
    await tester.drag(find.text('row 5'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(node.hasFocus, isFalse);
  });

  testWidgets('over the shell, the composer rides the keyboard', (
    tester,
  ) async {
    // The pull request page's Scaffold is the whole screen: a
    // bottomNavigationBar stays at the very bottom whatever the keyboard
    // does, so the composer grows by the inset instead.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: CommentComposer(onSubmit: (_) async => true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.getRect(find.byType(TextField));
    expect(field.bottom, lessThanOrEqualTo(500));
    expect(field.bottom, greaterThan(440));
  });

  testWidgets('inside the shell, with the inset already spent, it does not', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: CommentComposer(onSubmit: (_) async => true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.getRect(find.byType(TextField));
    expect(field.bottom, greaterThan(740));
  });
}
