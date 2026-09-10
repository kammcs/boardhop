import 'package:boardhop/features/pull_requests/diff/diff_model.dart';
import 'package:boardhop/features/pull_requests/diff/highlighter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _script(LineDiffResult r) => r.lines
    .map(
      (l) => switch (l.kind) {
        DiffKind.context => ' ${l.text}',
        DiffKind.added => '+${l.text}',
        DiffKind.removed => '-${l.text}',
      },
    )
    .join('\n');

void main() {
  group('LineDiff', () {
    test('identical inputs are all context with numbered lines', () {
      final r = LineDiff.compute('a\nb\nc\n', 'a\nb\nc\n');
      expect(r.hunks, 0);
      expect(r.lines.length, 3);
      expect(r.lines[2].oldNo, 3);
      expect(r.lines[2].newNo, 3);
    });

    test('classic Myers example ABCABBA → CBABAC', () {
      final r = LineDiff.compute('A\nB\nC\nA\nB\nB\nA\n', 'C\nB\nA\nB\nA\nC\n');
      expect(r.editDistance, 5);
      expect(r.added, 2);
      expect(r.removed, 3);
      // The script must replay old → new.
      final oldReplay = r.lines
          .where((l) => l.kind != DiffKind.added)
          .map((l) => l.text)
          .join();
      final newReplay = r.lines
          .where((l) => l.kind != DiffKind.removed)
          .map((l) => l.text)
          .join();
      expect(oldReplay, 'ABCABBA');
      expect(newReplay, 'CBABAC');
    });

    test('insert, delete and replace in the middle keep numbering', () {
      final r = LineDiff.compute(
        'one\ntwo\nthree\nfour\nfive\n',
        'one\ntwo!\nfour\nfive\nsix\n',
      );
      expect(_script(r), ' one\n-two\n-three\n+two!\n four\n five\n+six');
      expect(r.hunks, 2);
      final four = r.lines.firstWhere((l) => l.text == 'four');
      expect(four.oldNo, 4);
      expect(four.newNo, 3);
      final removedTwo = r.lines.firstWhere((l) => l.text == 'two');
      expect(removedTwo.emphasis, isEmpty);
      final six = r.lines.last;
      expect(six.oldNo, isNull);
      expect(six.newNo, 5);
    });

    test('equal-sized replaced blocks get intra-line emphasis', () {
      final r = LineDiff.compute('final x = 1;\n', 'final y = 1;\n');
      expect(r.lines.length, 2);
      expect(r.lines[0].emphasis, [(6, 7)]);
      expect(r.lines[1].emphasis, [(6, 7)]);
    });

    test('empty sides', () {
      expect(LineDiff.compute('', 'a\nb\n').added, 2);
      expect(LineDiff.compute('a\nb\n', '').removed, 2);
      expect(LineDiff.compute('', '').lines, isEmpty);
    });

    test('the 3,000-line fixture diffs quickly with a few dozen hunks', () {
      final a = SampleDiff.original();
      final b = SampleDiff.edited();
      expect(LineDiff.splitLines(a).length, greaterThanOrEqualTo(3000));
      final sw = Stopwatch()..start();
      final r = LineDiff.compute(a, b);
      final elapsed = sw.elapsed;
      expect(r.truncated, isFalse);
      expect(r.hunks, inInclusiveRange(20, 200));
      expect(r.lines.length, greaterThan(3000));
      // Debug-mode VM; the device number is in the spike report.
      expect(elapsed.inMilliseconds, lessThan(2000));
      // Replaying the script reproduces both sides exactly.
      final newSide = r.lines
          .where((l) => l.kind != DiffKind.removed)
          .map((l) => l.text)
          .toList();
      expect(newSide, LineDiff.splitLines(b));
    });
  });

  group('CodeHighlighter', () {
    test('splits whole-file spans into lines and keeps block comments', () {
      const code = 'class A {\n  /* one\n     two */\n  int x = 1;\n}\n';
      final lines = CodeHighlighter.highlightLines(
        code,
        'dart',
        Brightness.light,
      );
      expect(lines.length, 5);
      expect(lines.map((l) => l.map((r) => r.text).join()).toList(), [
        'class A {',
        '  /* one',
        '     two */',
        '  int x = 1;',
        '}',
      ]);
      // Both comment lines carry the same (comment) style.
      final one = lines[1].last.style;
      final two = lines[2].first.style;
      expect(one, isNotNull);
      expect(one?.color, two?.color);
    });

    test('unknown language falls back to plain runs', () {
      final lines = CodeHighlighter.highlightLines(
        'a\nb\n',
        null,
        Brightness.dark,
      );
      expect(lines.length, 2);
      expect(lines[0].single.style, isNull);
      expect(CodeHighlighter.languageFor('x/y.cs'), 'csharp');
      expect(CodeHighlighter.languageFor('README'), isNull);
    });

    test('emphasize splits runs at the changed ranges', () {
      const bold = TextStyle(fontWeight: FontWeight.bold);
      final runs = CodeHighlighter.emphasize(
        const [
          CodeRun('final ', null),
          CodeRun('x = 1;', TextStyle(color: Colors.red)),
        ],
        const [(6, 7)],
        bold,
      );
      expect(runs.map((r) => r.text).toList(), ['final ', 'x', ' = 1;']);
      expect(runs[1].style?.fontWeight, FontWeight.bold);
      expect(runs[1].style?.color, Colors.red);
      expect(runs[2].style?.fontWeight, isNull);
    });
  });
}
