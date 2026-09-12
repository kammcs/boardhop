import 'package:flutter/material.dart' hide Durations;

import '../../../data/models/work_item.dart';
import '../../../data/models/work_item_form.dart';
import '../../../theme/theme.dart';
import '../widgets/work_item_visuals.dart';
import 'controls/boolean_control.dart';
import 'controls/date_control.dart';
import 'controls/form_field_slot.dart';
import 'controls/identity_picker.dart';
import 'controls/picklist_control.dart';
import 'controls/tags_field.dart';
import 'controls/text_control.dart';
import 'controls/tree_picker.dart';
import 'work_item_form_state.dart';

/// The pickers the form opens. Null in a widget test, which keeps the body
/// free of repositories and of the network.
class FormSources {
  const FormSources({
    required this.identities,
    required this.classifications,
    required this.tags,
  });

  final IdentitySource identities;
  final ClassificationSource classifications;
  final Future<List<String>> Function() tags;
}

/// The create form itself: the pinned header (type, title and the core
/// chips) above a scrolling list of the layout's groups as cards.
///
/// It is a plain widget over a [WorkItemFormState], so the phone route and
/// the tablet dialog (phase 2) render the same thing; the arrangement
/// follows [Breakpoint], never the platform.
class WorkItemFormBody extends StatefulWidget {
  const WorkItemFormBody({super.key, required this.state, this.sources});

  final WorkItemFormState state;
  final FormSources? sources;

  @override
  State<WorkItemFormBody> createState() => _WorkItemFormBodyState();
}

class _WorkItemFormBodyState extends State<WorkItemFormBody> {
  final _keys = <String, GlobalKey>{};
  int _revealTick = 0;

  @override
  void initState() {
    super.initState();
    _revealTick = widget.state.revealTick;
    widget.state.addListener(_onState);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (widget.state.revealTick == _revealTick) return;
    _revealTick = widget.state.revealTick;
    final reference = widget.state.firstErrorField;
    final key = reference == null ? null : _keys[reference];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = key?.currentContext;
      if (context == null || !mounted) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.15,
        duration: Durations.normal,
      );
    });
  }

  GlobalKey _keyFor(String reference) =>
      _keys.putIfAbsent(reference, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.55,
                ),
                child: SingleChildScrollView(
                  child: FormHeader(state: state, sources: widget.sources),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: Spacing.xxl),
                  children: _cards(context, state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _cards(BuildContext context, WorkItemFormState state) {
    final theme = Theme.of(context);
    final out = <Widget>[];
    String? page;
    for (final group in state.groups) {
      if (group.pageLabel != null && group.pageLabel != page) {
        page = group.pageLabel;
        out.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              Spacing.lg,
              Spacing.lg,
              0,
            ),
            child: Text(page!, style: theme.textTheme.titleMedium),
          ),
        );
      }
      out.add(_GroupCard(group: group, body: _groupBody(state, group)));
    }
    return out;
  }

  List<Widget> _groupBody(WorkItemFormState state, FormGroupView group) => [
    for (final control in group.controls)
      KeyedSubtree(
        key: _keyFor(control.fieldReferenceName!),
        child: buildControl(
          state: state,
          control: control,
          sources: widget.sources,
          groupLabel: group.label,
        ),
      ),
  ];
}

/// One group of the layout as a card, or the disabled placeholder for the
/// panels that need an id (links, attachments, deployments).
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.body});

  final FormGroupView group;
  final List<Widget> body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: Spacing.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (group.label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.md),
                  child: Text(group.label, style: theme.textTheme.titleMedium),
                ),
              if (group.unavailable)
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        'Available after creation',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                )
              else
                ...body,
            ],
          ),
        ),
      ),
    );
  }
}

/// The control a field's type asks for (research/11 §4.3).
Widget buildControl({
  required WorkItemFormState state,
  required FormControl control,
  FormSources? sources,
  String groupLabel = '',
}) {
  final field = state.spec.fieldFor(control);
  if (field == null) return const SizedBox.shrink();
  final named = (control.label ?? '').isNotEmpty ? control.label! : field.name;
  // The legacy layout leaves the label off a control that is alone under a
  // group of the same name ("Description", "Repro Steps"); the card title
  // already says it.
  final label = named == groupLabel ? '' : named;
  final enabled = !state.saving;
  if (field.isIdentity || field.type == FieldType.identity) {
    return IdentityControl(
      state: state,
      field: field,
      label: label,
      source: sources?.identities,
      enabled: enabled,
    );
  }
  if (field.type == FieldType.treePath ||
      control.controlType == FormControlType.classification) {
    return TreeControl(
      state: state,
      field: field,
      label: label,
      source: sources?.classifications,
      enabled: enabled,
    );
  }
  if (field.type == FieldType.boolean) {
    return BooleanControl(
      state: state,
      field: field,
      label: label,
      enabled: enabled,
    );
  }
  if (field.type == FieldType.dateTime ||
      control.controlType == FormControlType.dateTime) {
    return DateControl(
      state: state,
      field: field,
      label: label,
      enabled: enabled,
    );
  }
  if (field.allowedValues.isNotEmpty) {
    return PicklistControl(
      state: state,
      field: field,
      label: label,
      enabled: enabled,
    );
  }
  return TextControl(
    state: state,
    field: field,
    label: label,
    watermark: control.emptyText,
    enabled: enabled,
  );
}

