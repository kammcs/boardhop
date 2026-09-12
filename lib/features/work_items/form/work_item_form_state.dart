import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/models/work_item.dart';
import '../../../data/models/work_item_form.dart';
import '../../../data/repositories/work_item_form_repository.dart';

/// Fields the pinned header owns, or that the server sets on a new item:
/// they never appear a second time among the group cards (research/11 §4.4).
const headerFieldRefs = <String>{
  'System.Title',
  'System.Id',
  'System.State',
  'System.Reason',
  'System.AssignedTo',
  'System.AreaPath',
  'System.IterationPath',
  'System.Tags',
  'System.ChangedDate',
};

/// The header's editable fields, in the order the chips sit in.
const headerValueFields = <String>[
  'System.Title',
  'System.AssignedTo',
  'System.AreaPath',
  'System.IterationPath',
  'System.Tags',
];

/// What a group of the layout holds instead of field controls.
enum FormPanelKind {
  /// Field controls, the ordinary case.
  none,

  /// A `LinksControl` over work item links: the Links page, and the
  /// "Related Work" group of the Details page.
  links,

  /// An `AttachmentsControl`: the Attachments page.
  attachments,

  /// A panel Azure DevOps fills from Git and the pipelines (the
  /// "Development" and "Deployment" groups). Shown as a line of text.
  external,
}

/// One card of the phone form: a labeled group of the layout with the
/// controls a new item can actually fill, or one of the panels
/// ([FormGroupView.panel]).
@immutable
class FormGroupView {
  const FormGroupView({
    required this.label,
    required this.controls,
    this.panel = FormPanelKind.none,
    this.pageLabel,
  });

  final String label;
  final List<FormControl> controls;

  /// Set when the group is a panel rather than a stack of field controls.
  final FormPanelKind panel;

  /// Set on the groups of a custom, Links or Attachments page, which follow
  /// the Details page under the page's own heading on a phone.
  final String? pageLabel;

  bool get isPanel => panel != FormPanelKind.none;
}

/// Whether one control of the layout belongs on this form.
typedef ControlFilter = bool Function(FormSpec spec, FormControl control);

/// True when the control is a field a new work item can be created with.
bool rendersOnCreate(FormSpec spec, FormControl control) {
  if (control.readOnly) return false;
  final field = _fieldOf(spec, control);
  return field != null && !field.readOnly;
}

/// True when the control belongs on the edit form: the same fields as on
/// create, plus the read-only ones that carry a value, which the web shows
/// as text (research/11 §4.3).
ControlFilter rendersOnEdit(bool Function(String reference) hasValue) =>
    (spec, control) {
      final field = _fieldOf(spec, control);
      if (field == null) return false;
      if (control.readOnly || field.readOnly) {
        return hasValue(field.referenceName);
      }
      return true;
    };

/// The field a renderable control names, or null when the control is not a
/// field of this form at all (a panel, a label, a header field, one of the
/// server's bookkeeping fields, or the history log).
FieldSpec? _fieldOf(FormSpec spec, FormControl control) {
  if (!control.visible || control.isPanel) return null;
  if (control.controlType == FormControlType.label ||
      control.controlType == FormControlType.other) {
    return null;
  }
  final reference = control.fieldReferenceName;
  if (reference == null || headerFieldRefs.contains(reference)) return null;
  if (FieldSpec.isBookkeeping(reference)) return null;
  final field = spec.fields[reference];
  if (field == null || field.type == FieldType.history) return null;
  return field;
}

/// One column of a page: a layout section with the groups a new item can
/// fill. [percentWidth] is the web's own share of the row, which the tablet
/// arrangement turns into flexes (research/11 §4.5).
@immutable
class FormColumnView {
  const FormColumnView({required this.percentWidth, required this.groups});

  final int percentWidth;
  final List<FormGroupView> groups;
}

/// One tab of the create form: the Details page, then any custom page.
/// History, Links and Attachments are not part of it (research/11 §4.4).
@immutable
class FormPageView {
  const FormPageView({
    required this.label,
    required this.columns,
    this.isDetails = false,
  });

  final String label;
  final List<FormColumnView> columns;
  final bool isDetails;

