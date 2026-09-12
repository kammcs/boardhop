import 'package:flutter/material.dart' hide Durations;
import 'package:flutter/services.dart';

import '../../../../data/models/work_item_form.dart';
import '../../../../theme/theme.dart';
import '../work_item_form_state.dart';
import 'form_field_slot.dart';

/// Free-text control: one line for a `string`, a growing box for `plainText`
/// and `html`, a numeric keyboard for `integer` and `double`.
///
/// The HTML case is plain text in phase 1 and is stored as
/// `<div>…</div>` by [WorkItemFormState.buildOps]; phase 2 swaps in the
/// rich editor (research/11 §8).
class TextControl extends StatefulWidget {
  const TextControl({
    super.key,
    required this.state,
    required this.field,
    required this.label,
    this.watermark,
    this.enabled = true,
  });

  final WorkItemFormState state;
  final FieldSpec field;
  final String label;
  final String? watermark;
  final bool enabled;

  @override
  State<TextControl> createState() => _TextControlState();
}

class _TextControlState extends State<TextControl> {
  late final TextEditingController _controller = TextEditingController(
    text: _initialText(),
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocus);

  String _initialText() {
    final value = widget.state.value(widget.field.referenceName);
    if (value == null) return '';
    if (value is num) {
      return value is int ||
              value == value.roundToDouble() && value.abs() < 1e15
          ? value.toInt().toString()
          : '$value';
    }
    return '$value';
  }

  bool get _numeric => widget.field.type.isNumeric;

  bool get _multiline =>
      widget.field.type == FieldType.html ||
      widget.field.type == FieldType.plainText;

  void _onFocus() {
    if (!_focus.hasFocus || !mounted) return;
    // The keyboard is about to cover the bottom of the page; bring the
    // control up with it (the thread composer's lesson).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focus.hasFocus) return;
      final box = context.findRenderObject();
      if (box == null || Scrollable.maybeOf(context) == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.2,
        duration: Durations.normal,
      );
    });
  }

  void _onChanged(String text) {
    final reference = widget.field.referenceName;
    if (!_numeric) {
      widget.state.setValue(reference, text);
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      widget.state.setValue(reference, null);
      widget.state.setParseError(reference, null);
      return;
    }
    final number = widget.field.type == FieldType.integer
        ? int.tryParse(trimmed)
        : num.tryParse(trimmed);
    if (number == null) {
      widget.state.setValue(reference, null);
      widget.state.setParseError(
        reference,
        widget.field.type == FieldType.integer
            ? 'Enter a whole number'
            : 'Enter a number',
      );
      return;
    }
    widget.state.setParseError(reference, null);
    widget.state.setValue(reference, number);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reference = widget.field.referenceName;
    return FormFieldSlot(
      label: widget.label,
      required: widget.field.alwaysRequired,
      helpText: widget.field.helpText,
      error: widget.state.errorFor(reference),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.enabled,
        minLines: _multiline ? 3 : 1,
        maxLines: _multiline ? 8 : 1,
        keyboardType: _numeric
            ? TextInputType.numberWithOptions(
                decimal: widget.field.type != FieldType.integer,
              )
            : _multiline
            ? TextInputType.multiline
            : TextInputType.text,
        inputFormatters: _numeric
            ? [
                FilteringTextInputFormatter.allow(
                  widget.field.type == FieldType.integer
                      ? RegExp(r'[\d\-]')
                      : RegExp(r'[\d\-\.,]'),
                ),
              ]
            : null,
        textInputAction: _multiline
            ? TextInputAction.newline
            : TextInputAction.next,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.watermark,
          errorText: widget.state.errorFor(reference) == null ? null : '',
          errorStyle: const TextStyle(height: 0, fontSize: 0),
        ),
        onChanged: _onChanged,
      ),
    );
  }
}
