import 'dart:async';

import 'package:boardhop/core/http/ado_exceptions.dart';
import 'package:boardhop/data/models/work_item_form.dart';
import 'package:boardhop/features/pull_requests/diff/diff_model.dart';
import 'package:boardhop/features/pull_requests/diff/diff_view.dart';
import 'package:boardhop/features/work_items/form/controls/attachment_picker.dart';
import 'package:boardhop/features/work_items/form/controls/attachments_section.dart'
    show AttachmentSource;
import 'package:boardhop/features/work_items/widgets/work_item_actions.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// research/17 decisions T3, T6, T7, T8 and T10 on the composer that writes
/// a work item comment, plus the diff-line composer. Every fake here is a
/// closure: `pick` is injected, so no test opens a platform picker.

const wit = 'https://dev.azure.com/puremedia/proj/_apis/wit/attachments';

final imageBytes = Uint8List.fromList(const [
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

PickedAttachment shot([String name = 'shot.png']) =>
    PickedAttachment(name: name, size: 5_432, bytes: imageBytes);

PickedAttachment notes() => PickedAttachment(
  name: 'notes.txt',
  size: 12,
  bytes: Uint8List.fromList(const [104, 105]),
);

/// A file over the 60 MB cap: `pickAttachment` never reads its bytes.
PickedAttachment huge() =>
    const PickedAttachment(name: 'capture.mov', size: 80 * 1024 * 1024);

void main() {
  late List<String> posted;
  late List<(String, int)> uploaded;
  late List<PickedAttachment> queue;
  late Object? uploadThrows;

  /// Held by the one test that needs to see an upload in flight.
  late Completer<void>? uploadGate;

  setUp(() {
    posted = [];
    uploaded = [];
    queue = [];
    uploadThrows = null;
    uploadGate = null;
  });

  AttachmentSource source() => AttachmentSource(
    bytes: (url) async => imageBytes,
    upload: (name, bytes) async {
      uploaded.add((name, bytes.length));
      await uploadGate?.future;
      final failure = uploadThrows;
      if (failure != null) throw failure;
      return AttachmentRef(
        id: 'a${uploaded.length}',
        url: '$wit/guid-${uploaded.length}?fileName=$name',
        fileName: name,
      );
    },
  );

  /// The picker the sheet's choice runs: hands back whatever the test
  /// queued, in order.
  Future<PickedAttachment?> pick(AttachmentPickSource _) async =>
      queue.isEmpty ? null : queue.removeAt(0);

  Future<void> pumpComposer(
    WidgetTester tester, {
    AttachmentSource? attachments,
    bool offline = false,
    void Function(int files)? onAttachmentsDropped,
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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
            attachments: attachments,
            offline: offline,
            onAttachmentsDropped: onAttachmentsDropped,
            pick: pick,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the sheet and takes the first source: what the user does.
  Future<void> attach(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from library'));
    await tester.pumpAndSettle();
  }

  group('the attach button', () {
    testWidgets('is absent without a source, so every existing host is '
        'unchanged', (tester) async {
      await pumpComposer(tester);
      expect(find.byIcon(Icons.attach_file), findsNothing);
    });

    testWidgets('is absent when the source cannot upload (a read-only host)', (
      tester,
    ) async {
      await pumpComposer(
        tester,
        attachments: AttachmentSource(bytes: (url) async => imageBytes),
      );
      expect(find.byIcon(Icons.attach_file), findsNothing);
    });

    testWidgets('is there with a source, left of Send', (tester) async {
      await pumpComposer(tester, attachments: source());
      expect(find.byTooltip('Attach a file'), findsOneWidget);
      expect(
        tester.getCenter(find.byIcon(Icons.attach_file)).dx,
        lessThan(tester.getCenter(find.byIcon(Icons.send)).dx),
      );
    });

    testWidgets('is disabled offline, and says why (T6)', (tester) async {
      await pumpComposer(tester, attachments: source(), offline: true);
      expect(find.byTooltip('Attachments need a connection'), findsOneWidget);
      expect(find.byTooltip('Attach a file'), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.attach_file),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('picking', () {
    testWidgets('a pick becomes a chip, and several accumulate (T7)', (
      tester,
    ) async {
      await pumpComposer(tester, attachments: source());
      queue = [shot(), notes()];
      await attach(tester);
      expect(find.byType(InputChip), findsOneWidget);
      await attach(tester);
      expect(find.byType(InputChip), findsNWidgets(2));
      expect(find.textContaining('shot.png'), findsOneWidget);
      expect(find.textContaining('notes.txt'), findsOneWidget);
      // Nothing has gone up yet: the upload is on Send (T3).
      expect(uploaded, isEmpty);
    });

    testWidgets('backing out of the picker leaves nothing behind', (
      tester,
    ) async {
      await pumpComposer(tester, attachments: source());
      await attach(tester);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('an oversize pick is refused inline, with no chip', (
      tester,
    ) async {
      await pumpComposer(tester, attachments: source());
      queue = [huge()];
      await attach(tester);
      expect(find.byType(InputChip), findsNothing);
      expect(
        find.textContaining('Azure DevOps accepts attachments up to'),
        findsOneWidget,
      );
      final style = tester
          .widget<Text>(
            find.textContaining('Azure DevOps accepts attachments up to'),
          )
          .style;
      expect(style?.color, BoardhopTheme.light().colorScheme.error);
    });

    testWidgets('a chip can be removed before Send', (tester) async {
      await pumpComposer(tester, attachments: source());
      queue = [shot(), notes()];
      await attach(tester);
      await attach(tester);
      await tester.tap(find.byTooltip('Remove shot.png'));
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsOneWidget);
      expect(find.textContaining('shot.png'), findsNothing);
    });
  });

  group('Send', () {
    testWidgets('uploads every file, then posts the trailing block in order '
        '(T8)', (tester) async {
      await pumpComposer(tester, attachments: source());
      queue = [shot(), notes()];
      await attach(tester);
      await attach(tester);
      await tester.enterText(find.byType(TextField), 'see these');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(uploaded, [('shot.png', imageBytes.length), ('notes.txt', 2)]);
      expect(posted, [
        'see these\n\n'
            '![shot.png]($wit/guid-1?fileName=shot.png)\n\n'
            '[notes.txt]($wit/guid-2?fileName=notes.txt)',
      ]);
      // The comment went: the chips and the text go with it.
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('see these'), findsNothing);
    });

    testWidgets('a comment may be files alone', (tester) async {
      await pumpComposer(tester, attachments: source());
      queue = [shot()];
      await attach(tester);
      // No text at all, and Send is live.
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.send),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(posted, ['![shot.png]($wit/guid-1?fileName=shot.png)']);
    });

    testWidgets('an empty composer still cannot Send', (tester) async {
      await pumpComposer(tester, attachments: source());
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byIcon(Icons.send),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('the upload in flight is what the spinner covers (T3)', (
      tester,
    ) async {
      await pumpComposer(tester, attachments: source());
      queue = [shot()];
      await attach(tester);
      await tester.enterText(find.byType(TextField), 'hold on');
      await tester.pumpAndSettle();

      // The host is not busy — it has not been asked to post yet — so the
      // spinner can only be the composer's own.
      final gate = uploadGate = Completer<void>();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      // One on the chip, one where the Send glyph was.
      expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
      expect(find.byIcon(Icons.send), findsNothing);
      // And nothing can be removed while it is on its way (T3): Material
      // animates the delete button out, so look after it has gone.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byTooltip('Remove shot.png'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(posted.length, 1);
      expect(find.byIcon(Icons.send), findsOneWidget);
    });

    testWidgets('a refused upload keeps the text and the chips and posts '
        'nothing (T3)', (tester) async {
      await pumpComposer(tester, attachments: source());
      queue = [shot()];
      await attach(tester);
      await tester.enterText(find.byType(TextField), 'important');
      await tester.pumpAndSettle();
      uploadThrows = const AdoServerException('The file is empty.');

      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(posted, isEmpty);
      expect(find.text('important'), findsOneWidget);
      expect(find.byType(InputChip), findsOneWidget);
      // The service's own words, on the chip that failed (T2).
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip).first).message,
        'The file is empty.',
      );

      // And it can be sent again once the cause is gone.
      uploadThrows = null;
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(posted.length, 1);
    });

    testWidgets('going offline mid-composition drops the files, keeps the '
        'comment and tells the host how many (T6)', (tester) async {
      var dropped = -1;
      await pumpComposer(
        tester,
        attachments: source(),
        onAttachmentsDropped: (files) => dropped = files,
      );
      queue = [shot(), notes()];
      await attach(tester);
      await attach(tester);
      await tester.enterText(find.byType(TextField), 'still worth saying');
      await tester.pumpAndSettle();
      uploadThrows = const AdoNetworkException('offline');

      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(dropped, 2);
      // The text alone reaches the host, which queues it.
      expect(posted, ['still worth saying']);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('offline with no text at all posts nothing: there would be '
        'an empty comment', (tester) async {
      await pumpComposer(
        tester,
        attachments: source(),
        onAttachmentsDropped: (_) {},
      );
      queue = [shot()];
      await attach(tester);
      uploadThrows = const AdoNetworkException('offline');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(posted, isEmpty);
      expect(find.byType(InputChip), findsOneWidget);
    });

    testWidgets('a host with no queue keeps the chips instead (a pull '
        'request)', (tester) async {
      await pumpComposer(tester, attachments: source());
      queue = [shot()];
      await attach(tester);
      await tester.enterText(find.byType(TextField), 'nope');
      await tester.pumpAndSettle();
      uploadThrows = const AdoNetworkException('offline');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(posted, isEmpty);
      expect(find.byType(InputChip), findsOneWidget);
    });
  });

  group('the Android keyboard (T10)', () {
    /// What `contentInsertionConfiguration` is wired to.
    ContentInsertionConfiguration? configuration(WidgetTester tester) => tester
        .widget<TextField>(find.byType(TextField))
        .contentInsertionConfiguration;

    testWidgets('an inserted image becomes a chip', (tester) async {
      await pumpComposer(tester, attachments: source());
      final config = configuration(tester);
      expect(config, isNotNull);
      expect(config!.allowedMimeTypes, contains('image/png'));

      config.onContentInserted(
        KeyboardInsertedContent(
          mimeType: 'image/png',
          uri: 'content://com.google.android.inputmethod/1',
          data: imageBytes,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsOneWidget);
      // Named off the clock and the MIME type: the keyboard sends neither.
      expect(find.textContaining('keyboard-'), findsOneWidget);
      expect(find.textContaining('.png'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(uploaded.single.$1, startsWith('keyboard-'));
      expect(posted.single, startsWith('!['));
    });

    testWidgets('content with no bytes is ignored', (tester) async {
      await pumpComposer(tester, attachments: source());
      configuration(tester)!.onContentInserted(
        const KeyboardInsertedContent(
          mimeType: 'image/png',
          uri: 'content://x/1',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('no source, and offline, mean no configuration at all', (
      tester,
    ) async {
      await pumpComposer(tester);
      expect(configuration(tester), isNull);
      await pumpComposer(tester, attachments: source(), offline: true);
      expect(configuration(tester), isNull);
    });
  });

  group('the diff-line composer', () {
    Future<void> pumpDiff(
      WidgetTester tester, {
      AttachmentSource? attachments,
    }) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final diff = LineDiff.compute('one\ntwo\n', 'one\ntwo\nthree\n');
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: DiffView(
              diff: diff,
              oldRuns: const [],
              newRuns: const [],
              canAct: true,
              composerLine: 3,
              uploads: attachments,
              pick: pick,
              onPost: (line, text) async => posted.add(text),
              onCancelComposer: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('has no attach button without a source', (tester) async {
      await pumpDiff(tester);
      expect(find.text('Post'), findsOneWidget);
      expect(find.byIcon(Icons.attach_file), findsNothing);
    });

    testWidgets('attaches, uploads on Post and appends the link', (
      tester,
    ) async {
      await pumpDiff(tester, attachments: source());
      queue = [shot()];
      await attach(tester);
      expect(find.byType(InputChip), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'see the shot');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();

      expect(uploaded.single.$1, 'shot.png');
      expect(posted, [
        'see the shot\n\n![shot.png]($wit/guid-1?fileName=shot.png)',
      ]);
    });

    testWidgets('the attach button is at the leading edge, Post at the '
        'trailing one', (tester) async {
      await pumpDiff(tester, attachments: source());
      expect(
        tester.getCenter(find.byIcon(Icons.attach_file)).dx,
        lessThan(tester.getCenter(find.text('Cancel')).dx),
      );
      expect(
        tester.getCenter(find.text('Cancel')).dx,
        lessThan(tester.getCenter(find.text('Post')).dx),
      );
    });
  });
}
