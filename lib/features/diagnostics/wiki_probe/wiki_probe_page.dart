import 'package:flutter/material.dart';

import '../../../data/models/wiki.dart';
import '../../../theme/theme.dart';
import '../../wiki/widgets/toc_sheet.dart';
import '../../wiki/widgets/wiki_markdown.dart';
import '../../wiki/widgets/wiki_picker_sheet.dart';
import '../../wiki/widgets/wiki_source_page.dart';
import '../../wiki/widgets/wiki_tree_view.dart';
import '../../wiki/wiki_prefs.dart';

/// The wiki probe: the Wiki hub's furniture on canned data — the tree rows
/// with their indents, chevrons and the greyed non-conformant row, the
/// Recent strip, the cache line, both empty states, the wiki picker, the
/// contents sheet, the reader's header and footer and the markdown body.
///
/// It composes the **widgets** rather than mounting `WikiTreePage` itself:
/// that page reads `WikiRepository` out of the context, and a probe that
/// needed a client, an account and a database could not be opened on a
/// simulator without signing in — which is the whole point of the probes
/// (the dashboard probe draws its cards the same way).
///
/// The tree is shaped like the scratch wiki (research/20 §1, quotable); the
/// markdown is invented. Nothing here is client data and nothing here
/// touches Azure DevOps. Diagnostics only (`AppConfig.diagnosticsEnabled`).
class WikiProbePage extends StatefulWidget {
  const WikiProbePage({super.key});

  @override
  State<WikiProbePage> createState() => _WikiProbePageState();
}

class _WikiProbePageState extends State<WikiProbePage> {
  final _headings = WikiHeadings();

  final Set<String> _expanded = ancestorPathsOf(WikiProbeData.selectedPath);
  String _selected = WikiProbeData.selectedPath;
  Wiki _wiki = WikiProbeData.projectWiki;
  String? _tapped;

  @override
  void dispose() {
    _headings.dispose();
    super.dispose();
  }

