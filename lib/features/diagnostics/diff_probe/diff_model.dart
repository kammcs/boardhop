import 'dart:math';

import 'package:diff_match_patch/diff_match_patch.dart' as dmp;

enum DiffKind { context, added, removed }

/// One row of a unified diff. [oldNo]/[newNo] are 1-based line numbers, null
/// on the side where the line does not exist.
class DiffLine {
  const DiffLine({
    required this.kind,
    required this.text,
    this.oldNo,
    this.newNo,
    this.emphasis = const <(int, int)>[],
  });

  final DiffKind kind;
  final String text;
  final int? oldNo;
  final int? newNo;

  /// Character ranges (start, end) inside [text] that differ from the paired
  /// line on the other side, for the stronger intra-line tint.
  final List<(int, int)> emphasis;

  DiffLine withEmphasis(List<(int, int)> ranges) => DiffLine(
    kind: kind,
    text: text,
    oldNo: oldNo,
    newNo: newNo,
    emphasis: ranges,
  );
}

class LineDiffResult {
  const LineDiffResult({
    required this.lines,
    required this.hunks,
    required this.added,
    required this.removed,
    required this.maxChars,
    required this.editDistance,
    required this.truncated,
  });

  final List<DiffLine> lines;
  final int hunks;
  final int added;
  final int removed;
  final int maxChars;
  final int editDistance;

  /// True when the Myers search was abandoned and the middle of the file
  /// was emitted as one delete-all / add-all block.
  final bool truncated;
}

/// Line-level diff. Myers O(ND) on the lines after trimming the common
/// prefix and suffix, then character-level emphasis inside replaced blocks
/// from `diff_match_patch`. Written here because the package's line mode is
/// not part of its public API and the package has not been updated since
/// 2021; this file is the seed of the production diff engine.
abstract final class LineDiff {
  static const int maxEditDistance = 4000;

  static List<String> splitLines(String text) {
    if (text.isEmpty) return const <String>[];
    final lines = text.split('\n');
    if (lines.last.isEmpty) lines.removeLast();
    return lines;
  }