  /// Every group of the page, columns flattened left to right: the phone
  /// arrangement and the group order phase 1 settled.
  List<FormGroupView> get groups => [
    for (final column in columns) ...column.groups,
  ];

  bool get isEmpty => columns.isEmpty;
}

/// What a group of panels renders as, or null when the form drops it (the
/// history log, which the detail page's discussion covers).
FormPanelKind? panelKindFor(Iterable<FormControl> panels) {
  var kind = FormPanelKind.none;
  for (final control in panels) {
    if (control.controlType == FormControlType.log) continue;
    if (control.isExternalPanel) return FormPanelKind.external;
    switch (control.controlType) {
      case FormControlType.links:
        kind = FormPanelKind.links;
      case FormControlType.attachments:
        kind = FormPanelKind.attachments;
      default:
        break;
    }
  }
  return kind == FormPanelKind.none ? null : kind;
}

/// The form's pages: Details first, then the custom pages, then Links and
/// Attachments (phase 5; History is never shown — the detail page carries
/// the discussion).
///
/// Each page keeps the layout's own columns, so the tablet arrangement can
/// put them next to each other; the phone arrangement flattens them
/// top-down through [FormPageView.groups].
List<FormPageView> pageViewsFor(FormSpec spec, {ControlFilter? renders}) {
  final filter = renders ?? rendersOnCreate;
  FormPageView? viewOf(FormPage page, {String? pageLabel}) {
    final columns = <FormColumnView>[];
    for (final section in page.sections) {
      final groups = <FormGroupView>[];
      for (final group in section.groups) {
        final controls = [
          for (final c in group.controls)
            if (filter(spec, c)) c,
        ];
        if (controls.isNotEmpty) {
          groups.add(
            FormGroupView(
              label: group.label,
              controls: controls,
              pageLabel: pageLabel,
            ),
          );
          continue;
        }
        final panels = group.controls.where((c) => c.isPanel).toList();
        if (panels.isEmpty || panels.length != group.controls.length) continue;
        final kind = panelKindFor(panels);
        if (kind == null) continue;
        var label = group.label.isEmpty
            ? (panels.first.label ?? '')
            : group.label;
        // A page of one panel ("Links", "Attachments") already says it in
        // its own heading or tab.
        if (label.toLowerCase() == (pageLabel ?? '').toLowerCase()) label = '';
        groups.add(
          FormGroupView(
            label: label,
            controls: panels,
            panel: kind,
            pageLabel: pageLabel,
          ),
        );
      }
      if (groups.isNotEmpty) {
        columns.add(
          FormColumnView(percentWidth: section.percentWidth, groups: groups),
        );
      }
    }
    if (columns.isEmpty) return null;
    return FormPageView(
      label: page.label,
      columns: columns,
      isDetails: pageLabel == null,
    );
  }

  final out = <FormPageView>[];
  final details = spec.layout.detailsPage;
  if (details != null) {
    final view = viewOf(details);
    if (view != null) {
      out.add(
        FormPageView(
          label: view.label.isEmpty ? 'Details' : view.label,
          columns: view.columns,
          isDetails: true,
        ),
      );
    }
  }
  for (final page in spec.layout.pages) {
    if (page.kind == FormPageKind.custom && page != details) {
      final view = viewOf(page, pageLabel: page.label);
      if (view != null) out.add(view);
    }
  }
  // Links and Attachments last, in the web's own order (research/11 §3).
  for (final kind in const [FormPageKind.links, FormPageKind.attachments]) {
    for (final page in spec.layout.pages) {
      if (page.kind != kind || page == details) continue;
      final fallback = kind == FormPageKind.links ? 'Links' : 'Attachments';
      final label = page.label.isEmpty ? fallback : page.label;
      final view = viewOf(page, pageLabel: label);
      if (view != null) {
        out.add(
          FormPageView(label: label, columns: view.columns, isDetails: false),
        );
      }
      break;
    }
  }
  return out;
}

