import 'package:flutter/material.dart';

import '../../../data/models/search.dart';

/// The one matched line a search hit carries, with the matched words in
/// bold (research/15 §4: `<highlighthit>` becomes bold, the rest is plain).
///
/// The spans are parsed in the data layer ([SearchHighlight]); all this
/// widget does is give the hit runs more weight and the full text colour,
/// leaving the rest in the quieter secondary colour so the match stands out
/// without any colour of its own — the theme's body style throughout, per
/// DESIGN.md.
class SearchHighlightText extends StatelessWidget {
  const SearchHighlightText({
    super.key,
    required this.highlight,
    this.maxLines = 2,
    this.style,
  });

  final SearchHighlight highlight;
  final int maxLines;

  /// The style the runs share; the quiet secondary body text by default,
  /// but a row that highlights its own title passes the title's style.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base =
        style ??
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant) ??
        const TextStyle();
    return Text.rich(
      TextSpan(
        children: [
          for (final span in highlight.spans)
            TextSpan(
              text: span.text,
              style: span.isHit
                  ? base.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    )
                  : null,
            ),
        ],
      ),
      style: base,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
