import 'package:boardhop/data/models/work_item.dart';
import 'package:boardhop/features/shared/attachments/attachment_links.dart';
import 'package:boardhop/features/work_items/widgets/rich_text_view.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
}