/// The Details page's groups in web order (every column flattened top-down),
/// then the custom pages under their own heading. History, Links and
/// Attachments pages are not part of the create form (research/11 §4.4).
List<FormGroupView> groupViewsFor(FormSpec spec, {ControlFilter? renders}) => [
  for (final page in pageViewsFor(spec, renders: renders)) ...page.groups,
];

/// Every field the form owns: the header's, the state chip's and the field
/// controls of the group cards, in that order.
Set<String> fieldRefsFor(
  List<FormGroupView> groups, {
  bool withReason = false,
}) => <String>{
  ...headerValueFields,
  'System.State',
  if (withReason) 'System.Reason',
  for (final g in groups)
    if (!g.isPanel)
      for (final c in g.controls) c.fieldReferenceName!,
};

/// A field value as the controls hold it: identities as [IdentityRef],
/// tags as a list, everything else as it came.
Object? decodeFieldValue(FormSpec spec, String reference, Object? value) {
  if (value == null) return null;
  if (reference == 'System.Tags') {
    return value is List
        ? [for (final t in value) '$t']
        : WorkItemFormRepository.parseTags(value);
  }
  final field = spec.fields[reference];
  if (field != null && (field.isIdentity || field.type == FieldType.identity)) {
    return value is IdentityRef ? value : IdentityRef.fromField(value);
  }
  return value;
}

/// One work item's own fields as the edit form holds them: every field the
/// form owns, identities and tags decoded, long text exactly as it is
/// stored (never converted, research/00 §0).
Map<String, Object?> valuesFromItem(FormSpec spec, WorkItem item) {
  final values = <String, Object?>{};
  for (final reference in fieldRefsFor(
    groupViewsFor(spec, renders: rendersOnEdit((r) => item.fields[r] != null)),
    withReason: true,
  )) {
    final raw = item.fields[reference];
    if (raw == null) continue;
    values[reference] = decodeFieldValue(spec, reference, raw);
  }
  values['System.State'] = item.state;
  return values;
}

/// `multilineFieldsFormat` per long-text field: the item's own format,
/// which the edit form follows and never offers to change (spike w01).
Map<String, String> formatsFromItem(FormSpec spec, WorkItem item) => {
  for (final entry in spec.fields.entries)
    if (entry.value.type.isMultiline) entry.key: item.formatOf(entry.key),
};

/// The item a new one is being linked to: the parent of an "Add child", or
/// the other end of an "Add related" (research/11 §4.1). The header shows it
/// as one line under the type chip.
@immutable
class FormLinkTarget {
  const FormLinkTarget({
    required this.id,
    required this.title,
    required this.rel,
    this.url,
  });

  final int id;
  final String title;

  /// `System.LinkTypes.Hierarchy-Reverse` (the target is the parent) or
  /// `System.LinkTypes.Related`.
  final String rel;
  final String? url;

  bool get isParent => rel == WorkItemRelation.parentRel;

  String get label => isParent ? 'Child of #$id' : 'Related to #$id';
}

/// Values, dirty set, errors and the debounced dry run of one create form.
///
/// The widgets read and write through this notifier only, so the same state
/// drives the phone page and (phase 2) the tablet dialog.
class WorkItemFormState extends ChangeNotifier {
  WorkItemFormState({
    required this.spec,
    Map<String, Object?> initialValues = const {},
    this.onDependentFieldChanged,
    this.isCreate = true,
    this.original,
    this.readOnly = false,
    this.link,
    Map<String, String> formats = const {},
    Set<String> dirtyFields = const {},
    Set<String> richFields = const {},
    List<WorkItemRelation> relations = const [],
    List<WorkItemRelation> newRelations = const [],
  }) : _baseRelations = [...relations],
       pages = pageViewsFor(
         spec,
         renders: isCreate
             ? null
             : rendersOnEdit(
                 (reference) => _isFilled(initialValues[reference]),
               ),
       ),
       _formats = {...formats},
       _dirty = {...dirtyFields},
       _richFields = {...richFields},
       _values = {...initialValues} {
    // Relations the form opens with that are not on the server yet: the
    // parent of an "Add child", and what a resumed draft had uploaded.
    // They ride into the create patch but do not make the form dirty.
    for (final relation in newRelations) {
      if (_hasRelation(relation)) continue;
      _addedRelations.add(relation);
    }
    fieldRefs = fieldRefsFor(groups, withReason: !isCreate);
    for (final group in groups) {
      if (group.isPanel) continue;
      for (final control in group.controls) {
        final reference = control.fieldReferenceName!;
        if (control.readOnly || (spec.fields[reference]?.readOnly ?? false)) {
          _readOnlyRefs.add(reference);
        }
      }
    }
    if (!isCreate) {
      // The item's long text is already HTML (or Markdown) in its own
      // format: never escape it again on the way back out (§4.3).
      for (final reference in fieldRefs) {
        if (spec.fields[reference]?.type == FieldType.html) {
          _richFields.add(reference);
        }
      }
      _originalState = original?.state ?? stateName;
    }
  }

