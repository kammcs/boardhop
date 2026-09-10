import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:html_editor_enhanced/html_editor.dart';

import '../../auth/auth_bloc.dart';
import '../../core/http/ado_exceptions.dart';
import '../../data/models/work_item.dart';
import '../../data/repositories/work_item_repository.dart';
import '../../data/write_queue.dart';
import '../../theme/theme.dart';

/// Edit the title and the description of a work item. HTML descriptions go
/// through `html_editor_enhanced` (spike F3: content is injected through
/// the WebView with a JSON string literal, and the editor keeps a stable
/// slot); Markdown descriptions are edited as text. Saved with `test /rev`
/// so a stale copy is refused, not overwritten.
class WorkItemEditPage extends StatefulWidget {
  const WorkItemEditPage({
    super.key,
    required this.org,
    required this.project,
    required this.id,
  });

  final String org;
  final String project;
  final int id;

  @override
  State<WorkItemEditPage> createState() => _WorkItemEditPageState();
}

class _WorkItemEditPageState extends State<WorkItemEditPage> {
  static const _descriptionField = 'System.Description';

  final _title = TextEditingController();
  final _markdown = TextEditingController();
  final _html = HtmlEditorController();
  late final Widget _editor = HtmlEditor(
    controller: _html,
    htmlEditorOptions: const HtmlEditorOptions(
      hint: 'Description',
      adjustHeightForKeyboard: false,
    ),
    htmlToolbarOptions: const HtmlToolbarOptions(
      toolbarPosition: ToolbarPosition.aboveEditor,
      toolbarType: ToolbarType.nativeScrollable,
      defaultToolbarButtons: [
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
    ),
    otherOptions: const OtherOptions(height: 380),
    callbacks: Callbacks(onInit: () => _editorReady = true),
  );

  WorkItem? _item;
  String _format = 'html';
  bool _editorReady = false;
  bool _contentPushed = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _title.dispose();
    _markdown.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = context.read<WorkItemRepository>();
    try {
      final item = await repo.refreshItem(
        widget.org,
        widget.project,
        widget.id,
      );
      if (!mounted) return;
      setState(() {
        _item = item;
        _format = item.formatOf(_descriptionField);
        _title.text = item.title;
        if (_format == 'markdown') {
          _markdown.text = item.description ?? '';
        }
        _loading = false;
      });
      _pushHtmlWhenReady();
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  /// The plugin's `setText` mangles backslashes and newlines; inject the
  /// HTML as a JSON string literal once the WebView reports ready.
  Future<void> _pushHtmlWhenReady() async {
    if (_format != 'html' || _contentPushed) return;
    for (var i = 0; i < 40 && !_editorReady; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted || _contentPushed) return;
    final html = _item?.description ?? '';
    if (html.isEmpty) {
      _contentPushed = true;
      return;
    }
    // The WebView channel can lag onInit by a few frames; retry briefly.
    for (var attempt = 0; attempt < 10 && mounted; attempt++) {
      final dynamic web = _html.editorController;
      try {
        if (web == null) {
          _html.setText(html);
        } else {
          await web.evaluateJavascript(
            source:
                "(function(){ try { \$('#summernote-2').summernote('code', ${jsonEncode(html)}); "
                "return 'ok'; } catch (e) { return 'js error: ' + e; } })()",
          );
        }
        _contentPushed = true;
        return;
      } on MissingPluginException {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    if (mounted) {
      setState(() => _error = 'The editor did not load; try again.');
    }
  }

  Future<void> _save() async {
    final item = _item;
    if (item == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = context.read<WorkItemRepository>();
    final queue = context.read<WriteQueue>();
    late final Map<String, Object?> values;
    try {
      final title = _title.text.trim();
      final String description;
      try {
        description = _format == 'markdown'
            ? _markdown.text
            : await _html.getText();
      } on MissingPluginException {
        setState(() => _error = 'The editor is not ready; try again.');
        return;
      }
      values = <String, Object?>{
        if (title.isNotEmpty && title != item.title) 'System.Title': title,
        if (description != (item.description ?? ''))
          _descriptionField: description,
      };
      if (values.isEmpty) {
        if (mounted) context.pop();
        return;
      }
      await repo.updateFields(widget.org, widget.project, item, values);
      if (mounted) context.pop();
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(AuthInteractionRequired(e.message));
      }
    } on AdoNetworkException {
      await queue.enqueuePatch(
        org: widget.org,
        project: widget.project,
        item: item,
        ops: [
          for (final e in values.entries)
            {'op': 'add', 'path': '/fields/${e.key}', 'value': e.value},
        ],
        description: 'Edit ${item.id}',
      );
      await repo.applyLocally(widget.org, widget.project, item, values);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Offline: the edit will sync later.')),
        );
        context.pop();
      }
    } on AdoStaleRevisionException {
      if (mounted) {
        setState(
          () => _error = 'This item changed elsewhere. Go back, reload it, and edit again.',
        );
      }
    } on AdoValidationException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.ruleErrors
              .map((r) => '${r.fieldReferenceName}: ${r.errorMessage}')
              .join('\n'),
        );
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit #${widget.id}'),
        leading: IconButton(
          tooltip: 'Discard',
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ContentColumn(
        // Every child is keyed and the progress/error rows keep their slots
        // (spike F3): an index shift would dispose the editor's WebView.
        child: ListView(
          padding: const EdgeInsets.only(bottom: Spacing.xxl),
          children: [
            SizedBox(
              key: const ValueKey('progress'),
              height: 4,
              child: _loading || _saving
                  ? const LinearProgressIndicator()
                  : null,
            ),
            if (_error != null)
              ListTile(
                key: const ValueKey('error'),
                leading: Icon(Icons.error_outline, color: scheme.error),
                title: Text(_error!),
              )
            else
              const SizedBox.shrink(key: ValueKey('error')),
            Padding(
              key: const ValueKey('title'),
              padding: Spacing.page,
              child: TextField(
                controller: _title,
                enabled: !_loading,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
            ),
            Padding(
              key: const ValueKey('label'),
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                Spacing.sm,
              ),
              child: Text(
                _format == 'markdown'
                    ? 'Description (Markdown)'
                    : 'Description',
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (_format == 'markdown')
              Padding(
                key: const ValueKey('markdown'),
                padding: Spacing.pageHorizontal,
                child: TextField(
                  controller: _markdown,
                  enabled: !_loading,
                  minLines: 8,
                  maxLines: 30,
                  style: BoardhopTheme.codeStyle(context),
                  decoration: const InputDecoration(
                    hintText: 'Markdown',
                    alignLabelWithHint: true,
                  ),
                ),
              )
            else
              // Stable slot for the WebView (spike F3): never insert widgets
              // above it after the first build.
              Padding(
                key: const ValueKey('description-editor'),
                padding: Spacing.pageHorizontal,
                child: _editor,
              ),
          ],
        ),
      ),
    );
  }
}
