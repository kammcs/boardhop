import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

/// Renders a work item long-text field or a comment body. HTML goes through
/// `flutter_widget_from_html_core` with attachment images fetched with the
/// caller's bearer token; Markdown goes through `flutter_markdown_plus`.
class RichTextView extends StatelessWidget {
  const RichTextView({
    super.key,
    required this.content,
    this.format = 'html',
    this.headers = const {},
  });

  final String content;

  /// `html` or `markdown` (from `multilineFieldsFormat`).
  final String format;

  /// `Authorization` header for `_apis/wit/attachments` images.
  final Map<String, String> headers;

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
      return MarkdownBody(data: content, selectable: true);
    }
    return HtmlWidget(
      content,
      textStyle: theme.textTheme.bodyMedium,
      factoryBuilder: () => _AuthedWidgetFactory(headers),
      onErrorBuilder: (context, element, error) => Text(
        'Could not render part of this field.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

class _AuthedWidgetFactory extends WidgetFactory {
  _AuthedWidgetFactory(this.headers);

  final Map<String, String> headers;

  @override
  ImageProvider? imageProviderFromNetwork(String url) =>
      CachedNetworkImageProvider(url, headers: headers);
}