/// Type, title and the core chips: the web's header row folded to phone
/// width (research/11 §3).
class FormHeader extends StatefulWidget {
  const FormHeader({super.key, required this.state, this.sources});

  final WorkItemFormState state;
  final FormSources? sources;

  @override
  State<FormHeader> createState() => _FormHeaderState();
}

class _FormHeaderState extends State<FormHeader> {
  late final TextEditingController _title = TextEditingController(
    text: widget.state.title,
  );

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  WorkItem get _probe => WorkItem(
    id: 0,
    rev: 0,
    fields: {
      'System.WorkItemType': widget.state.spec.type.name,
      'System.State': widget.state.stateName,
    },
  );

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visuals = WorkItemVisuals({state.spec.type.name: state.spec.type});
    final probe = _probe;
    final titleField = state.spec.fields['System.Title'];
    final titleError = state.errorFor('System.Title');
    final area = state.value('System.AreaPath') as String?;
    final iteration = state.value('System.IterationPath') as String?;
    final assignee = state.assignedTo;
    final tags = state.tags;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Chip(
                avatar: Icon(
                  visuals.typeIcon(probe),
                  size: 18,
                  color: visuals.typeColor(context, probe),
                ),
                label: Text(state.spec.type.name),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          FormFieldSlot(
            label: titleField?.name ?? 'Title',
            required: titleField?.alwaysRequired ?? true,
            error: titleError,
            child: TextField(
              controller: _title,
              enabled: !state.saving,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Enter title here',
                errorText: titleError == null ? null : '',
                errorStyle: const TextStyle(height: 0, fontSize: 0),
              ),
              onChanged: (text) => state.setValue('System.Title', text),
            ),
          ),
          Wrap(
            spacing: Spacing.sm,
            runSpacing: Spacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tooltip(
                message: 'A new item starts in its first state',
                child: Chip(
                  avatar: StateDot(
                    color: visuals.stateColorFor(
                      context,
                      probe,
                      state.stateName,
                    ),
                  ),
                  label: Text(state.stateName),
                  visualDensity: VisualDensity.compact,
                ),
              ),
              ActionChip(
                avatar: IdentityAvatar(identity: assignee, radius: 10),
                label: Text(assignee?.displayName ?? 'Assigned to'),
                tooltip: 'Assigned to',
                visualDensity: VisualDensity.compact,
                onPressed: state.saving || widget.sources == null
                    ? null
                    : () => _pickAssignee(assignee),
              ),
              ActionChip(
                avatar: const Icon(Icons.dashboard_outlined, size: 16),
                label: Text(_leaf(area) ?? 'Area'),
                tooltip: area ?? 'Area',
                visualDensity: VisualDensity.compact,
                onPressed: state.saving || widget.sources == null
                    ? null
                    : () => _pickPath(areas: true, current: area),
              ),
              ActionChip(
                avatar: const Icon(Icons.timelapse_outlined, size: 16),
                label: Text(_leaf(iteration) ?? 'Iteration'),
                tooltip: iteration ?? 'Iteration',
                visualDensity: VisualDensity.compact,
                onPressed: state.saving || widget.sources == null
                    ? null
                    : () => _pickPath(areas: false, current: iteration),
              ),
              ActionChip(
                avatar: const Icon(Icons.label_outline, size: 16),
                label: Text(tags.isEmpty ? 'Tags' : tags.join(', ')),
                tooltip: 'Tags',
                visualDensity: VisualDensity.compact,
                onPressed: state.saving || widget.sources == null
                    ? null
                    : () => _pickTags(tags),
              ),
            ],
          ),
          if (state.bannerError != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.md),
              child: Material(
                color: scheme.errorContainer,
                borderRadius: Radii.card,
                child: Padding(
                  padding: Spacing.card,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: scheme.onErrorContainer,
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(
                          state.bannerError!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String? _leaf(String? path) {
    if (path == null || path.isEmpty) return null;
    final segments = path.split(r'\').where((s) => s.isNotEmpty);
    return segments.isEmpty ? null : segments.last;
  }

  Future<void> _pickAssignee(IdentityRef? current) async {
    final picked = await pickIdentity(
      context,
      title: 'Assigned to',
      source: widget.sources!.identities,
      current: current,
    );
    if (picked == null) return;
    widget.state.setValue('System.AssignedTo', picked.person);
  }

  Future<void> _pickPath({
    required bool areas,
    required String? current,
  }) async {
    final picked = await pickClassificationPath(
      context,
      title: areas ? 'Area' : 'Iteration',
      source: widget.sources!.classifications,
      areas: areas,
      current: current,
    );
    if (picked == null) return;
    widget.state.setValue(
      areas ? 'System.AreaPath' : 'System.IterationPath',
      picked,
    );
  }

  Future<void> _pickTags(List<String> current) async {
    final picked = await pickTags(
      context,
      current: current,
      suggestions: widget.sources!.tags,
    );
    if (picked == null) return;
    widget.state.setValue('System.Tags', picked);
  }
}