  /// Fields the server owns on a new item: the initial state is the only one
  /// it accepts and it picks the reason itself (spike w16). On an edit both
  /// are the user's to change.
  static const _neverSentOnCreate = <String>{'System.State', 'System.Reason'};

  static bool _isFilled(Object? value) =>
      value != null &&
      !(value is String && value.trim().isEmpty) &&
      !(value is Iterable && value.isEmpty);

  static const dependentDebounce = Duration(milliseconds: 800);

  final FormSpec spec;

  /// A new item. An edit form carries [original] instead, where the format
  /// is the item's own and is never chosen in the editor (spike w01).
  final bool isCreate;

  /// The item being edited, at the revision the form was loaded from: the
  /// `test /rev` guard and the base every patch op is compared against.
  final WorkItem? original;

  /// The form is shown but not editable: the cached copy of an item opened
  /// without a connection (research/11 §4.6, online only).
  final bool readOnly;

  /// The parent (or related item) this new item is being created under.
  final FormLinkTarget? link;

  /// The state the item was loaded in; Reason appears once the user moves
  /// away from it.
  String _originalState = '';

  String get originalState => _originalState;

  /// The server refused the save with HTTP 412: the item moved on. The page
  /// offers Reload (keep my changes on top of the fresh copy) or Discard.
  bool conflict = false;

  /// Wired by the page for the conflict banner's two buttons.
  VoidCallback? onReload;
  VoidCallback? onDiscard;

  /// Details first, then the custom pages: tabs on a tablet, stacked
  /// sections on a phone.
  final List<FormPageView> pages;

  /// Every page's groups flattened, in web order.
  late final List<FormGroupView> groups = [
    for (final page in pages) ...page.groups,
  ];

  /// Every field the form owns, header first, then the cards in web order.
  late final Set<String> fieldRefs;

  /// Called after [dependentDebounce] when a field with `dependentFields`
  /// changed: the page answers with a `validateOnly` dry run.
  final VoidCallback? onDependentFieldChanged;

  /// The relations the item already has on the server (empty on a new
  /// item). Removals are remembered by key and resolved to an index against
  /// a freshly read item at save time (research/01 §2.6).
  final List<WorkItemRelation> _baseRelations;
  final Set<String> _removedRelations = {};
  final List<WorkItemRelation> _addedRelations = [];

  /// The user added or removed a link or an attachment: Save has work to do
  /// even when no field changed.
  bool _relationsDirty = false;

  final Map<String, Object?> _values;
  final Map<String, String> _errors = {};
  final Map<String, String> _parseErrors = {};
  final Set<String> _dirty;

  /// Long-text fields the rich editor filled: their value is already HTML
  /// (or Markdown) and is sent as it stands, never escaped.
  final Set<String> _richFields;

  /// Controls the layout or the process marks read-only: shown as text on an
  /// existing item, never validated and never sent.
  final Set<String> _readOnlyRefs = {};

  /// `html` or `markdown` per multiline field, for the
  /// `/multilineFieldsFormat` ops of the create patch (spike w01). Only a
  /// field the user switched to Markdown is in here.
  final Map<String, String> _formats;
  Timer? _debounce;

  /// Errors the server raised for fields this form does not show, and other
  /// refusals: a banner under the header.
  String? bannerError;

