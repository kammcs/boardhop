import 'package:boardhop/core/text/mention.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic identities: never a real GUID, never a real name.
const _ada = '2f1b1a70-6d24-4c0a-9f0b-6b6d2f9a1c33';
const _bay = '8c4d5e6f-1122-4333-8444-55556666aaaa';

String? _names(String guid) => switch (guid) {
  _ada => 'Ada Example',
  _bay => 'Bay Wilkins & Co',
  _ => null,
};

void main() {
  group('the wire form', () {
    test('markdown is the GUID alone', () {
      expect(
        Mentions.person(_ada, MentionWire.markdown, displayName: 'Ada Example'),
        '@<$_ada>',
      );
      // The name is not read on this route: the service renders it.
      expect(
        Mentions.person(_ada, MentionWire.markdown, displayName: ''),
        '@<$_ada>',
      );
    });

    test('html is the exact anchor the web writes', () {
      expect(
        Mentions.person(_ada, MentionWire.html, displayName: 'Ada Example'),
        '<a href="#" data-vss-mention="version:2.0,$_ada">@Ada Example</a>',
      );
    });

    test('html escapes the markup characters of a display name', () {
      expect(
        Mentions.person(_bay, MentionWire.html, displayName: 'Bay <W> & Co'),
        '<a href="#" data-vss-mention="version:2.0,$_bay">'
        '@Bay &lt;W&gt; &amp; Co</a>',
      );
    });

    test('a name that already carries the @ does not get a second one', () {
      expect(
        Mentions.person(_ada, MentionWire.html, displayName: '@Ada Example'),
        contains('>@Ada Example</a>'),
      );
    });

    test('both patterns match what the two wire forms produce', () {
      expect(
        Mentions.personAngle.hasMatch(
          Mentions.person(_ada, MentionWire.markdown, displayName: 'Ada'),
        ),
        isTrue,
      );
      final anchor = Mentions.person(
        _ada,
        MentionWire.html,
        displayName: 'Ada Example',
      );
      final m = Mentions.personAnchor.firstMatch(anchor);
      expect(m?.group(1), _ada);
      expect(m?.group(2), '@Ada Example');
    });
  });

  group('parseMarkdown', () {
    test('a body with no reference is one plain span', () {
      final spans = Mentions.parseMarkdown('ship it', nameFor: _names);
      expect(spans, [const MentionSpan('ship it')]);
      expect(spans.single.isPlain, isTrue);
    });

    test('a known person reads as @Name, an unknown one as @someone', () {
      expect(Mentions.parseMarkdown('hi @<$_ada>', nameFor: _names), const [
        MentionSpan('hi '),
        MentionSpan('@Ada Example', kind: MentionKind.person, id: _ada),
      ]);
      const stranger = 'ffffffff-0000-4000-8000-000000000000';
      expect(Mentions.parseMarkdown('hi @<$stranger>', nameFor: _names), const [
        MentionSpan('hi '),
        MentionSpan('@someone', kind: MentionKind.person, id: stranger),
      ]);
      expect(Mentions.unknownPerson, '@someone');
    });

    test('an upper-case GUID resolves and is reported lower-cased', () {
      final spans = Mentions.parseMarkdown(
        '@<${_ada.toUpperCase()}>',
        nameFor: (g) => g == _ada.toUpperCase() ? 'Ada Example' : null,
      );
      expect(spans.single.id, _ada);
      expect(spans.single.text, '@Ada Example');
    });

    test('people and artifacts mix, in document order', () {
      expect(
        Mentions.parseMarkdown(
          '@<$_ada> please look at #15545 before !8334 lands',
          nameFor: _names,
        ),
        const [
          MentionSpan('@Ada Example', kind: MentionKind.person, id: _ada),
          MentionSpan(' please look at '),
          MentionSpan(
            '#15545',
            kind: MentionKind.workItem,
            id: '15545',
            tappable: true,
          ),
          MentionSpan(' before '),
          MentionSpan(
            '!8334',
            kind: MentionKind.pullRequest,
            id: '8334',
            tappable: true,
          ),
          MentionSpan(' lands'),
        ],
      );
    });

    test('an artifact reference only counts at a word boundary', () {
      // A URL fragment, a path and a word are not references.
      for (final body in [
        'https://example.test/x/#123',
        'a/#5',
        'item#7',
        'wow!9',
      ]) {
        final spans = Mentions.parseMarkdown(body, nameFor: _names);
        expect(spans, [MentionSpan(body)], reason: body);
      }
      // A bracket or a leading position is.
      expect(
        Mentions.parseMarkdown('(#12)', nameFor: _names).map((s) => s.kind),
        [null, MentionKind.workItem, null],
      );
      expect(
        Mentions.parseMarkdown('!9 first', nameFor: _names).first.kind,
        MentionKind.pullRequest,
      );
    });

    test('an e-mail address is never a mention', () {
      const body = 'mail kelly@kammcs.com or @someone';
      expect(Mentions.parseMarkdown(body, nameFor: _names), [
        const MentionSpan(body),
      ]);
    });

    test('an empty body is no spans', () {
      expect(Mentions.parseMarkdown('', nameFor: _names), isEmpty);
    });
  });

  group('parseHtmlText', () {
    test('a version:2.0 anchor is a person and is not tappable', () {
      final spans = Mentions.parseHtmlText(
        '<p>Hello <a href="" data-vss-mention="version:2.0,$_ada" '
        'class="mention-link ">@Ada Example</a>, look</p>',
      );
      expect(spans, const [
        MentionSpan('Hello '),
        MentionSpan('@Ada Example', kind: MentionKind.person, id: _ada),
        MentionSpan(', look\n'),
      ]);
      expect(spans[1].tappable, isFalse);
    });

    test('a version:1.0 anchor is the artifact its class names', () {
      final spans = Mentions.parseHtmlText(
        'work item <a href="/o/p/_workitems/edit/15545" '
        'data-vss-mention="version:1.0,15545" '
        'class="mention-link mention-widget-workitem">#15545</a> and '
        '<a href="/o/_git/p/pullrequest/8334" '
        'data-vss-mention="version:1.0,8334" class="mention-link ">!8334</a>',
      );
      expect(spans, const [
        MentionSpan('work item '),
        MentionSpan(
          '#15545',
          kind: MentionKind.workItem,
          id: '15545',
          tappable: true,
        ),
        MentionSpan(' and '),
        MentionSpan(
          '!8334',
          kind: MentionKind.pullRequest,
          id: '8334',
          tappable: true,
        ),
      ]);
    });

    test('single quotes and a reordered attribute still match', () {
      final spans = Mentions.parseHtmlText(
        "<a class='mention-link' data-vss-mention='version:2.0,$_ada' "
        "href='#'>Ada Example</a>",
      );
      expect(spans.single.kind, MentionKind.person);
      // The anchor's own text wins, and the @ is added when it is missing.
      expect(spans.single.text, '@Ada Example');
    });

    test('an anchor with no readable name falls back to the resolver', () {
      expect(
        Mentions.parseHtmlText(
          '<a data-vss-mention="version:2.0,$_ada"></a>',
          nameFor: _names,
        ).single.text,
        '@Ada Example',
      );
      expect(
        Mentions.parseHtmlText('<a data-vss-mention="version:2.0,$_ada"></a>')
            .single
            .text,
        '@someone',
      );
    });

    test('a markdown mention inside rendered HTML still reads', () {
      // A markdown `@<guid>` that reached an HTML body (a history entry, a
      // notification payload) is not an anchor, so it is one plain span —
      // but `PlainText` still names it rather than showing the GUID.
      expect(
        Mentions.parseHtmlText(
          '<p>hi @<$_bay></p>',
          nameFor: _names,
        ).single.text.trim(),
        'hi @Bay Wilkins & Co',
      );
      expect(
        Mentions.parseHtmlText('<p>hi @<$_bay></p>').single.text.trim(),
        'hi @someone',
      );
    });

    test('plain HTML with no mention is one stripped span', () {
      expect(Mentions.parseHtmlText('<p>Ship <b>it</b></p>'), const [
        MentionSpan('Ship it\n'),
      ]);
      expect(Mentions.parseHtmlText(''), isEmpty);
    });
  });

  test('personLabel is the one rule for drawing a person', () {
    expect(Mentions.personLabel('Ada Example'), '@Ada Example');
    expect(Mentions.personLabel('@Ada Example'), '@Ada Example');
    expect(Mentions.personLabel('  '), '@someone');
    expect(Mentions.personLabel(null), '@someone');
  });
}
