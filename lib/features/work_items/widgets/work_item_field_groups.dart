import 'package:flutter/material.dart';

import '../../../data/models/work_item.dart';
import '../../../data/models/work_item_form.dart';
import '../../../theme/theme.dart';
import '../form/work_item_form_state.dart';
import 'rich_text_view.dart';
import 'work_item_visuals.dart';

/// One titled block of the work item detail page. An empty [title] renders
/// the child alone, under the same gutters.
class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty) ...[
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: Spacing.sm),
          ],
          child,
        ],
      ),
    );
  }
}

/// One `label → value` row: the shape the detail page's facts, links and
/// field groups all share, so their labels line up in one column.
class DetailFactRow extends StatelessWidget {
  const DetailFactRow({
    super.key,
    required this.label,
    this.value = '',
    this.child,
  });

  /// Wide enough for "QA Story Points" on two lines at phone width.
  static const double labelWidth = 104;

  final String label;

  /// The value as text; ignored when [child] is given.
  final String value;

  /// A richer value than text (an identity with its avatar).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: child ?? Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// The work item type's own form groups, read-only: every field of the
/// layout this item has a value for, in the web's order, long text as rich
/// text and everything else as a labeled row (research/11, follow-up).
///
/// One widget per section rather than one tall column, so the detail
/// page's `ListView` builds them lazily: a long-text field of a customized
/// process can be many screens tall on its own.
///
/// [groups] comes from [detailGroupsFor], which the page also asks whether
/// there is anything to show at all.
List<Widget> workItemFieldSections({
  required FormSpec spec,
  required WorkItem item,
  required List<FormGroupView> groups,
  Map<String, String> headers = const {},
}) {
  final out = <Widget>[];
  String? page;
  for (final group in groups) {
    // A custom page's groups follow the Details page under its own label.
    final pageLabel = group.pageLabel;
    if (pageLabel != null && pageLabel != page && pageLabel.isNotEmpty) {
      out.add(_PageHeading(label: pageLabel));
    }
    page = pageLabel;

    final rich = <FormControl>[];
    final facts = <FormControl>[];
    for (final control in group.controls) {
      final field = spec.fields[control.fieldReferenceName];
      if (field == null) continue;
      final isLongText =
          field.type.isMultiline || control.controlType == FormControlType.html;
      (isLongText ? rich : facts).add(control);
    }

    for (final control in rich) {
      final field = spec.fields[control.fieldReferenceName]!;
      out.add(
        DetailSection(
          title: _sectionTitle(group, control, field),
          child: RichTextView(
            content: '${item.fields[field.referenceName]}',
            format: item.formatOf(field.referenceName),
            headers: headers,
          ),
        ),
      );
    }
    if (facts.isNotEmpty) {
      out.add(
        DetailSection(
          title: group.label.trim(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final control in facts)
                _FieldRow(
                  field: spec.fields[control.fieldReferenceName]!,
                  label: _labelFor(
                    control,
                    spec.fields[control.fieldReferenceName]!,
                  ),
                  item: item,
                ),
            ],
          ),
        ),
      );
    }
  }
  return out;
}

/// A control's own label, without the layout's trailing punctuation, or the
/// field's name when the control carries none.
String _labelFor(FormControl control, FieldSpec field) {
  final own = (control.label ?? '')
      .trim()
      .replaceAll(RegExp(r'[:*]+$'), '')
      .trim();
  return own.isEmpty ? field.name : own;
}

/// The heading of a long-text section: the group's label when the group is
/// only that field (the web's "Description"), the control's otherwise.
String _sectionTitle(
  FormGroupView group,
  FormControl control,
  FieldSpec field,
) {
  final groupLabel = group.label.trim();
  if (group.controls.length == 1 && groupLabel.isNotEmpty) return groupLabel;
  return _labelFor(control, field);
}

/// The label of a custom page, above its groups..
class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.xl, Spacing.lg, 0),
    child: Text(label, style: Theme.of(context).textTheme.titleLarge),
  );
}

/// [workItemFieldSections] as one box, for a caller that is not a list.
class WorkItemFieldGroups extends StatelessWidget {
  const WorkItemFieldGroups({
    super.key,
    required this.spec,
    required this.item,
    required this.groups,
    this.headers = const {},
  });

  final FormSpec spec;
  final WorkItem item;
  final List<FormGroupView> groups;

  /// `Authorization` for the images of an HTML field.
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: workItemFieldSections(
      spec: spec,
      item: item,
      groups: groups,
      headers: headers,
    ),
  );
}

/// One field of a group as a row: its value as text, with the small avatar
/// in front of it when the field is an identity.
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.label,
    required this.item,
  });

  final FieldSpec field;
  final String label;
  final WorkItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final raw = item.fields[field.referenceName];
    final text = formatFieldValue(field, raw);
    if (field.isIdentity || field.type == FieldType.identity) {
      final person = raw is IdentityRef ? raw : IdentityRef.fromField(raw);
      if (person != null) {
        return DetailFactRow(
          label: label,
          child: Row(
            children: [
              IdentityAvatar(identity: person, radius: 9),
              const SizedBox(width: Spacing.xs),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
        );
      }
    }
    return DetailFactRow(label: label, value: text);
  }
}
