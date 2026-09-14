/// Server-rendered Azure DevOps HTML as the plain text a row can show.
///
/// The rules are the ones the Android enrichment service already applies to
/// comment bodies (`EnrichmentFormat.plainText`, research/14 §4.1), ported to
/// Dart for the search highlights (research/15 §4): a work item's description
/// and history highlights come back as HTML, and a search row draws one line
/// of text, not a rendered document. Keeping the two implementations
/// character-for-character alike means a comment reads the same in a
/// notification and in a search result.
///
/// Deliberately free of Flutter: it is pure string work and unit tested as
/// such.
abstract final class PlainText {
  /// `data-vss-mention` anchors: Azure DevOps renders the display name inside
  /// the anchor, sometimes already with the `@`.
  static final _mention = RegExp(
    r'<a\b[^>]*data-vss-mention[^>]*>(.*?)</a>',
    caseSensitive: false,
    dotAll: true,
  );

  /// The markdown wire form of a person mention, `@<{identityGuid}>` (spike
  /// w30). It reaches this class in two places the rendered anchor never
  /// does: a pull request comment's `content`, which has no rendered form at
  /// all, and a work item's `System.History`, which stores the comment's raw
  /// text. Stripped before the tag pass, or `<{guid}>` would look like a tag
  /// and leave a bare `@` behind.
  ///
  /// The pattern is a deliberate copy of `Mentions.personAngle`: this class
  /// is the Dart twin of two native ports and stays free of every import but
  /// the language's own.
  static final _angleMention = RegExp(r'@<([0-9a-fA-F-]{36})>');

  /// A person whose GUID resolves to nobody (research/16 M9). Never the raw
  /// GUID: the two native ports have no resolver at all and always land here.
  static const unknownMention = '@someone';

  static final _blockEnd = RegExp(
    r'</(p|div|li|ul|ol|tr|h[1-6]|blockquote|pre)\s*>|<br\s*/?>',
    caseSensitive: false,
  );
  static final _tag = RegExp(r'<[^>]*>');
  static final _manyNewlines = RegExp(r'\n{3,}');
  // Space, tab and the non-breaking space `&nbsp;` decodes to.
  static final _spaces = RegExp('[ \\t\u00a0]{2,}');
  static final _numericEntity = RegExp(
    r'&#(x?)([0-9a-fA-F]+);',
    caseSensitive: false,
  );

  /// Mentions become `@Name` — both the rendered anchor and the markdown
  /// `@<guid>` form — block ends become newlines, every other tag goes,
  /// entities are decoded and runs of spaces collapse.
  ///
  /// [trim] is off when the caller is stripping one piece of a larger
  /// fragment: trimming each piece on its own would glue the words on either
  /// side of a `<highlighthit>` marker together.
  ///
  /// [nameFor] answers the display name behind the GUID of an `@<guid>`
  /// mention; without it — which is the case in the Kotlin and Swift ports —
  /// such a mention reads [unknownMention]. The name is substituted before
  /// the tag pass, so a display name containing `<` would lose that run; no
  /// directory allows one, and the HTML wire form escapes instead
  /// (`Mentions.person`).
  static String strip(
    String? html, {
    bool trim = true,
    String? Function(String guid)? nameFor,
  }) {
    if (html == null || html.isEmpty) return '';
    var text = html.replaceAllMapped(_mention, (m) {
      final name = decodeEntities(m.group(1)!.replaceAll(_tag, '')).trim();
      if (name.isEmpty) return '';
      return name.startsWith('@') ? name : '@$name';
    });
    text = text.replaceAllMapped(_angleMention, (m) {
      final name = nameFor?.call(m.group(1)!)?.trim() ?? '';
      if (name.isEmpty) return unknownMention;
      return name.startsWith('@') ? name : '@$name';
    });
    text = text.replaceAll(_blockEnd, '\n');
    text = text.replaceAll(_tag, '');
    text = decodeEntities(text);
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    text = text.replaceAll(_manyNewlines, '\n\n');
    text = text.replaceAll(_spaces, ' ');
    return trim ? text.trim() : text;
  }

  /// The named and numeric entities Azure DevOps' editor emits.
  static String decodeEntities(String value) {
    if (!value.contains('&')) return value;
    var text = value.replaceAllMapped(_numericEntity, (m) {
      final radix = m.group(1)!.isEmpty ? 10 : 16;
      final code = int.tryParse(m.group(2)!, radix: radix);
      if (code == null || code < 0 || code > 0x10ffff) return m.group(0)!;
      return String.fromCharCode(code);
    });
    for (final entry in _entities) {
      text = text.replaceAll(entry.$1, entry.$2);
    }
    return text;
  }

  static const _entities = <(String, String)>[
    ('&nbsp;', ' '),
    ('&lt;', '<'),
    ('&gt;', '>'),
    ('&quot;', '"'),
    ('&apos;', "'"),
    ('&hellip;', '…'),
    ('&mdash;', '—'),
    ('&ndash;', '–'),
    // Last: an escaped ampersand must not re-open another entity.
    ('&amp;', '&'),
  ];

  /// The inverse of the entity decoding, so stripped text can be written back
  /// into a markup-carrying cache entry and read out unchanged. `&` first, or
  /// the ampersands of the escapes would be escaped again.
  static String escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
