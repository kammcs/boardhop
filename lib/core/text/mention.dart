import 'package:equatable/equatable.dart';

import 'plain_text.dart';

/// What a mention points at (research/16 §4.1).
///
/// Only [person] is a mention in the Azure DevOps sense — the service stamps
/// `mentions[]` and notifies. [workItem] and [pullRequest] are artifact
/// references the service auto-links at render time (`#123`, `!456`); they
/// need no client syntax, but the app still styles them and makes them
/// tappable (M10).
enum MentionKind { person, workItem, pullRequest }

/// The two spellings Azure DevOps accepts for a person mention (spike w30).
///
/// * [markdown] — `@<{identityGuid}>`, the form for a `format=markdown` work
///   item comment, a pull request thread comment and a pull request
///   description. The HTML anchor pasted into a markdown body is escaped and
///   is **not** a mention.
/// * [html] — `<a href="#" data-vss-mention="version:2.0,{guid}">@Name</a>`,
///   the form a `format=html` comment and every HTML work item field use, and
///   what the web UI itself writes.
enum MentionWire { markdown, html }

/// One run of a comment body on the read side: either plain text
/// ([kind] null) or a mention to draw differently.
///
/// [text] is what is drawn — for a person that is already `@Name` (or
/// `@someone`, M9), never the GUID. [id] carries the identity GUID for a
/// person and the artifact id for `#123` / `!456`. [tappable] is true only
/// for artifacts: there is no person page to route to (M9).
class MentionSpan extends Equatable {
  const MentionSpan(this.text, {this.kind, this.id, this.tappable = false});

  final String text;
  final MentionKind? kind;
  final String? id;
  final bool tappable;

  /// Plain text, the common case, so a caller can test one thing.
  bool get isPlain => kind == null;

  @override
  List<Object?> get props => [text, kind, id, tappable];

  @override
  String toString() =>
      'MentionSpan($text${kind == null ? '' : ', $kind, $id'}'
      '${tappable ? ', tappable' : ''})';
}

/// The one definition of "a mention" on the app side: the patterns, the wire
/// format and the read-side split into [MentionSpan]s.
///
/// The same two person patterns live in `relay/lib/src/hooks/routing_view.dart`
/// (`_htmlMention`, `_angleMention`) and a third copy, without the Dart
/// regexes, in the two native enrichment ports. They are deliberate copies:
/// each side has to work without the others, and the spellings are frozen by
/// the service, not by us.
abstract final class Mentions {
  /// What a person mention reads as when the GUID resolves to nobody (M9) —
  /// never the raw GUID.
  static const unknownPerson = PlainText.unknownMention;

  /// `@<{guid}>` — the markdown wire form. Case-insensitive by construction
  /// (the character class carries both cases); the relay lowercases the GUID
  /// before comparing and so does [identityId].
  static final personAngle = RegExp(r'@<([0-9a-fA-F-]{36})>');

  /// The rendered person anchor: `data-vss-mention="version:2.0,{guid}"`.
  /// Group 1 is the GUID, group 2 the anchor's inner markup (usually
  /// `@Display Name`).
  static final personAnchor = RegExp(
    r'''<a\b[^>]*data-vss-mention=["']version:2\.0,([0-9a-fA-F-]{36})["'][^>]*>(.*?)</a>''',
    caseSensitive: false,
    dotAll: true,
  );

  /// The rendered artifact anchor: `data-vss-mention="version:1.0,{id}"`,
  /// the id being a work item or pull request number. The class
  /// (`mention-widget-workitem`) or the href says which (spike w30 §4).
  static final artifactAnchor = RegExp(
    r'''<a\b[^>]*data-vss-mention=["']version:1\.0,(\d+)["'][^>]*>(.*?)</a>''',
    caseSensitive: false,
    dotAll: true,
  );

  /// `#123` at a word boundary. The lookbehind is what keeps
  /// `https://example.test/#123` and `a/#5` out: a `#` after a word character
  /// or a slash is part of a URL fragment or a path, not a reference.
  static final workItemRef = RegExp(r'(?<![\w/])#(\d+)\b');

  /// `!456` at a word boundary, same rule.
  static final pullRequestRef = RegExp(r'(?<![\w/])!(\d+)\b');

  /// Every reference a Markdown body can carry, in one pass so the spans come
  /// out in document order. Group 1 = person GUID, 2 = work item id,
  /// 3 = pull request id.
  static final _markdownRefs = RegExp(
    r'@<([0-9a-fA-F-]{36})>'
    r'|(?<![\w/])#(\d+)\b'
    r'|(?<![\w/])!(\d+)\b',
  );

  /// Either rendered anchor, in one pass. Group 1 = version (`1.0`/`2.0`),
  /// 2 = the GUID or artifact id, 3 = the anchor's whole opening tag (so the
  /// class can be read), 4 = the inner markup.
  static final _anchor = RegExp(
    r'''<a\b([^>]*data-vss-mention=["']version:(1\.0|2\.0),([0-9a-fA-F-]{36}|\d+)["'][^>]*)>(.*?)</a>''',
    caseSensitive: false,
    dotAll: true,
  );

