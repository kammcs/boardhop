import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:html_editor_enhanced/html_editor.dart';

import '../../core/http/ado_client.dart';
import '../../core/http/ado_exceptions.dart';
import '../../theme/theme.dart';
import 'html_constructs.dart';

/// Spike F3 part 2: HTML-native editor fidelity, measured on device.
///
/// Loads Azure DevOps HTML (the synthetic fixture, or a live work item
/// field) into `html_editor_enhanced`, reads it back through the browser
/// DOM, and reports which constructs survived. Nothing is written back.
class EditorProbePage extends StatefulWidget {
  const EditorProbePage({super.key});

  @override
  State<EditorProbePage> createState() => _EditorProbePageState();
}

class _EditorProbePageState extends State<EditorProbePage> {
  final _controller = HtmlEditorController();

  /// Built once. Rebuilding this page must not hand the plugin a new widget,
  /// or it reloads the WebView with `initialText` and drops the content.
  late final Widget _editor = HtmlEditor(
    controller: _controller,
    htmlEditorOptions: const HtmlEditorOptions(
      initialText: HtmlConstructs.synthetic,
      hint: 'Description',
      adjustHeightForKeyboard: false,
    ),
    htmlToolbarOptions: const HtmlToolbarOptions(
      toolbarPosition: ToolbarPosition.aboveEditor,
      toolbarType: ToolbarType.nativeScrollable,
    ),
    otherOptions: const OtherOptions(height: 420),
  );
  final _org = TextEditingController(text: 'puremedia');
  final _id = TextEditingController(text: '11921');
  String _field = 'Microsoft.VSTS.TCM.ReproSteps';
  String _input = HtmlConstructs.synthetic;
  String _inputName = 'synthetic';
  Map<String, bool>? _survival;
  double? _recall;
  int? _outputLength;
  String? _status;
  bool _busy = false;

  static const _fields = {
    'System.Description': 'Description',
    'Microsoft.VSTS.TCM.ReproSteps': 'ReproSteps',
    'Microsoft.VSTS.Common.AcceptanceCriteria': 'AcceptanceCriteria',
  };

  @override
  void dispose() {
    _org.dispose();
    _id.dispose();
    super.dispose();
  }

  /// The plugin's `setText` escapes quotes but not backslashes and rewrites
  /// newlines, which corrupts real descriptions. Inject the HTML as a JSON
  /// string literal through the WebView controller instead.
  Future<String> _setEditorHtml(String html) async {
    final dynamic web = _controller.editorController;
    if (web == null) {
      _controller.setText(html);
      return 'editorController null; used setText';
    }
    final result = await web.evaluateJavascript(
      source:
          "(function(){ try { \$('#summernote-2').summernote('code', ${jsonEncode(html)}); "
          "return 'ok len=' + \$('#summernote-2').summernote('code').length; } "
          "catch (e) { return 'js error: ' + e; } })()",
    );
    return 'js: $result';
  }

  Future<void> _loadWorkItem() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final json = await context.read<AdoClient>().getJson(
        org: _org.text.trim(),
        path: '_apis/wit/workitems/${_id.text.trim()}',
        apiVersion: '7.1',
        query: {'fields': _field},
      );
      final html = (json['fields'] as Map?)?[_field] as String? ?? '';
      if (html.isEmpty) {
        setState(() => _status = 'Field is empty on that work item.');
        return;
      }
      _input = html;
      _inputName = '#${_id.text.trim()} ${_fields[_field]}';
      final note = await _setEditorHtml(html);
      setState(() {
        _survival = null;
        _recall = null;
        _status = 'Loaded ${html.length} chars into the editor. $note';
      });
    } on AdoException catch (e) {
      setState(() => _status = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadSynthetic() async {
    _input = HtmlConstructs.synthetic;
    _inputName = 'synthetic';
    final note = await _setEditorHtml(_input);
    setState(() {
      _survival = null;
      _recall = null;
      _status = 'Loaded the synthetic fixture. $note';
    });
  }

  Future<void> _readBack() async {
    setState(() => _busy = true);
    try {
      final out = await _controller.getText();
      setState(() {
        _survival = HtmlConstructs.survival(_input, out);
        _recall = HtmlConstructs.textRecall(_input, out);
        _outputLength = out.length;
        _status = 'Read back ${out.length} chars.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _report() {
    final b = StringBuffer(
      'F3 editor probe (html_editor_enhanced): $_inputName\n',
    );
    b.writeln(
      'input ${_input.length} chars, output ${_outputLength ?? '-'} chars, '
      'text recall ${_recall == null ? '-' : '${(_recall! * 100).toStringAsFixed(0)}%'}',
    );
    for (final e in (_survival ?? const {}).entries) {
      b.writeln('${e.value ? 'kept' : 'LOST'}  ${e.key}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.boardhopColors;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor probe (spike F3)'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Copy report',
            icon: const Icon(Icons.copy),
            onPressed: _survival == null
                ? null
                : () => Clipboard.setData(ClipboardData(text: _report())),
          ),
        ],
      ),
      body: ListView(
        padding: Spacing.page,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _org,
                  decoration: const InputDecoration(labelText: 'Org'),
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: TextField(
                  controller: _id,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Work item'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _field,
            decoration: const InputDecoration(labelText: 'Field'),
            items: [
              for (final e in _fields.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => _field = v ?? _field),
          ),
          const SizedBox(height: Spacing.sm),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _loadSynthetic,
                child: const Text('Load synthetic'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _loadWorkItem,
                child: const Text('Load work item'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _readBack,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Read back & check'),
              ),
            ],
          ),
          // Always present so the editor keeps its slot in the children list;
          // inserting a widget above it would dispose and recreate the WebView.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            child: Text(
              _status ?? ' ',
              style: BoardhopTheme.codeStyle(context),
            ),
          ),
          KeyedSubtree(key: const ValueKey('f3-editor'), child: _editor),
          const SizedBox(height: Spacing.lg),
          if (_survival != null) ...[
            Text(
              '$_inputName: text recall ${(_recall! * 100).toStringAsFixed(0)}%, '
              'output $_outputLength chars (input ${_input.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: [
                for (final e in _survival!.entries)
                  Chip(
                    avatar: Icon(
                      e.value ? Icons.check : Icons.close,
                      size: 16,
                      color: e.value ? colors.runSucceeded : scheme.error,
                    ),
                    label: Text(e.key),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
