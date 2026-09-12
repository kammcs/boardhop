import 'dart:math' as math;

import 'package:flutter/material.dart' hide Durations;
import 'package:intl/intl.dart';

import '../../../data/models/work_item.dart';
import '../../../data/models/work_item_form.dart';
import '../../../theme/theme.dart';
import '../widgets/work_item_actions.dart';
import '../widgets/work_item_visuals.dart';
import 'controls/attachments_section.dart';
import 'controls/boolean_control.dart';
import 'controls/date_control.dart';
import 'controls/form_field_slot.dart';
import 'controls/identity_picker.dart';
import 'controls/links_section.dart';
import 'controls/picklist_control.dart';
import 'controls/rich_text_control.dart';
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
    this.links,
    this.attachments,
    this.headers = const {},
    this.onFormatChosen,
  });

  final IdentitySource identities;
  final ClassificationSource classifications;
  final Future<List<String>> Function() tags;

  /// The Links page: resolving, searching and opening link targets
  /// (phase 5). Null in a widget test, which renders the page read-only.
  final LinkSource? links;

  /// The Attachments page: fetching, uploading and committing files.
  final AttachmentSource? attachments;

  /// `Authorization` for the images an HTML field embeds, which are
  /// `_apis/wit/attachments` URLs and need the bearer token (research/01
  /// §10.3, spike w17).
  final Map<String, String> headers;

  /// Remembers the Markdown-or-HTML choice per project (`FormPrefs`).
  final void Function(String reference, String format)? onFormatChosen;
}

/// The create form itself: the pinned header (type, title and the core
/// chips) above the layout's groups as cards.
///
/// It is a plain widget over a [WorkItemFormState], so the phone route and
/// the tablet dialog render the same thing; the arrangement follows the
/// width it is given, never the platform. Under [wideMin] the groups stack
/// in one column (a phone, or a small tablet in portrait); above it the
/// layout's own sections become columns and the custom pages become tabs
/// (research/11 §4.5).
class WorkItemFormBody extends StatefulWidget {
  const WorkItemFormBody({super.key, required this.state, this.sources});

  /// The width from which the form lays its sections out in columns.
  static const double wideMin = 640;

  final WorkItemFormState state;
  final FormSources? sources;

  @override
  State<WorkItemFormBody> createState() => _WorkItemFormBodyState();
}

class _WorkItemFormBodyState extends State<WorkItemFormBody> {
  /// One key per control slot, and the slot each field was last built in:
  /// the legacy layout may put the same field in two places, and two
  /// `GlobalKey`s with the same name in one frame would be an error.
  final _keys = <String, GlobalKey>{};
  final _slots = <String, String>{};
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
    final key = reference == null ? null : _keys[_slots[reference] ?? ''];
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

