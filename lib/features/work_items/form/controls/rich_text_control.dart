import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html_editor_enhanced/html_editor.dart';

import '../../../../data/models/work_item_form.dart';
import '../../../../theme/theme.dart';
import '../../widgets/html_field_editor.dart';
import '../../widgets/rich_text_view.dart';
import '../work_item_form_state.dart';
import 'form_field_slot.dart';

/// An `html` field (`HtmlFieldControl`): a card with the rendered value and
/// an edit affordance, opening the shared rich editor full screen on a
/// phone and as a large dialog from medium up (research/11 §4.3).
///
/// The content is never converted between HTML and Markdown (research/00
/// §0): the editor writes back exactly what the user wrote, and the format
/// op rides along on create when Markdown was chosen.
class RichTextControl extends StatelessWidget {
  const RichTextControl({
    super.key,
    required this.state,
    required this.field,
    required this.label,
    this.enabled = true,
    this.onFormatChosen,
  });

  final WorkItemFormState state;
  final FieldSpec field;
  final String label;
  final bool enabled;

  /// Remembers the choice per project (`FormPrefs`).
  final void Function(String reference, String format)? onFormatChosen;

  /// "Add description…" on the description, and the same sentence with the
  /// field's own name elsewhere ("Add repro steps…").
  String get placeholder {
    final name = (label.isEmpty ? field.name : label).toLowerCase();
    return 'Add $name…';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reference = field.referenceName;
    final content = (state.value(reference) as String? ?? '').trim();
    final format = state.formatOf(reference);
    final error = state.errorFor(reference);
    return FormFieldSlot(
      label: label,
      required: field.alwaysRequired,
      helpText: field.helpText,
      error: error,
      child: InkWell(
        onTap: enabled ? () => _edit(context) : null,
        borderRadius: Radii.card,
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(
            enabled: enabled,
            errorText: error == null ? null : '',
            errorStyle: const TextStyle(height: 0, fontSize: 0),
            contentPadding: const EdgeInsets.all(Spacing.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ClipRect(
                    child: content.isEmpty
                        ? Text(
                            placeholder,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        // `heightFactor: 1` keeps the card as tall as the
                        // content; a plain Align would fill the 220 cap.
                        : Align(
                            alignment: Alignment.topLeft,
                            heightFactor: 1,
                            child: RichTextView(
                              content: content,
                              format: format,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Icon(
                Icons.edit_outlined,
                size: 20,
                color: enabled ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final reference = field.referenceName;
    final result = await openRichTextEditor(
      context,
      title: label.isEmpty ? field.name : label,
      content: state.value(reference) as String? ?? '',
      format: state.formatOf(reference),
      allowFormatChoice: state.canChooseFormat(reference),
    );
    if (result == null) return;
    state.setRichValue(reference, result.content, format: result.format);
    onFormatChosen?.call(reference, result.format);
  }
}

/// What the editor answers with.
@immutable
class RichTextResult {
  const RichTextResult({required this.content, required this.format});

  final String content;

  /// `html` or `markdown`.
  final String format;
}

/// Opens the editor: full screen on a phone, a large dialog from medium up
/// (research/11 §4.5).
Future<RichTextResult?> openRichTextEditor(
  BuildContext context, {
  required String title,
  required String content,
  String format = 'html',
  bool allowFormatChoice = false,
}) {
  final editor = RichTextEditor(
    title: title,
    content: content,
    format: format,
    allowFormatChoice: allowFormatChoice,
  );
  if (context.breakpoint.isCompact) {
    return Navigator.of(context).push<RichTextResult>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => editor),
    );
  }
  return showDialog<RichTextResult>(
    context: context,
    builder: (context) {
      final size = MediaQuery.sizeOf(context);
      return Dialog(
        insetPadding: const EdgeInsets.all(Spacing.xl),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 900,
            maxHeight: size.height * 0.9,
          ),
          child: editor,
        ),
      );
    },
  );
}

/// The editor itself: the shared `html_editor_enhanced` host, or a
/// monospace Markdown box with a preview toggle when Markdown was chosen.
class RichTextEditor extends StatefulWidget {
  const RichTextEditor({
    super.key,
    required this.title,
    required this.content,
    this.format = 'html',
    this.allowFormatChoice = false,
  });

  final String title;
  final String content;
  final String format;

  /// The Markdown choice is only offered on a new item's description
  /// (spike w01); an existing item follows its own format map.
  final bool allowFormatChoice;

  @override
  State<RichTextEditor> createState() => _RichTextEditorState();
}

class _RichTextEditorState extends State<RichTextEditor> {
  final _html = HtmlEditorController();
  late final TextEditingController _markdown = TextEditingController(
    text: widget.format == 'markdown' ? widget.content : '',
  );
  late String _format = widget.format;

  /// What the WebView is seeded with. Cleared when the user switches format
  /// so switching back does not bring the old content along.
  late String _initialHtml = widget.format == 'markdown' ? '' : widget.content;
  bool _preview = false;
  String? _error;

  @override
  void dispose() {
    _markdown.dispose();
    super.dispose();
  }

  bool get _isMarkdown => _format == 'markdown';

  Future<void> _done() async {
    if (_isMarkdown) {
      Navigator.of(context)
          .pop(RichTextResult(content: _markdown.text, format: 'markdown'));
      return;
    }
    String html;
    try {
      html = await _html.getText();
    } on MissingPluginException {
      setState(() => _error = 'The editor is not ready; try again.');
      return;
    }
    // Summernote answers with an empty paragraph for an empty document.
    if (html.trim() == '<p><br></p>' || html.trim() == '<br>') html = '';
    if (mounted) {
      Navigator.of(context).pop(RichTextResult(content: html, format: 'html'));
    }
  }

  /// Boardhop never converts between the two formats (research/00 §0), so
  /// switching with content asks before dropping it.
  Future<void> _setFormat(String next) async {
    if (next == _format) return;
    final hasContent = _isMarkdown
        ? _markdown.text.trim().isNotEmpty
        : (await _currentHtml()).trim().isNotEmpty;
    if (!mounted) return;
    if (hasContent) {
      final drop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: Text(
            next == 'markdown' ? 'Switch to Markdown?' : 'Switch to rich text?',
          ),
          content: const Text(
            'What you have written is cleared: Boardhop never converts '
            'between HTML and Markdown.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (drop != true || !mounted) return;
    }
    _markdown.clear();
    try {
      _html.clear();
    } on MissingPluginException {
      // The WebView was never built; nothing to clear.
    }
    setState(() {
      _format = next;
      _initialHtml = '';
      _preview = false;
    });
  }

  Future<String> _currentHtml() async {
    try {
      return await _html.getText();
    } on MissingPluginException {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
            child: FilledButton(onPressed: _done, child: const Text('Done')),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The WebView keeps a fixed height (`adjustHeightForKeyboard`
            // is off, spike F3), so it stays short enough to scroll clear
            // of the keyboard inside the list.
            final chrome = widget.allowFormatChoice ? 64.0 : 0.0;
            final height = (constraints.maxHeight - chrome - Spacing.xl).clamp(
              240.0,
              520.0,
            );
            return ListView(
              padding: const EdgeInsets.only(bottom: Spacing.xxl),
              children: [
                if (_error != null)
                  ListTile(
                    key: const ValueKey('error'),
                    leading: Icon(Icons.error_outline, color: scheme.error),
                    title: Text(_error!),
                  )
                else
                  const SizedBox.shrink(key: ValueKey('error')),
                if (widget.allowFormatChoice)
                  Padding(
                    key: const ValueKey('format'),
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.lg,
                      Spacing.sm,
                      Spacing.lg,
                      Spacing.md,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: 'html',
                                label: Text('Rich text'),
                              ),
                              ButtonSegment(
                                value: 'markdown',
                                label: Text('Markdown'),
                              ),
                            ],
                            selected: {_format},
                            onSelectionChanged: (picked) =>
                                _setFormat(picked.first),
                          ),
                        ),
                        if (_isMarkdown) ...[
                          const SizedBox(width: Spacing.sm),
                          IconButton(
                            tooltip: _preview ? 'Write' : 'Preview',
                            isSelected: _preview,
                            icon: const Icon(Icons.visibility_outlined),
                            selectedIcon: const Icon(Icons.edit_outlined),
                            onPressed: () =>
                                setState(() => _preview = !_preview),
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  const SizedBox.shrink(key: ValueKey('format')),
                if (_isMarkdown)
                  Padding(
                    key: const ValueKey('markdown'),
                    padding: Spacing.pageHorizontal,
                    child: _preview
                        ? Container(
                            constraints: BoxConstraints(minHeight: height),
                            alignment: Alignment.topLeft,
                            child: RichTextView(
                              content: _markdown.text,
                              format: 'markdown',
                            ),
                          )
                        : TextField(
                            controller: _markdown,
                            autofocus: true,
                            minLines: 10,
                            maxLines: 40,
                            style: BoardhopTheme.codeStyle(context),
                            keyboardType: TextInputType.multiline,
                            decoration: const InputDecoration(
                              hintText: 'Markdown',
                              alignLabelWithHint: true,
                            ),
                          ),
                  )
                else
                  // Stable slot for the WebView (spike F3): never insert a
                  // widget above it after the first build.
                  Padding(
                    key: const ValueKey('html'),
                    padding: Spacing.pageHorizontal,
                    child: HtmlFieldEditor(
                      controller: _html,
                      html: _initialHtml,
                      hint: widget.title,
                      height: height,
                      onError: (message) {
                        if (mounted) setState(() => _error = message);
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
