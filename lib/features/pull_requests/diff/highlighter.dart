import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

/// A styled fragment of one line.
class CodeRun {
  const CodeRun(this.text, this.style);

  final String text;
  final TextStyle? style;
}

/// Whole-file syntax highlighting split into lines, so multi-line constructs
/// (block comments, raw strings) keep their color and each row can be
/// rendered independently.
abstract final class CodeHighlighter {
  static final Highlight _highlight = Highlight()
    ..registerLanguages(builtinLanguages);

  static const _byExtension = <String, String>{
    'dart': 'dart',
    'cs': 'csharp',
    'ts': 'typescript',
    'tsx': 'typescript',
    'js': 'javascript',
    'jsx': 'javascript',
    'py': 'python',
    'json': 'json',
    'yaml': 'yaml',
    'yml': 'yaml',
    'md': 'markdown',
    'xml': 'xml',
    'html': 'xml',
    'css': 'css',
    'scss': 'scss',
    'kt': 'kotlin',
    'kts': 'kotlin',
    'swift': 'swift',
    'java': 'java',
    'sql': 'sql',
    'sh': 'bash',
    'ps1': 'powershell',
    'go': 'go',
    'rs': 'rust',
    'rb': 'ruby',
    'php': 'php',
    'gradle': 'gradle',
    'toml': 'ini',
    'ini': 'ini',
    'proto': 'protobuf',
    'c': 'c',
    'h': 'c',
    'cpp': 'cpp',
    'cc': 'cpp',
    'hpp': 'cpp',
    'm': 'objectivec',
    'mm': 'objectivec',
    'vue': 'vue',
    'less': 'less',
    'graphql': 'graphql',
    'gql': 'graphql',
    'groovy': 'groovy',
    'scala': 'scala',
    'lua': 'lua',
    'pl': 'perl',
    'r': 'r',
    'vb': 'vbnet',
    'fs': 'fsharp',
    'ex': 'elixir',
    'exs': 'elixir',
    'hs': 'haskell',
    'bat': 'dos',
    'cmd': 'dos',
    'psm1': 'powershell',
    'bash': 'bash',
    'zsh': 'bash',
    'makefile': 'makefile',
    'mk': 'makefile',
    'tf': 'ini',
    'csproj': 'xml',
    'props': 'xml',
    'targets': 'xml',
    'plist': 'xml',
    'svg': 'xml',
    'xaml': 'xml',
    'resx': 'xml',
    'config': 'xml',
    'properties': 'properties',
    'env': 'properties',
    'diff': 'diff',
    'patch': 'diff',
    'tex': 'latex',
    'nginx': 'nginx',
    'http': 'http',
    'cmake': 'cmake',
  };

  static const _byName = <String, String>{
    'dockerfile': 'dockerfile',
    'makefile': 'makefile',
    'cmakelists.txt': 'cmake',
    '.gitignore': 'properties',
    '.editorconfig': 'ini',
  };

  /// highlight.js language name for a file path, or null for plain text.
  static String? languageFor(String path) {
    final slash = path.lastIndexOf('/');
    final name = (slash < 0 ? path : path.substring(slash + 1)).toLowerCase();
    final byName = _byName[name];
    if (byName != null) return byName;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return null;
    return _byExtension[name.substring(dot + 1)];
  }

  /// [highlightLines] on a background isolate, for whole files: the
  /// grammar work for a few thousand lines takes hundreds of milliseconds
  /// (spike F5) and must not block the UI thread. Registration is lazy, so
  /// a fresh isolate costs little.
  static Future<List<List<CodeRun>>> highlightLinesAsync(
    String code,
    String? language,
    Brightness brightness,
  ) {
    if (language == null) return Future.value(_plain(code));
    return Isolate.run(() => highlightLines(code, language, brightness));
  }

  static Map<String, TextStyle> themeFor(Brightness b) =>
      b == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme;

  /// Highlights [code] and returns one run list per line. Falls back to
  /// unstyled runs when [language] is null or unknown.
  static List<List<CodeRun>> highlightLines(
    String code,
    String? language,
    Brightness brightness,
  ) {
    if (language == null) return _plain(code);
    final HighlightResult result;
    try {
      result = _highlight.highlight(code: code, language: language);
    } catch (_) {
      return _plain(code);
    }
    final renderer = TextSpanRenderer(null, themeFor(brightness));
    result.render(renderer);
    final span = renderer.span;
    if (span == null) return _plain(code);
    final lines = <List<CodeRun>>[<CodeRun>[]];
    void visit(InlineSpan s, TextStyle? inherited) {
      if (s is! TextSpan) return;
      final style = inherited == null
          ? s.style
          : (s.style == null ? inherited : inherited.merge(s.style));
      final text = s.text;
      if (text != null && text.isNotEmpty) {
        final parts = text.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (i > 0) lines.add(<CodeRun>[]);
          if (parts[i].isNotEmpty) lines.last.add(CodeRun(parts[i], style));
        }
      }
      for (final c in s.children ?? const <InlineSpan>[]) {
        visit(c, style);
      }
    }

    visit(span, null);
    if (lines.isNotEmpty && lines.last.isEmpty && code.endsWith('\n')) {
      lines.removeLast();
    }
    return lines;
  }

  static List<List<CodeRun>> _plain(String code) {
    final lines = code.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    return [
      for (final l in lines) [if (l.isNotEmpty) CodeRun(l, null)],
    ];
  }

  /// Splits [runs] so that every character inside one of [ranges] sits in a
  /// run of its own with [emphasis] merged in.
  static List<CodeRun> emphasize(
    List<CodeRun> runs,
    List<(int, int)> ranges,
    TextStyle emphasis,
  ) {
    if (ranges.isEmpty) return runs;
    final out = <CodeRun>[];
    var pos = 0;
    for (final run in runs) {
      final start = pos;
      final end = pos + run.text.length;
      var cursor = start;
      for (final (rs, re) in ranges) {
        final s = rs.clamp(start, end);
        final e = re.clamp(start, end);
        if (e <= s) continue;
        if (s > cursor) {
          out.add(
            CodeRun(run.text.substring(cursor - start, s - start), run.style),
          );
        }
        out.add(
          CodeRun(
            run.text.substring(s - start, e - start),
            run.style == null ? emphasis : run.style!.merge(emphasis),
          ),
        );
        cursor = e;
      }
      if (cursor < end) {
        out.add(CodeRun(run.text.substring(cursor - start), run.style));
      }
      pos = end;
    }
    return out;
  }
}