  GlobalKey _keyFor(String slot, String reference) {
    _slots[reference] = slot;
    return _keys.putIfAbsent(slot, GlobalKey.new);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return AnimatedBuilder(
      animation: state,
      builder: (context, _) => SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >= WorkItemFormBody.wideMin
              ? _wide(context, state, constraints)
              : _stacked(context, state, constraints),
        ),
      ),
    );
  }

  /// Phone (and a narrow dialog): the header above one scrolling column of
  /// cards, every page's groups under its own heading.
  Widget _stacked(
    BuildContext context,
    WorkItemFormState state,
    BoxConstraints constraints,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.55),
          child: SingleChildScrollView(
            child: FormHeader(state: state, sources: widget.sources),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: Spacing.xxl),
            children: _cards(context, state),
          ),
        ),
      ],
    );
  }

  /// Tablet: the header on two rows, the pages as tabs and each page's
  /// sections next to each other (research/11 §4.5).
  Widget _wide(
    BuildContext context,
    WorkItemFormState state,
    BoxConstraints constraints,
  ) {
    final pages = state.pages;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.55),
          child: SingleChildScrollView(
            child: FormHeader(
              state: state,
              sources: widget.sources,
              wide: true,
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
    if (pages.length < 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: pages.isEmpty
                ? const SizedBox.shrink()
                : _pageColumns(context, state, pages.first),
          ),
        ],
      );
    }
    return DefaultTabController(
      length: pages.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final page in pages) Tab(text: page.label)],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final page in pages) _pageColumns(context, state, page),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One page's sections as columns. The web's own `percentWidth` drives
  /// the split (50/50 on a stock type); three sections put the first in 60%
  /// and stack the other two in 40%, and a fourth spans the width beneath.
  Widget _pageColumns(
    BuildContext context,
    WorkItemFormState state,
    FormPageView page,
  ) {
    final columns = page.columns;
    Widget groupsOf(Iterable<FormColumnView> sections) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections)
          for (final (index, group) in section.groups.indexed)
            _GroupCard(
              group: group,
              body: _groupBody(
                state,
                group,
                '${page.label}/${columns.indexOf(section)}/$index',
              ),
              padding: const EdgeInsets.only(bottom: Spacing.md),
            ),
      ],
    );

    final Widget body;
    if (columns.length < 2) {
      body = groupsOf(columns);
    } else {
      final right = columns.sublist(1, math.min(3, columns.length));
      final below = columns.length > 3
          ? columns.sublist(3)
          : const <FormColumnView>[];
      final twoWay = right.length == 1;
      final leftFlex = twoWay ? columns.first.percentWidth : 60;
      final rightFlex = twoWay ? right.first.percentWidth : 40;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: math.max(1, leftFlex),
                child: groupsOf([columns.first]),
              ),
              const SizedBox(width: Spacing.lg),
              Expanded(flex: math.max(1, rightFlex), child: groupsOf(right)),
            ],
          ),
          if (below.isNotEmpty) groupsOf(below),
        ],
      );
    }
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.md,
        Spacing.lg,
        Spacing.xxl,
      ),
      child: body,
    );
  }

  List<Widget> _cards(BuildContext context, WorkItemFormState state) {
    final theme = Theme.of(context);
    final out = <Widget>[];
    String? page;
    var index = 0;
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
      out.add(
        _GroupCard(
          group: group,
          body: _groupBody(state, group, 'stacked/${index++}'),
        ),
      );
    }
    return out;
  }

  List<Widget> _groupBody(
    WorkItemFormState state,
    FormGroupView group,
    String slot,
  ) {
    if (group.isPanel) {
      return [buildPanel(state: state, group: group, sources: widget.sources)];
    }
    return [
      for (final control in group.controls)
        KeyedSubtree(
          key: _keyFor(
            '$slot/${control.fieldReferenceName}',
            control.fieldReferenceName!,
          ),
          child: buildControl(
            state: state,
            control: control,
            sources: widget.sources,
            groupLabel: group.label,
          ),
        ),
    ];
  }
}

/// One of the layout's panels: the Links list, the Attachments list, or a
/// line of text for the panels Azure DevOps fills itself (research/11
/// §4.3).
Widget buildPanel({
  required WorkItemFormState state,
  required FormGroupView group,
  FormSources? sources,
}) => switch (group.panel) {
  FormPanelKind.links => LinksSection(
    state: state,
    source: sources?.links,
    enabled: !state.locked,
  ),
  FormPanelKind.attachments => AttachmentsSection(
    state: state,
    source: sources?.attachments,
    enabled: !state.locked,
  ),
  // "Development" (branches, commits, pull requests) and "Deployment"
  // (pipeline environments) are artifact links the service writes; the app
  // never edits them.
  FormPanelKind.external => const _ManagedElsewhere(),
  FormPanelKind.none => const SizedBox.shrink(),
};

class _ManagedElsewhere extends StatelessWidget {
  const _ManagedElsewhere();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(Icons.cloud_outlined, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Text(
            'Managed in Azure DevOps',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// One group of the layout as a card: field controls, or one of the panels
/// (links, attachments, the service's own artifact lists).
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.body,
    this.padding = const EdgeInsets.fromLTRB(
      Spacing.lg,
      Spacing.md,
      Spacing.lg,
      0,
    ),
  });