  /// One action the banner offers, "Keep draft" after a save that could not
  /// reach the server (research/11 §4.6).
  String? bannerActionLabel;
  VoidCallback? onBannerAction;

  bool saving = false;

  /// Bumped by the page when the body should scroll the first failing
  /// control into view (research/11 §4.3).
  int revealTick = 0;

  void revealFirstError() {
    revealTick++;
    notifyListeners();
  }

  Object? value(String reference) => _values[reference];

  String? errorFor(String reference) => _errors[reference];

  bool get isDirty => _dirty.isNotEmpty || _relationsDirty;

  // ----------------------------------------------------------- relations

  /// Every relation the form holds: the server's, minus what was removed,
  /// plus what was added. In create mode all of them are additions.
  List<WorkItemRelation> get relations => [
    for (final r in _baseRelations)
      if (!_removedRelations.contains(r.key)) r,
    ..._addedRelations,
  ];

  /// The links to other work items, which the Links page groups by kind.
  List<WorkItemRelation> get linkRelations => [
    for (final r in relations)
      if (r.isWorkItemLink) r,
  ];

  /// The `AttachedFile` relations, which the Attachments page lists.
  List<WorkItemRelation> get attachmentRelations => [
    for (final r in relations)
      if (r.isAttachment) r,
  ];

  bool get hasRelationChanges =>
      _removedRelations.isNotEmpty || _addedRelations.isNotEmpty;

  Set<String> get removedRelationKeys => Set.unmodifiable(_removedRelations);

  /// The additions as the patch carries them.
  List<Map<String, Object?>> get addedRelationValues => [
    for (final r in _addedRelations) relationValue(r),
  ];

  /// An attachment was added or dropped: the only relation change the form
  /// writes without waiting for Save.
  bool get hasAttachmentChanges =>
      _addedRelations.any((r) => r.isAttachment) ||
      _baseRelations.any(
        (r) => r.isAttachment && _removedRelations.contains(r.key),
      );

  static Map<String, Object?> relationValue(WorkItemRelation relation) =>
      <String, Object?>{
        'rel': relation.rel,
        'url': relation.url,
        if (relation.attributes.isNotEmpty) 'attributes': relation.attributes,
      };

  bool _hasRelation(WorkItemRelation relation) =>
      relations.any((r) => r.key == relation.key);

  /// Adds a link or an attachment. A work item has at most one parent, so a
  /// second parent link **replaces** the first (the old one is removed in
  /// the same patch, research/11 §4.3).
  void addRelation(WorkItemRelation relation) {
    if (relation.isParent) {
      for (final existing in relations) {
        if (existing.isParent) _drop(existing);
      }
    }
    if (!_hasRelation(relation)) {
      // Re-adding exactly what was just removed is the removal undone.
      if (!_removedRelations.remove(relation.key)) {
        _addedRelations.add(relation);
      }
    }
    _relationsDirty = true;
    notifyListeners();
  }

  void removeRelation(WorkItemRelation relation) {
    _drop(relation);
    _relationsDirty = true;
    notifyListeners();
  }

  void _drop(WorkItemRelation relation) {
    _addedRelations.removeWhere((r) => r.key == relation.key);
    if (_baseRelations.any((r) => r.key == relation.key)) {
      _removedRelations.add(relation.key);
    }
  }

  /// The item was patched while the form stayed open (an attachment added
  /// to an existing item is written at once, research/11 §4.3): [relations]
  /// becomes the new base, and whatever the patch did **not** carry — the
  /// links, which wait for Save — stays pending on top of it.
  void rebaseRelations(List<WorkItemRelation> relations) {
    final onServer = {for (final r in relations) r.key};
    final stillAdded = [
      for (final r in _addedRelations)
        if (!onServer.contains(r.key)) r,
    ];
    final stillRemoved = {
      for (final key in _removedRelations)
        if (onServer.contains(key)) key,
    };
    _baseRelations
      ..clear()
      ..addAll(relations);
    _addedRelations
      ..clear()
      ..addAll(stillAdded);
    _removedRelations
      ..clear()
      ..addAll(stillRemoved);
    _relationsDirty = hasRelationChanges;
    notifyListeners();
  }

