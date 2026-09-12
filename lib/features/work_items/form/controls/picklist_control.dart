import 'package:flutter/material.dart';

import '../../../../data/models/work_item_form.dart';
import '../../../../theme/theme.dart';
import '../work_item_form_state.dart';
import 'form_field_slot.dart';

/// A field with allowed values: a tile that opens the list as a bottom sheet
/// on a phone and as a menu from medium up.
///
/// A field the process does not declare a picklist keeps a free-text row, as
/// the web does for a field that is not limited to its values
/// ([WorkItemFormState.allowsFreeText]).
class PicklistControl extends StatelessWidget {
  const PicklistControl({
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
    final text = raw == null ? '' : '$raw';
    final tile = PickerTile(
      text: text.isEmpty ? 'Not set' : text,
      placeholder: text.isEmpty,
      enabled: enabled,
      hasError: state.errorFor(reference) != null,
      onTap: () => _pick(context, text),
    );
    return FormFieldSlot(
      label: label,
      required: field.alwaysRequired,
      helpText: field.helpText,
      error: state.errorFor(reference),
      // From medium up the list drops from the tile as a menu, as the web
      // does; a phone opens the bottom sheet (research/11 §4.5).
      child: context.breakpoint.isCompact
          ? tile
          : MenuAnchor(
              style: const MenuStyle(
                maximumSize: WidgetStatePropertyAll(Size(320, 420)),
              ),
              menuChildren: [
                if (!field.alwaysRequired)
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.clear),
                    onPressed: () => state.setValue(reference, null),
                    child: const Text('Clear'),
                  ),
                for (final value in field.allowedValues)
                  MenuItemButton(
                    trailingIcon: value == text
                        ? const Icon(Icons.check)
                        : null,
                    onPressed: () => state.setValue(reference, value),
                    child: Text(value),
                  ),
                if (WorkItemFormState.allowsFreeText(field))
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.edit_outlined),
                    onPressed: () => _pick(context, text),
                    child: const Text('Other value…'),
                  ),
              ],
              builder: (context, controller, child) => PickerTile(
                text: text.isEmpty ? 'Not set' : text,
                placeholder: text.isEmpty,
                enabled: enabled,
                hasError: state.errorFor(reference) != null,
                onTap: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
    );
  }

  Future<void> _pick(BuildContext context, String current) async {
    final picked = await pickAllowedValue(
      context,
      title: label,
      values: field.allowedValues,
      current: current,
      allowFreeText: WorkItemFormState.allowsFreeText(field),
      allowClear: !field.alwaysRequired,
    );
    if (picked == null) return;
    state.setValue(field.referenceName, picked.value);
  }
}

/// What the value sheet answers with; `value` is null for "Clear".
class AllowedValueChoice {
  const AllowedValueChoice(this.value);

  final String? value;
}

Future<AllowedValueChoice?> pickAllowedValue(
  BuildContext context, {
  required String title,
  required List<String> values,
  required String current,
  bool allowFreeText = false,
  bool allowClear = true,
}) {
  if (!context.breakpoint.isCompact) {
    return showDialog<AllowedValueChoice>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
            child: _AllowedValueSheet(
              title: title,
              values: values,
              current: current,
              allowFreeText: allowFreeText,
              allowClear: allowClear,
            ),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<AllowedValueChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AllowedValueSheet(
      title: title,
      values: values,
      current: current,
      allowFreeText: allowFreeText,
      allowClear: allowClear,
    ),
  );
}

class _AllowedValueSheet extends StatefulWidget {
  const _AllowedValueSheet({
    required this.title,
    required this.values,
    required this.current,
    required this.allowFreeText,
    required this.allowClear,
  });

  final String title;
  final List<String> values;
  final String current;
  final bool allowFreeText;
  final bool allowClear;

  @override
  State<_AllowedValueSheet> createState() => _AllowedValueSheetState();
}

class _AllowedValueSheetState extends State<_AllowedValueSheet> {
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.sm,
            ),
            child: Text(widget.title, style: theme.textTheme.titleMedium),
          ),
          if (widget.allowClear)
            ListTile(
              leading: const Icon(Icons.clear),
              title: const Text('Clear'),
              onTap: () =>
                  Navigator.of(context).pop(const AllowedValueChoice(null)),
            ),
          for (final value in widget.values)
            ListTile(
              title: Text(value),
              trailing: value == widget.current
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(AllowedValueChoice(value)),
            ),
          if (widget.allowFreeText)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.sm,
                Spacing.lg,
                Spacing.lg,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _other,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Other value',
                      ),
                      onSubmitted: (text) =>
                          Navigator.of(context)
                              .pop(AllowedValueChoice(text.trim())),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context)
                            .pop(AllowedValueChoice(_other.text.trim())),
                    child: const Text('Use'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
