import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

/// The one style a mention wears, wherever it is drawn (research/16 M6).
///
/// Used by [MentionController.buildTextSpan] for a picked token in a composer
/// and by every read surface — the restyled `data-vss-mention` anchor in
/// `RichTextView`, and the `@<guid>` / `#123` / `!456` runs of a Markdown
/// comment — so a mention looks the same before and after it is posted.
///
/// Colour and weight only, deliberately:
///
/// * a `fontSize` here crops the field a [TextEditingController] draws
///   (flutter#178110), so the run keeps the size of the text around it;
/// * colour alone is never the signal (DESIGN §3) — the `@`, `#` or `!`
///   glyph carries the meaning — but Kelly wants a mention very obvious in
///   both themes (2026-09-14), so the run wears `BoardhopColors.mention`
///   (the link blue, not the slate primary) at semibold.
TextStyle mentionTextStyle(BuildContext context) => TextStyle(
  color: context.boardhopColors.mention,
  fontWeight: FontWeight.w600,
);
