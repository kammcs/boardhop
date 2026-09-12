import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/auth_bloc.dart';
import '../../../auth/auth_service.dart';
import '../../../core/http/ado_exceptions.dart';
import '../../../data/models/work_item.dart';
import '../../../data/models/work_item_form.dart';
import '../../../data/repositories/work_item_form_repository.dart';
import '../../../data/repositories/work_item_repository.dart';
import '../../../theme/theme.dart';
import '../../shared/account_scope.dart';
import 'controls/identity_picker.dart';
import 'controls/tree_picker.dart';
import 'form_prefs.dart';
import 'work_item_form_body.dart';
import 'work_item_form_state.dart';

/// Create a work item of one type: `…/work-items/new?type=Bug`.
///
/// The form opens on the server's own defaults — a `validateOnly` dry run of
/// the type plus the pre-fills answers with State, Reason, Area and
/// Iteration (spike w16) — merged over the field defaults and under
/// whatever the caller pre-filled (a board column, a parent, a template).
///
/// Arrangement: full screen on a phone; a centered box up to 960 dp wide and
/// 90% of the height from medium up (research/11 §4.5). The `+` of the Work
/// app bar shows that box as a real dialog over the list or board
/// ([asDialog]); the route renders the same box centered on its own page, so
/// a deep link works at any width.
class WorkItemFormPage extends StatefulWidget {
  const WorkItemFormPage({
    super.key,
    required this.org,
    required this.project,
    required this.typeName,
    this.teamId,
    this.stateName,
    this.lane,
    this.laneField,
    this.parentId,
    this.templateId,
    this.asDialog = false,
  });

  final String org;
  final String project;
  final String typeName;

  /// The board's team when the form came from a board (phase 4); the
  /// project's default team otherwise.
  final String? teamId;

  /// A board column's state. Only the type's initial state is legal on
  /// create (spike w16), so phase 4 patches it after the create; the form
  /// keeps it for that step.
  final String? stateName;

  final String? lane;
  final String? laneField;
  final int? parentId;
  final String? templateId;

  /// Shown inside `showDialog` rather than as a route: the form pops the
  /// dialog itself and the view behind it stays visible.
  final bool asDialog;

  @override
  State<WorkItemFormPage> createState() => _WorkItemFormPageState();
}

