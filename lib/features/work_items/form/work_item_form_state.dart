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

/// One card of the phone form: a labeled group of the layout with the
/// controls a new item can actually fill.
///
/// A group whose controls are all panels (links, attachments, deployments,
/// the history log) keeps its label and renders disabled: those need an id,
/// so they only work after the item exists (phase 5).
@immutable
class FormGroupView {
  const FormGroupView({
    required this.label,
    required this.controls,
    this.unavailable = false,
    this.pageLabel,
  });

  final String label;
  final List<FormControl> controls;
  final bool unavailable;

  /// Set on the groups of a custom page, which follow the Details page
  /// under the page's own heading.
  final String? pageLabel;
}

/// True when the control is a field a new work item can be created with.
bool rendersOnCreate(FormSpec spec, FormControl control) {
  if (!control.visible || control.readOnly || control.isPanel) return false;
  if (control.controlType == FormControlType.label ||
      control.controlType == FormControlType.other) {
    return false;
  }
  final reference = control.fieldReferenceName;
  if (reference == null || headerFieldRefs.contains(reference)) return false;
  if (FieldSpec.isBookkeeping(reference)) return false;
  final field = spec.fields[reference];
  if (field == null || field.readOnly) return false;
  return field.type != FieldType.history;
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

/// The create form's pages: Details first, then the custom pages.
///
/// Each page keeps the layout's own columns, so the tablet arrangement can
/// put them next to each other; the phone arrangement flattens them
/// top-down through [FormPageView.groups].
List<FormPageView> pageViewsFor(FormSpec spec) {
  FormPageView? viewOf(FormPage page, {String? pageLabel}) {
    final columns = <FormColumnView>[];
    for (final section in page.sections) {
      final groups = <FormGroupView>[];
      for (final group in section.groups) {
        final controls = [
          for (final c in group.controls)
            if (rendersOnCreate(spec, c)) c,
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
        final panels = group.controls.where((c) => c.isPanel).length;
        if (panels > 0 && panels == group.controls.length) {
          groups.add(
            FormGroupView(
              label: group.label.isEmpty
                  ? (group.controls.first.label ?? 'Links')
                  : group.label,
              controls: const [],
              unavailable: true,
              pageLabel: pageLabel,
            ),
          );
        }
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
  return out;
}

/// The Details page's groups in web order (every column flattened top-down),
/// then the custom pages under their own heading. History, Links and
/// Attachments pages are not part of the create form (research/11 §4.4).
List<FormGroupView> groupViewsFor(FormSpec spec) => [
  for (final page in pageViewsFor(spec)) ...page.groups,
];

/// Every field the form owns: the header's, the state chip's and the field
/// controls of the group cards, in that order.
Set<String> fieldRefsFor(List<FormGroupView> groups) => <String>{
  ...headerValueFields,
  'System.State',
  for (final g in groups)
    for (final c in g.controls) c.fieldReferenceName!,
};

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
    Map<String, String> formats = const {},
  }) : pages = pageViewsFor(spec),
       _formats = {...formats},
       _values = {...initialValues} {
    fieldRefs = fieldRefsFor(groups);
  }

  /// Fields the server owns on a new item: the initial state is the only one
  /// it accepts and it picks the reason itself (spike w16).
  static const _neverSent = <String>{'System.State', 'System.Reason'};

  static const dependentDebounce = Duration(milliseconds: 800);

  final FormSpec spec;

  /// A new item. Phase 3 edits an existing one, where the format is the
  /// item's own and is never chosen in the editor (spike w01).
  final bool isCreate;

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

  final Map<String, Object?> _values;
  final Map<String, String> _errors = {};
  final Map<String, String> _parseErrors = {};
  final Set<String> _dirty = {};

  /// Long-text fields the rich editor filled: their value is already HTML
  /// (or Markdown) and is sent as it stands, never escaped.
  final Set<String> _richFields = {};

  /// `html` or `markdown` per multiline field, for the
  /// `/multilineFieldsFormat` ops of the create patch (spike w01). Only a
  /// field the user switched to Markdown is in here.
  final Map<String, String> _formats;
  Timer? _debounce;

  /// Errors the server raised for fields this form does not show, and other
  /// refusals: a banner under the header.
  String? bannerError;

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

  bool get isDirty => _dirty.isNotEmpty;

  bool get hasErrors => _errors.isNotEmpty;

  Map<String, Object?> get values => Map.unmodifiable(_values);

  String get title => (_values['System.Title'] as String? ?? '').trim();

  String get stateName =>
      _values['System.State'] as String? ?? spec.initialState ?? '';

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

  void setBanner(String? message) {
    bannerError = message;
    notifyListeners();
  }

  /// Required and allowed-value checks, run as the user types and before the
  /// dry run. The server stays the authority on everything else.
  bool validateLocally() {
    _errors
      ..clear()
      ..addAll(_parseErrors);
    for (final reference in fieldRefs) {
      if (_parseErrors.containsKey(reference)) continue;
      if (_neverSent.contains(reference)) continue;
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
      if (_neverSent.contains(reference)) continue;
      if (FieldSpec.isBookkeeping(reference)) continue;
      final raw = _values[reference];
      if (raw == null) continue;
      if (raw is Iterable && raw.isEmpty) continue;
      if (raw is String) {
        final text = raw.trim();
        if (text.isEmpty) continue;
        final isHtmlField = spec.fields[reference]?.type == FieldType.html;
        out[reference] = isHtmlField && !_richFields.contains(reference)
            ? htmlFromPlainText(text)
            : text;
        continue;
      }
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
      relations: relations,
    );
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
