import 'dart:typed_data';

import 'package:boardhop/features/shared/attachments/inline_attachment_source.dart';
import 'package:boardhop/features/shared/attachments/inline_attachments.dart';
import 'package:boardhop/features/shared/mention/mention_markdown.dart';
import 'package:boardhop/features/work_items/form/controls/attachments_section.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic ids; the URL shapes are the ones spikes w32/s50 measured.
const guid = 'c50b0d6e-1111-4222-8333-444455556666';
const repoGuid = '9a8b7c6d-5555-4444-8333-222211110000';
const projectGuid = '98720989-1234-4321-8888-aaaabbbbcccc';

const witImage =
    'https://dev.azure.com/contoso/$projectGuid'
    '/_apis/wit/attachments/$guid?fileName=shot.png';
const witFile =
    'https://dev.azure.com/contoso/$projectGuid'
    '/_apis/wit/attachments/$guid?fileName=notes.txt';
const prImage =
    'https://dev.azure.com/contoso/$projectGuid'
    '/_apis/git/repositories/$repoGuid/pullRequests/8334/attachments/shot.png';
const elsewhere = 'https://example.com/pictures/cat.png';

/// What the host answers with: the tap is recorded rather than performed, so
/// the routing can be read without a navigator or a share sheet.
class _Opened {
  final urls = <String>[];
  final names = <String>[];
  String? message;

  InlineAttachments get attachments => InlineAttachments(
    headers: const {'Authorization': 'Bearer tok'},
    onOpen: (context, url, name) async {
      urls.add(url);
      names.add(name);
      return message;
    },
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: BoardhopTheme.light(),
  home: Scaffold(body: child),
);

Future<void> _pump(
  WidgetTester tester,
  String data, {
  InlineAttachments? attachments,
}) async {
  await tester.pumpWidget(
    _app(MentionMarkdown(data: data, attachments: attachments)),
  );
  await tester.pump();
}

/// The provider behind the one image on screen.
ImageProvider _provider(WidgetTester tester) =>
    tester.widget<Image>(find.byType(Image)).image;

void main() {
  group('an image in a Markdown body', () {
    testWidgets('an attachment is fetched with the bearer token', (
      tester,
    ) async {
      final host = _Opened();
      await _pump(
        tester,
        '![a shot]($witImage)',
        attachments: host.attachments,
      );

      final provider = _provider(tester);
      expect(provider, isA<CachedNetworkImageProvider>());
      expect((provider as CachedNetworkImageProvider).headers, {
        'Authorization': 'Bearer tok',
      });
      expect(provider.url, witImage);
    });

    testWidgets('a pull request attachment too', (tester) async {
      final host = _Opened();
      await _pump(tester, '![]($prImage)', attachments: host.attachments);

      expect(_provider(tester), isA<CachedNetworkImageProvider>());
    });

    testWidgets('height is capped so a photo cannot fill the page', (
      tester,
    ) async {
      final host = _Opened();
      await _pump(
        tester,
        '![a shot]($witImage)',
        attachments: host.attachments,
      );

      final box = tester.widget<ConstrainedBox>(
        find
            .ancestor(
              of: find.byType(Image),
              matching: find.byType(ConstrainedBox),
            )
            .first,
      );
      expect(box.constraints.maxHeight, inlineImageMaxHeight);
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.scaleDown);
    });

    testWidgets('a URL that is not an attachment gets no headers', (
      tester,
    ) async {
      final host = _Opened();
      await _pump(tester, '![cat]($elsewhere)', attachments: host.attachments);

      final provider = _provider(tester);
      expect(provider, isA<NetworkImage>());
      expect((provider as NetworkImage).headers, isNull);
    });

    testWidgets(
      'a failed load shows the glyph and the alt text, never a blank',
      (tester) async {
        final host = _Opened();
        // `Image.network` in a widget test gets flutter_test's canned 400, so
        // the error builder is what is drawn (T9: never an empty box).
        await _pump(
          tester,
          '![cat]($elsewhere)',
          attachments: host.attachments,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
        expect(find.text('cat'), findsOneWidget);
      },
    );

    testWidgets('with no alt text the broken row names the file', (
      tester,
    ) async {
      final host = _Opened();
      await _pump(
        tester,
        '![](${elsewhere.replaceFirst('cat.png', 'dog.png')})',
        attachments: host.attachments,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(find.text('dog.png'), findsOneWidget);
    });

    testWidgets('tapping an attachment image opens it', (tester) async {
      final host = _Opened();
      await _pump(
        tester,
        '![a shot]($witImage)',
        attachments: host.attachments,
      );

      // The tap is invoked rather than gestured: an image whose bytes never
      // arrive lays out at zero size in a test, so there is nothing to hit.
      final tap = find.ancestor(
        of: find.byType(Image),
        matching: find.byType(GestureDetector),
      );
      expect(tap, findsOneWidget);
      tester.widget<GestureDetector>(tap).onTap!();
      await tester.pump();

      expect(host.urls, [witImage]);
      expect(host.names, ['shot.png']);
    });

    testWidgets('an image with no opener is inert rather than broken', (
      tester,
    ) async {
      await _pump(tester, '![a shot]($witImage)');

      expect(find.byType(Image), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(Image),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });
  });

  group('a file link in a Markdown body', () {
    testWidgets('an attachment href opens through the host', (tester) async {
      final host = _Opened();
      await _pump(
        tester,
        '[notes.txt]($witFile)',
        attachments: host.attachments,
      );

      await tester.tap(find.text('notes.txt'));
      await tester.pump();

      expect(host.urls, [witFile]);
      expect(host.names, ['notes.txt']);
    });

    testWidgets('an ordinary link does not', (tester) async {
      final host = _Opened();
      await _pump(
        tester,
        '[the docs](https://example.com/docs)',
        attachments: host.attachments,
      );

      await tester.tap(find.text('the docs'));
      await tester.pump();

      expect(host.urls, isEmpty);
    });

    testWidgets('a failure to open is shown as a snackbar', (tester) async {
      final host = _Opened()..message = 'Could not open the file: nope';
      await _pump(
        tester,
        '[notes.txt]($witFile)',
        attachments: host.attachments,
      );

      await tester.tap(find.text('notes.txt'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not open the file: nope'), findsOneWidget);
    });
  });

  group('inlineAttachmentsOf', () {
    test('a work item attachment keys the byte cache by its guid', () {
      final info = inlineAttachmentInfo(witImage);
      expect(info.name, 'shot.png');
      expect(info.url, witImage);
      expect(info.id, guid);
      expect(info.isImage, isTrue);
    });

    test('a pull request attachment has no id: the name is not unique', () {
      final info = inlineAttachmentInfo(prImage);
      expect(info.name, 'shot.png');
      expect(info.id, isNull);
    });

    test('a non-image attachment reads as a file', () {
      expect(inlineAttachmentInfo(witFile).isImage, isFalse);
    });

    test('the headers come off the source', () {
      final inline = inlineAttachmentsOf(
        AttachmentSource(
          bytes: (_) async => Uint8List(0),
          headers: const {'Authorization': 'Bearer tok'},
        ),
      );
      expect(inline.headers, {'Authorization': 'Bearer tok'});
      expect(inline.onOpen, isNotNull);
    });
  });
}
