import 'package:flutter/material.dart';

import '../../../../data/models/work_item_form.dart';
import '../../../../theme/theme.dart';
import '../work_item_form_state.dart';
import 'form_field_slot.dart';

/// A `boolean` field. The label lives on the switch tile itself, so the slot
/// only carries the help text and the error.
class BooleanControl extends StatelessWidget {
  const BooleanControl({
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

  @override
  Widget build(BuildContext context) {
    final reference = field.referenceName;
    final raw = state.value(reference);
    final value = raw is bool ? raw : '$raw'.toLowerCase() == 'true';
    return FormFieldSlot(
      label: '',
      helpText: field.helpText,
      error: state.errorFor(reference),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: enabled ? (next) => state.setValue(reference, next) : null,
        visualDensity: VisualDensity.compact,
        shape: const RoundedRectangleBorder(borderRadius: Radii.card),
      ),
    );
  }
}
