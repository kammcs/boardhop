// Spike F3: HTML round-trip fidelity of the candidate rich-text editors.
//
// Feeds Azure DevOps description HTML through each editor's import and
// export and reports which constructs survive. Runs on a committed synthetic
// fixture always, and on real samples from research/spikes/results/
// f3-samples.json (gitignored client data) when that file exists.
//
// It is a measurement, not a gate: the only assertions are that neither
// engine throws on the synthetic fixture. The report is written to
// research/spikes/results/f3-roundtrip.md (gitignored).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:parchment/codecs.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

/// One synthetic description exercising every construct seen in the corpus.
const synthetic = '''
<div><h2>Summary</h2>
<div>Checkout <b>fails</b> for <i>guest</i> users with <u>expired</u> carts. See <a href="https://example.test/runbook">runbook</a>.</div>
<div><span style="color:rgb(255, 0, 0);background-color:rgb(255, 255, 0);">Priority: high</span></div>
<h3>Steps</h3>
<ol>
<li>Open the store as a guest</li>
<li>Add an item
<ul><li>Any SKU</li><li>Quantity &gt; 1</li></ul>
</li>
<li>Wait <b>30 minutes</b> then pay</li>
</ol>
<div>Assigned to <a href="#" data-vss-mention="version:2.0,11111111-2222-3333-4444-555555555555">@Kelly Kamm</a> for triage.</div>
<table style="width:100%;border-collapse:collapse;"><tbody>
<tr><td style="border:1px solid #ccc;"><b>Env</b></td><td style="border:1px solid #ccc;"><b>Result</b></td></tr>
<tr><td style="border:1px solid #ccc;">Prod</td><td style="border:1px solid #ccc;">500</td></tr>
<tr><td style="border:1px solid #ccc;">Staging</td><td style="border:1px solid #ccc;">OK</td></tr>
</tbody></table>
<div><img src="https://dev.azure.com/puremedia/aaaa/_apis/wit/attachments/bbbb?fileName=shot.png" alt="screenshot" style="width:420px;"></div>
<pre><code>POST /api/checkout
{ "cart": "c-42" }</code></pre>
<div>Trailing line with <s>strike</s> and a<br>line break.</div>
</div>
''';

/// Constructs and how to detect them in HTML.
final constructs = <String, RegExp>{
  'table': RegExp(r'<table', caseSensitive: false),
  'table-cells': RegExp(r'<td|<th', caseSensitive: false),
  'ordered-list': RegExp(r'<ol', caseSensitive: false),
  'unordered-list': RegExp(r'<ul', caseSensitive: false),
  'nested-list': RegExp(
    r'<li[^>]*>(?:(?!</li>).)*<(ul|ol)',
    caseSensitive: false,
    dotAll: true,
  ),
  'image': RegExp(r'<img', caseSensitive: false),
  'image-src-attachments': RegExp(
    r'_apis/wit/attachments',
    caseSensitive: false,
  ),
  'mention-attr': RegExp(r'data-vss-mention', caseSensitive: false),
  'mention-text': RegExp(r'@Kelly Kamm|@[A-Z][a-z]+ [A-Z][a-z]+'),
  'heading': RegExp(r'<h[1-6]', caseSensitive: false),
  'code': RegExp(r'<(pre|code)', caseSensitive: false),
  'link-href': RegExp(r'<a[^>]+href="https?://', caseSensitive: false),
  'inline-color': RegExp(r'color\s*:', caseSensitive: false),
  'bold': RegExp(r'<(b|strong)\b', caseSensitive: false),
  'italic': RegExp(r'<(i|em)\b', caseSensitive: false),
  'underline': RegExp(
    r'<u\b|text-decoration\s*:\s*underline',
    caseSensitive: false,
  ),
  'strike': RegExp(r'<(s|strike|del)\b|line-through', caseSensitive: false),
  'line-break': RegExp(r'<br', caseSensitive: false),
};

