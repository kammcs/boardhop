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

/// The Details page's groups in web order (every column flattened top-down),
/// then the custom pages under their own heading. History, Links and
/// Attachments pages are not part of the create form (research/11 §4.4).
List<FormGroupView> groupViewsFor(FormSpec spec) {
  final out = <FormGroupView>[];

  void addPage(FormPage page, {String? pageLabel}) {
    for (final section in page.sections) {
      for (final group in section.groups) {
        final controls = [
          for (final c in group.controls)
            if (rendersOnCreate(spec, c)) c,
        ];
        if (controls.isNotEmpty) {
          out.add(
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
          out.add(
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
    }
  }

  final details = spec.layout.detailsPage;
  if (details != null) addPage(details);
  for (final page in spec.layout.pages) {
    if (page.kind == FormPageKind.custom && page != details) {
      addPage(page, pageLabel: page.label);
    }
  }
  return out;
}

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
  }) : groups = groupViewsFor(spec),
       _values = {...initialValues} {
    fieldRefs = fieldRefsFor(groups);
  }

  /// Fields the server owns on a new item: the initial state is the only one
  /// it accepts and it picks the reason itself (spike w16).
  static const _neverSent = <String>{'System.State', 'System.Reason'};

  static const dependentDebounce = Duration(milliseconds: 800);

  final FormSpec spec;
  final List<FormGroupView> groups;

  /// Every field the form owns, header first, then the cards in web order.
  late final Set<String> fieldRefs;

  /// Called after [dependentDebounce] when a field with `dependentFields`
  /// changed: the page answers with a `validateOnly` dry run.
  final VoidCallback? onDependentFieldChanged;

  final Map<String, Object?> _values;
  final Map<String, String> _errors = {};
  final Map<String, String> _parseErrors = {};
  final Set<String> _dirty = {};
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
        out[reference] = spec.fields[reference]?.type == FieldType.html
            ? htmlFromPlainText(text)
            : text;
        continue;
      }
      out[reference] = raw;
    }
    return WorkItemFormRepository.buildCreateOps(
      out,
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

  /// Phase 1 stores an HTML field as escaped text in one `<div>`; phase 2
  /// swaps in `html_editor_enhanced` (research/11 §8).
  // TODO(phase2): replace with the rich editor and keep the user's HTML.
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
