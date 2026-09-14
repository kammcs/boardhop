import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../../core/text/mention.dart';
import '../../shared/mention/mention_markdown.dart';
import '../../shared/mention/mention_style.dart';

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
      );
    }
    return HtmlWidget(
      content,
      textStyle: theme.textTheme.bodyMedium,
      factoryBuilder: () => _AuthedWidgetFactory(headers, onOpenMention),
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
  _AuthedWidgetFactory(this.headers, this.onOpenMention);

  final Map<String, String> headers;
  final void Function(MentionKind kind, String id)? onOpenMention;

  @override
  ImageProvider? imageProviderFromNetwork(String url) =>
      CachedNetworkImageProvider(url, headers: headers);

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
