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
import '../widgets/work_item_visuals.dart';
import 'controls/attachments_section.dart';
import 'controls/identity_picker.dart';
import 'controls/links_section.dart';
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
    this.relation,
    this.templateId,
    this.resumeDraft = false,
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
       relation = null,
       templateId = null,
       resumeDraft = false;

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

  /// The item the new one is linked to: its parent by default, or the other
  /// end of a Related link when [relation] is `related` (research/11 §4.1).
  final int? parentId;

  /// `related` for "Add related"; null or `child` for "Add child".
  final String? relation;

  final String? templateId;

  /// Opens with the project's saved draft for this type applied and dirty
  /// (the chooser's "Resume draft" row).
  final bool resumeDraft;

  /// Shown inside `showDialog` rather than as a route: the form pops the
  /// dialog itself and the view behind it stays visible.
  final bool asDialog;

  @override
  State<WorkItemFormPage> createState() => _WorkItemFormPageState();
}

/// What a board column's `+` asked for and the create could not carry: only
/// the type's initial state is legal on a create (spike w18), and the
/// board's lane field is not part of the form's layout, so both are written
/// by a second, `test /rev`-guarded patch (research/11 4.1).
List<Map<String, Object?>> boardFollowUpOps(
  WorkItem created, {
  String? stateName,
  String? laneField,
  String? lane,
}) {
  final ops = <Map<String, Object?>>[];
  if (stateName != null && stateName.isNotEmpty && created.state != stateName) {
    ops.add({'op': 'add', 'path': '/fields/System.State', 'value': stateName});
  }
  if (laneField != null &&
      laneField.isNotEmpty &&
      lane != null &&
      lane.isNotEmpty &&
      created.field<String>(laneField) != lane) {
    ops.add({'op': 'add', 'path': '/fields/$laneField', 'value': lane});
  }
  return ops;
}

/// What the discard dialog of a new item answers.
enum _DraftChoice { cancel, discard, keep }

class _WorkItemFormPageState extends State<WorkItemFormPage> {
  WorkItemFormState? _form;
  FormSources? _sources;