  static LineDiffResult compute(String oldText, String newText) {
    final a = splitLines(oldText);
    final b = splitLines(newText);
    var prefix = 0;
    while (prefix < a.length && prefix < b.length && a[prefix] == b[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < a.length - prefix &&
        suffix < b.length - prefix &&
        a[a.length - 1 - suffix] == b[b.length - 1 - suffix]) {
      suffix++;
    }
    final midA = a.sublist(prefix, a.length - suffix);
    final midB = b.sublist(prefix, b.length - suffix);

    final out = <DiffLine>[];
    for (var i = 0; i < prefix; i++) {
      out.add(
        DiffLine(kind: DiffKind.context, text: a[i], oldNo: i + 1, newNo: i + 1),
      );
    }
    final (ops, distance, truncated) = _myers(midA, midB);
    var oi = prefix;
    var ni = prefix;
    for (final op in ops) {
      switch (op) {
        case _Op.keep:
          out.add(
            DiffLine(
              kind: DiffKind.context,
              text: a[oi],
              oldNo: oi + 1,
              newNo: ni + 1,
            ),
          );
          oi++;
          ni++;
        case _Op.remove:
          out.add(DiffLine(kind: DiffKind.removed, text: a[oi], oldNo: oi + 1));
          oi++;
        case _Op.add:
          out.add(DiffLine(kind: DiffKind.added, text: b[ni], newNo: ni + 1));
          ni++;
      }
    }
    for (var i = 0; i < suffix; i++) {
      out.add(
        DiffLine(
          kind: DiffKind.context,
          text: a[oi + i],
          oldNo: oi + i + 1,
          newNo: ni + i + 1,
        ),
      );
    }
    _emphasize(out);

    var hunks = 0;
    var added = 0;
    var removed = 0;
    var maxChars = 0;
    var inHunk = false;
    for (final l in out) {
      maxChars = max(maxChars, l.text.length);
      switch (l.kind) {
        case DiffKind.context:
          inHunk = false;
        case DiffKind.added:
          added++;
          if (!inHunk) hunks++;
          inHunk = true;
        case DiffKind.removed:
          removed++;
          if (!inHunk) hunks++;
          inHunk = true;
      }
    }
    return LineDiffResult(
      lines: out,
      hunks: hunks,
      added: added,
      removed: removed,
      maxChars: maxChars,
      editDistance: distance,
      truncated: truncated,
    );
  }

  /// Classic Myers with a trace of V arrays. Returns the edit script, the
  /// edit distance, and whether the search was cut off at [maxEditDistance].
  static (List<_Op>, int, bool) _myers(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;
    if (n == 0 && m == 0) return (const <_Op>[], 0, false);
    if (n == 0) return (List.filled(m, _Op.add), m, false);
    if (m == 0) return (List.filled(n, _Op.remove), n, false);
    final maxD = min(n + m, maxEditDistance);
    final offset = maxD;
    var v = List<int>.filled(2 * maxD + 2, 0);
    final trace = <List<int>>[];
    for (var d = 0; d <= maxD; d++) {
      trace.add(v);
      final next = List<int>.of(v);
      for (var k = -d; k <= d; k += 2) {
        int x;
        if (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) {
          x = v[offset + k + 1];
        } else {
          x = v[offset + k - 1] + 1;
        }
        var y = x - k;
        while (x < n && y < m && a[x] == b[y]) {
          x++;
          y++;
        }
        next[offset + k] = x;
        if (x >= n && y >= m) {
          trace.add(next);
          return (_backtrack(trace, a, b, offset, d), d, false);
        }
      }
      v = next;
    }
    // Too different to be worth an exact script.
    return (
      [...List.filled(n, _Op.remove), ...List.filled(m, _Op.add)],
      maxD,
      true,
    );
  }

  static List<_Op> _backtrack(
    List<List<int>> trace,
    List<String> a,
    List<String> b,
    int offset,
    int d,
  ) {
    final ops = <_Op>[];
    var x = a.length;
    var y = b.length;
    for (var step = d; step > 0; step--) {
      final v = trace[step];
      final k = x - y;
      final int prevK;
      if (k == -step || (k != step && v[offset + k - 1] < v[offset + k + 1])) {
        prevK = k + 1;
      } else {
        prevK = k - 1;
      }
      final prevX = v[offset + prevK];
      final prevY = prevX - prevK;
      while (x > prevX && y > prevY) {
        ops.add(_Op.keep);
        x--;
        y--;
      }
      if (x == prevX) {
        ops.add(_Op.add);
        y--;
      } else {
        ops.add(_Op.remove);
        x--;
      }
    }
    while (x > 0 && y > 0) {
      ops.add(_Op.keep);
      x--;
      y--;
    }
    return ops.reversed.toList();
  }

  /// For each block of removed lines immediately followed by the same
  /// number of added lines, mark the character ranges that changed.
  static void _emphasize(List<DiffLine> lines) {
    var i = 0;
    while (i < lines.length) {
      if (lines[i].kind != DiffKind.removed) {
        i++;
        continue;
      }
      var j = i;
      while (j < lines.length && lines[j].kind == DiffKind.removed) {
        j++;
      }
      var k = j;
      while (k < lines.length && lines[k].kind == DiffKind.added) {
        k++;
      }
      final removedCount = j - i;
      final addedCount = k - j;
      if (removedCount == addedCount) {
        for (var p = 0; p < removedCount; p++) {
          final (oldRanges, newRanges) = charRanges(
            lines[i + p].text,
            lines[j + p].text,
          );
          lines[i + p] = lines[i + p].withEmphasis(oldRanges);
          lines[j + p] = lines[j + p].withEmphasis(newRanges);
        }
      }
      i = k;
    }
  }

  /// Character ranges that differ between two lines, semantic cleanup on.
  static (List<(int, int)>, List<(int, int)>) charRanges(
    String oldLine,
    String newLine,
  ) {
    final diffs = dmp.diff(oldLine, newLine);
    dmp.cleanupSemantic(diffs);
    final oldRanges = <(int, int)>[];
    final newRanges = <(int, int)>[];
    var o = 0;
    var n = 0;
    for (final d in diffs) {
      final len = d.text.length;
      switch (d.operation) {
        case dmp.DIFF_EQUAL:
          o += len;
          n += len;
        case dmp.DIFF_DELETE:
          oldRanges.add((o, o + len));
          o += len;
        case dmp.DIFF_INSERT:
          newRanges.add((n, n + len));
          n += len;
      }
    }
    return (oldRanges, newRanges);
  }
}

enum _Op { keep, add, remove }

/// A synthetic Dart file and an edited copy, deterministic, no client data.
abstract final class SampleDiff {
  static const _names = <String>[
    'account',
    'board',
    'column',
    'comment',
    'iteration',
    'pipeline',
    'project',
    'review',
    'sprint',
    'thread',
  ];

