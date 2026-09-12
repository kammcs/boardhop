import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html_editor_enhanced/html_editor.dart';

/// The one `html_editor_enhanced` host in the app: the toolbar, the options
/// and the content-injection dance settled by spike F3, shared by the work
/// item edit page and the create form's rich text control.
///
/// The plugin's `setText` mangles backslashes and newlines, so the HTML is
/// injected through the WebView as a JSON string literal once the editor
/// reports ready ([html] may arrive later, when the item's read comes back).
/// The widget keeps its editor in a `late final`, so a rebuild never
/// recreates the WebView; callers must still keep its slot in the list
/// stable (never insert a widget above it after the first build).
class HtmlFieldEditor extends StatefulWidget {
  const HtmlFieldEditor({
    super.key,
    required this.controller,
    this.html,
    this.hint = 'Description',
    this.height = 380,
    this.onError,
    this.onInsertImage,
  });

  /// Owned by the caller, which reads the result with `getText()`.
  final HtmlEditorController controller;

  /// The content to load; null until the caller has it.
  final String? html;

  final String hint;
  final double height;

  /// Raised when the WebView never accepted the content.
  final ValueChanged<String>? onError;

  /// Phase 5: "Insert image" in the toolbar. Runs the attachment picker and
  /// the upload, and answers with the attachment URL to embed (or null when
  /// the user backed out or the upload failed).
  final Future<String?> Function()? onInsertImage;

  /// The toolbar both callers show. Summernote's own picture button is off
  /// (it would embed base64 or ask for a URL); the image goes in through
  /// [onInsertImage] as a custom toolbar button instead.
  static HtmlToolbarOptions toolbarOptions({List<Widget> custom = const []}) =>
      HtmlToolbarOptions(
        toolbarPosition: ToolbarPosition.aboveEditor,
        toolbarType: ToolbarType.nativeScrollable,
        customToolbarButtons: custom,
        defaultToolbarButtons: const [
          StyleButtons(),
          FontButtons(clearAll: false, subscript: false, superscript: false),
          ListButtons(listStyles: false),
          ParagraphButtons(
            textDirection: false,
            lineHeight: false,
            caseConverter: false,
          ),
          InsertButtons(
            picture: false,
            audio: false,
            video: false,
            otherFile: false,
            table: true,
            hr: true,
          ),
        ],
      );

  @override
  State<HtmlFieldEditor> createState() => _HtmlFieldEditorState();
}

class _HtmlFieldEditorState extends State<HtmlFieldEditor> {
  late final Widget _editor = HtmlEditor(
    controller: widget.controller,
    htmlEditorOptions: HtmlEditorOptions(
      hint: widget.hint,
      adjustHeightForKeyboard: false,
    ),
    htmlToolbarOptions: HtmlFieldEditor.toolbarOptions(
      custom: [
        if (widget.onInsertImage != null)
          IconButton(
            key: const ValueKey('insert-image'),
            tooltip: 'Insert image',
            icon: const Icon(Icons.image_outlined),
            onPressed: _insertImage,
          ),
      ],
    ),
    otherOptions: OtherOptions(height: widget.height),
    callbacks: Callbacks(onInit: () => _ready = true),
  );

  bool _ready = false;
  bool _pushed = false;

  @override
  void initState() {
    super.initState();
    if (widget.html != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => pushWhenReady());
    }
  }

  @override
  void didUpdateWidget(HtmlFieldEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_pushed && widget.html != null && widget.html != oldWidget.html) {
      pushWhenReady();
    }
  }

  /// Waits for the WebView's `onInit`, then injects the HTML. Retries
  /// briefly: the plugin channel can lag `onInit` by a few frames.
  Future<void> pushWhenReady() async {
    if (_pushed) return;
    for (var i = 0; i < 40 && !_ready; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted || _pushed) return;
    final html = widget.html ?? '';
    if (html.isEmpty) {
      _pushed = true;
      return;
    }
    for (var attempt = 0; attempt < 10 && mounted; attempt++) {
      final dynamic web = widget.controller.editorController;
      try {
        if (web == null) {
          widget.controller.setText(html);
        } else {
          await web.evaluateJavascript(
            source:
                "(function(){ try { \$('#summernote-2').summernote('code', ${jsonEncode(html)}); "
                "return 'ok'; } catch (e) { return 'js error: ' + e; } })()",
          );
        }
        _pushed = true;
        return;
      } on MissingPluginException {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    if (mounted) widget.onError?.call('The editor did not load; try again.');
  }

  /// Uploads an image and pastes it at the caret. The upload also becomes
  /// an `AttachedFile` relation on the item (the callback's job), so an
  /// embedded image is never an orphaned attachment.
  Future<void> _insertImage() async {
    final pick = widget.onInsertImage;
    if (pick == null) return;
    final url = await pick();
    if (url == null || url.isEmpty || !mounted) return;
    final inserted = await insertHtmlAtCaret(
      widget.controller,
      '<img src="$url">',
    );
    if (!inserted && mounted) {
      widget.onError?.call('The editor is not ready; try again.');
    }
  }

  @override
  Widget build(BuildContext context) => _editor;
}

/// Pastes HTML at the caret through the WebView, as a JSON string literal.
///
/// The plugin's own `insertHtml` interpolates into a single-quoted
/// JavaScript string, which a file name with a quote in it would break; the
/// same JSON-encoded injection as the initial content load (spike F3) is
/// safe for anything.
Future<bool> insertHtmlAtCaret(
  HtmlEditorController controller,
  String html,
) async {
  final dynamic web = controller.editorController;
  if (web == null) {
    try {
      controller.insertHtml(html);
      return true;
    } on MissingPluginException {
      return false;
    }
  }
  try {
    await web.evaluateJavascript(
      source:
          "(function(){ try { \$('#summernote-2').summernote('pasteHTML', "
          "${jsonEncode(html)}); return 'ok'; } "
          "catch (e) { return 'js error: ' + e; } })()",
    );
    return true;
  } on MissingPluginException {
    return false;
  }
}
