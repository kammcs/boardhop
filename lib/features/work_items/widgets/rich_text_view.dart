import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../../core/text/mention.dart';
import '../../shared/attachments/attachment_links.dart';
import '../../shared/attachments/inline_attachments.dart';
import '../../shared/mention/mention_markdown.dart';
import '../../shared/mention/mention_style.dart';
import '../../wiki/wiki_link_open.dart';

/// Renders a work item long-text field or a comment body. HTML goes through
/// `flutter_widget_from_html_core` with attachment images fetched with the
/// caller's bearer token; Markdown goes through `flutter_markdown_plus`.
///
/// Mentions are drawn rather than left as the raw markup Azure DevOps sends
/// (research/16 §4.4): a person is a styled, untappable `@Name` run and a
/// `#123` / `!456` reference is a styled run that calls [onOpenMention].
/// Routing stays with the page, which is the only thing that knows the
/// account and the organization.
class RichTextView extends StatelessWidget {
  const RichTextView({
    super.key,
    required this.content,
    this.format = 'html',
    this.headers = const {},
    this.mentionNames = const {},
    this.onOpenMention,
    this.attachments,
    this.attachmentBase,
  });

  final String content;

  /// `html` or `markdown` (from `multilineFieldsFormat`).
  final String format;

  /// `Authorization` header for `_apis/wit/attachments` images.
  final Map<String, String> headers;

  /// Lower-cased identity GUID → display name, for the Markdown form only:
  /// the server's HTML already carries the name inside the anchor.
  final Map<String, String> mentionNames;

  /// Tapping a work item or pull request reference.
  final void Function(MentionKind kind, String id)? onOpenMention;

  /// Images and file links inside a Markdown body: the bearer token and the
  /// way to open one. Falls back to [headers] alone, so a caller that only
  /// has the token still gets authed images (research/17 §4).
  final InlineAttachments? attachments;

