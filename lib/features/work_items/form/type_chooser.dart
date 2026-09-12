import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../data/models/work_item.dart';
import '../../../data/models/work_item_form.dart';
import '../../../theme/theme.dart';
import '../../boards/widgets/kanban_board.dart' show tintApiColor;

/// What the user picked: a type, and either the template to pre-fill it
/// with (null is "Blank") or the draft to resume.
class TypeChoice {
  const TypeChoice(this.typeName, {this.template, this.draft});

  final String typeName;
  final WorkItemTemplate? template;

  /// The project's saved draft of this type, when the user picked its
  /// "Resume draft" row (research/11 4.6).
  final WorkItemDraft? draft;

  bool get resumesDraft => draft != null;
}

/// How one draft reads in the chooser: `Task - Login fails - 5m ago`. The
/// age uses the app's own relative wording (`5m`, `3h`, `Sep 3`).
String draftRowLabel(WorkItemDraft draft) {
  final title = (draft.title ?? '').trim();
  final age = relativeTime(draft.savedAt);
  return '${draft.type} - ${title.isEmpty ? '(untitled)' : title} - '
      '${age == 'just now' ? age : '$age ago'}';
}

/// The chooser's rows: the backlog levels top-down, then everything else
/// under "Other", with the project's last used type pinned on top
/// (research/11 §4.2).
class TypeChooserModel {
  const TypeChooserModel({
    required this.backlog,
    required this.other,
    this.recent,
  });

  final List<WorkItemType> backlog;
  final List<WorkItemType> other;

  /// The type last created in this project, when it is still offered.
  final WorkItemType? recent;

  List<WorkItemType> get all => [...backlog, ...other];
}

/// Orders the types for the chooser.
///
/// The backlog levels come back rank-descending from
/// `WorkItemFormRepository.parseBacklogTypes`. A level the team hid (Epics
/// in the scratch project) still contributes its types: the level is off the
/// backlog, the type is not, and only `Microsoft.HiddenCategory` says a type
/// is never offered.
TypeChooserModel buildTypeChooserModel({
  required List<WorkItemType> types,
  required BacklogTypes backlog,
  String? recentTypeName,
}) {
  final byName = {for (final t in types) t.name: t};
  bool offered(WorkItemType type) =>
      !type.isDisabled && !backlog.hiddenTypes.contains(type.name);

  final ordered = <WorkItemType>[];
  final seen = <String>{};
  for (final level in backlog.levels) {
    for (final name in level.typeNames) {
      final type = byName[name];
      if (type == null || !offered(type) || !seen.add(name)) continue;
      ordered.add(type);
    }
  }
  final rest = [
    for (final type in types)
      if (offered(type) && !seen.contains(type.name)) type,
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  final recent = recentTypeName == null ? null : byName[recentTypeName];
  return TypeChooserModel(
    backlog: ordered,
    other: rest,
    recent: recent != null && offered(recent) ? recent : null,
  );
}

/// The chooser: a bottom sheet on a phone, a menu under the `+` from medium
/// up ([Breakpoint], never the platform).
Future<TypeChoice?> showTypeChooser(
  BuildContext context, {
  required TypeChooserModel model,
  Map<String, List<WorkItemTemplate>> templates = const {},
  List<WorkItemDraft> drafts = const [],
  ValueChanged<WorkItemDraft>? onDeleteDraft,
  RenderBox? anchor,
}) {
  if (context.breakpoint.isCompact || anchor == null) {
    return showModalBottomSheet<TypeChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _TypeSheet(
        model: model,
        templates: templates,
        drafts: drafts,
        onDeleteDraft: onDeleteDraft,
      ),
    );
  }
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final topLeft = anchor.localToGlobal(
    anchor.size.bottomLeft(Offset.zero),
    ancestor: overlay,
  );
  final bottomRight = anchor.localToGlobal(
    anchor.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );
  return showMenu<TypeChoice>(
    context: context,
    position: RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy,
      overlay.size.width - bottomRight.dx,
      0,
    ),
    items: _menuItems(context, model, templates, drafts, onDeleteDraft),
  );
}