  /// The relation ops of an edit patch, with the removal indices taken from
  /// [fresh] — the item read again immediately before the save.
  ///
  /// [attachmentsOnly] is the immediate write an upload triggers: it must
  /// not drag a link the user added but has not saved along with it.
  List<Map<String, Object?>> buildRelationOps(
    WorkItem fresh, {
    bool attachmentsOnly = false,
  }) => WorkItemFormRepository.buildRelationOps(
    fresh,
    removedKeys: attachmentsOnly
        ? [
            for (final r in fresh.relations)
              if (r.isAttachment && _removedRelations.contains(r.key)) r.key,
          ]
        : _removedRelations,
    additions: attachmentsOnly
        ? [
            for (final r in _addedRelations)
              if (r.isAttachment) relationValue(r),
          ]
        : addedRelationValues,
  );

  /// The fields the user changed, kept across a conflict reload.
  Set<String> get dirtyFields => Set.unmodifiable(_dirty);

  bool isDirtyField(String reference) => _dirty.contains(reference);

  /// True for a control the process or the layout marks read-only: the edit
  /// form shows its value as text (research/11 §4.3).
  bool isReadOnlyField(String reference) => _readOnlyRefs.contains(reference);

  bool get hasErrors => _errors.isNotEmpty;

  /// No control takes input: a save is in flight, or the form opened on a
  /// cached copy with no connection.
  bool get locked => saving || readOnly;

  Map<String, Object?> get values => Map.unmodifiable(_values);

  String get title => (_values['System.Title'] as String? ?? '').trim();

  String get stateName =>
      _values['System.State'] as String? ?? spec.initialState ?? '';

  String? get reason => _values['System.Reason'] as String?;

  /// The states this item may move to, the current one included when Azure
  /// DevOps lists it (spike w18); empty on a new item, whose state the
  /// server owns.
  List<String> get legalTransitions =>
      isCreate ? const [] : spec.transitionsFrom(stateName);

  /// Reason follows a transition: the web reveals it as soon as the state
  /// moves, and the server picks the default when none is sent.
  bool get showReason => !isCreate && stateName != _originalState;

  /// Moves the item to another state. The reason of the state it came from
  /// never travels with it: it is cleared so the server can pick the
  /// default for the new state unless the user names one.
  void setStateName(String next) {
    if (next == stateName) return;
    // The reason of the state it came from is dropped, not cleared on the
    // server: an unsent Reason lets the server pick the new state's default
    // (spike w18: New → Active came back with "Approved").
    _values['System.Reason'] = null;
    _dirty.remove('System.Reason');
    _errors.remove('System.Reason');
    setValue('System.State', next);
  }

  void setConflict(bool value) {
    conflict = value;
    if (value) bannerError = null;
    notifyListeners();
  }

  List<String> get tags {
    final raw = _values['System.Tags'];
    if (raw is List) return [for (final t in raw) '$t'];
    return WorkItemFormRepository.parseTags(raw);
  }

  IdentityRef? get assignedTo {
    final raw = _values['System.AssignedTo'];
    return raw is IdentityRef ? raw : IdentityRef.fromField(raw);
  }

  /// The first field with an error, in form order, for scroll-into-view.
  String? get firstErrorField {
    for (final reference in fieldRefs) {
      if (_errors.containsKey(reference)) return reference;
    }
    return _errors.keys.firstOrNull;
  }

  void setValue(String reference, Object? next, {bool markDirty = true}) {
    _values[reference] = next;
    if (markDirty) _dirty.add(reference);
    _errors.remove(reference);
    _parseErrors.remove(reference);
    bannerError = null;
    notifyListeners();
    final field = spec.fields[reference];
    if (markDirty && field != null && field.dependentFields.isNotEmpty) {
      _debounce?.cancel();
      _debounce = Timer(
        dependentDebounce,
        () => onDependentFieldChanged?.call(),
      );
    }
  }

  /// The rich editor's answer for a long-text field: the value is content
  /// in [format] and goes into the patch verbatim.
  void setRichValue(
    String reference,
    String content, {
    String format = 'html',
  }) {
    _richFields.add(reference);
    setFormat(reference, format);
    setValue(reference, content);
  }