String visibleText(String html) {
  final doc = html_parser.parse(html);
  final text = doc.body?.text ?? '';
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Word-level overlap of visible text: 1.0 means every word came back.
double textRecall(String input, String output) {
  final a = visibleText(input).split(' ').where((w) => w.isNotEmpty).toList();
  final b = visibleText(output).split(' ').where((w) => w.isNotEmpty).toList();
  if (a.isEmpty) return 1;
  final counts = <String, int>{};
  for (final w in b) {
    counts[w] = (counts[w] ?? 0) + 1;
  }
  var hit = 0;
  for (final w in a) {
    final c = counts[w] ?? 0;
    if (c > 0) {
      hit++;
      counts[w] = c - 1;
    }
  }
  return hit / a.length;
}

class Engine {
  Engine(this.name, this.roundTrip);
  final String name;
  final String Function(String html) roundTrip;
}

String quillRoundTrip(String html) {
  final delta = HtmlToDelta().convert(html);
  return QuillDeltaToHtmlConverter(delta.toJson()).convert();
}

String parchmentRoundTrip(String html) {
  final doc = parchmentHtml.decode(html);
  return parchmentHtml.encode(doc);
}

final engines = <Engine>[
  Engine('flutter_quill (delta_from_html + vsc_delta_to_html)', quillRoundTrip),
  Engine('fleather (parchment html codec)', parchmentRoundTrip),
];

class Outcome {
  Outcome(this.engine, this.sample, this.input, this.output, this.error);
  final String engine;
  final String sample;
  final String input;
  final String? output;
  final Object? error;

  Map<String, bool?> get survival => {
    for (final e in constructs.entries)
      if (e.value.hasMatch(input))
        e.key: output == null ? null : e.value.hasMatch(output!),
  };

  double get recall => output == null ? 0 : textRecall(input, output!);
}

Outcome run(Engine engine, String sampleName, String html) {
  try {
    final out = engine.roundTrip(html);
    return Outcome(engine.name, sampleName, html, out, null);
  } catch (e) {
    return Outcome(engine.name, sampleName, html, null, e);
  }
}

List<(String, String)> loadRealSamples() {
  final file = File('../results/f3-samples.json');
  if (!file.existsSync()) return const [];
  final all = (jsonDecode(file.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  // Cover each construct with the richest sample not yet chosen; cap at 8.
  final wanted = [
    'table',
    'nested-list',
    'image',
    'mention',
    'code',
    'heading',
    'inline-color',
    'link',
  ];
  final picked = <Map<String, dynamic>>[];
  for (final tag in wanted) {
    final candidate = all
        .where((s) => (s['tags'] as List).contains(tag) && !picked.contains(s))
        .firstOrNull;
    if (candidate != null) picked.add(candidate);
  }
  return [
    for (final s in picked)
      (
        '#${s['id']} ${s['field'].toString().split('.').last}',
        s['html'] as String,
      ),
  ];
}

String report(List<Outcome> outcomes) {
  final b = StringBuffer('# Spike F3: HTML round-trip report\n\n');
  b.writeln('Generated ${DateTime.now().toIso8601String()}\n');
  final samples = outcomes.map((o) => o.sample).toSet();
  for (final sample in samples) {
    b.writeln('## $sample\n');
    final rows = outcomes.where((o) => o.sample == sample).toList();
    final keys = rows.first.survival.keys.toList();
    b.writeln('| construct | ${rows.map((r) => r.engine).join(' | ')} |');
    b.writeln('|---|${rows.map((_) => '---').join('|')}|');
    for (final k in keys) {
      b.writeln(
        '| $k | ${rows.map((r) => switch (r.survival[k]) {
          true => 'kept',
          false => 'LOST',
          null => 'error',
        }).join(' | ')} |',
      );
    }
    b.writeln(
      '| text recall | ${rows.map((r) => '${(r.recall * 100).toStringAsFixed(0)}%').join(' | ')} |',
    );
    b.writeln(
      '| output length | ${rows.map((r) => '${r.output?.length ?? '-'} (in ${r.input.length})').join(' | ')} |',
    );
    for (final r in rows.where((r) => r.error != null)) {
      b.writeln('\n${r.engine} threw: `${r.error}`');
    }
    b.writeln();
  }
  b.writeln('## Synthetic fixture output\n');
  for (final r in outcomes.where((o) => o.sample == 'synthetic')) {
    b.writeln('### ${r.engine}\n');
    b.writeln('```html\n${r.output ?? r.error}\n```\n');
  }
  return b.toString();
}

void main() {
  test('F3 round-trip report', () {
    final outcomes = <Outcome>[];
    for (final engine in engines) {
      outcomes.add(run(engine, 'synthetic', synthetic));
    }
    for (final (name, html) in loadRealSamples()) {
      for (final engine in engines) {
        outcomes.add(run(engine, name, html));
      }
    }

    final md = report(outcomes);
    final out = File('../results/f3-roundtrip.md');
    if (out.parent.existsSync()) out.writeAsStringSync(md);

    // Compact console summary: survival counts per engine.
    for (final engine in engines) {
      final mine = outcomes.where((o) => o.engine == engine.name);
      var kept = 0, lost = 0, errors = 0;
      for (final o in mine) {
        if (o.error != null) {
          errors++;
          continue;
        }
        for (final v in o.survival.values) {
          if (v == true) kept++;
          if (v == false) lost++;
        }
      }
      final recall =
          mine.map((o) => o.recall).fold(0.0, (a, b) => a + b) / mine.length;
      // ignore: avoid_print
      print(
        '${engine.name}: kept=$kept lost=$lost errors=$errors '
        'avgTextRecall=${(recall * 100).toStringAsFixed(0)}% samples=${mine.length}',
      );
    }

    for (final o in outcomes.where((o) => o.sample == 'synthetic')) {
      expect(o.error, isNull, reason: '${o.engine} threw on the fixture');
    }
  });
}
