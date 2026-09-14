import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/text/mention.dart';

/// One picked mention inside a composer's text.
///
/// A token is a range over the controller's text, not a widget: Flutter
/// asserts on a `WidgetSpan` returned from `buildTextSpan`
/// (flutter#63863), so a mention is a styled run of ordinary characters —
/// which is also what GitHub, Twitter and Apple Messages ship.
@immutable
class MentionToken {
  const MentionToken({
    required this.start,
    required this.end,
    required this.kind,
    required this.label,
    this.id,
  });

  /// First character of the run, inclusive.
  final int start;

  /// One past the last character of the run.
  final int end;

  final MentionKind kind;

  /// What the run reads: `@Kelly Kamm`, `#15545`, `!8334`. It always
  /// includes the trigger character, because the trigger is part of what the
  /// pick replaced.
  final String label;

  /// The identity GUID for a person (research/16 §1: the Azure DevOps
  /// identity id, not the Entra object id), or the artifact id.
  final String? id;

  MentionToken shifted(int delta) => MentionToken(
    start: start + delta,
    end: end + delta,
    kind: kind,
    label: label,
    id: id,
  );

  @override
  String toString() => 'MentionToken($start..$end, ${kind.name}, $label, $id)';
}

/// An open trigger: the character, what has been typed after it, and the
/// range the pick will replace.
@immutable
class MentionTrigger {
  const MentionTrigger({
    required this.character,
    required this.kind,
    required this.query,
    required this.range,
  });

  /// `@`, `#` or `!`.
  final String character;

  final MentionKind kind;

  /// Everything between the trigger character and the caret. May contain
  /// spaces so a full name matches (research/16 M14: `kel ka` finds Kelly
  /// Kamm); never a newline or a `.`.
  final String query;

  /// The trigger character through the caret, i.e. what [MentionController
  /// .insertToken] replaces with the label.
  final TextRange range;

  @override
  String toString() => 'MentionTrigger($character, "$query", $range)';
}

/// A [TextEditingController] that remembers which runs of its text are picked
/// mentions, draws them, and can serialise them to the Azure DevOps wire
/// form.
///
/// Three framework rules shape this class, each from an open Flutter bug
/// (research/16 §2, r2-ux §4a):
///
/// * `buildTextSpan` never returns a `WidgetSpan` (flutter#63863 asserts), a
///   `GestureRecognizer` (flutter#97433 throws on mobile) or a different
///   `fontSize` (flutter#178110 crops the field). A token is colour and
///   weight only.
/// * `withComposing` is honoured, so an IME's candidate underline survives.
///   Every package surveyed drops it.
/// * The caret is never moved from a listener — the engine restarts the
///   Android IME whenever the framework rewrites the composing region. After
///   a pick the caret is set with the text in one atomic value, then
///   re-asserted in a post-frame callback in case the IME moved it back.
///
/// Token positions are **re-derived on every value change** by diffing the
/// old and new text rather than trusted, because autocorrect and an IME
/// commit can rewrite arbitrary ranges. A token whose own run was touched
/// stops being a mention and degrades to plain text (research/16 M6), which
/// is what the server would have done with it anyway.
class MentionController extends TextEditingController {
  MentionController({super.text});

  /// The trigger table (research/16 M8).
  static const Map<String, MentionKind> triggers = {
    '@': MentionKind.person,
    '#': MentionKind.workItem,
    '!': MentionKind.pullRequest,
  };

  /// How far back from the caret a trigger is looked for.
  ///
  /// The query may contain spaces, so without a bound a paragraph with a
  /// stray `@` near its start would keep a hopeless query alive and scan the
  /// whole text on every keystroke. No real display name is this long.
  static const int maxQueryLength = 50;

  /// A character a trigger may follow: the start of the text, whitespace, or
  /// a bracket, so `kelly@kammcs.com` never opens a picker (research/16 §2).
  static final RegExp _boundaryBefore = RegExp(r'[\s(\[]');

  /// An `@word` the user typed by hand rather than picked (research/16 M7).
  /// The negative lookbehind is the same word-boundary rule as the trigger's,
  /// and succeeds at offset 0 where there is nothing to look behind at.
  static final RegExp _atWord = RegExp(
    r'(?<![^\s(\[])@([A-Za-z0-9_][A-Za-z0-9_\-]*)',
  );

  List<MentionToken> _tokens = const [];
  bool _disposed = false;

