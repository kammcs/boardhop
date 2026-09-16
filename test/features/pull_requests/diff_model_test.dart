import 'package:boardhop/features/pull_requests/diff/diff_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// `hunkStarts` is what the ▲▼ control walks in Changes mode (R5): the row
/// index of the first line of every change run, in the same order and the
/// same count as [LineDiffResult.hunks].
void main() {
  group('hunkStarts', () {
    test('an unchanged file has no stops', () {
      const text = 'a\nb\nc\n';
      final r = LineDiff.compute(text, text);
      expect(r.hunks, 0);
      expect(r.hunkStarts, isEmpty);
    });

    test('one changed line in the middle is one stop at its row', () {
      final r = LineDiff.compute('a\nb\nc\n', 'a\nB\nc\n');

      expect(r.hunkStarts, hasLength(r.hunks));
      // The removed line comes first in a unified diff, so the stop is the
      // row that starts the run, not the added line under it.
      final start = r.hunkStarts.single;
      expect(r.lines[start].kind, anyOf(DiffKind.removed, DiffKind.added));
      expect(r.lines[start - 1].kind, DiffKind.context);
    });

    test('two runs separated by context are two stops in order', () {
      final r = LineDiff.compute('a\nb\nc\nd\ne\nf\n', 'a\nB\nc\nd\nE\nf\n');

      expect(r.hunks, 2);
      expect(r.hunkStarts, hasLength(2));
      expect(r.hunkStarts.first, lessThan(r.hunkStarts.last));
      for (final i in r.hunkStarts) {
        expect(r.lines[i].kind, isNot(DiffKind.context));
        // Every stop begins a run: the row above it is context or nothing.
        if (i > 0) expect(r.lines[i - 1].kind, DiffKind.context);
      }
    });

    test('adjacent removed and added lines are one run, not two', () {
      final r = LineDiff.compute('a\nb\nc\n', 'a\nX\nY\nc\n');
      expect(r.hunks, 1);
      expect(r.hunkStarts, hasLength(1));
    });

    test('a change at the very first row starts at index 0', () {
      final r = LineDiff.compute('a\nb\n', 'A\nb\n');
      expect(r.hunkStarts.first, 0);
    });

    test('a change at the last row is still a stop', () {
      final r = LineDiff.compute('a\nb\n', 'a\nB\n');
      final start = r.hunkStarts.single;
      expect(start, greaterThan(0));
      expect(r.lines[start].kind, isNot(DiffKind.context));
    });

    test('a new file is one stop at the top', () {
      final r = LineDiff.compute('', 'a\nb\nc\n');
      expect(r.added, 3);
      expect(r.hunks, 1);
      expect(r.hunkStarts, [0]);
    });

    test('a deleted file is one stop at the top', () {
      final r = LineDiff.compute('a\nb\nc\n', '');
      expect(r.removed, 3);
      expect(r.hunkStarts, [0]);
    });

    test('the count and the stops never disagree, even on a big file', () {
      final old = List.generate(400, (i) => 'line $i').join('\n');
      final now = List.generate(
        400,
        (i) => i % 7 == 0 ? 'line $i changed' : 'line $i',
      ).join('\n');

      final r = LineDiff.compute(old, now);

      expect(r.hunkStarts, hasLength(r.hunks));
      expect(r.hunkStarts, orderedEquals(r.hunkStarts.toList()..sort()));
      expect(r.hunkStarts.toSet(), hasLength(r.hunkStarts.length));
      for (final i in r.hunkStarts) {
        expect(i, inInclusiveRange(0, r.lines.length - 1));
      }
    });
  });
}
