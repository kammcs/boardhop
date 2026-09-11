import 'package:boardhop/features/pull_requests/diff/highlighter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('languageFor handles paths, names without extensions and case', () {
    expect(CodeHighlighter.languageFor('/src/App.TSX'), 'typescript');
    expect(CodeHighlighter.languageFor('/Dockerfile'), 'dockerfile');
    expect(CodeHighlighter.languageFor('/a/b/Makefile'), 'makefile');
    expect(CodeHighlighter.languageFor('/x/.gitignore'), 'properties');
    expect(CodeHighlighter.languageFor('/x/Foo.csproj'), 'xml');
    expect(CodeHighlighter.languageFor('/x/notes'), isNull);
    expect(CodeHighlighter.languageFor('/x/data.unknownext'), isNull);
  });

  test('highlightLinesAsync runs on an isolate and keeps line count', () async {
    const code = 'void main() {\n  print("hi"); // c\n}\n';
    final lines = await CodeHighlighter.highlightLinesAsync(
      code,
      'dart',
      Brightness.light,
    );
    expect(lines.length, 3);
    expect(lines[1].map((r) => r.text).join(), '  print("hi"); // c');
    expect(lines[1].any((r) => r.style != null), isTrue);
    final plain = await CodeHighlighter.highlightLinesAsync(
      code,
      null,
      Brightness.light,
    );
    expect(plain.length, 3);
    expect(plain[0].single.style, isNull);
  });
}