  /// `html` or `markdown` for a multiline field; html unless the user chose
  /// otherwise on this new item.
  String formatOf(String reference) => _formats[reference] ?? 'html';

  bool isMarkdown(String reference) => formatOf(reference) == 'markdown';

  /// Markdown is only offered for the description of a new item (spike
  /// w01); everything else follows the item's format map.
  bool canChooseFormat(String reference) =>
      isCreate && reference == 'System.Description';

  /// Switches a long-text field between the rich editor and Markdown. The
  /// content is never converted (research/00 §0, "Rich text"): the field is
  /// cleared when the format changes with content in the old one, so no
  /// HTML is ever stored as Markdown or the other way round.
  void setFormat(String reference, String format) {
    final next = format == 'markdown' ? 'markdown' : 'html';
    if (formatOf(reference) == next) return;
    _formats[reference] = next;
    notifyListeners();
  }

  /// A value the user typed that is not a number yet: kept apart from the
  /// rule errors so a later [validateLocally] does not drop it.
  void setParseError(String reference, String? message) {
    if (message == null) {
      _parseErrors.remove(reference);
      _errors.remove(reference);
    } else {
      _parseErrors[reference] = message;
      _errors[reference] = message;
    }
    notifyListeners();
  }

  void setSaving(bool value) {
    saving = value;
    notifyListeners();
  }

  void setBanner(String? message, {String? actionLabel, VoidCallback? action}) {
    bannerError = message;
    bannerActionLabel = message == null ? null : actionLabel;
    onBannerAction = message == null ? null : action;
    notifyListeners();
  }

  /// The values a draft keeps: everything the patch would send, encoded the
  /// way the patch encodes it (identities as `"Name <unique>"`, tags
  /// joined, dates ISO), so the draft is plain JSON.
  Map<String, Object?> draftValues() {
    final out = <String, Object?>{};
    for (final reference in fieldRefs) {
      if (isCreate && _neverSentOnCreate.contains(reference)) continue;
      if (FieldSpec.isBookkeeping(reference)) continue;
      final raw = _sendable(reference);
      if (raw == null) continue;
      out[reference] = WorkItemFormRepository.encodeValue(reference, raw);
    }
    return out;
  }

  /// `html` or `markdown` per field the user chose a format for.
  Map<String, String> get formats => Map.unmodifiable(_formats);

  /// Required and allowed-value checks, run as the user types and before the
  /// dry run. The server stays the authority on everything else.
  bool validateLocally() {
    _errors
      ..clear()
      ..addAll(_parseErrors);
    for (final reference in fieldRefs) {
      if (_parseErrors.containsKey(reference)) continue;
      if (isCreate && _neverSentOnCreate.contains(reference)) continue;
      if (reference == 'System.Reason' && !showReason) continue;
      if (_readOnlyRefs.contains(reference)) continue;
      final field = spec.fields[reference];
      if (field == null) continue;
      final value = _values[reference];
      final empty =
          value == null ||
          (value is String && value.trim().isEmpty) ||
          (value is Iterable && value.isEmpty);
      if (field.alwaysRequired && empty) {
        _errors[reference] = '${field.name} is required';
        continue;
      }
      if (empty || field.allowedValues.isEmpty || allowsFreeText(field)) {
        continue;
      }
      final text = value is String ? value : '$value';
      if (!field.allowedValues.contains(text)) {
        _errors[reference] = 'Pick one of the allowed values';
      }
    }
    notifyListeners();
    return _errors.isEmpty;
  }

  /// Rule errors from a refused dry run or save: under their field when the
  /// form shows it, in the banner otherwise.
  void applyRuleErrors(WorkItemRuleException error) {
    _errors
      ..clear()
      ..addAll(_parseErrors);
    final elsewhere = <String>[];
    for (final e in error.errors) {
      final message = e.message.isEmpty ? 'This value was refused' : e.message;
      if (fieldRefs.contains(e.fieldReferenceName)) {
        _errors[e.fieldReferenceName] = message;
      } else {
        final name =
            spec.fields[e.fieldReferenceName]?.name ?? e.fieldReferenceName;
        elsewhere.add('$name: $message');
      }
    }
    bannerError = elsewhere.isNotEmpty
        ? elsewhere.join('\n')
        : (error.errors.isEmpty ? error.message : null);
    notifyListeners();
  }

