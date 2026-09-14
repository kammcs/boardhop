import 'dart:typed_data';

import 'package:boardhop/features/shared/attachments/pending_attachments.dart';
import 'package:boardhop/features/work_items/form/controls/attachment_picker.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// research/17 decision T7: the chip strip above a comment field. What is
/// about to be sent has to be readable and removable before Send, and a
/// refusal has to be visible on the file it belongs to.

/// A 1x1 PNG, so `Image.memory` has something real to decode.
final pngBytes = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

PendingAttachment image({bool uploading = false, String? error}) =>
    PendingAttachment(
      picked: PickedAttachment(name: 'shot.png', size: 5_432, bytes: pngBytes),
      uploading: uploading,
      error: error,
    );

PendingAttachment file() => PendingAttachment(
  picked: PickedAttachment(
    name: 'notes.txt',
    size: 1_024,
    bytes: Uint8List.fromList(const [104, 105]),
  ),
);

void main() {
  Future<void> pump(
    WidgetTester tester,
    List<PendingAttachment> attachments, {
    void Function(PendingAttachment)? onRemove,
    ThemeData? theme,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? BoardhopTheme.light(),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(textScale),
              size: const Size(400, 800),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 380,
                child: PendingAttachmentsBar(
                  attachments: attachments,
                  onRemove: onRemove,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an empty strip draws nothing', (tester) async {
    await pump(tester, const []);
    expect(find.byType(InputChip), findsNothing);
    expect(find.byType(Wrap), findsNothing);
  });

  testWidgets('a picked image previews itself from memory, with its size', (
    tester,
  ) async {
    await pump(tester, [image()]);
    expect(find.byType(InputChip), findsOneWidget);
    // The bytes are already in hand: no network round-trip to draw a chip.
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('shot.png'), findsOneWidget);
    expect(find.textContaining('5 KB'), findsOneWidget);
  });

  testWidgets('anything else gets the type glyph', (tester) async {
    await pump(tester, [file()]);
    expect(find.byType(Image), findsNothing);
    // `.txt` — the same glyph the attachment rows use.
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
  });

  testWidgets('a chip can be removed before Send', (tester) async {
    final removed = <String>[];
    await pump(tester, [image(), file()], onRemove: (a) => removed.add(a.name));
    expect(find.byType(InputChip), findsNWidgets(2));
    await tester.tap(find.byTooltip('Remove notes.txt'));
    await tester.pump();
    expect(removed, ['notes.txt']);
  });

  testWidgets('an upload in flight shows progress and cannot be removed', (
    tester,
  ) async {
    await pump(tester, [image(uploading: true)], onRemove: (_) {});
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Remove shot.png'), findsNothing);
  });

  testWidgets('no remover at all leaves the chips without a delete button', (
    tester,
  ) async {
    await pump(tester, [image()]);
    expect(find.byTooltip('Remove shot.png'), findsNothing);
  });

  testWidgets('a refused upload paints the chip and keeps the message', (
    tester,
  ) async {
    const message = 'The file is empty.';
    await pump(tester, [image(error: message)], onRemove: (_) {});
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    final scheme = BoardhopTheme.light().colorScheme;
    expect(
      tester.widget<InputChip>(find.byType(InputChip)).backgroundColor,
      scheme.errorContainer,
    );
    // The service's own words, verbatim (T2), in the tooltip.
    expect(tester.widget<Tooltip>(find.byType(Tooltip).first).message, message);
  });

  testWidgets('dark mode takes its colours from the theme', (tester) async {
    await pump(tester, [image(error: 'nope')], theme: BoardhopTheme.dark());
    expect(
      tester.widget<InputChip>(find.byType(InputChip)).backgroundColor,
      BoardhopTheme.dark().colorScheme.errorContainer,
    );
  });

  testWidgets('at xxxL the chips wrap instead of overflowing', (tester) async {
    await pump(
      tester,
      [image(), file(), image()],
      onRemove: (_) {},
      // The largest dynamic type iOS offers.
      textScale: 3.2,
    );
    expect(tester.takeException(), isNull);
    final chips = tester.widgetList<InputChip>(find.byType(InputChip));
    expect(chips.length, 3);
    // Three chips at 3.2x cannot share one 380 pt row: the Wrap ran on.
    final tops = {
      for (final chip in find.byType(InputChip).evaluate())
        tester.getRect(find.byWidget(chip.widget)).top,
    };
    expect(tops.length, greaterThan(1));
    for (final chip in find.byType(InputChip).evaluate()) {
      expect(tester.getRect(find.byWidget(chip.widget)).right, lessThan(381));
    }
  });
}
