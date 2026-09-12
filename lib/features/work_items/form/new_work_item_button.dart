import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/auth_bloc.dart';
import '../../../core/http/ado_exceptions.dart';
import '../../../data/models/work_item_form.dart';
import '../../../data/repositories/work_item_form_repository.dart';
import '../../../data/repositories/work_item_repository.dart';
import '../../../theme/theme.dart';
import '../../shared/account_scope.dart';
import 'form_prefs.dart';
import 'type_chooser.dart';
import 'work_item_form_page.dart';

/// Opens the create form and answers with the new item's id, or null when
/// nothing was created.
///
/// From medium up the form is the centered box shown as a real dialog over
/// whatever is on screen (the list, the board, a work item), which stays
/// visible around it; a phone pushes the route, so a deep link works at any
/// width (research/11 §4.5).
Future<int?> openWorkItemForm(
  BuildContext context, {
  required String org,
  required String project,
  required String typeName,
  String? teamId,
  String? stateName,
  String? lane,
  String? laneField,
  int? parentId,
  String? relation,
  String? templateId,
  bool resumeDraft = false,
}) {
  if (context.breakpoint.isCompact) {
    final base = projectRoute(context, org, project);
    final query = <String, String>{
      'type': typeName,
      'team': ?teamId,
      'state': ?stateName,
      if (lane != null && lane.isNotEmpty) 'lane': lane,
      'laneField': ?laneField,
      if (parentId != null) 'parent': '$parentId',
      'rel': ?relation,
      'template': ?templateId,
      if (resumeDraft) 'draft': '1',
    };
    return context.push<int>(
      Uri(path: '$base/work-items/new', queryParameters: query).toString(),
    );
  }
  return showDialog<int>(
    context: context,
    // The account's repositories are provided by the `/a/:account` shell
    // route, so the dialog has to live in the navigator below it; the root
    // navigator is above them and `context.read` there throws.
    useRootNavigator: false,
    builder: (_) => WorkItemFormPage(
      org: org,
      project: project,
      typeName: typeName,
      teamId: teamId,
      stateName: stateName,
      lane: lane,
      laneField: laneField,
      parentId: parentId,
      relation: relation,
      templateId: templateId,
      resumeDraft: resumeDraft,
      asDialog: true,
    ),
  );
}

/// Everything the chooser shows: the project's types in backlog order, the
/// team's templates and the drafts waiting to be resumed.
class TypeChooserData {
  const TypeChooserData({
    required this.model,
    required this.templates,
    required this.drafts,
    required this.teamId,
  });

  final TypeChooserModel model;
  final Map<String, List<WorkItemTemplate>> templates;
  final List<WorkItemDraft> drafts;
  final String teamId;
}

/// Reads the chooser's input. [limitTo] keeps only those type names, which
/// is what a board column offers (the board's own types, research/11 §4.1).
Future<TypeChooserData> loadTypeChooserData(
  BuildContext context, {
  required String org,
  required String project,
  String? teamId,
  Set<String>? limitTo,
}) async {
  final forms = context.read<WorkItemFormRepository>();
  final workItems = context.read<WorkItemRepository>();
  final types = await workItems.types(org, project);
  final team = teamId ?? await forms.defaultTeamId(org, project);
  final backlog = await forms.backlogTypes(org, project, team: team);
  final recent = await FormPrefs.lastType(org, project);
  final templates = await _templates(forms, org, project, team);
  final drafts = await _drafts(forms, org, project);
  var model = buildTypeChooserModel(
    types: types,
    backlog: backlog,
    recentTypeName: recent,
  );
  if (limitTo != null) {
    // A board column offers the board's types only, in backlog order, with
    // nothing hidden under "Other".
    model = TypeChooserModel(
      backlog: [
        for (final type in model.all)
          if (limitTo.contains(type.name)) type,
      ],
      other: const [],
    );
  }
  return TypeChooserData(
    model: model,
    templates: templates,
    drafts: limitTo == null
        ? drafts
        : [
            for (final d in drafts)
              if (limitTo.contains(d.type)) d,
          ],
    teamId: team,
  );
}

/// Templates only show when the team has some (spike w20 put one on the
/// scratch team), and a team without permission to read them is not an
/// error.
Future<Map<String, List<WorkItemTemplate>>> _templates(
  WorkItemFormRepository forms,
  String org,
  String project,
  String team,
) async {
  try {
    final all = await forms.templates(org, project, team);
    final out = <String, List<WorkItemTemplate>>{};
    for (final template in all) {
      out.putIfAbsent(template.workItemTypeName, () => []).add(template);
    }
    return out;
  } on AdoException {
    return const {};
  }
}

Future<List<WorkItemDraft>> _drafts(
  WorkItemFormRepository forms,
  String org,
  String project,
) async {
  try {
    return await forms.drafts(org, project);
  } catch (_) {
    // A draft is a convenience; never let a bad cache row stop the chooser.
    return const [];
  }
}

/// The `+` of the Work app bar, immediately left of the Items/Board pill on
/// both views (research/11 §4.1). Icon only on a phone, icon and label from
/// medium up, the same rule the pill follows.
class NewWorkItemButton extends StatefulWidget {
  const NewWorkItemButton({
    super.key,
    required this.org,
    required this.project,
    this.teamId,
    this.onCreated,
  });

  final String org;
  final String project;

  /// The team whose defaults the form takes; the project's default team
  /// when the caller has none (the board passes its own).
  final String? teamId;

  /// Called after the form closes, so the list or board picks the new item
  /// up with the reload it already has.
  final ValueChanged<int?>? onCreated;

  @override
  State<NewWorkItemButton> createState() => _NewWorkItemButtonState();
}

class _NewWorkItemButtonState extends State<NewWorkItemButton> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    final anchor = context.findRenderObject() as RenderBox?;
    final forms = context.read<WorkItemFormRepository>();
    try {
      final data = await loadTypeChooserData(
        context,
        org: widget.org,
        project: widget.project,
        teamId: widget.teamId,
      );
      if (!mounted) return;
      final choice = await showTypeChooser(
        context,
        model: data.model,
        templates: data.templates,
        drafts: data.drafts,
        onDeleteDraft: (draft) =>
            forms.clearDraft(widget.org, widget.project, draft.type),
        anchor: anchor,
      );
      if (choice == null || !mounted) return;
      // The `+` is busy only while the metadata loads and the chooser is
      // open. It must not stay disabled while the form itself is open: a
      // tab re-tap can drop that route without the await ever returning
      // (phase 2 review).
      setState(() => _busy = false);
      final draft = choice.draft;
      final id = await openWorkItemForm(
        context,
        org: widget.org,
        project: widget.project,
        typeName: choice.typeName,
        teamId: draft?.prefill['team'] ?? widget.teamId,
        stateName: draft?.prefill['state'],
        lane: draft?.prefill['lane'],
        laneField: draft?.prefill['laneField'],
        parentId: int.tryParse(draft?.prefill['parent'] ?? ''),
        relation: draft?.prefill['rel'],
        templateId: choice.template?.id ?? draft?.prefill['template'],
        resumeDraft: draft != null,
      );
      if (!mounted) return;
      widget.onCreated?.call(id);
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on AdoException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.breakpoint.isCompact;
    if (compact) {
      return IconButton(
        tooltip: 'New work item',
        icon: const Icon(Icons.add),
        onPressed: _busy ? null : _open,
      );
    }
    return TextButton.icon(
      icon: const Icon(Icons.add),
      label: const Text('New'),
      onPressed: _busy ? null : _open,
    );
  }
}