  /// The parent (or related item) a create form was opened from, once it
  /// has been read: the header's "Child of #..." line and the relation the
  /// create patch carries.
  FormLinkTarget? _link;
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
        relations: item.relations,
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
        relations: item.relations,
        // What the user added but has not saved survives the reload; a
        // removal does not, because the fresh list is the authority on
        // what is still there.
        newRelations: [
          for (final value in form.addedRelationValues)
            WorkItemRelation.fromJson(value.cast<String, dynamic>()),
        ],
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
      // The board's lane is a WEF field the layout does not carry, so it
      // never rides in the create patch; the follow-up patch writes it
      // beside the column's state (spike w18).
      if (widget.parentId != null) {
        final parents = await workItems.batch(widget.org, widget.project, [
          widget.parentId!,
        ]);
        final parent = parents.isEmpty ? null : parents.first;
        if (parent != null) {
          _link = FormLinkTarget(
            id: parent.id,
            title: parent.title,
            rel: widget.relation == 'related'
                ? WorkItemRelation.relatedRel
                : WorkItemRelation.parentRel,
            url: parent.url,
          );
          // A child starts where its parent lives (research/11 4.7).
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

      // The project's saved draft for this type, applied last and dirty
      // from the start, so Create is live and closing offers to keep it
      // again (research/11 4.6).
      final draft = widget.resumeDraft
          ? await repo.draft(widget.org, widget.project, widget.typeName)
          : null;

      final values = await _initialValues(spec, prefill);
      final dirty = <String>{};
      final rich = <String>{};
      if (draft != null) {
        for (final entry in draft.values.entries) {
          values[entry.key] = decodeFieldValue(spec, entry.key, entry.value);
          dirty.add(entry.key);
          // A draft keeps long text exactly as the patch would send it, so
          // it is never escaped a second time on the way back out.
          if (spec.fields[entry.key]?.type == FieldType.html) {
            rich.add(entry.key);
          }
        }
      }
      final sources = await _pickerSources(team: team, defaults: defaults);
      final format =
          draft?.formats['System.Description'] ??
          await FormPrefs.descriptionFormat(widget.org, widget.project);

      if (!mounted) return;
      // The "Add child" parent and whatever a resumed draft had uploaded
      // are relations from the start: the Links and Attachments pages show
      // them, and they ride in the create patch (spike w16).
      final link = _link;
      final form = WorkItemFormState(
        spec: spec,
        initialValues: values,
        onDependentFieldChanged: _dryRun,
        formats: {...?draft?.formats, 'System.Description': format},
        dirtyFields: dirty,
        richFields: rich,
        link: link,
        newRelations: [
          if (link?.url != null)
            WorkItemRelation(rel: link!.rel, url: link.url!),
          for (final value in draft?.relations ?? const [])
            WorkItemRelation.fromJson(value.cast<String, dynamic>()),
        ],
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
    final workItems = context.read<WorkItemRepository>();
    final accountId = AccountScope.of(context);
    final auth = context.read<AuthService>();
    final me = auth.accountById(accountId)?.username;
    // Attachment bytes and the images an HTML field embeds are `_apis`
    // routes gated by the token (research/01 §10.3, spike w17).
    final headers = await _authHeaders(auth, accountId);
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
      final visuals = await _visuals(workItems);
      return FormSources(
        links: LinkSource(
          resolve: (ids) => workItems.batch(widget.org, widget.project, ids),
          search: (text) =>
              repo.searchWorkItems(widget.org, widget.project, text),
          open: _openLinked,
          visuals: visuals,
        ),
        attachments: AttachmentSource(
          bytes: repo.attachmentBytes,
          upload: (name, bytes) =>
              repo.uploadAttachment(widget.org, widget.project, name, bytes),
          // On a new item the relation rides in the create patch; on an
          // existing one it is written straight away (research/11 §4.3).
          commit: widget.isEdit ? _commitRelations : null,
          headers: headers,
        ),
        headers: headers,
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

  Future<Map<String, String>> _authHeaders(
    AuthService auth,
    String accountId,
  ) async {
    try {
      final token = await auth.accessToken(accountId: accountId);
      return {'Authorization': 'Bearer $token'};
    } on AdoException {
      // The images then show their placeholder; the form itself still
      // loads from the cache.
      return const {};
    }
  }

  /// Type icons and state colors for the Links rows.
  Future<WorkItemVisuals> _visuals(WorkItemRepository workItems) async {
    try {
      final types = await workItems.types(widget.org, widget.project);
      return WorkItemVisuals({for (final t in types) t.name: t});
    } on AdoException {
      return const WorkItemVisuals({});
    }
  }

  /// Opens a linked item. The dialog stays where it is: the route is pushed
  /// on the shell's navigator, which is where the form's own route lives.
  void _openLinked(int id) => GoRouter.of(
    context,
  ).push('${projectRoute(context, widget.org, widget.project)}/work-items/$id');

  /// Writes the pending **attachment** relations of an existing item at
  /// once, so an uploaded file is never an orphan. Links are not written
  /// here: they wait for Save, as the rest of the form does. The removal
  /// indices come from a fresh read and the patch is guarded by that
  /// revision (research/01 §2.6).
  Future<bool> _commitRelations() async {
    final form = _form;
    final item = _item;
    if (form == null || item == null || !form.hasAttachmentChanges) return true;
    final workItems = context.read<WorkItemRepository>();
    try {
      final fresh = await workItems.refreshItem(
        widget.org,
        widget.project,
        widget.itemId!,
      );
      final ops = form.buildRelationOps(fresh, attachmentsOnly: true);
      if (ops.isEmpty) {
        form.rebaseRelations(fresh.relations);
        return true;
      }
      var saved = await workItems.patch(widget.org, widget.project, fresh, [
        {'op': 'test', 'path': '/rev', 'value': fresh.rev},
        ...ops,
      ]);
      // The patch asks for `$expand=relations`; if it ever answers without
      // them the form would think the write had not landed, so read again
      // rather than rebase on an empty list.
      if (saved.relations.isEmpty) {
        saved = await workItems.refreshItem(
          widget.org,
          widget.project,
          widget.itemId!,
        );
      }
      if (!mounted) return true;
      setState(() => _item = saved);
      form.rebaseRelations(saved.relations);
      return true;
    } on AdoAuthException catch (e) {
      if (mounted) {
        context.read<AuthBloc>().add(
          AuthInteractionRequired(
            e.message,
            accountId: AccountScope.maybeOf(context),
          ),
        );
      }
      return false;
    } on AdoException {
      // The change stays pending and Save will try again.
      return false;
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
          _createOps(form),
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
        }, parentUrl: (_link?.isParent ?? false) ? _link!.url : null),
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
    // A board column's `+` shows where the card will land, not where the
    // server starts it: the state is read-only on create and is patched in
    // as soon as the item exists (spike w18).
    if (widget.stateName != null) values['System.State'] = widget.stateName;
    return values;
  }

  /// The create patch. The link the form was opened from, the links of the
  /// Links page and the uploads of the Attachments page are all relations
  /// of the form state by now, and [WorkItemFormState.buildOps] folds them
  /// in (spike w16: they ride in the create call).
  List<Map<String, Object?>> _createOps(WorkItemFormState form) =>
      form.buildOps();

  /// Keeps what has been typed as the project's draft for this type, so the
  /// chooser can offer it again (research/11 4.6). Never for an edit.
  Future<void> _keepDraft() async {
    final form = _form;
    if (form == null || widget.isEdit) return;
    await _repo.saveDraft(
      widget.org,
      WorkItemDraft(
        project: widget.project,
        type: widget.typeName,
        savedAt: DateTime.now(),
        values: form.draftValues(),
        formats: form.formats,
        // The link the form was opened from, the links added on the Links
        // page and the files already uploaded: resuming keeps all of them.
        relations: form.addedRelationValues,
        prefill: {
          if (widget.teamId != null) 'team': widget.teamId,
          if (widget.stateName != null) 'state': widget.stateName,
          if (widget.lane != null) 'lane': widget.lane,
          if (widget.laneField != null) 'laneField': widget.laneField,
          if (widget.parentId != null) 'parent': '${widget.parentId}',
          if (widget.relation != null) 'rel': widget.relation,
          if (widget.templateId != null) 'template': widget.templateId,
        },
      ),
    );
  }

  /// The dialog pops itself; the route goes through go_router.
  void _close([Object? result]) {
    if (widget.asDialog) {
      Navigator.of(context).pop(result);
    } else {
      context.pop(result);
    }
  }

  /// Closing a dirty form. An edit asks to discard; a new item offers to
  /// keep what has been typed as a draft first (research/11 4.6).
  Future<bool> _confirmDiscard() async {
    final form = _form;
    if (form == null || !form.isDirty) return true;
    if (widget.isEdit) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: const Text('Discard your changes?'),
          content: const Text(
            'The item keeps the values it has on the server.',
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
    final choice = await showDialog<_DraftChoice>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('Keep this work item as a draft?'),
        content: const Text(
          'It has not been created yet. A draft is offered again in the '
          'type chooser.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_DraftChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_DraftChoice.discard),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_DraftChoice.keep),
            child: const Text('Keep draft'),
          ),
        ],
      ),
    );
    switch (choice) {
      case null:
      case _DraftChoice.cancel:
        return false;
      case _DraftChoice.discard:
        return true;
      case _DraftChoice.keep:
        await _keepDraft();
        return true;
    }
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
    form.setSaving(true);
    final repo = _repo;
    final workItems = context.read<WorkItemRepository>();
    try {
      // Removing a relation is positional (research/01 §2.6), so the item
      // is read again and the indices are taken from that copy; the patch
      // is guarded by its revision, and a 412 raises the conflict banner
      // rather than writing against a list that moved.
      var base = item;
      if (form.hasRelationChanges) {
        base = await workItems.refreshItem(
          widget.org,
          widget.project,
          widget.itemId!,
        );
        if (base.rev != item.rev) {
          form.setConflict(true);
          return;
        }
        if (mounted) setState(() => _item = base);
      }
      final ops = form.buildEditOps(base);
      if (ops.length < 2) {
        _close(false);
        return;
      }
      await repo.validatePatch(widget.org, widget.project, base, ops);
      await workItems.patch(widget.org, widget.project, base, ops);
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
    final workItems = context.read<WorkItemRepository>();
    final ops = _createOps(form);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final base = projectRoute(context, widget.org, widget.project);
    void openAction(int id) => router.push('$base/work-items/$id');
    try {
      await repo.validate(widget.org, widget.project, widget.typeName, ops);
      var item = await repo.create(
        widget.org,
        widget.project,
        widget.typeName,
        ops,
      );
      await FormPrefs.setLastType(widget.org, widget.project, widget.typeName);
      await _repo.clearDraft(widget.org, widget.project, widget.typeName);
      // A board column's state and lane are a second call: a new item can
      // only start in the type's initial state (spike w18).
      final followUp = boardFollowUpOps(
        item,
        stateName: widget.stateName,
        laneField: widget.laneField,
        lane: widget.lane,
      );
      if (followUp.isNotEmpty) {
        try {
          item = await workItems.patch(
            widget.org,
            widget.project,
            item,
            followUp,
          );
        } on AdoException catch (e) {
          // The item exists; only the move failed. Say so and leave it
          // open to the user rather than pretending nothing happened.
          if (!mounted) return;
          final created = item;
          _close(created.id);
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  '${widget.typeName} #${created.id} created in '
                  '${created.state} (could not move to ${widget.stateName}): '
                  '${e.message}',
                ),
                action: SnackBarAction(
                  label: 'Open',
                  onPressed: () => openAction(created.id),
                ),
                persist: false,
              ),
            );
          return;
        }
      }
      if (!mounted) return;
      _close(item.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${widget.typeName} #${item.id} created'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => openAction(item.id),
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
    } on AdoNetworkException {
      // Nothing is queued (research/11 4.6), but what was typed need not be
      // lost: the banner offers to keep it as a draft.
      form.setBanner(
        'Creating a work item needs a connection',
        actionLabel: 'Keep draft',
        action: _keepDraftFromBanner,
      );
    } on AdoException catch (e) {
      form.setBanner(
        e.message,
        actionLabel: 'Keep draft',
        action: _keepDraftFromBanner,
      );
    } finally {
      if (mounted) form.setSaving(false);
    }
  }

  /// The banner's "Keep draft": saves and closes the form, as the discard
  /// dialog's Keep draft does.
  Future<void> _keepDraftFromBanner() async {
    await _keepDraft();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Draft kept')));
    _close();
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