  static String original({int lines = 3000, int seed = 7}) =>
      _generate(lines: lines, seed: seed, edit: false);

  static String edited({int lines = 3000, int seed = 7}) =>
      _generate(lines: lines, seed: seed, edit: true);

  static String _generate({
    required int lines,
    required int seed,
    required bool edit,
  }) {
    final rng = Random(seed);
    final b = StringBuffer();
    b.writeln('/// Generated fixture for spike F5.');
    b.writeln('///');
    b.writeln('/// Every [Service] below is a copy with different names, so');
    b.writeln('/// the highlighter sees classes, strings, comments and numbers.');
    b.writeln("import 'dart:async';");
    b.writeln('');
    var block = 0;
    while (b.toString().split('\n').length < lines) {
      final name = _names[rng.nextInt(_names.length)];
      final cls = '${name[0].toUpperCase()}${name.substring(1)}Service$block';
      // Draw every random value up front so an edit never shifts the
      // stream for the blocks after it.
      final retries = rng.nextInt(5) + 1;
      final budget = rng.nextInt(1000);
      final delay = rng.nextInt(400);
      final editHere = edit && block % 3 == 1;
      final editKind = block % 9;
      b.writeln('/* Block $block: $name service.');
      b.writeln('   Multi-line comment to check whole-file highlighting. */');
      b.writeln('class $cls {');
      b.writeln('  $cls(this.client, {this.retries = $retries});');
      b.writeln('');
      b.writeln('  final Object client;');
      b.writeln('  final int retries;');
      if (editHere && editKind == 1) {
        b.writeln('  final Duration timeout = const Duration(seconds: 30);');
        b.writeln('  final bool verbose = false;');
        b.writeln('  final List<String> tags = <String>[];');
      }
      b.writeln('');
      b.writeln('  Future<List<String>> list$block(String org) async {');
      if (editHere && editKind == 4) {
        b.writeln("    final uri = Uri.https('dev.azure.com', '/\$org/_apis/$name', {'api-version': '7.1', 'top': '200'});");
      } else {
        b.writeln("    final uri = Uri.https('dev.azure.com', '/\$org/_apis/$name', {'api-version': '7.1'});");
      }
      b.writeln('    for (var attempt = 0; attempt < retries; attempt++) {');
      b.writeln('      try {');
      if (!(editHere && editKind == 7)) {
        b.writeln('        // $budget ms budget per attempt');
        b.writeln('        await Future<void>.delayed(const Duration(milliseconds: $delay));');
      }
      b.writeln("        return <String>['\$uri', '$name-\$attempt'];");
      b.writeln('      } on TimeoutException {');
      b.writeln('        continue;');
      b.writeln('      }');
      b.writeln('    }');
      b.writeln("    throw StateError('$cls gave up after \$retries attempts');");
      b.writeln('  }');
      b.writeln('}');
      b.writeln('');
      block++;
    }
    return b.toString();
  }
}
