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
  /// when the caller has none (phase 4 passes the board's).
  final String? teamId;

  /// Called after the form closes, so the list or board picks the new item
  /// up with the reload it already has.
  final VoidCallback? onCreated;

  @override
  State<NewWorkItemButton> createState() => _NewWorkItemButtonState();
}

class _NewWorkItemButtonState extends State<NewWorkItemButton> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    final forms = context.read<WorkItemFormRepository>();
    final workItems = context.read<WorkItemRepository>();
    final anchor = context.findRenderObject() as RenderBox?;
    try {
      final types = await workItems.types(widget.org, widget.project);
      final team =
          widget.teamId ??
          await forms.defaultTeamId(widget.org, widget.project);
      final backlog = await forms.backlogTypes(
        widget.org,
        widget.project,
        team: team,
      );
      final recent = await FormPrefs.lastType(widget.org, widget.project);
      final templates = await _templates(forms, team);
      if (!mounted) return;
      final model = buildTypeChooserModel(
        types: types,
        backlog: backlog,
        recentTypeName: recent,
      );
      final choice = await showTypeChooser(
        context,
        model: model,
        templates: templates,
        anchor: anchor,
      );
      if (choice == null || !mounted) return;
      // From medium up the form is a centered dialog over the list or the
      // board, which stays visible around it (research/11 §4.5); a phone
      // pushes the route.
      if (context.breakpoint.isCompact) {
        final base = projectRoute(context, widget.org, widget.project);
        final query = {
          'type': choice.typeName,
          if (choice.template != null) 'template': choice.template!.id,
          if (widget.teamId != null) 'team': widget.teamId!,
        };
        await context.push(
          Uri(path: '$base/work-items/new', queryParameters: query).toString(),
        );
      } else {
        await showDialog<int>(
          context: context,
          // The account's repositories are provided by the `/a/:account`
          // shell route, so the dialog has to live in the navigator below
          // it; the root navigator is above them and `context.read` there
          // throws.
          useRootNavigator: false,
          builder: (_) => WorkItemFormPage(
            org: widget.org,
            project: widget.project,
            typeName: choice.typeName,
            teamId: widget.teamId,
            templateId: choice.template?.id,
            asDialog: true,
          ),
        );
      }
      if (!mounted) return;
      widget.onCreated?.call();
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

  /// Templates only show when the team has some (none exist yet, spike s25),
  /// and a team without permission to read them is not an error.
  Future<Map<String, List<WorkItemTemplate>>> _templates(
    WorkItemFormRepository forms,
    String team,
  ) async {
    try {
      final all = await forms.templates(widget.org, widget.project, team);
      final out = <String, List<WorkItemTemplate>>{};
      for (final template in all) {
        out.putIfAbsent(template.workItemTypeName, () => []).add(template);
      }
      return out;
    } on AdoException {
      return const {};
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
