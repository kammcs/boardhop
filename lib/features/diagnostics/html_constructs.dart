/// Construct detectors shared by the F3 harness and the on-device editor
/// probe. Each regex answers "does this HTML still contain X?".
abstract final class HtmlConstructs {
  static final Map<String, RegExp> detectors = <String, RegExp>{
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
    'mention-text': RegExp(r'@[A-Z][a-z]+ [A-Z][a-z]+'),
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

  /// For each construct present in [input]: true if it is also in [output].
  static Map<String, bool> survival(String input, String output) => {
    for (final e in detectors.entries)
      if (e.value.hasMatch(input)) e.key: e.value.hasMatch(output),
  };

  static String visibleText(String html) => html
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Word-level recall of the visible text: 1.0 means every word came back.
  static double textRecall(String input, String output) {
    final a = visibleText(input).split(' ').where((w) => w.isNotEmpty);
    final b = visibleText(output).split(' ').where((w) => w.isNotEmpty);
    if (a.isEmpty) return 1;
    final counts = <String, int>{};
    for (final w in b) {
      counts[w] = (counts[w] ?? 0) + 1;
    }
    var hit = 0;
    var total = 0;
    for (final w in a) {
      total++;
      final c = counts[w] ?? 0;
      if (c > 0) {
        hit++;
        counts[w] = c - 1;
      }
    }
    return hit / total;
  }

  /// One synthetic description exercising every construct in the corpus.
  static const synthetic = '''
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
}
