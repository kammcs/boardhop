import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/features/work_items/form/controls/attachment_picker.dart';
import 'package:boardhop/features/work_items/form/controls/attachments_section.dart';
import 'package:boardhop/features/work_items/form/controls/tags_field.dart';
import 'package:boardhop/features/work_items/widgets/work_item_actions.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps one button that opens [open], at the given window size.
Future<void> _pumpOpener(
  WidgetTester tester,
  Future<void> Function(BuildContext context) open, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: BoardhopTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _openState(WidgetTester tester, {required Size size}) =>
    _pumpOpener(
      tester,
      (context) async {
        await pickStateChange(
          context,
          states: const ['New', 'Active', 'Resolved'],
          current: 'New',
          colorOf: (context, state) => Theme.of(context).colorScheme.primary,
        );
      },
      size: size,
    );

Future<void> _openTags(WidgetTester tester, {required Size size}) =>
    _pumpOpener(
      tester,
      (context) async {
        await pickTags(
          context,
          current: const ['boardhop'],
          suggestions: () async => const ['template'],
        );
      },
      size: size,
    );

Future<void> _openAttachmentSource(WidgetTester tester, {required Size size}) =>
    _pumpOpener(
      tester,
      (context) async {
        await showAttachmentSourceSheet(context);
      },
      size: size,
    );

void main() {
  // The three pickers that were bottom sheets at every width, beside
  // sibling controls that open anchored menus and centered dialogs inside
  // the tablet's own form dialog (iPad walkthrough).
  group('from medium up the form pickers are centered dialogs', () {
    const tablet = Size(1200, 900);

    testWidgets('the state transition list', (tester) async {
      await _openState(tester, size: tablet);

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.widgetWithText(ListTile, 'Active'), findsOneWidget);
    });

    testWidgets('the tags picker', (tester) async {
      await _openTags(tester, size: tablet);

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Tags'), findsOneWidget);
    });

    testWidgets('the add-attachment source list', (tester) async {
      await _openAttachmentSource(tester, size: tablet);

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Take photo'), findsOneWidget);
    });
  });

  group('a phone keeps the bottom sheets', () {
    const phone = Size(400, 900);

    testWidgets('the state transition list', (tester) async {
      await _openState(tester, size: phone);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      // The last row clears the home indicator.
      expect(find.byType(SafeArea), findsWidgets);
    });

    testWidgets('the tags picker and the attachment source list', (
      tester,
    ) async {
      await _openTags(tester, size: phone);
      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      await _openAttachmentSource(tester, size: phone);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('the attachment viewer', () {
    testWidgets('is a dark full-screen page with a close button', (
      tester,
    ) async {
      const info = AttachmentInfo(
        relation: WorkItemRelation(
          rel: WorkItemRelation.attachedFileRel,
          url: 'https://dev.azure.com/o/_apis/wit/attachments/abc',
        ),
        name: 'photo-20260912-095803.jpg',
        url: 'https://dev.azure.com/o/_apis/wit/attachments/abc',
        id: 'abc',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: AttachmentViewer(
            info: info,
            source: AttachmentSource(
              bytes: (_) async => throw UnimplementedError(),
              upload: (_, _) async => throw UnimplementedError(),
            ),
          ),
        ),
      );
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, Colors.black);
      expect(scaffold.extendBodyBehindAppBar, isTrue);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('photo-20260912-095803.jpg'), findsOneWidget);
    });
  });
}
