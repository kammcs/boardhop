import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/features/shared/attachments/attachment_links.dart';
import 'package:boardhop/features/shared/attachments/inline_attachments.dart';
import 'package:boardhop/features/work_items/widgets/rich_text_view.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// research/17 §1 bug (a): the comments API rewrites an image `src` inside
/// the `renderedText` of an `html`-format comment to a U+0006 sentinel
/// followed by the base-less path `/{guid}?fileName=…`. Spike w32 §3 has
/// the `repr()`; 12 of 33 client comment images look like that and render as
/// nothing today.
const guid = 'c50b0d6e-1111-4222-8333-444455556666';
const projectGuid = '98720989-1234-4321-8888-aaaabbbbcccc';

const commentUrl =
    'https://dev.azure.com/contoso/$projectGuid'
    '/_apis/wit/workItems/15545/comments/123';
const absolute =
    'https://dev.azure.com/contoso/$projectGuid'
    '/_apis/wit/attachments/$guid?fileName=shot.png';

const headers = {'Authorization': 'Bearer tok'};

/// What the service really answers on the html route.
WorkItemComment htmlComment() => WorkItemComment.fromJson({
  'id': 123,
  'url': commentUrl,
  'format': 'html',
  'text': '<p>look</p><p><img src="$absolute" alt="shot"></p>',
  'renderedText':
      '<p>look</p>'
      '<p><img src="$attachmentSentinel/$guid?fileName=shot.png" alt="shot"></p>',
  'createdBy': {'displayName': 'Kelly Kamm', 'id': 'k'},
});

/// And on the markdown route, where `renderedText` is already well formed.
WorkItemComment markdownComment() => WorkItemComment.fromJson({
  'id': 124,
  'url': commentUrl,
  'format': 'markdown',
  'text': '![shot]($absolute)',
  'renderedText': '<p><img src="$absolute" alt="shot"></p>',
  'createdBy': {'displayName': 'Kelly Kamm', 'id': 'k'},
});

