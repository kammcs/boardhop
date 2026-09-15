import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/theme.dart';

/// K9's *Show source*: the page's raw markdown, monospaced and selectable.
///
/// The reader is read-only, so this is the only place the wiki's own text is
/// visible — it is what a placeholder card's Show source will open too
/// (K3), which is why it takes a plain string rather than a page.
class WikiSourcePage extends StatelessWidget {
  const WikiSourcePage({super.key, required this.title, required this.source});

  final String title;
  final String source;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: source));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Source copied')));
              }
            },
          ),
          const SizedBox(width: Spacing.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        // Markdown is written in columns, so the source pans sideways
        // rather than wrapping a table row into nonsense (DESIGN §7).
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.md,
            Spacing.lg,
            scrollEndPadding(context).bottom + Spacing.xl,
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              source,
              style: BoardhopTheme.codeStyle(context),
            ),
          ),
        ),
      ),
    );
  }
}
