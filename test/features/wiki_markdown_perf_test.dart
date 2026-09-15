import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

/// W-A's timing spike for research/20 §4.2: how long a long wiki page takes
/// to parse and to build its first frame through `MarkdownBody`, so W-C can
/// pick the size above which the reader's body becomes a `SuperListView`.
///
/// Two things are measured separately, because they behave nothing alike:
///
/// * the **parse** (`markdown` with `ExtensionSet.gitHubWeb`) is linear in
///   the page and cheap;
/// * the **first frame** is where the time goes, because `MarkdownBody`
///   inside a scroll view builds *and lays out* every block of the document
///   before the first pixel — nothing is culled by the viewport. The cost is
///   super-linear, and `selectable: true` (a `SelectableText.rich` per
///   block) multiplies it, which is why the plan's `SelectionArea` around a
///   non-selectable body is measured too.
///
/// Read the numbers as a ladder, not as absolutes: this runs on the test VM
/// with software rendering and test fonts, so a phone is slower still. The
/// shape — where the curve leaves "instant" — is what the threshold is
/// picked from.
///
/// Measured on this Mac on 2026-09-15 (`flutter test`, software rendering):
///
/// | page | parse | first frame, SelectionArea | first frame, selectable |
/// |---|---|---|---|
/// | 25 KB | ~16 ms | 329 ms | 2 414 ms |
/// | 50 KB | 31 ms | 524 ms | 3 819 ms |
/// | 100 KB | 55 ms | 873 ms | 6 692 ms |
/// | 200 KB | 106 ms | 1 755 ms | 12 929 ms |
/// | 400 KB | 209 ms | — | — |
///
/// So: the parse is never the problem (0.5 ms/KB, linear); `selectable:
/// true` costs about 7x the whole-document layout and must not be used —
/// the plan's `SelectionArea` around a plain body is the cheap one; and
/// even then the first frame grows about 8.7 ms per KB, so ~100 KB is
/// where `MarkdownBody` stops being instant and the `SuperListView` body
/// has to take over.
///
/// The build ladder is **skipped by default**: it takes minutes. Flip
/// [_runBuildLadder] to re-measure (after a package bump, or on another
/// machine); the parse ladder and one small build always run.
const _runBuildLadder = false;

void main() {
  /// A page of about [targetBytes] of markdown, in repeating sections, with
  /// the mix the client wiki actually has (research/20 §1): headings,
  /// paragraphs with links and references, tables, task lists, fences,
  /// attachment images and blockquotes. One repeated paragraph would
  /// measure the wrong thing — the table and fence builders are the
  /// expensive ones.
  String page(int targetBytes) {
    final out = StringBuffer('# Synthetic wiki page\n\n[[_TOC_]]\n\n');
    var section = 0;
    while (out.length < targetBytes) {
      section++;
      out
        ..writeln('## Section $section')
        ..writeln()
        ..writeln(
          'A paragraph with a [relative link](./Other-page), an absolute '
          '[wiki link](/Boardhop/Constructs), `inline code`, **bold** and '
          '_italic_ text, and a reference to #15545 for good measure. It '
          'runs long enough to wrap on a phone and to be worth laying out.',
        )
        ..writeln()
        ..writeln('### Subsection $section.1')
        ..writeln()
        ..writeln('| Column | Value | Note |')
        ..writeln('|---|---|---|');
      for (var row = 0; row < 6; row++) {
        out.writeln('| row $row | value $row | a note about row $row |');
      }
      out
        ..writeln()
        ..writeln('- a list item')
        ..writeln('- [x] a done task')
        ..writeln('- [ ] an open task')
        ..writeln()
        ..writeln('```dart')
        ..writeln("void main() => print('section \$section');")
        ..writeln('final items = <int>[for (var i = 0; i < 10; i++) i];')
        ..writeln('```')
        ..writeln()
        ..writeln('![an attachment](/.attachments/boardhop-w37-b64.png)')
        ..writeln()
        ..writeln(
          '> A blockquote closing the section, because the client wiki has '
          'those too.',
        )
        ..writeln();
    }
    return out.toString();
  }

  int parseMicros(String data) {
    final sw = Stopwatch()..start();
    md.Document(
      extensionSet: md.ExtensionSet.gitHubWeb,
      encodeHtml: false,
    ).parseLines(const LineSplitter().convert(data));
    return sw.elapsedMicroseconds;
  }

  /// [selectable] true is `MarkdownBody`'s own selection (one
  /// `SelectableText.rich` per block); false is the plan's design, a plain
  /// body inside one `SelectionArea`.
  Widget host(String data, {required bool selectable}) {
    final body = MarkdownBody(
      data: data,
      selectable: selectable,
      extensionSet: md.ExtensionSet.gitHubWeb,
      // No network in a widget test, and an attachment needs the bearer
      // token anyway; a box is what the real builder shows while the bytes
      // are in flight.
      imageBuilder: (_, _, _) => const SizedBox(width: 120, height: 80),
    );
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: selectable ? body : SelectionArea(child: body),
        ),
      ),
    );
  }

  Future<void> measureBuild(
    WidgetTester tester,
    int kb, {
    required bool selectable,
  }) async {
    final data = page(kb * 1024);
    final sw = Stopwatch()..start();
    await tester.pumpWidget(host(data, selectable: selectable));
    final built = sw.elapsedMicroseconds;
    debugPrint(
      'WIKI PERF build ${data.length ~/ 1024} KB '
      '(${selectable ? 'selectable' : 'SelectionArea'}): '
      '${(built / 1000).toStringAsFixed(1)} ms to the first frame',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }

  test('parse time by page size', () {
    for (final kb in [50, 100, 200, 400]) {
      final data = page(kb * 1024);
      // One warm-up: the first parse pays for the regexes.
      parseMicros(data);
      final micros = [for (var i = 0; i < 3; i++) parseMicros(data)]..sort();
      debugPrint(
        'WIKI PERF parse ${data.length ~/ 1024} KB: '
        '${(micros[1] / 1000).toStringAsFixed(1)} ms (median of 3)',
      );
    }
  });

  testWidgets('a small page builds and scrolls', (tester) async {
    await tester.pumpWidget(host(page(16 * 1024), selectable: false));

    expect(find.byType(MarkdownBody), findsOneWidget);
    // MarkdownBody wraps each table in a scroll view of its own, so the
    // page's own one is the first.
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -900),
    );
    await tester.pump();
  });

  testWidgets('first-frame build ladder, SelectionArea body', (tester) async {
    for (final kb in [25, 50, 100, 200]) {
      await measureBuild(tester, kb, selectable: false);
    }
  }, skip: !_runBuildLadder);

  testWidgets('first-frame build ladder, MarkdownBody(selectable: true)', (
    tester,
  ) async {
    for (final kb in [25, 50, 100, 200]) {
      await measureBuild(tester, kb, selectable: true);
    }
  }, skip: !_runBuildLadder);
}