  /// The text to send for a person mention.
  ///
  /// [MentionWire.markdown] is the app's route everywhere today (work item
  /// comments are posted `format=markdown`, pull request comments are
  /// Markdown by definition); [MentionWire.html] exists for the HTML field
  /// editor, whose value is HTML and where the angle form would be escaped.
  /// [displayName] is only read for the HTML form — the markdown form carries
  /// the GUID alone and the service renders the name itself.
  static String person(
    String guid,
    MentionWire wire, {
    required String displayName,
  }) {
    if (wire == MentionWire.markdown) return '@<$guid>';
    final name = displayName.trim();
    final label = name.startsWith('@') ? name.substring(1).trim() : name;
    return '<a href="#" data-vss-mention="version:2.0,$guid">'
        '@${PlainText.escape(label)}</a>';
  }

  /// A Markdown body (a work item comment's `text`, a pull request comment's
  /// `content`) split into the runs a view draws.
  ///
  /// [nameFor] answers the display name behind a GUID, or null when it is not
  /// known — an unresolved person reads [unknownPerson], never the GUID (M9).
  /// `#123` and `!456` become tappable artifact spans (M10); everything else
  /// is plain text, returned verbatim so the Markdown around it still parses.
  static List<MentionSpan> parseMarkdown(
    String content, {
    required String? Function(String guid) nameFor,
  }) {
    if (content.isEmpty) return const [];
    final spans = <MentionSpan>[];
    var at = 0;
    for (final m in _markdownRefs.allMatches(content)) {
      if (m.start > at) spans.add(MentionSpan(content.substring(at, m.start)));
      final guid = m.group(1);
      final workItem = m.group(2);
      if (guid != null) {
        spans.add(
          MentionSpan(
            personLabel(nameFor(guid)),
            kind: MentionKind.person,
            id: identityId(guid),
          ),
        );
      } else {
        spans.add(
          MentionSpan(
            m.group(0)!,
            kind: workItem != null
                ? MentionKind.workItem
                : MentionKind.pullRequest,
            id: workItem ?? m.group(3),
            tappable: true,
          ),
        );
      }
      at = m.end;
    }
    if (at < content.length) spans.add(MentionSpan(content.substring(at)));
    return spans;
  }

  /// Server-rendered HTML (a work item comment's `renderedText`, an HTML
  /// field) split into the same runs.
  ///
  /// Both anchor versions are recognised: `version:2.0` is a person and is
  /// never tappable, `version:1.0` is a work item or a pull request and is.
  /// Everything between the anchors goes through [PlainText.strip] with
  /// [trim] off, so a caller gets text it can draw directly and the spaces
  /// either side of an anchor survive.
  ///
  /// [nameFor] is only consulted when an anchor carries no readable name.
  static List<MentionSpan> parseHtmlText(
    String html, {
    String? Function(String guid)? nameFor,
  }) {
    if (html.isEmpty) return const [];
    final spans = <MentionSpan>[];
    void addPlain(String piece) {
      if (piece.isEmpty) return;
      final text = PlainText.strip(piece, trim: false, nameFor: nameFor);
      if (text.isNotEmpty) spans.add(MentionSpan(text));
    }

    var at = 0;
    for (final m in _anchor.allMatches(html)) {
      addPlain(html.substring(at, m.start));
      final tag = m.group(1)!;
      final id = m.group(3)!;
      final inner = PlainText.strip(m.group(4)!).trim();
      if (m.group(2) == '2.0') {
        spans.add(
          MentionSpan(
            inner.isEmpty ? personLabel(nameFor?.call(id)) : personLabel(inner),
            kind: MentionKind.person,
            id: identityId(id),
          ),
        );
      } else {
        final isWorkItem =
            tag.toLowerCase().contains('mention-widget-workitem') ||
            tag.contains('_workitems/');
        spans.add(
          MentionSpan(
            inner.isEmpty ? '${isWorkItem ? '#' : '!'}$id' : inner,
            kind: isWorkItem ? MentionKind.workItem : MentionKind.pullRequest,
            id: id,
            tappable: true,
          ),
        );
      }
      at = m.end;
    }
    addPlain(html.substring(at));
    return spans;
  }

  /// `Kelly Kamm` → `@Kelly Kamm`, `@Kelly` → `@Kelly`, nothing →
  /// [unknownPerson]. The same rule the two native enrichment ports apply.
  static String personLabel(String? displayName) {
    final name = displayName?.trim() ?? '';
    if (name.isEmpty) return unknownPerson;
    return name.startsWith('@') ? name : '@$name';
  }

  /// Identity GUIDs are compared lowercased (the relay does the same), so
  /// `@<ABC…>` and `@<abc…>` are one person.
  static String identityId(String guid) => guid.toLowerCase();
}