  final FormGroupView group;
  final List<Widget> body;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
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
  final label = _sameLabel(named, groupLabel) ? '' : named;
  final enabled = !state.locked;
  // A read-only control of an existing item is text, as the web shows it
  // (research/11 §4.3); it is never offered on a new item.
  if (state.isReadOnlyField(field.referenceName)) {
    return ReadOnlyControl(state: state, field: field, label: label);
  }
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
  if (field.type == FieldType.html ||
      control.controlType == FormControlType.html) {
    return RichTextControl(
      state: state,
      field: field,
      label: label,
      enabled: enabled,
      headers: sources?.headers ?? const {},
      attachments: sources?.attachments,
      onFormatChosen: sources?.onFormatChosen,
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

/// A field the process or the layout marks read-only, on an existing item:
/// its value as text under the same label the editable controls use.
class ReadOnlyControl extends StatelessWidget {
  const ReadOnlyControl({
    super.key,
    required this.state,
    required this.field,
    required this.label,
  });

  final WorkItemFormState state;
  final FieldSpec field;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return FormFieldSlot(
      label: label,
      helpText: field.helpText,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Text(
          displayValue(state.value(field.referenceName)),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  static String displayValue(Object? value) => switch (value) {
    null => '—',
    IdentityRef person => person.displayName,
    DateTime date => DateFormat.yMMMd().add_jm().format(date.toLocal()),
    Iterable<Object?> list => list.join(', '),
    _ => '$value',
  };
}

/// A control label and its group label are the same thing to the reader
/// even when the process spells one with a colon or another case.
bool _sameLabel(String a, String b) {
  String normal(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'[:*]+$'), '').trim();
  final left = normal(a);
  return left.isNotEmpty && left == normal(b);
}

/// Type, title and the core chips: the web's header row, folded to phone
/// width or laid out on two rows on a tablet (research/11 §3).
class FormHeader extends StatefulWidget {
  const FormHeader({
    super.key,
    required this.state,
    this.sources,
    this.wide = false,
  });

  final WorkItemFormState state;
  final FormSources? sources;

  /// Title, State and Assigned to on one row, the paths and tags below.
  final bool wide;

  @override
  State<FormHeader> createState() => _FormHeaderState();
}

class _FormHeaderState extends State<FormHeader> {
  /// The raw value, not `state.title`: a template's leading text
  /// ("[template] ") keeps its trailing space and the caret sits after it.
  late final TextEditingController _title = TextEditingController.fromValue(
    TextEditingValue(
      text: widget.state.value('System.Title') as String? ?? '',
      selection: TextSelection.collapsed(
        offset: (widget.state.value('System.Title') as String? ?? '').length,
      ),
    ),
  );

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  WorkItem get _probe => WorkItem(
    id: widget.state.original?.id ?? 0,
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
    final id = state.original?.id;
    final idLabel = id == null ? null : '#$id';
    final reasonField = state.spec.fields['System.Reason'];

    final typeChip = Chip(
      avatar: Icon(
        visuals.typeIcon(probe),
        size: 18,
        color: visuals.typeColor(context, probe),
      ),
      label: Text(state.spec.type.name),
      visualDensity: VisualDensity.compact,
    );
    // "Add child" and "Add related" say what the new item hangs off, since
    // the link itself is only visible after the item exists (phase 5).
    final link = state.link;
    final linkLine = link == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Row(
              children: [
                Icon(
                  link.isParent
                      ? Icons.account_tree_outlined
                      : Icons.link_outlined,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: Spacing.xs),
                Flexible(
                  child: Text(
                    link.title.isEmpty
                        ? link.label
                        : '${link.label} - ${link.title}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
    // On a new item the server owns the state (spike w16); on an existing
    // one the chip opens the legal transitions (research/11 §4.3).
    final initialState = state.spec.initialState;
    final moves =
        state.isCreate &&
        initialState != null &&
        initialState.isNotEmpty &&
        initialState != state.stateName;
    final stateChip = state.isCreate
        ? Tooltip(
            message: moves
                ? 'Created in $initialState, then moved to ${state.stateName}'
                : 'A new item starts in its first state',
            child: Chip(
              avatar: StateDot(
                color: visuals.stateColorFor(context, probe, state.stateName),
              ),
              label: Text(state.stateName),
              visualDensity: VisualDensity.compact,
            ),
          )
        : ActionChip(
            avatar: StateDot(
              color: visuals.stateColorFor(context, probe, state.stateName),
            ),
            label: Text(state.stateName),
            tooltip: 'Change state',
            visualDensity: VisualDensity.compact,
            onPressed: state.locked ? null : () => _pickState(visuals, probe),
          );
    final assigneeChip = ActionChip(
      avatar: IdentityAvatar(identity: assignee, radius: 10),
      label: Text(
        assignee?.displayName ?? 'Assigned to',
        overflow: TextOverflow.ellipsis,
      ),
      tooltip: 'Assigned to',
      visualDensity: VisualDensity.compact,
      onPressed: state.locked || widget.sources == null
          ? null
          : () => _pickAssignee(assignee),
    );
    final areaChip = ActionChip(
      avatar: const Icon(Icons.dashboard_outlined, size: 16),
      label: Text(_leaf(area) ?? 'Area', overflow: TextOverflow.ellipsis),
      tooltip: area ?? 'Area',
      visualDensity: VisualDensity.compact,
      onPressed: state.locked || widget.sources == null
          ? null
          : () => _pickPath(areas: true, current: area),
    );
    final iterationChip = ActionChip(
      avatar: const Icon(Icons.timelapse_outlined, size: 16),
      label: Text(
        _leaf(iteration) ?? 'Iteration',
        overflow: TextOverflow.ellipsis,
      ),
      tooltip: iteration ?? 'Iteration',
      visualDensity: VisualDensity.compact,
      onPressed: state.locked || widget.sources == null
          ? null
          : () => _pickPath(areas: false, current: iteration),
    );
    final tagsChip = ActionChip(
      avatar: const Icon(Icons.label_outline, size: 16),
      label: Text(
        tags.isEmpty ? 'Tags' : tags.join(', '),
        overflow: TextOverflow.ellipsis,
      ),
      tooltip: 'Tags',
      visualDensity: VisualDensity.compact,
      onPressed: state.locked || widget.sources == null
          ? null
          : () => _pickTags(tags),
    );

    final titleSlot = FormFieldSlot(
      label: titleField?.name ?? 'Title',
      required: titleField?.alwaysRequired ?? true,
      error: titleError,
      child: TextField(
        controller: _title,
        enabled: !state.locked,
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
    );

    // HTTP 412: the item moved on while the form was open. Nothing is
    // overwritten silently — Reload keeps what the user typed on top of the
    // fresh copy, Discard drops it (research/11 §4.6).
    final conflictBanner = !state.conflict
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: Spacing.md),
            child: Material(
              color: scheme.tertiaryContainer,
              borderRadius: Radii.card,
              child: Padding(
                padding: Spacing.card,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.sync_problem_outlined,
                          size: 18,
                          color: scheme.onTertiaryContainer,
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            'This item changed on the server',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: state.locked ? null : state.onDiscard,
                          child: const Text('Discard'),
                        ),
                        const SizedBox(width: Spacing.sm),
                        FilledButton.tonal(
                          onPressed: state.locked ? null : state.onReload,
                          child: const Text('Reload'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );

    final banner = state.bannerError == null
        ? null
        : Padding(
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
                    if (state.bannerActionLabel != null) ...[
                      const SizedBox(width: Spacing.sm),
                      TextButton(
                        onPressed: state.saving ? null : state.onBannerAction,
                        child: Text(state.bannerActionLabel!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );

    const chipDrop = EdgeInsets.only(bottom: Spacing.md);
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
          if (widget.wide) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(padding: chipDrop, child: typeChip),
                if (idLabel != null) ...[
                  const SizedBox(width: Spacing.sm),
                  Padding(
                    padding: chipDrop,
                    child: Text(idLabel, style: theme.textTheme.titleMedium),
                  ),
                ],
                const SizedBox(width: Spacing.md),
                Expanded(child: titleSlot),
                const SizedBox(width: Spacing.md),
                Padding(padding: chipDrop, child: stateChip),
                const SizedBox(width: Spacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Padding(padding: chipDrop, child: assigneeChip),
                ),
              ],
            ),
            ?linkLine,
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [areaChip, iterationChip, tagsChip],
            ),
          ] else ...[
            Row(
              children: [
                typeChip,
                if (idLabel != null) ...[
                  const SizedBox(width: Spacing.sm),
                  Text(idLabel, style: theme.textTheme.titleMedium),
                ],
              ],
            ),
            ?linkLine,
            const SizedBox(height: Spacing.sm),
            titleSlot,
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                stateChip,
                assigneeChip,
                areaChip,
                iterationChip,
                tagsChip,
              ],
            ),
          ],
          // A transition reveals Reason right under the chips, as the web
          // does; unsent, the server picks the new state's default.
          if (state.showReason && reasonField != null)
            Padding(
              padding: const EdgeInsets.only(top: Spacing.md),
              child: PicklistControl(
                state: state,
                field: reasonField,
                label: reasonField.name,
                enabled: !state.locked,
              ),
            ),
          ?conflictBanner,
          ?banner,
        ],
      ),
    );
  }

  static String? _leaf(String? path) {
    if (path == null || path.isEmpty) return null;
    final segments = path.split(r'\').where((s) => s.isNotEmpty);
    return segments.isEmpty ? null : segments.last;
  }

  /// The state chip of an existing item: the legal transitions only
  /// (`transitions[state]`, spike w18), through the same sheet the detail
  /// page uses.
  Future<void> _pickState(WorkItemVisuals visuals, WorkItem probe) async {
    final state = widget.state;
    final picked = await pickStateChange(
      context,
      states: state.legalTransitions,
      current: state.stateName,
      colorOf: (context, name) => visuals.stateColorFor(context, probe, name),
      categoryOf: (name) => state.spec.type.stateNamed(name)?.category,
    );
    if (picked == null) return;
    state.setStateName(picked.state);
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