  /// `…/_apis/wit/attachments` for the project this content belongs to,
  /// which is what puts an image back together when the service sent the
  /// sentinel form (see [normalizeAttachmentHtml]). Null leaves the src
  /// alone rather than guessing a project.
  final String? attachmentBase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (content.trim().isEmpty) {
      return Text(
        'Nothing here yet.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    if (format == 'markdown') {
      return MentionMarkdown(
        data: content,
        names: mentionNames,
        onOpen: onOpenMention,
        attachments:
            attachments ??
            (headers.isEmpty ? null : InlineAttachments(headers: headers)),
      );
    }
    return HtmlWidget(
      // The comments API rewrites an image src to `\x06/{guid}?fileName=…`
      // inside the rendered form of an html-format comment (spike w32 §3).
      // It has to be repaired here rather than in the image hook below,
      // because the HTML renderer resolves a relative src against its own
      // base URL first and drops the image when there is none — the hook is
      // never reached.
      normalizeAttachmentHtml(content, base: attachmentBase),
      textStyle: theme.textTheme.bodyMedium,
      factoryBuilder: () => _AuthedWidgetFactory(
        headers,
        onOpenMention,
        attachmentBase,
        attachments,
        context,
      ),
      // An image inside a work item comment is an `<img>` in the service's
      // rendered HTML, not Markdown, so the Markdown path's own tap does
      // not reach it: without this an inline image is the one image in the
      // app that does not open (decision T9).
      onTapImage: (image) {
        final url = image.sources.isEmpty ? null : image.sources.first.url;
        if (url == null || attachments?.onOpen == null) return;
        final full = normalizeAttachmentUrl(url, base: attachmentBase);
        if (!isAttachmentUrl(full)) return;
        openInlineAttachment(context, full, attachments);
      },
      onErrorBuilder: (context, element, error) => Text(
        'Could not render part of this field.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

/// One `data-vss-mention` anchor, read off the server's rendered HTML.
///
/// `version:2.0` is a person and carries the identity GUID; `version:1.0` is
/// a work item or pull request and carries its id, the kind coming from the
/// anchor's class or its href (spike w30 §4).
@immutable
class MentionAnchor {
  const MentionAnchor(this.kind, this.id);

  final MentionKind kind;
  final String id;

  static const attribute = 'data-vss-mention';

  /// Null when the element is not a mention anchor.
  ///
  /// Takes the tag and the attribute map rather than the `html` package's
  /// `Element` so this file needs no dependency the app does not already
  /// declare, and so the rule is unit-testable without parsing anything.
  static MentionAnchor? read({
    required String? tag,
    required Map<Object, String> attributes,
  }) {
    if (tag != 'a') return null;
    final value = attributes[attribute];
    if (value == null) return null;
    final at = value.indexOf(',');
    if (at < 0) return null;
    final version = value.substring(0, at).trim();
    final id = value.substring(at + 1).trim();
    if (id.isEmpty) return null;
    if (version == 'version:2.0') {
      return MentionAnchor(MentionKind.person, Mentions.identityId(id));
    }
    if (version != 'version:1.0') return null;
    final classes = attributes['class'] ?? '';
    final href = attributes['href'] ?? '';
    final workItem =
        classes.contains('mention-widget-workitem') ||
        href.contains('_workitems/');
    return MentionAnchor(
      workItem ? MentionKind.workItem : MentionKind.pullRequest,
      id,
    );
  }

  /// Only an artifact opens something: there is no person page (M9).
  bool get tappable => kind != MentionKind.person;
}

class _AuthedWidgetFactory extends WidgetFactory {
  _AuthedWidgetFactory(
    this.headers,
    this.onOpenMention,
    this.attachmentBase,
    this.attachments,
    this.host,
  );

  final Map<String, String> headers;
  final void Function(MentionKind kind, String id)? onOpenMention;

  /// See [RichTextView.attachmentBase]. Belt and braces: the body is
  /// normalised before it is parsed, so a sentinel should never reach here.
  final String? attachmentBase;

  /// How a file link inside this body is opened, and the element it is
  /// opened from — the factory has no context of its own and the viewer
  /// needs a navigator.
  final InlineAttachments? attachments;
  final BuildContext host;

  /// T9's 320 pt cap, on the HTML path too.
  ///
  /// A work item comment is rendered HTML, not Markdown, so the Markdown
  /// builder's [inlineImageMaxHeight] never reached it: a portrait photo
  /// posted from a phone filled the whole screen on the iPhone and more
  /// than a screen on the iPad (T-C). Capping the built widget rather than
  /// the `Image` keeps the package's own `AspectRatio` and tap detector
  /// inside the box, and only an **attachment** src is touched — an icon or
  /// a badge in a description keeps whatever size the author gave it.
  @override
  Widget? buildImage(BuildTree tree, ImageMetadata data) {
    final built = super.buildImage(tree, data);
    final src = data.sources.isEmpty ? null : data.sources.first;
    if (built == null || src == null) return built;
    if (!isAttachmentUrl(
      normalizeAttachmentUrl(src.url, base: attachmentBase),
    )) {
      return built;
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: inlineImageMaxHeight),
      child: built,
    );
  }

  @override
  ImageProvider? imageProviderFromNetwork(String url) =>
      CachedNetworkImageProvider(
        normalizeAttachmentUrl(url, base: attachmentBase),
        headers: headers,
      );

  /// A file attached to a work item **comment** is an ordinary `<a href>`
  /// in the service's rendered HTML (`<a rel=nofollow>`, research/17 §1), so
  /// without this it would open in a browser, which cannot authenticate the
  /// URL and lands on a sign-in page. It goes through the same opener the
  /// Markdown side and the attachment rows use instead: the viewer for an
  /// image, the share sheet for anything else (T9).
  ///
  /// Every other link is left exactly as it was.
  @override
  Future<bool> onTapUrl(String url) async {
    final full = normalizeAttachmentUrl(url, base: attachmentBase);
    if (attachments?.onOpen != null && isAttachmentUrl(full)) {
      if (!host.mounted) return false;
      await openInlineAttachment(host, full, attachments);
      return true;
    }
    // A wiki URL pasted into a description or a comment opens the in-app
    // reader (research/20 K5); everything else keeps going to the browser.
    if (host.mounted && openWikiLink(host, url)) return true;
    return super.onTapUrl(url);
  }

  /// Mention anchors never become live links.
  ///
  /// The server writes `<a href="#" …>` for a person and a `dev.azure.com`
  /// path for a reference; both would otherwise open in a browser. `super`
  /// is deliberately not called for them, because that is what registers the
  /// `a[href]` op — the tint, the underline and the tap. What replaces it is
  /// the mention run's own style and, for a reference, a recogniser that
  /// calls back into the page.
  @override
  void parse(BuildTree tree) {
    final mention = MentionAnchor.read(
      tag: tree.element.localName,
      attributes: tree.element.attributes,
    );
    if (mention == null) {
      super.parse(tree);
      return;
    }
    tree.inherit<BuildContext?>(_mentionStyle);
    final onOpen = onOpenMention;
    if (mention.tappable && onOpen != null) {
      tree.register(
        BuildOp(
          debugLabel: 'mention[$attributeLabel]',
          alwaysRenderBlock: false,
          onParsed: (parsed) {
            final recognizer = buildGestureRecognizer(
              parsed,
              onTap: () => onOpen(mention.kind, mention.id),
            );
            if (recognizer == null) return parsed;
            return parsed..inherit<GestureRecognizer>(_recognizer, recognizer);
          },
        ),
      );
    }
  }

  static const attributeLabel = MentionAnchor.attribute;

  static InheritedProperties _mentionStyle(
    InheritedProperties resolving,
    BuildContext? context,
  ) => context == null
      ? resolving
      : resolving.copyWith(style: mentionTextStyle(context));

  static InheritedProperties _recognizer(
    InheritedProperties resolving,
    GestureRecognizer value,
  ) => resolving.copyWith<GestureRecognizer>(value: value);
}
