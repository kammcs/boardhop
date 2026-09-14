import 'package:boardhop/core/text/mention.dart';
import 'package:boardhop/features/work_items/widgets/rich_text_view.dart';
import 'package:flutter/material.dart';
import 'package:boardhop/theme/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// research/16 §4.4 and M9/M10: what Azure DevOps renders for a work item
/// comment must not reach the screen as a live `<a href="#">` link. A person
/// is a styled run nobody can tap; `#123` and `!456` are styled runs that
/// open the thing they name.
const guid = '11111111-2222-3333-4444-555555555555';

const comment =
    '<p>hi '
    '<a href="#" data-vss-mention="version:2.0,$guid" class="mention-link">'
    '@Kelly Kamm</a> see '
    '<a href="/o/proj/_workitems/edit/15545" data-vss-mention="version:1.0,15545" '
    'class="mention-link mention-widget-workitem">#15545</a> and '
    '<a href="/o/_git/proj/pullrequest/8334" data-vss-mention="version:1.0,8334" '
    'class="mention-link ">!8334</a> and '
    '<a href="https://example.test/docs">the docs</a></p>';

void main() {
  late List<String> opened;

  Future<void> pump(WidgetTester tester, {String content = comment}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: RichTextView(
            content: content,
            onOpenMention: (kind, id) => opened.add('${kind.name}:$id'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Every drawn run, with the style and whether it can be tapped.
  List<({String text, TextStyle? style, bool tappable})> runs(
    WidgetTester tester,
  ) {
    final out = <({String text, TextStyle? style, bool tappable})>[];
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      rich.text.visitChildren((span) {
        if (span is TextSpan && (span.text ?? '').isNotEmpty) {
          out.add((
            text: span.text!,
            style: span.style,
            tappable: span.recognizer != null,
          ));
        }
        return true;
      });
    }
    return out;
  }

  setUp(() => opened = []);

  testWidgets('a person anchor is a styled run and cannot be tapped', (
    tester,
  ) async {
    await pump(tester);
    final person = runs(tester).firstWhere((r) => r.text == '@Kelly Kamm');
    expect(person.style?.color, BoardhopColors.light.mention);
    expect(person.style?.fontWeight, FontWeight.w600);
    // No underline, and nothing to tap: there is no person page (M9).
    expect(person.style?.decoration, isNot(TextDecoration.underline));
    expect(person.tappable, isFalse);
    // The plain text around it keeps the body style.
    expect(runs(tester).firstWhere((r) => r.text == 'hi ').tappable, isFalse);
  });

  testWidgets('a work item reference opens that work item', (tester) async {
    await pump(tester);
    final reference = runs(tester).firstWhere((r) => r.text == '#15545');
    expect(reference.style?.color, BoardhopColors.light.mention);
    expect(reference.tappable, isTrue);

    await tester.tapOnText(find.textRange.ofSubstring('#15545'));
    await tester.pumpAndSettle();
    expect(opened, ['workItem:15545']);
  });

  testWidgets('a pull request reference opens that pull request', (
    tester,
  ) async {
    await pump(tester);
    await tester.tapOnText(find.textRange.ofSubstring('!8334'));
    await tester.pumpAndSettle();
    expect(opened, ['pullRequest:8334']);
  });

  testWidgets('an ordinary link is left exactly as it was', (tester) async {
    await pump(tester);
    final link = runs(tester).firstWhere((r) => r.text == 'the docs');
    expect(link.style?.decoration, TextDecoration.underline);
    expect(link.tappable, isTrue);
    expect(link.style?.fontWeight, isNot(FontWeight.w600));
  });

  testWidgets('a Markdown field draws the same runs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: BoardhopTheme.light(),
        home: Scaffold(
          body: RichTextView(
            content: 'hi @<$guid> see #15545',
            format: 'markdown',
            mentionNames: const {guid: 'Kelly Kamm'},
            onOpenMention: (kind, id) => opened.add('${kind.name}:$id'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('@Kelly Kamm'), findsOneWidget);
    expect(find.textContaining(guid), findsNothing);
  });

  testWidgets('an anchor the app does not know is left to the browser', (
    tester,
  ) async {
    await pump(
      tester,
      content:
          '<p><a href="#" data-vss-mention="version:9.9,$guid">@Nope</a></p>',
    );
    final run = runs(tester).firstWhere((r) => r.text == '@Nope');
    expect(run.tappable, isTrue);
    expect(run.style?.decoration, TextDecoration.underline);
  });

  group('MentionAnchor.read', () {
    test('tells a person from a work item from a pull request', () {
      expect(
        MentionAnchor.read(
          tag: 'a',
          attributes: {'data-vss-mention': 'version:2.0,${guid.toUpperCase()}'},
        ),
        isA<MentionAnchor>()
            .having((a) => a.kind, 'kind', MentionKind.person)
            // GUIDs are compared lower-cased, as the relay does.
            .having((a) => a.id, 'id', guid)
            .having((a) => a.tappable, 'tappable', isFalse),
      );
      expect(
        MentionAnchor.read(
          tag: 'a',
          attributes: {
            'data-vss-mention': 'version:1.0,15545',
            'class': 'mention-link mention-widget-workitem',
          },
        )?.kind,
        MentionKind.workItem,
      );
      expect(
        MentionAnchor.read(
          tag: 'a',
          attributes: {
            'data-vss-mention': 'version:1.0,8334',
            'class': 'mention-link ',
            'href': '/o/_git/proj/pullrequest/8334',
          },
        )?.kind,
        MentionKind.pullRequest,
      );
      // The class is missing on some payloads; the href still says which.
      expect(
        MentionAnchor.read(
          tag: 'a',
          attributes: {
            'data-vss-mention': 'version:1.0,15545',
            'href': '/o/proj/_workitems/edit/15545',
          },
        )?.kind,
        MentionKind.workItem,
      );
    });

    test('anything else is not a mention', () {
      expect(MentionAnchor.read(tag: 'a', attributes: const {}), isNull);
      expect(
        MentionAnchor.read(
          tag: 'span',
          attributes: {'data-vss-mention': 'version:2.0,$guid'},
        ),
        isNull,
      );
      expect(
        MentionAnchor.read(
          tag: 'a',
          attributes: const {'data-vss-mention': 'version:2.0'},
        ),
        isNull,
      );
      expect(
        MentionAnchor.read(
          tag: 'a',
          attributes: const {'data-vss-mention': 'version:1.0,'},
        ),
        isNull,
      );
    });
  });
}
