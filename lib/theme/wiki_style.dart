import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'boardhop_colors.dart';
import 'boardhop_theme.dart';
import 'tokens.dart';

/// The wiki reader's Markdown style sheet (research/20 §4.2, W-C item 1).
///
/// It lives in `lib/theme/` rather than beside the reader because it is the
/// only place a wiki page's colours, type ramp and spacing are decided, and
/// DESIGN §1 keeps that in one place. Nothing here reads a hex literal or a
/// `Colors.*`: every value comes from the scheme, [BoardhopColors] or a
/// token.
///
/// Three things it fixes that the package's `fromTheme` gets wrong for us:
///
/// * links are `Colors.blue` in the stock sheet, which DESIGN §3 forbids —
///   they wear [BoardhopColors.mention] and an underline, so a link is not
///   signalled by colour alone (§8);
/// * `h4`, `h5` and `h6` are all `bodyLarge`, so a four-level page reads as
///   one level; and
/// * the checkbox of a task list takes `theme.primaryColor`, which in the
///   neutral slate dark scheme is all but the surface it sits on — the
///   `[x]` and `[ ]` glyphs were invisible on `/Boardhop/Constructs`.
MarkdownStyleSheet wikiStyleSheet(BuildContext context) {
  final theme = Theme.of(context);
  final text = theme.textTheme;
  final scheme = theme.colorScheme;
  final colors = context.boardhopColors;
  final code = BoardhopTheme.codeStyle(context);

  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    a: TextStyle(
      color: colors.mention,
      decoration: TextDecoration.underline,
      decorationColor: colors.mention,
    ),
    p: text.bodyMedium,
    pPadding: const EdgeInsets.only(bottom: Spacing.sm),
    h1: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    h1Padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.xs),
    h2: text.titleLarge,
    h2Padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.xs),
    h3: text.titleMedium,
    h3Padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.xs),
    h4: text.titleSmall,
    h4Padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.xs),
    h5: text.labelLarge,
    h5Padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.xs),
    h6: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
    h6Padding: const EdgeInsets.only(top: Spacing.sm, bottom: Spacing.xs),
    code: code.copyWith(
      backgroundColor: colors.codeBackground,
      fontSize: (text.bodyMedium?.fontSize ?? 14) * 0.9,
    ),
    codeblockPadding: const EdgeInsets.all(Spacing.md),
    codeblockDecoration: BoxDecoration(
      color: colors.codeBackground,
      borderRadius: Radii.card,
      border: Border.all(color: scheme.outlineVariant),
    ),
    blockquote: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    blockquotePadding: const EdgeInsets.fromLTRB(
      Spacing.md,
      Spacing.sm,
      Spacing.md,
      Spacing.sm,
    ),
    blockquoteDecoration: BoxDecoration(
      color: scheme.surfaceContainerLow,
      borderRadius: Radii.chip,
      border: Border(left: BorderSide(color: scheme.outline, width: 3)),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: scheme.outlineVariant)),
    ),
    // The bullet and the checkbox of a list. `fontSize` is what the package
    // sizes the checkbox icon by, so it has to be a real size and not the
    // inherited null.
    listBullet: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    listIndent: Spacing.xl,
    // The package sizes the task-list **icon** from this `fontSize`, and an
    // icon is not text: it does not follow the text scaler on its own, so at
    // xxxL the checkboxes stayed tiny beside their labels (iPhone 17,
    // W-C walkthrough). Scaling it here is what keeps the pair legible.
    checkbox: text.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontSize: MediaQuery.textScalerOf(context)
          .scale(text.bodyMedium?.fontSize ?? 14),
    ),
    blockSpacing: Spacing.sm,
    // A stray `table` that did not reach the wiki table builder (a nested
    // one, say) still has to be legible rather than a blue-bordered grid.
    tableHead: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
    tableBody: text.bodyMedium,
    tableHeadAlign: TextAlign.left,
    tableBorder: TableBorder.all(color: scheme.outlineVariant),
    tableCellsPadding: const EdgeInsets.symmetric(
      horizontal: Spacing.md,
      vertical: Spacing.sm,
    ),
    tableHeadCellsDecoration: BoxDecoration(color: scheme.surfaceContainer),
  );
}

/// The background a find-in-page hit is drawn on (W-C item 12).
///
/// A tint rather than a fill: the hit keeps the body's own text colour, so
/// it reads the same at xxxL and in both themes, and the run underneath is
/// still the paragraph's.
Color wikiMarkBackground(BuildContext context) =>
    Theme.of(context).colorScheme.tertiaryContainer;