  void _say(String what) {
    setState(() => _tapped = what);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(what)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = visibleWikiRows(WikiProbeData.tree, _expanded);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wiki probe'),
        actions: [
          IconButton(
            tooltip: 'Wiki picker',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () async {
              final picked = await showWikiPicker(
                context,
                wikis: WikiProbeData.wikis,
                currentId: _wiki.id,
                projectName: WikiProbeData.project,
              );
              if (picked != null && mounted) setState(() => _wiki = picked);
            },
          ),
          IconButton(
            tooltip: 'Contents',
            icon: const Icon(Icons.toc),
            onPressed: () async {
              final picked = await showWikiContents(
                context,
                headings: _headings.contents,
                pageTitle: WikiPageNode.titleOf(_selected),
              );
              if (picked != null && mounted) _say('Heading: ${picked.text}');
            },
          ),
          IconButton(
            tooltip: 'Show source',
            icon: const Icon(Icons.code),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => WikiSourcePage(
                  title: WikiPageNode.titleOf(_selected),
                  source: WikiProbeData.markdown,
                ),
              ),
            ),
          ),
          const SizedBox(width: Spacing.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ContentColumn(
          child: ListView(
            padding: EdgeInsets.only(
              bottom: scrollEndPadding(context).bottom + Spacing.xl,
            ),
            children: [
              _label(theme, 'Title line: ${wikiSubtitle(_wiki)}'),
              const WikiCacheLine(offline: true),
              WikiRecentsStrip(
                recents: WikiProbeData.recents,
                onOpen: (r) => _say('Recent: ${r.title}'),
              ),
              for (final row in rows)
                WikiTreeTile(
                  row: row,
                  expanded: _expanded.contains(row.node.path),
                  selected: row.node.path == _selected,
                  onTap: () => setState(() => _selected = row.node.path),
                  onToggle: () => setState(() {
                    if (!_expanded.remove(row.node.path)) {
                      _expanded.add(row.node.path);
                    }
                  }),
                ),
              const Divider(),
              _label(theme, 'Reader: $_selected'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: WikiMarkdown(
                  content: WikiProbeData.markdown,
                  wiki: _wiki,
                  pagePath: _selected,
                  headings: _headings,
                  onOpenPage: (path, {anchor}) =>
                      _say('Page: $path${anchor == null ? '' : ' #$anchor'}'),
                  onOpenAnchor: (anchor) => _say('Anchor: #$anchor'),
                  onOpenAttachment: (path) => _say('Attachment: $path'),
                  onOpenMention: (kind, id) => _say('${kind.name} $id'),
                  onOpenOnWeb: () => _say('Open on web'),
                  onOpenQuery: (id) => _say('Query: $id'),
                  subPages: WikiProbeData.subPages,
                  names: WikiProbeData.names,
                ),
              ),
              const Divider(),
              _label(theme, 'Empty states'),
              WikiEmptyState(
                title: 'This project has no wiki',
                body:
                    'A project wiki is created on the web, and code wikis '
                    'are published from a repository folder.',
                actionLabel: 'Open on web',
                onAction: () => _say('Open on web'),
              ),
              const WikiNotice(
                message:
                    'This sign-in cannot read this project’s wiki. A project '
                    'or organization administrator can check that the Wiki '
                    'is enabled and that you have access to it.',
                icon: Icons.lock_outline,
                tone: WikiNoticeTone.quiet,
              ),
              const SizedBox(height: Spacing.sm),
              const WikiNotice(message: 'Something went wrong reading a page.'),
              if (_tapped != null)
                Padding(
                  padding: Spacing.page,
                  child: Text(
                    'Last tap: $_tapped',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Spacing.lg,
      Spacing.lg,
      Spacing.lg,
      Spacing.xs,
    ),
    child: Text(text, style: theme.textTheme.titleSmall),
  );
}

/// The canned tree, wikis, recents and markdown, kept beside the page so a
/// widget test can draw exactly what a simulator shows.
abstract final class WikiProbeData {
  static const project = 'Probe project';

  static const selectedPath = '/Boardhop/Links';

  static const projectWiki = Wiki(
    id: 'probe-wiki',
    name: 'Probe-project.wiki',
    type: WikiType.projectWiki,
    versions: ['wikiMaster'],
  );

  static const codeWiki = Wiki(
    id: 'probe-code-wiki',
    name: 'docs-wiki',
    type: WikiType.codeWiki,
    repositoryId: 'probe-repo',
    mappedPath: '/docs',
    versions: ['main', 'release'],
  );

  static const wikis = [projectWiki, codeWiki];

  static const recents = [
    WikiRecent(path: '/Boardhop/Links', title: 'Links'),
    WikiRecent(path: '/Boardhop/Constructs', title: 'Constructs'),
    WikiRecent(path: '/Boardhop', title: 'Boardhop'),
  ];

  static const names = {'11111111-2222-3333-4444-555555555555': 'Ada Example'};

  /// What `[[_TOSP_]]` draws on the probe page.
  static const subPages = [
    WikiPageNode(path: '/Boardhop/Links/Deep child', id: 242),
    WikiPageNode(path: '/Boardhop/Links/Re-Order', id: 244),
  ];

  /// The scratch wiki's own shape (research/20 §1): four levels deep, a
  /// non-conformant page that cannot be opened, and a page outside `.order`
  /// sorted last.
  static final tree = WikiPageNode(
    path: '/',
    isParentPage: true,
    subPages: [
      WikiPageNode(
        path: '/Boardhop',
        id: 236,
        isParentPage: true,
        subPages: [
          const WikiPageNode(path: '/Boardhop/Constructs', id: 238, order: 1),
          WikiPageNode(
            path: '/Boardhop/Links',
            id: 240,
            isParentPage: true,
            subPages: const [
              WikiPageNode(
                path: '/Boardhop/Links/Deep child',
                id: 242,
                isParentPage: true,
                subPages: [
                  WikiPageNode(
                    path: '/Boardhop/Links/Deep child/Level 4',
                    id: 246,
                  ),
                ],
              ),
              WikiPageNode(path: '/Boardhop/Links/Re-Order', id: 244, order: 1),
            ],
          ),
          const WikiPageNode(
            path: '/Boardhop/Pushed page',
            order: 2,
            isNonConformant: true,
          ),
          const WikiPageNode(
            path: '/Boardhop/Pushed tidy',
            id: 249,
            order: WikiPageNode.unordered,
          ),
        ],
      ),
    ],
  );

  /// Every construct the reader has to draw (W-C item 13): the front
  /// matter, both placeholders in each form, the table extremes, the HTML
  /// subset, the code block with its copy button and the attachment sizes.
  /// Invented text; nothing here is client data and nothing here touches
  /// Azure DevOps.
  static final markdown =
      '''
---
title: Probe page
tags:
- boardhop
- probe
owner: Nobody
---
[[_TOC_]]

# Probe page

A paragraph with a [relative link](/Boardhop/Constructs), a
[sibling](./Re-Order), a [parent](../Constructs), an [anchor](#second-heading)
and an [external link](https://example.com). References: #15545 and !8334, and
a mention @<11111111-2222-3333-4444-555555555555>. Ship it :rocket: and an
escaped \\#ff0000 stays text.

Inline HTML: <u>underlined</u>, <sup>up</sup>, <sub>down</sub>,
<del>struck</del>, <ins>inserted</ins>, <small>small</small>,
<font color="red">a colour tag keeps its text</font> and a
<span style="font-weight:bold">span</span> does too.

Inline math \$E = mc^2\$ next to a price of \$5 and \$7, which is not math.

![An attachment](/.attachments/probe.png)

![A sized attachment](/.attachments/probe.png =24x24)

## Child pages

[[_TOSP_]]

## Second heading

| Column | Another | Break |
|---|:---:|---:|
| a value | another value | one<br/>two |
| #15545 | `code` | [a link](/Boardhop) |

### A wide table

| One | Two | Three | Four | Five | Six | Seven |
|---|---|---|---|---|---|---|
| a rather long cell that has to wrap rather than stretch the column | b | c | d | e | f | g |
| 1 | 2 | 3 | 4 | 5 | 6 | 7 |

- [ ] a task
- [x] a done task

```dart
// A heading inside a fence is not a heading:
// # not a heading
void main() => print('hello');
final items = <int>[for (var i = 0; i < 10; i++) i];
```

### A long code block

```yaml
${List.generate(40, (i) => 'key$i: value number $i').join('\n')}
```

## Placeholders

::: mermaid
graph LR
  A[Phone] --> B[Relay]
:::

```mermaid
sequenceDiagram
  App->>ADO: GET pages
```

\$\$
\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}
\$\$

::: video
<iframe width="560" src="https://example.com/embed/probe"></iframe>
:::

::: query-table 11111111-2222-3333-4444-555555555555
:::

## HTML block

<div style="border:1px solid #ccc; padding:8px">
<b>bold html</b><br>
<img src="/.attachments/probe.png" width="32" alt="html img">
</div>

<details>
<summary>Collapsed section</summary>
Hidden text inside details.
</details>

### Third heading

> A quote.

#### Fourth heading, not in the contents sheet

Text after it. A footnote[^1].

[^1]: The footnote's text.
''';
}
