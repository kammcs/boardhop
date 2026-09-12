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
import '../../shared/unsaved_work.dart';
import 'controls/identity_picker.dart';
import 'controls/tree_picker.dart';
import 'form_prefs.dart';
import 'work_item_form_body.dart';
import 'work_item_form_state.dart';

/// Create a work item of one type (`…/work-items/new?type=Bug`), or edit an
/// existing one through the same form ([WorkItemFormPage.edit],
/// `…/work-items/15542/edit`).
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
  }) : itemId = null;

  /// Edit an existing item: the same form, loaded from the item's own
  /// fields and saved with `test /rev` (research/11 §4.6). The type comes
  /// from the item, so the caller names only its id.
  const WorkItemFormPage.edit({
    super.key,
    required this.org,
    required this.project,
    required int id,
    this.asDialog = false,
  }) : itemId = id,
       typeName = '',
       teamId = null,
       stateName = null,
       lane = null,
       laneField = null,
       parentId = null,
       templateId = null;

  final String org;
  final String project;

  /// The type to create. Empty in edit mode, where the item names it.
  final String typeName;

  /// The item being edited, or null on a new item.
  final int? itemId;

  bool get isEdit => itemId != null;

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

  /// Edit mode: the item at the revision the form is guarded by, and
  /// whether it came from the cache with no connection (the form is then
  /// read-only, research/11 §4.6).
  WorkItem? _item;
  bool _offline = false;

  /// Bumped when a conflict reload replaces the form state, so the body —
  /// and the title's own controller — is rebuilt from the fresh values.
  int _epoch = 0;

  late final UnsavedWorkGuard _guard = UnsavedWorkGuard(
    isDirty: () => _form?.isDirty ?? false,
    confirmLeave: _confirmDiscard,
  );

  @override
  void initState() {
    super.initState();
    UnsavedWork.register(_guard);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    UnsavedWork.unregister(_guard);
    _disposeForm();
    super.dispose();
  }

  /// The app bar reads the form (Save waits for the first change, and shows
  /// the spinner while it saves), so the page rebuilds with it. The body
  /// has its own `AnimatedBuilder`.
  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  void _disposeForm() {
    _form?.removeListener(_onFormChanged);
    _form?.dispose();
    _form = null;
  }

  WorkItemFormRepository get _repo => context.read<WorkItemFormRepository>();

  Future<void> _load() => widget.isEdit ? _loadEdit() : _loadCreate();

  /// The item, its form spec and its own values. The cached copy shows
  /// first when the network is gone, read-only behind a banner: the form
  /// never queues an edit (research/11 §4.6).
  Future<void> _loadEdit() async {
    setState(() {
      _loading = true;
      _error = null;
      _offline = false;
    });
    final repo = _repo;
    final workItems = context.read<WorkItemRepository>();
    try {
      final cached = await workItems
          .watchItem(widget.org, widget.itemId!)
          .first;
      var offline = false;
      WorkItem item;
      try {
        item = await workItems.refreshItem(
          widget.org,
          widget.project,
          widget.itemId!,
        );
      } on AdoNetworkException {
        if (cached == null) rethrow;
        item = cached;
        offline = true;
      }
      final spec = await repo.formSpec(widget.org, widget.project, item.type);
      final sources = await _pickerSources();
      if (!mounted) return;
      final form = WorkItemFormState(
        spec: spec,
        initialValues: valuesFromItem(spec, item),
        formats: formatsFromItem(spec, item),
        isCreate: false,
        original: item,
        readOnly: offline,
        onDependentFieldChanged: _dryRun,
      )..onDiscard = _discardConflict;
      form.onReload = () => _reload(keepChanges: true);
      _disposeForm();
      form.addListener(_onFormChanged);
      setState(() {
        _item = item;
        _offline = offline;
        _epoch++;
        _form = form;
        _sources = sources;
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
    } on AdoNetworkException {
      if (mounted) {
        setState(() => _error = 'Editing needs a connection');
      }
    } on AdoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Re-reads the item after a conflict. [keepChanges] puts the user's
  /// changed fields back on top of the fresh copy; without it their edits
  /// are dropped for the server's values.
  Future<void> _reload({required bool keepChanges}) async {
    final form = _form;
    if (form == null) return;
    final keep = <String, Object?>{
      if (keepChanges)
        for (final reference in form.dirtyFields)
          reference: form.value(reference),
    };
    final workItems = context.read<WorkItemRepository>();
    setState(() => _loading = true);
    try {
      final item = await workItems.refreshItem(
        widget.org,
        widget.project,
        widget.itemId!,
      );
      if (!mounted) return;
      final next = WorkItemFormState(
        spec: form.spec,
        initialValues: {...valuesFromItem(form.spec, item), ...keep},
        formats: formatsFromItem(form.spec, item),
        dirtyFields: keep.keys.toSet(),
        isCreate: false,
        original: item,
        onDependentFieldChanged: _dryRun,
      )..onDiscard = _discardConflict;
      next.onReload = () => _reload(keepChanges: true);
      _disposeForm();
      next.addListener(_onFormChanged);
      setState(() {
        _item = item;
        _epoch++;
        _form = next;
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
      if (mounted) form.setBanner(e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _discardConflict() => _reload(keepChanges: false);

  Future<void> _loadCreate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = _repo;
    final workItems = context.read<WorkItemRepository>();
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
      final sources = await _pickerSources(team: team, defaults: defaults);
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
      _disposeForm();
      form.addListener(_onFormChanged);
      setState(() {
        _form = form;
        _sources = sources;
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

  /// The pickers the header and the controls open: people, the area and
  /// iteration trees and the tag suggestions, all from the team whose
  /// defaults the form follows.
  ///
  /// In edit mode a refusal is not fatal — a form on a cached item simply
  /// opens without its pickers.
  Future<FormSources?> _pickerSources({
    String? team,
    TeamDefaults? defaults,
  }) async {
    final repo = _repo;
    final accountId = AccountScope.of(context);
    final me = context.read<AuthService>().accountById(accountId)?.username;
    try {
      final teamId =
          team ??
          widget.teamId ??
          await repo.defaultTeamId(widget.org, widget.project);
      final teamDefaults =
          defaults ??
          await repo.teamDefaults(widget.org, widget.project, team: teamId);
      // The Graph reads take the project **id**; the route carries the name
      // and `graph/descriptors/{name}` answers HTTP 400, which used to send
      // the people search org-wide (spike s30).
      final projectId = await _projectId(repo);
      final members = await _teamMembers(projectId, teamId);
      final recent = await FormPrefs.recentAssignees(
        widget.org,
        widget.project,
      );
      return FormSources(
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
              repo.teamIterations(widget.org, widget.project, team: teamId),
          currentIterationPath: teamDefaults.currentIterationPath,
          backlogIterationPath: teamDefaults.backlogIterationPath,
        ),
        tags: () => repo.tags(widget.org, widget.project),
        onFormatChosen: (reference, chosen) {
          if (reference == 'System.Description') {
            FormPrefs.setDescriptionFormat(widget.org, widget.project, chosen);
          }
        },
      );
    } on AdoException {
      if (!widget.isEdit) rethrow;
      return null;
    }
  }

  /// The debounced dry run a field with `dependentFields` triggers: the
  /// server re-evaluates its rules and answers with per-field messages
  /// (research/11 §2).
  Future<void> _dryRun() async {
    final form = _form;
    final item = _item;
    if (form == null || form.saving || form.title.isEmpty) return;
    if (widget.isEdit && (item == null || _offline)) return;
    try {
      if (item != null) {
        await _repo.validatePatch(
          widget.org,
          widget.project,
          item,
          form.buildEditOps(item),
        );
      } else {
        await _repo.validate(
          widget.org,
          widget.project,
          widget.typeName,
          form.buildOps(parentUrl: _parentUrl),
        );
      }
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
        values[reference] = decodeFieldValue(
          spec,
          reference,
          field!.defaultValue,
        );
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
        values[reference] = decodeFieldValue(spec, reference, value);
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
      values[entry.key] = decodeFieldValue(spec, entry.key, entry.value);
    }
    if (widget.stateName != null) values['System.State'] = spec.initialState;
    return values;
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
        title: Text(
          widget.isEdit ? 'Discard your changes?' : 'Discard this work item?',
        ),
        content: Text(
          widget.isEdit
              ? 'The item keeps the values it has on the server.'
              : 'It has not been created yet.',
        ),
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

  /// Saves an edit: the dry run with `test /rev`, then the real patch with
  /// only the changed fields. A 412 raises the conflict banner rather than
  /// overwriting whoever else wrote (research/11 §4.6).
  Future<void> _save() async {
    final form = _form;
    final item = _item;
    if (form == null || item == null || form.saving) return;
    form
      ..setConflict(false)
      ..clearServerErrors();
    if (!form.validateLocally()) {
      form.revealFirstError();
      return;
    }
    final ops = form.buildEditOps(item);
    if (ops.length < 2) {
      _close(false);
      return;
    }
    form.setSaving(true);
    final repo = _repo;
    final workItems = context.read<WorkItemRepository>();
    try {
      await repo.validatePatch(widget.org, widget.project, item, ops);
      await workItems.patch(widget.org, widget.project, item, ops);
      if (!mounted) return;
      _close(true);
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
    } on AdoStaleRevisionException {
      form.setConflict(true);
    } on WorkItemRuleException catch (e) {
      form
        ..applyRuleErrors(e)
        ..revealFirstError();
    } on AdoValidationException catch (e) {
      form
        ..applyRuleErrors(WorkItemRuleException.fromValidation(e))
        ..revealFirstError();
    } on AdoNetworkException {
      // The full form is online only: nothing is queued (research/11 §4.6).
      form.setBanner('Editing needs a connection');
    } on AdoException catch (e) {
      form.setBanner(e.message);
    } finally {
      if (mounted) form.setSaving(false);
    }
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
    final form = _form;
    final saving = form?.saving ?? false;
    final edit = widget.isEdit;
    // Create is always available (the local checks say what is missing);
    // Save waits until something actually changed.
    final canSubmit = form != null && !saving && (!edit || form.isDirty);
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
      title: Text(edit ? '#${widget.itemId}' : 'New ${widget.typeName}'),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
          child: FilledButton(
            onPressed: canSubmit ? (edit ? _save : _create) : null,
            child: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(edit ? 'Save' : 'Create'),
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
        // The full form is online only (research/11 §4.6): a cached item
        // opens read-only and says so.
        if (_offline)
          Material(
            color: scheme.secondaryContainer,
            child: ListTile(
              leading: Icon(
                Icons.cloud_off_outlined,
                color: scheme.onSecondaryContainer,
              ),
              title: Text(
                'Editing needs a connection',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
              trailing: TextButton(
                onPressed: _loading ? null : _load,
                child: const Text('Retry'),
              ),
            ),
          ),
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
              // A conflict reload replaces the state: the key rebuilds the
              // body, and with it the title's own controller.
              child: WorkItemFormBody(
                key: ValueKey(_epoch),
                state: form,
                sources: _sources,
              ),
            ),
          ),
      ],
    );
  }
}