Future<void> pump(WidgetTester tester, WorkItemComment c) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: BoardhopTheme.light(),
      home: Scaffold(
        body: RichTextView(
          content: c.displayHtml,
          headers: headers,
          attachmentBase: witAttachmentBase(c.url),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The one image on screen, with its provider.
CachedNetworkImageProvider provider(WidgetTester tester) =>
    tester.widget<Image>(find.byType(Image)).image
        as CachedNetworkImageProvider;

void main() {
  group('WorkItemComment.displayHtml', () {
    test('an html comment is drawn from text, not renderedText', () {
      final c = htmlComment();
      expect(c.displayHtml, c.text);
      expect(c.displayHtml.contains(attachmentSentinel), isFalse);
      expect(c.displayHtml, contains(absolute));
    });

    test('a markdown comment keeps the server-rendered form', () {
      final c = markdownComment();
      expect(c.displayHtml, c.renderedText);
    });

    test('an html comment with no text falls back to renderedText', () {
      final c = WorkItemComment.fromJson({
        'id': 1,
        'format': 'html',
        'text': '',
        'renderedText': '<p>only rendered</p>',
        'createdBy': {'displayName': 'K'},
      });
      expect(c.displayHtml, '<p>only rendered</p>');
    });

    test('the comment carries its own url, which names the project', () {
      expect(htmlComment().url, commentUrl);
      expect(
        witAttachmentBase(htmlComment().url),
        'https://dev.azure.com/contoso/$projectGuid/_apis/wit/attachments',
      );
    });
  });

  group('a comment image reaches the screen', () {
    testWidgets('an html comment draws the absolute URL with the token', (
      tester,
    ) async {
      await pump(tester, htmlComment());

      expect(find.byType(Image), findsOneWidget);
      expect(provider(tester).url, absolute);
      expect(provider(tester).headers, headers);
    });

    testWidgets('a markdown comment does too', (tester) async {
      await pump(tester, markdownComment());

      expect(provider(tester).url, absolute);
    });

    testWidgets(
      'a sentinel that survives into the body is repaired before parsing',
      (tester) async {
        // The belt-and-braces path: a body whose `text` was empty, so the
        // sentinel form is what is drawn. The HTML renderer drops a relative
        // src outright when it has no base URL, so this cannot be left to
        // the image hook.
        await tester.pumpWidget(
          MaterialApp(
            theme: BoardhopTheme.light(),
            home: Scaffold(
              body: RichTextView(
                content: htmlComment().renderedText,
                headers: headers,
                attachmentBase: witAttachmentBase(commentUrl),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(Image), findsOneWidget);
        expect(provider(tester).url, absolute);
      },
    );

    testWidgets('without a base the sentinel image is not invented', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: RichTextView(
              content: htmlComment().renderedText,
              headers: headers,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsNothing);
    });
  });

  /// T-A open item 2 / decision T9: a **file** attached to a work item
  /// comment arrives as an ordinary `<a rel=nofollow>` in the service's
  /// rendered HTML. Left alone it would open in a browser, which cannot
  /// authenticate an attachment URL and lands on a sign-in page.
  group('a file link inside a comment', () {
    const fileUrl =
        'https://dev.azure.com/contoso/$projectGuid'
        '/_apis/wit/attachments/$guid?fileName=notes.txt';

    late List<String> opened;

    Future<void> pumpBody(
      WidgetTester tester,
      String html, {
      bool withOpener = true,
      String? base,
    }) async {
      opened = [];
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: RichTextView(
              content: html,
              headers: headers,
              attachmentBase: base,
              attachments: InlineAttachments(
                headers: headers,
                onOpen: withOpener
                    ? (context, url, name) async {
                        opened.add('$url|$name');
                        return null;
                      }
                    : null,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// What a tap on the one image would run, if anything.
    VoidCallback? tapImage(WidgetTester tester) {
      final detectors = find.ancestor(
        of: find.byType(Image),
        matching: find.byType(GestureDetector),
      );
      if (detectors.evaluate().isEmpty) return null;
      return tester.widget<GestureDetector>(detectors.first).onTap;
    }

    /// Every tappable run on screen.
    List<TapGestureRecognizer> taps(WidgetTester tester) {
      final out = <TapGestureRecognizer>[];
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
            out.add(span.recognizer! as TapGestureRecognizer);
          }
          return true;
        });
      }
      return out;
    }

    testWidgets('opens through the share sheet, not the browser', (
      tester,
    ) async {
      await pumpBody(tester, '<p><a href="$fileUrl">notes.txt</a></p>');
      expect(
        find.textContaining('notes.txt', findRichText: true),
        findsWidgets,
      );
      final tap = taps(tester);
      expect(tap, hasLength(1));
      tap.single.onTap!();
      await tester.pumpAndSettle();
      expect(opened, ['$fileUrl|notes.txt']);
    });

    testWidgets('a sentinel href is repaired first', (tester) async {
      await pumpBody(
        tester,
        '<p><a href="$attachmentSentinel/$guid?fileName=notes.txt">'
        'notes.txt</a></p>',
        base: witAttachmentBase(commentUrl),
      );
      taps(tester).single.onTap!();
      await tester.pumpAndSettle();
      expect(opened, ['$fileUrl|notes.txt']);
    });

    testWidgets('an ordinary link is left exactly as it was', (tester) async {
      await pumpBody(
        tester,
        '<p><a href="https://example.test/docs">the docs</a></p>',
      );
      taps(tester).single.onTap!();
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
    });

    testWidgets('an image in a comment opens the viewer too (T9)', (
      tester,
    ) async {
      // The Markdown path has its own tap; the HTML path is where a work
      // item comment's image actually arrives.
      await pumpBody(tester, '<p><img src="$absolute" alt="shot"></p>');
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<CachedNetworkImageProvider>());
      // The image never loads in a test, so it has no box to tap: the
      // detector the renderer wrapped it in is what a tap would reach.
      tapImage(tester)!();
      await tester.pumpAndSettle();
      expect(opened, ['$absolute|shot.png']);
    });

    testWidgets('a foreign image is not routed anywhere', (tester) async {
      await pumpBody(
        tester,
        '<p><img src="https://example.test/logo.png" alt="logo"></p>',
      );
      tapImage(tester)?.call();
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
    });

    testWidgets('no opener means the link stays inert', (tester) async {
      await pumpBody(
        tester,
        '<p><a href="$fileUrl">notes.txt</a></p>',
        withOpener: false,
      );
      taps(tester).single.onTap!();
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
    });
  });

  /// Decision T9 caps an inline image at [inlineImageMaxHeight]. The
  /// Markdown builder does it for a pull request comment; a **work item**
  /// comment is rendered HTML, and until T-C nothing capped it there — a
  /// portrait photo from a phone filled the whole iPhone screen and more
  /// than the iPad's.
  group('an attachment image is capped on the HTML path', () {
    Future<void> pumpHtml(
      WidgetTester tester,
      String html, {
      String? base,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: BoardhopTheme.light(),
          home: Scaffold(
            body: RichTextView(
              content: html,
              headers: headers,
              attachmentBase: base,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    /// The cap the renderer put around the one image, if it put one there.
    BoxConstraints? capOf(WidgetTester tester) {
      final boxes = find.ancestor(
        of: find.byType(Image),
        matching: find.byType(ConstrainedBox),
      );
      for (final box in tester.widgetList<ConstrainedBox>(boxes)) {
        if (box.constraints.maxHeight == inlineImageMaxHeight) {
          return box.constraints;
        }
      }
      return null;
    }

    testWidgets('a comment image gets the 320 pt cap', (tester) async {
      await pumpHtml(tester, '<p><img src="$absolute" alt="shot"></p>');

      expect(capOf(tester)?.maxHeight, inlineImageMaxHeight);
    });

    testWidgets('a repaired sentinel image is capped too', (tester) async {
      await pumpHtml(
        tester,
        '<p><img src="$attachmentSentinel/$guid?fileName=shot.png"></p>',
        base: witAttachmentBase(commentUrl),
      );

      expect(capOf(tester)?.maxHeight, inlineImageMaxHeight);
    });

    testWidgets('an image that is not an attachment keeps its own size', (
      tester,
    ) async {
      await pumpHtml(
        tester,
        '<p><img src="https://example.test/logo.png" alt="logo"></p>',
      );

      expect(find.byType(Image), findsOneWidget);
      expect(capOf(tester), isNull);
    });
  });
}