List<PopupMenuEntry<TypeChoice>> _menuItems(
  BuildContext context,
  TypeChooserModel model,
  Map<String, List<WorkItemTemplate>> templates,
  List<WorkItemDraft> drafts,
  ValueChanged<WorkItemDraft>? onDeleteDraft,
) {
  final items = <PopupMenuEntry<TypeChoice>>[];
  void addType(WorkItemType type, {String? caption}) {
    if (caption != null) {
      items.add(
        PopupMenuItem<TypeChoice>(
          enabled: false,
          height: 32,
          child: Text(
            caption,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final forType = templates[type.name] ?? const <WorkItemTemplate>[];
    items.add(
      PopupMenuItem<TypeChoice>(
        value: TypeChoice(type.name),
        child: _TypeRowContent(type: type),
      ),
    );
    for (final template in forType) {
      items.add(
        PopupMenuItem<TypeChoice>(
          value: TypeChoice(type.name, template: template),
          child: Padding(
            padding: const EdgeInsets.only(left: Spacing.xl),
            child: Text(template.name),
          ),
        ),
      );
    }
  }

  for (final draft in drafts) {
    items.add(
      PopupMenuItem<TypeChoice>(
        value: TypeChoice(draft.type, draft: draft),
        child: Row(
          children: [
            const Icon(Icons.history_outlined, size: 20),
            const SizedBox(width: Spacing.md),
            Flexible(
              child: Text(
                'Resume draft: ${draftRowLabel(draft)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onDeleteDraft != null)
              IconButton(
                tooltip: 'Delete draft',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () {
                  onDeleteDraft(draft);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
  if (drafts.isNotEmpty) items.add(const PopupMenuDivider());
  if (model.recent != null) {
    addType(model.recent!, caption: 'Recent');
    items.add(const PopupMenuDivider());
  }
  for (final type in model.backlog) {
    addType(type);
  }
  if (model.other.isNotEmpty) {
    items.add(const PopupMenuDivider());
    for (final type in model.other) {
      addType(type);
    }
  }
  return items;
}

class _TypeSheet extends StatefulWidget {
  const _TypeSheet({
    required this.model,
    required this.templates,
    this.drafts = const [],
    this.onDeleteDraft,
  });

  final TypeChooserModel model;
  final Map<String, List<WorkItemTemplate>> templates;
  final List<WorkItemDraft> drafts;
  final ValueChanged<WorkItemDraft>? onDeleteDraft;

  @override
  State<_TypeSheet> createState() => _TypeSheetState();
}

class _TypeSheetState extends State<_TypeSheet> {
  late final List<WorkItemDraft> _drafts = [...widget.drafts];

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final templates = widget.templates;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Spacing.lg,
              0,
              Spacing.lg,
              Spacing.sm,
            ),
            child: Text('New work item', style: theme.textTheme.titleMedium),
          ),
          for (final draft in _drafts)
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: Text('Resume draft: ${draftRowLabel(draft)}'),
              trailing: widget.onDeleteDraft == null
                  ? null
                  : IconButton(
                      tooltip: 'Delete draft',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        widget.onDeleteDraft!(draft);
                        setState(() => _drafts.remove(draft));
                      },
                    ),
              onTap: () =>
                  Navigator.of(context)
                      .pop(TypeChoice(draft.type, draft: draft)),
            ),
          if (_drafts.isNotEmpty) const Divider(height: 1),
          if (model.recent != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.xs,
                Spacing.lg,
                Spacing.xs,
              ),
              child: Text(
                'Recent',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            _TypeRow(
              type: model.recent!,
              templates: templates[model.recent!.name] ?? const [],
            ),
            const Divider(height: 1),
          ],
          for (final type in model.backlog)
            _TypeRow(type: type, templates: templates[type.name] ?? const []),
          if (model.other.isNotEmpty)
            ExpansionTile(
              title: Text('Other', style: theme.textTheme.titleSmall),
              children: [
                for (final type in model.other)
                  _TypeRow(
                    type: type,
                    templates: templates[type.name] ?? const [],
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.type, this.templates = const []});

  final WorkItemType type;
  final List<WorkItemTemplate> templates;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) {
      return ListTile(
        leading: Icon(type.icon, color: typeChooserColor(context, type)),
        title: Text(type.name),
        onTap: () => Navigator.of(context).pop(TypeChoice(type.name)),
      );
    }
    return ExpansionTile(
      leading: Icon(type.icon, color: typeChooserColor(context, type)),
      title: Text(type.name),
      children: [
        ListTile(
          contentPadding: const EdgeInsets.only(
            left: Spacing.xxl + Spacing.lg,
            right: Spacing.lg,
          ),
          title: const Text('Blank'),
          onTap: () => Navigator.of(context).pop(TypeChoice(type.name)),
        ),
        for (final template in templates)
          ListTile(
            contentPadding: const EdgeInsets.only(
              left: Spacing.xxl + Spacing.lg,
              right: Spacing.lg,
            ),
            title: Text(template.name),
            subtitle: template.description == null
                ? null
                : Text(template.description!),
            onTap: () =>
                Navigator.of(context)
                    .pop(TypeChoice(type.name, template: template)),
          ),
      ],
    );
  }
}

class _TypeRowContent extends StatelessWidget {
  const _TypeRowContent({required this.type});

  final WorkItemType type;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(type.icon, size: 20, color: typeChooserColor(context, type)),
      const SizedBox(width: Spacing.md),
      Flexible(child: Text(type.name, overflow: TextOverflow.ellipsis)),
    ],
  );
}

/// The process colour of a type, tinted for dark mode, falling back to the
/// theme's palette (DESIGN.md §3).
Color typeChooserColor(BuildContext context, WorkItemType type) {
  final api = parseHexColor(type.color);
  return api == null
      ? context.boardhopColors.workItemType(type.name)
      : tintApiColor(context, api);
}
