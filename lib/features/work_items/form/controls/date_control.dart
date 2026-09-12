import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import '../../../../data/models/work_item_form.dart';
import '../work_item_form_state.dart';
import 'form_field_slot.dart';

/// A `dateTime` field: a tile that opens the platform date picker. The value
/// is stored as a `DateTime` and sent as midnight UTC, which is what the web
/// writes for a date-only field.
class DateControl extends StatelessWidget {
  const DateControl({
    super.key,
    required this.state,
    required this.field,
    required this.label,
    this.enabled = true,
  });

  final WorkItemFormState state;
  final FieldSpec field;
  final String label;
  final bool enabled;

  DateTime? get _value {
    final raw = state.value(field.referenceName);
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return FormFieldSlot(
      label: label,
      required: field.alwaysRequired,
      helpText: field.helpText,
      error: state.errorFor(field.referenceName),
      child: PickerTile(
        icon: Icons.calendar_today_outlined,
        text: value == null ? 'Not set' : DateFormat.yMMMd().format(value),
        placeholder: value == null,
        enabled: enabled,
        hasError: state.errorFor(field.referenceName) != null,
        onTap: () => _pick(context, value),
      ),
    );
  }

  Future<void> _pick(BuildContext context, DateTime? current) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    state.setValue(
      field.referenceName,
      DateTime.utc(picked.year, picked.month, picked.day),
    );
  }
}
