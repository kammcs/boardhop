import 'package:flutter/material.dart';

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
///   glyph carries the meaning, the tint only makes the run findable.
TextStyle mentionTextStyle(BuildContext context) => TextStyle(
  color: Theme.of(context).colorScheme.primary,
  fontWeight: FontWeight.w500,
);