class _WorkItemFormPageState extends State<WorkItemFormPage> {
  WorkItemFormState? _form;
  FormSources? _sources;
  String? _parentUrl;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _form?.dispose();
    super.dispose();
  }

  WorkItemFormRepository get _repo => context.read<WorkItemFormRepository>();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = _repo;
    final workItems = context.read<WorkItemRepository>();
    final accountId = AccountScope.of(context);
    final me = context.read<AuthService>().accountById(accountId)?.username;
    try {
      final spec = await repo.formSpec(
        widget.org,
        widget.project,
        widget.typeName,
      );
      final team =
          widget.teamId ?? await repo.defaultTeamId(widget.org, widget.project);
      final defaults = await repo.teamDefaults(
        widget.org,
        widget.project,
        team: team,
      );

      final prefill = <String, Object?>{};
      if (defaults.defaultArea != null) {
        prefill['System.AreaPath'] = defaults.defaultArea;
      }
      if (defaults.iterationPath != null) {
        prefill['System.IterationPath'] = defaults.iterationPath;
      }
      if (widget.laneField != null && widget.lane != null) {
        prefill[widget.laneField!] = widget.lane;
      }
      if (widget.parentId != null) {
        final parents = await workItems.batch(widget.org, widget.project, [
          widget.parentId!,
        ]);
        final parent = parents.isEmpty ? null : parents.first;
        if (parent != null) {
          _parentUrl = parent.url;
          if (parent.areaPath != null) {
            prefill['System.AreaPath'] = parent.areaPath;
          }
          if (parent.iterationPath != null) {
            prefill['System.IterationPath'] = parent.iterationPath;
          }
        }
      }
      if (widget.templateId != null) {
        final template = await repo.template(
          widget.org,
          widget.project,
          team,
          widget.templateId!,
        );
        prefill.addAll(template.fields);
      }

      final values = await _initialValues(spec, prefill);
      // The Graph reads take the project **id**; the route carries the name
      // and `graph/descriptors/{name}` answers HTTP 400, which used to send
      // the people search org-wide (spike s30).
      final projectId = await _projectId(repo);
      final members = await _teamMembers(projectId, team);
      final recent = await FormPrefs.recentAssignees(
        widget.org,
        widget.project,
      );
      final format = await FormPrefs.descriptionFormat(
        widget.org,
        widget.project,
      );

      if (!mounted) return;
      final form = WorkItemFormState(
        spec: spec,
        initialValues: values,
        onDependentFieldChanged: _dryRun,
        formats: {'System.Description': format},
      );
      _form?.dispose();
      setState(() {
        _form = form;
        _sources = FormSources(
          identities: IdentitySource(
            members: () async => members,
            search: (query) => repo.searchPeople(widget.org, projectId, query),
            resolve: (person) => repo.resolveIdentityId(widget.org, person),
            me: _meAmong(members, me),
            recent: recent,
            onPicked: (person) =>
                FormPrefs.rememberAssignee(widget.org, widget.project, person),
          ),
          classifications: ClassificationSource(
            nodes: ({required bool areas}) => repo.classificationNodes(
              widget.org,
              widget.project,
              areas: areas,
            ),
            teamIterations: () =>
                repo.teamIterations(widget.org, widget.project, team: team),
            currentIterationPath: defaults.currentIterationPath,
            backlogIterationPath: defaults.backlogIterationPath,
          ),
          tags: () => repo.tags(widget.org, widget.project),
          onFormatChosen: (reference, chosen) {
            if (reference == 'System.Description') {
              FormPrefs.setDescriptionFormat(
                widget.org,
                widget.project,
                chosen,
              );
            }
          },
        );
      });
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
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The debounced dry run a field with `dependentFields` triggers: the
  /// server re-evaluates its rules and answers with per-field messages
  /// (research/11 §2).
  Future<void> _dryRun() async {
    final form = _form;
    if (form == null || form.saving || form.title.isEmpty) return;
    try {
      await _repo.validate(
        widget.org,
        widget.project,
        widget.typeName,
        form.buildOps(parentUrl: _parentUrl),
      );
      form.clearServerErrors();
    } on WorkItemRuleException catch (e) {
      form.applyRuleErrors(e);
    } on AdoException {
      // Offline or a transient refusal: the save will say so.
    }
  }

  /// The project's id, falling back to the name when the read fails: the
  /// search then behaves as it did before, org-wide.
  Future<String> _projectId(WorkItemFormRepository repo) async {
    try {
      return await repo.projectId(widget.org, widget.project);
    } on AdoException {
      return widget.project;
    }
  }

  Future<List<IdentityRef>> _teamMembers(String projectId, String team) async {
    try {
      return await _repo.teamMembers(widget.org, projectId, team);
    } on AdoException {
      // The picker still has "Me", the search and the recents.
      return const [];
    }
  }

  IdentityRef? _meAmong(List<IdentityRef> members, String? username) {
    if (username == null || username.isEmpty) return null;
    for (final member in members) {
      if ((member.uniqueName ?? '').toLowerCase() == username.toLowerCase()) {
        return member;
      }
    }
    return IdentityRef(displayName: username, uniqueName: username);
  }

  /// Field defaults, then the server's dry-run answer, then the pre-fills.
  Future<Map<String, Object?>> _initialValues(
    FormSpec spec,
    Map<String, Object?> prefill,
  ) async {
    final references = fieldRefsFor(groupViewsFor(spec));
    final values = <String, Object?>{};
    for (final reference in references) {
      final field = spec.fields[reference];
      if (field?.defaultValue != null) {
        values[reference] = _decode(spec, reference, field!.defaultValue);
      }
    }
    values['System.State'] = spec.initialState;

    try {
      final probe = await _repo.validate(
        widget.org,
        widget.project,
        widget.typeName,
        WorkItemFormRepository.buildCreateOps({
          ...prefill,
          'System.Title': prefill['System.Title'] ?? 'New ${widget.typeName}',
        }, parentUrl: _parentUrl),
      );
      for (final reference in references) {
        if (reference == 'System.Title') continue;
        final value = probe.fields[reference];
        if (value == null) continue;
        values[reference] = _decode(spec, reference, value);
      }
      if (probe.state.isNotEmpty) values['System.State'] = probe.state;
    } on WorkItemRuleException {
      // The dry run without a real title can be refused on a rule; the
      // form still opens on the field defaults.
    } on AdoAuthException {
      rethrow;
    } on AdoException {
      // Offline or refused: the field defaults carry the form.
    }

    for (final entry in prefill.entries) {
      values[entry.key] = _decode(spec, entry.key, entry.value);
    }
    if (widget.stateName != null) values['System.State'] = spec.initialState;
    return values;
  }

  /// A field value as the controls hold it: identities as [IdentityRef],
  /// tags as a list, everything else as it came.
  static Object? _decode(FormSpec spec, String reference, Object? value) {
    if (value == null) return null;
    if (reference == 'System.Tags') {
      return value is List
          ? [for (final t in value) '$t']
          : WorkItemFormRepository.parseTags(value);
    }
    final field = spec.fields[reference];
    if (field != null &&
        (field.isIdentity || field.type == FieldType.identity)) {
      return value is IdentityRef ? value : IdentityRef.fromField(value);
    }
    return value;
  }

  /// The dialog pops itself; the route goes through go_router.
  void _close([Object? result]) {
    if (widget.asDialog) {
      Navigator.of(context).pop(result);
    } else {
      context.pop(result);
    }
  }

  Future<bool> _confirmDiscard() async {
    final form = _form;
    if (form == null || !form.isDirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('Discard this work item?'),
        content: const Text('It has not been created yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _create() async {
    final form = _form;
    if (form == null || form.saving) return;
    form.clearServerErrors();
    if (!form.validateLocally()) {
      form.revealFirstError();
      return;
    }
    form.setSaving(true);
    final repo = _repo;
    final ops = form.buildOps(parentUrl: _parentUrl);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final base = projectRoute(context, widget.org, widget.project);
    try {
      await repo.validate(widget.org, widget.project, widget.typeName, ops);
      final item = await repo.create(
        widget.org,
        widget.project,
        widget.typeName,
        ops,
      );
      await FormPrefs.setLastType(widget.org, widget.project, widget.typeName);
      if (!mounted) return;
      _close(item.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${widget.typeName} #${item.id} created'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => router.push('$base/work-items/${item.id}'),
            ),
            // Flutter 3.47 keeps a snackbar with an action open until it is
            // dismissed and queues every later one behind it.
            persist: false,
          ),
        );
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on WorkItemRuleException catch (e) {
      form
        ..applyRuleErrors(e)
        ..revealFirstError();
    } on AdoException catch (e) {
      form.setBanner(e.message);
    } finally {
      if (mounted) form.setSaving(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = _form;
    final saving = form?.saving ?? false;
    final boxed = widget.asDialog || !context.breakpoint.isCompact;
    return PopScope(
      canPop: !(form?.isDirty ?? false) && !saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || saving) return;
        if (await _confirmDiscard() && mounted) _close();
      },
      child: boxed ? _box(context) : _fullScreen(context),
    );
  }

  /// Phone: a route of its own.
  Widget _fullScreen(BuildContext context) =>
      Scaffold(appBar: _appBar(primary: true), body: _content(context));

  /// Tablet: the centered box, either as the dialog the `+` shows or
  /// centered on this route's own page (research/11 §4.5).
  Widget _box(BuildContext context) {
    final box = Dialog(
      insetPadding: const EdgeInsets.all(Spacing.xl),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 960,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        // Fill the width the box is allowed, rather than shrink-wrapping
        // whatever the form happens to measure.
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _appBar(primary: false),
              Expanded(child: _content(context)),
            ],
          ),
        ),
      ),
    );
    return widget.asDialog ? box : Scaffold(body: Center(child: box));
  }

  PreferredSizeWidget _appBar({required bool primary}) {
    final saving = _form?.saving ?? false;
    return AppBar(
      primary: primary,
      leading: IconButton(
        tooltip: 'Close',
        icon: const Icon(Icons.close),
        onPressed: saving
            ? null
            : () async {
                if (await _confirmDiscard() && mounted) _close();
              },
      ),
      title: Text('New ${widget.typeName}'),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
          child: FilledButton(
            onPressed: _form == null || saving ? null : _create,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create'),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final form = _form;
    final saving = form?.saving ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading || saving) const LinearProgressIndicator(),
        if (_error != null)
          Material(
            color: scheme.errorContainer,
            child: ListTile(
              leading: Icon(
                Icons.error_outline,
                color: scheme.onErrorContainer,
              ),
              title: Text(
                _error!,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
              trailing: TextButton(
                onPressed: _loading ? null : _load,
                child: const Text('Retry'),
              ),
            ),
          ),
        if (form == null)
          Expanded(
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator.adaptive()
                  : const SizedBox.shrink(),
            ),
          )
        else
          Expanded(
            child: ContentColumn(
              child: WorkItemFormBody(state: form, sources: _sources),
            ),
          ),
      ],
    );
  }
}