  /// The picked mentions, in text order.
  List<MentionToken> get tokens => List.unmodifiable(_tokens);

  @override
  set value(TextEditingValue newValue) {
    _tokens = _rederive(_tokens, super.value.text, newValue.text);
    super.value = newValue;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Drop every token, leaving the text alone.
  ///
  /// A host calls this when it reuses the controller for a different draft
  /// without changing the text.
  void clearTokens() {
    if (_tokens.isEmpty) return;
    _tokens = const [];
    notifyListeners();
  }

  /// Where a picker should open, read from the caret.
  ///
  /// Null when the caret is not after a trigger, when the trigger is not at a
  /// word boundary, when the caret sits inside a token already (the caret may
  /// sit there, M6, but there is nothing to pick), or when the query broke on
  /// a newline, a `.`, or a space typed straight after the trigger.
  MentionTrigger? get activeTrigger {
    final selection = value.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final caret = selection.baseOffset;
    final source = text;
    if (caret < 0 || caret > source.length) return null;

    final limit = math.max(0, caret - maxQueryLength - 1);
    for (var i = caret - 1; i >= limit; i--) {
      final ch = source[i];
      // A newline ends the query, and so does a `.` — which is what keeps
      // `v1.2` and a sentence's full stop from opening anything.
      if (ch == '\n' || ch == '.') return null;
      final kind = triggers[ch];
      if (kind == null) continue;
      if (i > 0 && !_boundaryBefore.hasMatch(source[i - 1])) return null;
      for (final token in _tokens) {
        if (i >= token.start && i < token.end) return null;
      }
      final query = source.substring(i + 1, caret);
      if (query.startsWith(' ')) return null;
      return MentionTrigger(
        character: ch,
        kind: kind,
        query: query,
        range: TextRange(start: i, end: caret),
      );
    }
    return null;
  }

  /// Replace [replacing] (the trigger character and its query) with [label],
  /// record it as a token, and leave the caret after it.
  ///
  /// One space follows the label unless the next character already is one, so
  /// the user keeps typing a sentence rather than a run-on word.
  void insertToken(
    MentionKind kind,
    String? id,
    String label, {
    required TextRange replacing,
  }) {
    final source = text;
    final start = replacing.start.clamp(0, source.length);
    final end = replacing.end.clamp(start, source.length);
    final needsSpace = end >= source.length || source[end] != ' ';
    final inserted = needsSpace ? '$label ' : label;
    final updated = source.replaceRange(start, end, inserted);
    final caret = start + inserted.length;

    // Everything else shifts exactly as a hand edit of the same shape would.
    final kept = _rederive(_tokens, source, updated);
    _tokens = <MentionToken>[
      ...kept,
      MentionToken(
        start: start,
        end: start + label.length,
        kind: kind,
        label: label,
        id: id,
      ),
    ]..sort((a, b) => a.start.compareTo(b.start));

    // One atomic value: the text and the caret change together, so no
    // listener ever sees the caret move on its own (the Android IME restart,
    // flutter/engine#25180).
    _setRaw(
      TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: caret),
        composing: TextRange.empty,
      ),
    );
    _reassertCaret(caret, updated);
  }

  /// The text as Azure DevOps should store it: every person token becomes
  /// `@<guid>` (or the anchor), artifacts keep their plain `#123` / `!456`
  /// because the service links those itself (research/16 §1).
  ///
  /// Called at the composer's submit boundary, before `enqueueComment`, so a
  /// queued offline comment already carries real GUIDs (M13).
  String toWire(MentionWire wire) {
    if (_tokens.isEmpty) return text;
    final source = text;
    final out = StringBuffer();
    var at = 0;
    for (final token in _tokens) {
      if (token.start < at || token.end > source.length) continue;
      if (source.substring(token.start, token.end) != token.label) continue;
      out
        ..write(source.substring(at, token.start))
        ..write(_wireFor(token, wire));
      at = token.end;
    }
    out.write(source.substring(at));
    return out.toString();
  }

  /// Hand-typed `@word`s that are not picked mentions, for the M7 hint.
  ///
  /// Distinct, in the order they appear. A bare `@` is not one: the picker is
  /// open at that point and the user has not typed a name yet.
  List<String> get unresolvedAtWords {
    final out = <String>[];
    for (final match in _atWord.allMatches(text)) {
      final at = match.start;
      final inToken = _tokens.any((t) => at >= t.start && at < t.end);
      if (inToken) continue;
      final word = match.group(0)!;
      if (!out.contains(word)) out.add(word);
    }
    return out;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = text;
    final composing = value.composing;
    final showComposing =
        withComposing &&
        value.isComposingRangeValid &&
        !composing.isCollapsed &&
        composing.start >= 0 &&
        composing.end <= source.length;
    final live = <MentionToken>[
      for (final t in _tokens)
        if (t.start >= 0 && t.end <= source.length && t.start < t.end) t,
    ];
    if (live.isEmpty && !showComposing) {
      return TextSpan(style: style, text: source);
    }

    // Split at the union of the token boundaries and the composing range, so
    // neither can swallow the other.
    final cuts = <int>{0, source.length};
    for (final token in live) {
      cuts
        ..add(token.start)
        ..add(token.end);
    }
    if (showComposing) {
      cuts
        ..add(composing.start)
        ..add(composing.end);
    }
    final bounds = cuts.toList()..sort();

    final tokenStyle = TextStyle(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w500,
    );
    const composingStyle = TextStyle(decoration: TextDecoration.underline);

    final children = <InlineSpan>[];
    for (var i = 0; i + 1 < bounds.length; i++) {
      final from = bounds[i];
      final to = bounds[i + 1];
      if (from >= to) continue;
      final inToken = live.any((t) => from >= t.start && to <= t.end);
      final inComposing =
          showComposing && from >= composing.start && to <= composing.end;
      TextStyle? run;
      if (inToken) run = tokenStyle;
      if (inComposing) {
        run = run == null ? composingStyle : run.merge(composingStyle);
      }
      children.add(TextSpan(text: source.substring(from, to), style: run));
    }
    return TextSpan(style: style, children: children);
  }

  void _setRaw(TextEditingValue newValue) {
    super.value = newValue;
  }

  /// Put the caret back after the inserted token once the frame the pick
  /// caused has been laid out.
  ///
  /// Setting it with the text above is enough on iOS; an Android IME that is
  /// mid-composition can answer the text change with a selection of its own,
  /// and this is the only safe moment to correct that (never from a
  /// listener).
  void _reassertCaret(int caret, String forText) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      if (text != forText) return;
      final selection = value.selection;
      if (selection.isCollapsed && selection.baseOffset == caret) return;
      if (caret < 0 || caret > text.length) return;
      _setRaw(
        value.copyWith(
          selection: TextSelection.collapsed(offset: caret),
          composing: TextRange.empty,
        ),
      );
    });
  }

  /// The wire spelling of one token: `Mentions.person` for a person with a
  /// GUID, the label itself for an artifact (the service links `#123` and
  /// `!456` on its own) or a person no GUID was ever resolved for.
  static String _wireFor(MentionToken token, MentionWire wire) {
    final id = token.id;
    if (token.kind != MentionKind.person || id == null || id.isEmpty) {
      return token.label;
    }
    return Mentions.person(id, wire, displayName: token.label);
  }

  /// Move or drop [tokens] for the edit that turned [oldText] into
  /// [newText].
  ///
  /// The edit is recovered as the one replaced range between the texts'
  /// common prefix and common suffix. A token entirely before it is
  /// untouched, one entirely after it shifts, and one the range reaches into
  /// stops being a mention (M6).
  static List<MentionToken> _rederive(
    List<MentionToken> tokens,
    String oldText,
    String newText,
  ) {
    if (tokens.isEmpty || oldText == newText) return tokens;
    final oldLength = oldText.length;
    final newLength = newText.length;
    final shortest = math.min(oldLength, newLength);

    var prefix = 0;
    while (prefix < shortest &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shortest - prefix &&
        oldText.codeUnitAt(oldLength - 1 - suffix) ==
            newText.codeUnitAt(newLength - 1 - suffix)) {
      suffix++;
    }

    final changeStart = prefix;
    final changeEnd = oldLength - suffix;
    final delta = newLength - oldLength;

    final kept = <MentionToken>[];
    for (final token in tokens) {
      final MentionToken moved;
      if (token.end <= changeStart) {
        moved = token;
      } else if (token.start >= changeEnd) {
        moved = token.shifted(delta);
      } else {
        continue;
      }
      // Belt and braces against an autocorrect rewrite the diff described
      // as something else: a token must still read as its own label.
      if (moved.start < 0 || moved.end > newLength) continue;
      if (newText.substring(moved.start, moved.end) != moved.label) continue;
      kept.add(moved);
    }
    return kept;
  }
}