  /// Clears what the server said, keeping what the user has typed wrong.
  void clearServerErrors() {
    _errors
      ..clear()
      ..addAll(_parseErrors);
    bannerError = null;
    notifyListeners();
  }

  /// The JSON Patch for the dry run and the create, built through phase 0's
  /// [WorkItemFormRepository.buildCreateOps].
  List<Map<String, Object?>> buildOps({
    String? parentUrl,
    List<Map<String, Object?>> relations = const [],
  }) {
    final out = <String, Object?>{};
    for (final reference in fieldRefs) {
      if (_neverSentOnCreate.contains(reference)) continue;
      if (FieldSpec.isBookkeeping(reference)) continue;
      final raw = _sendable(reference);
      if (raw == null) continue;
      out[reference] = raw;
    }
    final markdown = <String>{
      for (final entry in _formats.entries)
        if (entry.value == 'markdown' && out.containsKey(entry.key)) entry.key,
    };
    return WorkItemFormRepository.buildCreateOps(
      out,
      markdownDescription: markdown.contains('System.Description'),
      markdownFields: markdown.difference(const {'System.Description'}),
      parentUrl: parentUrl,
      // The links and attachments of the Links and Attachments pages ride
      // in the create call (spike w16), after whatever the caller adds.
      relations: [...relations, ...addedRelationValues],
    );
  }

  /// The edit patch: `test /rev` and only the fields whose value actually
  /// changed, built through phase 0's
  /// [WorkItemFormRepository.buildEditOps] (research/11 §4.6).
  ///
  /// A field the user never touched is only offered when it has a value, so
  /// a field the form shows empty is never cleared behind their back; a
  /// field they emptied themselves is dirty and is cleared.
  List<Map<String, Object?>> buildEditOps([WorkItem? item]) {
    final base = item ?? original;
    if (base == null) return const [];
    final out = <String, Object?>{};
    for (final reference in fieldRefs) {
      if (FieldSpec.isBookkeeping(reference)) continue;
      if (_readOnlyRefs.contains(reference)) continue;
      if (reference == 'System.Reason' && !showReason) continue;
      final dirty = _dirty.contains(reference);
      final raw = _sendable(reference);
      if (raw == null && !dirty) continue;
      out[reference] = raw ?? '';
    }
    return WorkItemFormRepository.buildEditOps(
      base,
      out,
      formats: {
        for (final entry in _formats.entries)
          if (out.containsKey(entry.key)) entry.key: entry.value,
      },
      // Removal is positional, so the indices come from the item this
      // patch is guarded by (research/01 §2.6).
      relationOps: hasRelationChanges ? buildRelationOps(base) : const [],
    );
  }

  /// One value as the patch carries it, or null when there is nothing to
  /// send: empty strings and empty lists are "no value".
  Object? _sendable(String reference) {
    final raw = _values[reference];
    if (raw == null) return null;
    if (raw is Iterable && raw.isEmpty) return null;
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return null;
      final isHtmlField = spec.fields[reference]?.type == FieldType.html;
      return isHtmlField && !_richFields.contains(reference)
          ? htmlFromPlainText(text)
          : text;
    }
    return raw;
  }

  /// Free text next to the allowed values. `FieldSpec` carries no
  /// `isLimitedToAllowedValues` (it is not in the type's field read), so a
  /// field the process declares a picklist is closed and anything else — an
  /// integer field such as Priority — keeps the escape hatch the web has.
  static bool allowsFreeText(FieldSpec field) =>
      !field.isPicklist && !field.type.isPicklistType;

  /// An HTML field filled as plain text (a widget test, or a control the
  /// rich editor never opened) is escaped into one `<div>`; content the
  /// rich editor produced goes through [setRichValue] and is sent as it is.
  static String htmlFromPlainText(String text) {
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\r\n', '\n')
        .replaceAll('\n', '<br>');
    return '<div>$escaped</div>';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
