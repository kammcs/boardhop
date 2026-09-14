import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'attachment_links.dart';

/// What a Markdown body needs to draw and open the attachments inside it.
///
/// Deliberately a pair of plain values rather than the form's
/// `AttachmentSource`: that type lives beside the picker, and a widget in
/// `features/shared` must not drag `image_picker` and `file_picker` into its
/// import graph. `inlineAttachmentsOf` in `inline_attachment_source.dart`
/// adapts one to the other for the pages, which already have it.
@immutable
class InlineAttachments {
  const InlineAttachments({this.headers = const {}, this.onOpen});

  /// `Authorization` for the image fetch. Every attachment URL is
  /// authenticated, and an unauthenticated GET does not fail: it answers
  /// HTTP 203 with a sign-in page, which decodes to nothing (spike w32 §3).
  final Map<String, String> headers;

  /// Opens one attachment — an image full screen, anything else through the
  /// share sheet (decision T9). Answers the message to show when it could
  /// not be opened, and null when it went. Null leaves images and links
  /// drawn but inert.
  final Future<String?> Function(BuildContext context, String url, String name)?
  onOpen;
}

/// How tall an inline image is allowed to be (decision T9). A comment is a
/// conversation, not a gallery: a phone photo at its own aspect ratio would
/// push the next comment off the screen.
const double inlineImageMaxHeight = 320;

/// One `![alt](url)` inside a Markdown body.
///
/// Three things the package's default image builder does not do, all of
/// which showed up as real defects (research/17 §1, bug (b)): an Azure
/// DevOps attachment is fetched with the bearer token through the same
/// managed cache the HTML path uses, a failed fetch draws a visible glyph
/// instead of `kDefaultImageErrorWidgetBuilder`'s empty `SizedBox`, and the
/// image is capped and tappable like every other image in the app.
///
/// The `#WxH` fragment the default builder honours cannot be honoured here:
/// `flutter_markdown_plus` splits it off the source and hands the builder a
/// `Uri` without it (`builder.dart` `_buildImage`), so the height cap is the
/// only sizing there is.
class InlineMarkdownImage extends StatelessWidget {
  const InlineMarkdownImage({
    super.key,
    required this.url,
    this.alt,
    this.attachments,
  });

  final String url;
  final String? alt;
  final InlineAttachments? attachments;

  /// The alt text, or the file name when the author wrote `![](…)` — the
  /// broken-image row has to say *which* image is missing.
  String get _label {
    final text = alt?.trim();
    if (text != null && text.isNotEmpty) return text;
    return attachmentFileName(url);
  }

  Widget _broken(BuildContext context, Object error, StackTrace? stack) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.broken_image_outlined,
          size: 20,
          color: theme.colorScheme.error,
        ),
        const SizedBox(width: Spacing.xs),
        Flexible(
          child: Text(
            _label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final attachment = isAttachmentUrl(url);
    final headers = attachments?.headers ?? const <String, String>{};
    final image = attachment
        ? Image(
            image: CachedNetworkImageProvider(url, headers: headers),
            fit: BoxFit.scaleDown,
            semanticLabel: _label,
            errorBuilder: _broken,
          )
        : Image.network(
            url,
            fit: BoxFit.scaleDown,
            semanticLabel: _label,
            errorBuilder: _broken,
          );
    final capped = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: inlineImageMaxHeight),
      child: image,
    );
    final open = attachments?.onOpen;
    if (!attachment || open == null) return capped;
    // `flutter_markdown_plus` already wraps a *linked* image in a
    // `GestureDetector` of its own; this one is the inner child, so the tap
    // lands here and the lightbox wins over whatever the link pointed at.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openInlineAttachment(context, url, attachments),
      child: capped,
    );
  }
}

/// Opens an attachment and surfaces the failure where the tap happened.
///
/// A snackbar rather than an inline error because the caller is a run of
/// text inside a comment: there is nowhere to put a row, and nothing was
/// lost — the tap simply did not open (DESIGN §7).
Future<void> openInlineAttachment(
  BuildContext context,
  String url,
  InlineAttachments? attachments,
) async {
  final open = attachments?.onOpen;
  if (open == null) return;
  final message = await open(context, url, attachmentFileName(url));
  if (message == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
