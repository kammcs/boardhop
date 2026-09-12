import 'package:equatable/equatable.dart';
import 'package:xml/xml.dart';

import '../../core/http/ado_exceptions.dart';
import 'work_item.dart';

/// Field types from `GET {org}/_apis/wit/fields` (research/11 §2). The per
/// type field list (`workitemtypes/{type}/fields?$expand=All`) carries the
/// rules but no type, so the two are merged into one [FieldSpec].
enum FieldType {
  string('string'),
  integer('integer'),
  decimal('double'),
  dateTime('dateTime'),
  plainText('plainText'),
  html('html'),
  treePath('treePath'),
  history('history'),
  boolean('boolean'),
  identity('identity'),
  picklistString('picklistString'),
  picklistInteger('picklistInteger'),
  picklistDouble('picklistDouble'),
  unknown('');

  const FieldType(this.wireName);

  /// The value Azure DevOps sends in `type`.
  final String wireName;

  static FieldType parse(Object? value) {
    final name = (value as String? ?? '').toLowerCase();
    for (final t in values) {
      if (t.wireName.toLowerCase() == name) return t;
    }
    return unknown;
  }

  bool get isNumeric =>
      this == integer ||
      this == decimal ||
      this == picklistInteger ||
      this == picklistDouble;

  bool get isPicklistType =>
      this == picklistString ||
      this == picklistInteger ||
      this == picklistDouble;

  /// Long text: rendered in an editor rather than a one-line field.
  bool get isMultiline => this == html || this == plainText || this == history;
}

/// One field of one work item type: the org's type information merged with
/// the type's rules (`alwaysRequired`, `allowedValues`, `defaultValue`,
/// `helpText`, `dependentFields`).
class FieldSpec extends Equatable {
  const FieldSpec({
    required this.referenceName,
    required this.name,
    this.type = FieldType.string,
    this.isIdentity = false,
    this.isPicklist = false,
    this.readOnly = false,
    this.alwaysRequired = false,
    this.allowedValues = const [],
    this.allowedIdentities = const [],
    this.defaultValue,
    this.helpText,
    this.dependentFields = const [],
  });

  /// From `workitemtypes/{type}/fields?$expand=All`: rules only, no type.
  factory FieldSpec.fromTypeField(Map<String, dynamic> json) {
    final values = <String>[];
    final identities = <IdentityRef>[];
    for (final v in (json['allowedValues'] as List?) ?? const []) {
      if (v is Map) {
        // Identity fields answer with objects (they are empty in both
        // puremedia projects, spike s25, but the shape is documented).
        identities.add(IdentityRef.fromJson(v.cast<String, dynamic>()));
      } else if (v != null) {
        values.add(v.toString());
      }
    }
    return FieldSpec(
      referenceName: json['referenceName'] as String? ?? '',
      name: json['name'] as String? ?? '',
      alwaysRequired: json['alwaysRequired'] as bool? ?? false,
      readOnly: json['readOnly'] as bool? ?? false,
      allowedValues: values,
      allowedIdentities: identities,
      defaultValue: json['defaultValue'],
      helpText: json['helpText'] as String?,
      dependentFields: [
        for (final d in (json['dependentFields'] as List?) ?? const [])
          if (d is Map && d['referenceName'] is String)
            d['referenceName'] as String,
      ],
    );
  }

  /// From the org-wide `wit/fields` list: type information only.
  factory FieldSpec.fromOrgField(Map<String, dynamic> json) => FieldSpec(
    referenceName: json['referenceName'] as String? ?? '',
    name: json['name'] as String? ?? '',
    type: FieldType.parse(json['type']),
    isIdentity: json['isIdentity'] as bool? ?? false,
    isPicklist: json['isPicklist'] as bool? ?? false,
    readOnly: json['readOnly'] as bool? ?? false,
  );

  factory FieldSpec.fromJson(Map<String, dynamic> json) => FieldSpec(
    referenceName: json['referenceName'] as String? ?? '',
    name: json['name'] as String? ?? '',
    type: FieldType.parse(json['type']),
    isIdentity: json['isIdentity'] as bool? ?? false,
    isPicklist: json['isPicklist'] as bool? ?? false,
    readOnly: json['readOnly'] as bool? ?? false,
    alwaysRequired: json['alwaysRequired'] as bool? ?? false,
    allowedValues: [
      for (final v in (json['allowedValues'] as List?) ?? const []) '$v',
    ],
    allowedIdentities: [
      for (final v in (json['allowedIdentities'] as List?) ?? const [])
        if (v is Map) IdentityRef.fromJson(v.cast<String, dynamic>()),
    ],
    defaultValue: json['defaultValue'],
    helpText: json['helpText'] as String?,
    dependentFields: [
      for (final v in (json['dependentFields'] as List?) ?? const []) '$v',
    ],
  );

  final String referenceName;
  final String name;
  final FieldType type;
  final bool isIdentity;
  final bool isPicklist;
  final bool readOnly;
  final bool alwaysRequired;

  /// Scalar allowed values; empty when the field is free text.
  final List<String> allowedValues;

  /// Allowed values of an identity field, which come back as objects.
  final List<IdentityRef> allowedIdentities;

  final Object? defaultValue;
  final String? helpText;

  /// Fields whose rules may change when this one changes: the trigger for a
  /// debounced `validateOnly` run (research/11 §2).
  final List<String> dependentFields;

  bool get hasAllowedValues =>
      allowedValues.isNotEmpty || allowedIdentities.isNotEmpty;

  /// Type information comes from the org field list, rules from the type's
  /// field list; this merges the org copy into a rules copy.
  FieldSpec withOrgField(FieldSpec? org) => org == null
      ? this
      : FieldSpec(
          referenceName: referenceName,
          name: name.isEmpty ? org.name : name,
          type: org.type,
          isIdentity: org.isIdentity,
          isPicklist: org.isPicklist || isPicklist,
          readOnly: org.readOnly || readOnly,
          alwaysRequired: alwaysRequired,
          allowedValues: allowedValues,
          allowedIdentities: allowedIdentities,
          defaultValue: defaultValue,
          helpText: helpText,
          dependentFields: dependentFields,
        );

  Map<String, dynamic> toJson() => {
    'referenceName': referenceName,
    'name': name,
    'type': type.wireName,
    if (isIdentity) 'isIdentity': true,
    if (isPicklist) 'isPicklist': true,
    if (readOnly) 'readOnly': true,
    if (alwaysRequired) 'alwaysRequired': true,
    if (allowedValues.isNotEmpty) 'allowedValues': allowedValues,
    if (allowedIdentities.isNotEmpty)
      'allowedIdentities': [
        for (final i in allowedIdentities)
          {
            'displayName': i.displayName,
            if (i.uniqueName != null) 'uniqueName': i.uniqueName,
            if (i.id != null) 'id': i.id,
            if (i.descriptor != null) 'descriptor': i.descriptor,
            if (i.imageUrl != null) 'imageUrl': i.imageUrl,
          },
      ],
    if (defaultValue != null) 'defaultValue': defaultValue,
    if (helpText != null) 'helpText': helpText,
    if (dependentFields.isNotEmpty) 'dependentFields': dependentFields,
  };

  /// Fields the server maintains, which a form neither shows nor sends:
  /// counts, the classification ids and levels, revisions and the dates and
  /// identities Azure DevOps stamps itself (research/11 §4.3).
  static bool isBookkeeping(String referenceName) {
    final leaf = referenceName.split('.').last;
    if (leaf.endsWith('Count')) return true;
    if (leaf.endsWith('Id')) return true;
    if (RegExp(r'Level\d+$').hasMatch(leaf)) return true;
    return _bookkeepingFields.contains(referenceName);
  }

  static const _bookkeepingFields = <String>{
    'System.Rev',
    'System.Watermark',
    'System.History',
    'System.NodeName',
    'System.TeamProject',
    'System.WorkItemType',
    'System.Parent',
    'System.AuthorizedAs',
    'System.AuthorizedDate',
    'System.ChangedBy',
    'System.ChangedDate',
    'System.CreatedBy',
    'System.CreatedDate',
    'System.RevisedDate',
    'System.BoardColumn',
    'System.BoardColumnDone',
    'System.BoardLane',
    'Microsoft.VSTS.Common.ActivatedBy',
    'Microsoft.VSTS.Common.ActivatedDate',
    'Microsoft.VSTS.Common.ClosedBy',
    'Microsoft.VSTS.Common.ClosedDate',
    'Microsoft.VSTS.Common.ResolvedBy',
    'Microsoft.VSTS.Common.ResolvedDate',
    'Microsoft.VSTS.Common.StateChangeDate',
    'Microsoft.VSTS.Common.StackRank',
    'Microsoft.VSTS.Common.BacklogPriority',
  };

  @override
  List<Object?> get props => [
    referenceName,
    name,
    type,
    isIdentity,
    isPicklist,
    readOnly,
    alwaysRequired,
    allowedValues,
    allowedIdentities,
    defaultValue,
    helpText,
    dependentFields,
  ];
}

/// Control kinds met in the legacy `<FORM><Layout>` tree (spike s26) and in
/// the Processes layout API (spike s24); anything else is [other].
enum FormControlType {
  field('FieldControl'),
  html('HtmlFieldControl'),
  dateTime('DateTimeControl'),
  classification('WorkItemClassificationControl'),
  links('LinksControl'),
  attachments('AttachmentsControl'),
  label('LabelControl'),
  log('WorkItemLogControl'),
  deployments('DeploymentsControl'),
  other('');

  const FormControlType(this.wireName);

  final String wireName;

  static FormControlType parse(Object? value) {
    final name = (value as String? ?? '').toLowerCase();
    for (final t in values) {
      if (t != other && t.wireName.toLowerCase() == name) return t;
    }
    return other;
  }
}

enum FormPageKind { details, history, links, attachments, custom }

/// One control of the form: a field, or one of the built-in panels (links,
/// attachments, the history log, the deployments panel).
class FormControl extends Equatable {
  const FormControl({
    this.fieldReferenceName,
    this.label,
    this.controlType = FormControlType.field,
    this.readOnly = false,
    this.visible = true,
    this.emptyText,
  });

  factory FormControl.fromJson(Map<String, dynamic> json) => FormControl(
    fieldReferenceName: json['field'] as String?,
    label: json['label'] as String?,
    controlType: FormControlType.parse(json['type']),
    readOnly: json['readOnly'] as bool? ?? false,
    visible: json['visible'] as bool? ?? true,
    emptyText: json['emptyText'] as String?,
  );

  /// `<Control Label="Assi&amp;gned To" FieldName="System.AssignedTo"
  /// Type="FieldControl" EmptyText="Unassigned" />`
  factory FormControl.fromXml(XmlElement element) => FormControl(
    fieldReferenceName: _blankToNull(element.getAttribute('FieldName')),
    label: stripAccelerator(element.getAttribute('Label')),
    controlType: FormControlType.parse(element.getAttribute('Type')),
    readOnly: _isTrue(element.getAttribute('ReadOnly')),
    visible: !_isTrue(element.getAttribute('Hidden')),
    emptyText: _blankToNull(element.getAttribute('EmptyText')),
  );

  /// Field reference name, or the pseudo-name of a panel (`Development`,
  /// `Related Work`, `Deployments`), or null.
  final String? fieldReferenceName;
  final String? label;
  final FormControlType controlType;
  final bool readOnly;
  final bool visible;

  /// Placeholder the web shows in an empty control ("Enter title here").
  final String? emptyText;

  /// A `LabelControl` with neither label nor field: the web's vertical
  /// spacer in the header, which the app drops.
  bool get isSpacer =>
      controlType == FormControlType.label &&
      (label == null || label!.isEmpty) &&
      fieldReferenceName == null;

  /// True for the panels that are not a single field value.
  bool get isPanel =>
      controlType == FormControlType.links ||
      controlType == FormControlType.attachments ||
      controlType == FormControlType.log ||
      controlType == FormControlType.deployments;

  Map<String, dynamic> toJson() => {
    if (fieldReferenceName != null) 'field': fieldReferenceName,
    if (label != null) 'label': label,
    'type': controlType.wireName,
    if (readOnly) 'readOnly': true,
    if (!visible) 'visible': false,
    if (emptyText != null) 'emptyText': emptyText,
  };

  /// Labels carry Windows accelerators (`Assi&gned To`, `&&` for a literal
  /// ampersand).
  static String? stripAccelerator(String? label) {
    if (label == null) return null;
    final out = StringBuffer();
    for (var i = 0; i < label.length; i++) {
      if (label[i] != '&') {
        out.write(label[i]);
      } else if (i + 1 < label.length && label[i + 1] == '&') {
        out.write('&');
        i++;
      }
    }
    return out.toString();
  }

  static String? _blankToNull(String? s) => (s == null || s.isEmpty) ? null : s;

  static bool _isTrue(String? s) => (s ?? '').toLowerCase() == 'true';

  @override
  List<Object?> get props => [
    fieldReferenceName,
    label,
    controlType,
    readOnly,
    visible,
    emptyText,
  ];
}

/// A labeled card of controls. An anonymous group (the wrappers the legacy
/// layout nests three deep) keeps an empty label.
class FormGroup extends Equatable {
  const FormGroup({required this.label, this.controls = const []});

  factory FormGroup.fromJson(Map<String, dynamic> json) => FormGroup(
    label: json['label'] as String? ?? '',
    controls: [
      for (final c in (json['controls'] as List?) ?? const [])
        if (c is Map) FormControl.fromJson(c.cast<String, dynamic>()),
    ],
  );

  final String label;
  final List<FormControl> controls;

  Map<String, dynamic> toJson() => {
    'label': label,
    'controls': [for (final c in controls) c.toJson()],
  };

  @override
  List<Object?> get props => [label, controls];
}

/// A column of one page, with the web's percent width (50/50 on the Details
/// page of a stock type, 100 elsewhere).
class FormSection extends Equatable {
  const FormSection({this.percentWidth = 100, this.groups = const []});

  factory FormSection.fromJson(Map<String, dynamic> json) => FormSection(
    percentWidth: (json['percentWidth'] as num?)?.toInt() ?? 100,
    groups: [
      for (final g in (json['groups'] as List?) ?? const [])
        if (g is Map) FormGroup.fromJson(g.cast<String, dynamic>()),
    ],
  );

  final int percentWidth;
  final List<FormGroup> groups;

  Map<String, dynamic> toJson() => {
    'percentWidth': percentWidth,
    'groups': [for (final g in groups) g.toJson()],
  };

  @override
  List<Object?> get props => [percentWidth, groups];
}

/// One tab of the form: Details, then any custom pages, then History, Links
/// and Attachments.
class FormPage extends Equatable {
  const FormPage({
    required this.label,
    required this.kind,
    this.sections = const [],
  });

  factory FormPage.fromJson(Map<String, dynamic> json) => FormPage(
    label: json['label'] as String? ?? '',
    kind: FormPageKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => FormPageKind.custom,
    ),
    sections: [
      for (final s in (json['sections'] as List?) ?? const [])
        if (s is Map) FormSection.fromJson(s.cast<String, dynamic>()),
    ],
  );

  final String label;
  final FormPageKind kind;

  /// Top-level columns, each holding this page's groups in web order.
  final List<FormSection> sections;

  List<FormControl> get controls => [
    for (final s in sections)
      for (final g in s.groups) ...g.controls,
  ];

  Map<String, dynamic> toJson() => {
    'label': label,
    'kind': kind.name,
    'sections': [for (final s in sections) s.toJson()],
  };

  @override
  List<Object?> get props => [label, kind, sections];
}

/// The form tree of one work item type: the header controls the web pins
/// above the tabs, then one page per tab.
///
/// Parsed from the type's `xmlForm` (spike s26), which is the legacy
/// `<FORM><Layout>` tree and is the only layout source that works for stock
/// and customized types alike — the Processes layout API refuses locked
/// types with VS403115 (spike s24).
class FormLayout extends Equatable {
  const FormLayout({this.header = const [], this.pages = const []});

  factory FormLayout.fromJson(Map<String, dynamic> json) => FormLayout(
    header: [
      for (final c in (json['header'] as List?) ?? const [])
        if (c is Map) FormControl.fromJson(c.cast<String, dynamic>()),
    ],
    pages: [
      for (final p in (json['pages'] as List?) ?? const [])
        if (p is Map) FormPage.fromJson(p.cast<String, dynamic>()),
    ],
  );

  /// Parses `xmlForm`; null when it is missing, malformed or has no layout,
  /// which is what puts [FormSpec] on the field-list fallback.
  static FormLayout? tryParse(String? xmlForm) {
    if (xmlForm == null || xmlForm.trim().isEmpty) return null;
    try {
      final document = XmlDocument.parse(xmlForm);
      final layout =
          document.findAllElements('WebLayout').firstOrNull ??
          document.findAllElements('Layout').firstOrNull;
      if (layout == null) return null;
      final parsed = _fromLayoutElement(layout);
      return parsed.isEmpty ? null : parsed;
    } catch (_) {
      return null;
    }
  }

  /// Controls above the tabs: title and id, then assigned to, state,
  /// reason, area, iteration and the last-changed date.
  final List<FormControl> header;
  final List<FormPage> pages;

  bool get isEmpty => header.isEmpty && pages.isEmpty;

  FormPage? get detailsPage {
    for (final p in pages) {
      if (p.kind == FormPageKind.details) return p;
    }
    return pages.isEmpty ? null : pages.first;
  }

  List<FormPage> get pagesOfKind =>
      pages.where((p) => p.kind != FormPageKind.history).toList();

  Map<String, dynamic> toJson() => {
    'header': [for (final c in header) c.toJson()],
    'pages': [for (final p in pages) p.toJson()],
  };

  static FormLayout _fromLayoutElement(XmlElement layout) {
    final header = <FormControl>[];
    final pages = <FormPage>[];
    for (final child in layout.childElements) {
      if (child.localName == 'TabGroup') {
        var index = 0;
        for (final tab in child.childElements) {
          if (tab.localName != 'Tab') continue;
          pages.add(_page(tab, index++));
        }
      } else {
        _controlsInto(child, header);
      }
    }
    return FormLayout(header: header, pages: pages);
  }

  static void _controlsInto(XmlElement element, List<FormControl> sink) {
    for (final child in element.childElements) {
      if (child.localName == 'Control') {
        final control = FormControl.fromXml(child);
        if (!control.isSpacer) sink.add(control);
      } else {
        _controlsInto(child, sink);
      }
    }
  }

  static FormPage _page(XmlElement tab, int index) {
    final sections = <FormSection>[];
    for (final child in tab.childElements) {
      final columns = child.localName == 'Group' && _label(child) == null
          ? child.childElements.where((e) => e.localName == 'Column').toList()
          : const <XmlElement>[];
      if (columns.isEmpty) {
        final groups = _groupsIn(child);
        if (groups.isNotEmpty) {
          sections.add(
            FormSection(percentWidth: _percentWidth(child), groups: groups),
          );
        }
        continue;
      }
      for (final column in columns) {
        final groups = _groupsIn(column);
        if (groups.isNotEmpty) {
          sections.add(
            FormSection(percentWidth: _percentWidth(column), groups: groups),
          );
        }
      }
    }
    final label = _label(tab) ?? '';
    return FormPage(
      label: label,
      kind: _kindOf(label, sections, index),
      sections: sections,
    );
  }

  /// Walks a column and returns its labeled groups in document order, with
  /// the anonymous wrapper groups and columns collapsed away. Controls that
  /// sit outside any labeled group land in a leading group with an empty
  /// label.
  static List<FormGroup> _groupsIn(XmlElement element) {
    final out = <(String, List<FormControl>)>[];
    (String, List<FormControl>)? current;

    void walk(XmlElement node) {
      for (final child in node.childElements) {
        switch (child.localName) {
          case 'Control':
            final control = FormControl.fromXml(child);
            if (control.isSpacer) continue;
            if (current == null) {
              current = ('', <FormControl>[]);
              out.add(current!);
            }
            current!.$2.add(control);
          case 'Group':
            final label = _label(child);
            if (label == null || label.isEmpty) {
              walk(child);
            } else {
              final previous = current;
              current = (label, <FormControl>[]);
              out.add(current!);
              walk(child);
              current = previous;
            }
          default:
            walk(child);
        }
      }
    }

    if (element.localName == 'Group') {
      final label = _label(element);
      if (label != null && label.isNotEmpty) {
        current = (label, <FormControl>[]);
        out.add(current!);
      }
    }
    walk(element);
    return [
      for (final g in out)
        if (g.$2.isNotEmpty) FormGroup(label: g.$1, controls: g.$2),
    ];
  }

  /// The tab's role, from what it holds (a lone log, links or attachments
  /// panel) and then from its label, so a localized form still lands right.
  static FormPageKind _kindOf(
    String label,
    List<FormSection> sections,
    int index,
  ) {
    final types = <FormControlType>{
      for (final s in sections)
        for (final g in s.groups)
          for (final c in g.controls) c.controlType,
    };
    if (types.length == 1) {
      switch (types.first) {
        case FormControlType.log:
          return FormPageKind.history;
        case FormControlType.links:
          return FormPageKind.links;
        case FormControlType.attachments:
          return FormPageKind.attachments;
        default:
          break;
      }
    }
    switch (label.toLowerCase()) {
      case 'details':
        return FormPageKind.details;
      case 'history':
        return FormPageKind.history;
      case 'links':
        return FormPageKind.links;
      case 'attachments':
        return FormPageKind.attachments;
    }
    return index == 0 ? FormPageKind.details : FormPageKind.custom;
  }

  static String? _label(XmlElement element) {
    final label = FormControl.stripAccelerator(element.getAttribute('Label'));
    return (label == null || label.isEmpty) ? null : label;
  }

  static int _percentWidth(XmlElement element) =>
      int.tryParse(element.getAttribute('PercentWidth') ?? '') ?? 100;

  @override
  List<Object?> get props => [header, pages];
}

/// Where the layout came from: the type's `xmlForm`, or the field list when
/// that is missing or fails to parse.
enum FormSource { xmlForm, fieldList }

/// Everything a form needs for one project and type, assembled once and
/// cached for a day.
class FormSpec extends Equatable {
  const FormSpec({
    required this.type,
    required this.fields,
    required this.layout,
    required this.source,
  });

  factory FormSpec.fromJson(Map<String, dynamic> json) => FormSpec(
    type: WorkItemType.fromJson(
      (json['type'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    fields: {
      for (final f in (json['fields'] as List?) ?? const [])
        if (f is Map)
          (f['referenceName'] as String? ?? ''): FieldSpec.fromJson(
            f.cast<String, dynamic>(),
          ),
    },
    layout: FormLayout.fromJson(
      (json['layout'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
    source: json['source'] == FormSource.fieldList.name
        ? FormSource.fieldList
        : FormSource.xmlForm,
  );

  final WorkItemType type;
  final Map<String, FieldSpec> fields;
  final FormLayout layout;
  final FormSource source;

  /// Controls of the Details page in web order.
  List<FormControl> get controlsOnDetails => layout.detailsPage?.controls ?? [];

  FieldSpec? fieldFor(FormControl control) {
    final reference = control.fieldReferenceName;
    return reference == null ? null : fields[reference];
  }

  /// Required fields the user can actually fill: `System.AreaId` and
  /// `System.IterationId` are `alwaysRequired` too but the server derives
  /// them from the paths (spike s25).
  List<FieldSpec> get requiredFields => [
    for (final f in fields.values)
      if (f.alwaysRequired && !FieldSpec.isBookkeeping(f.referenceName)) f,
  ];

  /// The one state a new item may start in (`transitions[""]`, spike s25).
  String? get initialState =>
      type.transitions['']?.firstOrNull ??
      (type.states.isEmpty ? null : type.states.first.name);

  /// Legal target states from [state]; the current state is included when
  /// Azure DevOps lists it.
  List<String> transitionsFrom(String state) =>
      type.transitions[state] ?? const [];

  Map<String, dynamic> toJson() => {
    'type': type.toJson(),
    'fields': [for (final f in fields.values) f.toJson()],
    'layout': layout.toJson(),
    'source': source.name,
  };

  @override
  List<Object?> get props => [type, fields, layout, source];
}

/// An area or iteration node from `wit/classificationnodes`.
class ClassificationNode extends Equatable {
  const ClassificationNode({
    required this.id,
    required this.identifier,
    required this.name,
    required this.path,
    required this.structureType,
    this.hasChildren = false,
    this.startDate,
    this.finishDate,
    this.children = const [],
  });

  factory ClassificationNode.fromJson(Map<String, dynamic> json) {
    final attributes = (json['attributes'] as Map?)?.cast<String, dynamic>();
    final structureType = json['structureType'] as String? ?? '';
    return ClassificationNode(
      id: (json['id'] as num?)?.toInt() ?? 0,
      identifier: json['identifier'] as String? ?? '',
      name: json['name'] as String? ?? '',
      path: fieldPath(json['path'] as String?, structureType),
      structureType: structureType,
      hasChildren: json['hasChildren'] as bool? ?? false,
      startDate: DateTime.tryParse(attributes?['startDate'] as String? ?? ''),
      finishDate: DateTime.tryParse(attributes?['finishDate'] as String? ?? ''),
      children: [
        for (final c in (json['children'] as List?) ?? const [])
          if (c is Map) ClassificationNode.fromJson(c.cast<String, dynamic>()),
      ],
    );
  }

  final int id;
  final String identifier;
  final String name;

  /// The path in the form the work item fields use: `Project\Iteration 1`,
  /// not the node's own `\Project\Iteration\Iteration 1`.
  final String path;
  final String structureType;
  final bool hasChildren;
  final DateTime? startDate;
  final DateTime? finishDate;
  final List<ClassificationNode> children;

  bool get isIteration => structureType == 'iteration';

  /// Every node of the subtree, this one first, depth first.
  Iterable<ClassificationNode> get flattened sync* {
    yield this;
    for (final c in children) {
      yield* c.flattened;
    }
  }

  /// `\DevOps Mobile App\Iteration\Iteration 1` → `DevOps Mobile App\
  /// Iteration 1`: the node path carries the `Area` or `Iteration` root
  /// segment that the work item field value leaves out.
  static String fieldPath(String? nodePath, String structureType) {
    if (nodePath == null || nodePath.isEmpty) return '';
    final segments = nodePath.split(r'\').where((s) => s.isNotEmpty).toList();
    final root = structureType == 'iteration' ? 'Iteration' : 'Area';
    if (segments.length > 1 && segments[1] == root) segments.removeAt(1);
    return segments.join(r'\');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'identifier': identifier,
    'name': name,
    // The path is already in field form; keep it round-trippable.
    'path': path,
    'structureType': structureType,
    'hasChildren': hasChildren,
    if (startDate != null || finishDate != null)
      'attributes': {
        if (startDate != null) 'startDate': startDate!.toIso8601String(),
        if (finishDate != null) 'finishDate': finishDate!.toIso8601String(),
      },
    if (children.isNotEmpty) 'children': [for (final c in children) c.toJson()],
  };

  @override
  List<Object?> get props => [id, path, children];
}

/// One row of `work/teamsettings/iterations` read without `$timeframe`: the
/// whole iteration list of a team, which the iteration picker shows under
/// "Team" ahead of the project's tree (spike s30).
class TeamIteration extends Equatable {
  const TeamIteration({
    required this.id,
    required this.name,
    required this.path,
    this.timeFrame,
    this.startDate,
    this.finishDate,
  });

  final String id;
  final String name;

  /// Project-relative in the wire (`DevOps Mobile App\Iteration 1` in the
  /// scratch project, spike s30); the field value wants the same form.
  final String path;

  /// `past`, `current` or `future`.
  final String? timeFrame;
  final DateTime? startDate;
  final DateTime? finishDate;

  bool get isCurrent => (timeFrame ?? '').toLowerCase() == 'current';

  @override
  List<Object?> get props => [id, name, path, timeFrame];
}

/// The defaults a new item inherits from the team on screen (research/11
/// §4.7).
class TeamDefaults extends Equatable {
  const TeamDefaults({
    required this.teamId,
    this.defaultArea,
    this.currentIterationPath,
    this.backlogIterationPath,
    this.bugsBehavior,
  });

  factory TeamDefaults.fromJson(Map<String, dynamic> json) => TeamDefaults(
    teamId: json['teamId'] as String? ?? '',
    defaultArea: json['defaultArea'] as String?,
    currentIterationPath: json['currentIterationPath'] as String?,
    backlogIterationPath: json['backlogIterationPath'] as String?,
    bugsBehavior: json['bugsBehavior'] as String?,
  );

  final String teamId;
  final String? defaultArea;

  /// The team's current sprint, from `teamsettings/iterations?$timeframe=
  /// current`; null when the team has no current iteration.
  final String? currentIterationPath;

  /// `teamsettings.backlogIteration`, the fallback when there is no sprint.
  final String? backlogIterationPath;

  /// `asRequirements` or `asTasks`: where a new Bug belongs.
  final String? bugsBehavior;

  String? get iterationPath => currentIterationPath ?? backlogIterationPath;

  Map<String, dynamic> toJson() => {
    'teamId': teamId,
    if (defaultArea != null) 'defaultArea': defaultArea,
    if (currentIterationPath != null)
      'currentIterationPath': currentIterationPath,
    if (backlogIterationPath != null)
      'backlogIterationPath': backlogIterationPath,
    if (bugsBehavior != null) 'bugsBehavior': bugsBehavior,
  };

  @override
  List<Object?> get props => [
    teamId,
    defaultArea,
    currentIterationPath,
    backlogIterationPath,
    bugsBehavior,
  ];
}

/// A team template: a named set of field values to apply to a new item.
class WorkItemTemplate extends Equatable {
  const WorkItemTemplate({
    required this.id,
    required this.name,
    required this.workItemTypeName,
    this.description,
    this.fields = const {},
  });

  factory WorkItemTemplate.fromJson(Map<String, dynamic> json) =>
      WorkItemTemplate(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        workItemTypeName: json['workItemTypeName'] as String? ?? '',
        description: json['description'] as String?,
        fields:
            (json['fields'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v as Object?),
            ) ??
            const {},
      );

  final String id;
  final String name;
  final String workItemTypeName;
  final String? description;
  final Map<String, Object?> fields;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'workItemTypeName': workItemTypeName,
    if (description != null) 'description': description,
    'fields': fields,
  };

  @override
  List<Object?> get props => [id, name, workItemTypeName, fields];
}

/// One backlog level from `work/backlogconfiguration`, top-down.
class BacklogLevel extends Equatable {
  const BacklogLevel({
    required this.id,
    required this.name,
    required this.rank,
    this.typeNames = const [],
    this.isHidden = false,
  });

  factory BacklogLevel.fromJson(Map<String, dynamic> json) => BacklogLevel(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    rank: (json['rank'] as num?)?.toInt() ?? 0,
    typeNames: [
      for (final t in (json['workItemTypes'] as List?) ?? const [])
        if (t is Map && t['name'] is String) t['name'] as String,
    ],
    isHidden: json['isHidden'] as bool? ?? false,
  );

  final String id;
  final String name;

  /// Portfolio backlogs come back unordered; `rank` is what sorts them
  /// (Epics 4, Features 3, requirement 2, task 1 in the scratch project).
  final int rank;
  final List<String> typeNames;
  final bool isHidden;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'rank': rank,
    'workItemTypes': [
      for (final t in typeNames) {'name': t},
    ],
    if (isHidden) 'isHidden': true,
  };

  @override
  List<Object?> get props => [id, name, rank, typeNames, isHidden];
}

/// The type chooser's input: the backlog levels top-down, the types that
/// are never offered, and how the project treats bugs.
class BacklogTypes extends Equatable {
  const BacklogTypes({
    this.levels = const [],
    this.hiddenTypes = const {},
    this.bugsBehavior,
  });

  factory BacklogTypes.fromJson(Map<String, dynamic> json) => BacklogTypes(
    levels: [
      for (final l in (json['levels'] as List?) ?? const [])
        if (l is Map) BacklogLevel.fromJson(l.cast<String, dynamic>()),
    ],
    hiddenTypes: {
      for (final t in (json['hiddenTypes'] as List?) ?? const []) '$t',
    },
    bugsBehavior: json['bugsBehavior'] as String?,
  );

  final List<BacklogLevel> levels;
  final Set<String> hiddenTypes;
  final String? bugsBehavior;

  /// Type names of the visible levels, top-down, without duplicates.
  List<String> get orderedTypeNames {
    final seen = <String>{};
    return [
      for (final l in levels)
        if (!l.isHidden)
          for (final t in l.typeNames)
            if (!hiddenTypes.contains(t) && seen.add(t)) t,
    ];
  }

  Map<String, dynamic> toJson() => {
    'levels': [for (final l in levels) l.toJson()],
    'hiddenTypes': hiddenTypes.toList(),
    if (bugsBehavior != null) 'bugsBehavior': bugsBehavior,
  };

  @override
  List<Object?> get props => [levels, hiddenTypes, bugsBehavior];
}

/// One entry of `customProperties.RuleValidationErrors[]` from a 400
/// (spike w16).
class ValidationError extends Equatable {
  const ValidationError({
    required this.fieldReferenceName,
    this.flags = const [],
    this.message = '',
  });

  factory ValidationError.fromJson(Map<String, dynamic> json) =>
      ValidationError(
        fieldReferenceName: json['fieldReferenceName'] as String? ?? '',
        flags: parseFlags(
          json['fieldStatusFlags'] as String? ?? json['fieldStatus'] as String?,
        ),
        message: json['errorMessage'] as String? ?? '',
      );

  factory ValidationError.fromRuleError(RuleValidationError error) =>
      ValidationError(
        fieldReferenceName: error.fieldReferenceName,
        flags: parseFlags(error.fieldStatus ?? error.errorCode),
        message: error.errorMessage,
      );

  final String fieldReferenceName;

  /// `fieldStatusFlags` split up: `required`, `invalidEmpty`, `hasValues`,
  /// `limitedToValues`, `invalidListValue`.
  final List<String> flags;
  final String message;

  bool get isRequired => flags.contains('required');
  bool get isInvalidValue =>
      flags.contains('invalidListValue') || flags.contains('invalidValue');

  static List<String> parseFlags(String? raw) => [
    for (final f in (raw ?? '').split(','))
      if (f.trim().isNotEmpty) f.trim(),
  ];

  /// Reads the rule errors out of a 400 body, which carries them under
  /// `customProperties` on the wire and at the top level in some tools.
  static List<ValidationError> parseBody(Map<String, dynamic> body) {
    final custom = (body['customProperties'] as Map?)?['RuleValidationErrors'];
    final raw = custom ?? body['RuleValidationErrors'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map) ValidationError.fromJson(e.cast<String, dynamic>()),
    ];
  }

  RuleValidationError toRuleError() => RuleValidationError(
    fieldReferenceName: fieldReferenceName,
    errorCode: flags.join(', '),
    errorMessage: message,
    fieldStatus: flags.join(', '),
  );

  @override
  List<Object?> get props => [fieldReferenceName, flags, message];
}

/// A work item save the server refused on field rules. Stays inside the
/// `AdoException` family (as an `AdoValidationException`) so existing
/// handlers keep working, and adds the per-field list the form shows under
/// its controls.
///
/// The other 400, an unknown field (`typeKey`
/// `WorkItemTrackingFieldDefinitionNotFoundException`), has no rule errors
/// and stays a plain `AdoException` with its message.
class WorkItemRuleException extends AdoValidationException {
  WorkItemRuleException(
    super.message, {
    required this.errors,
    super.statusCode,
    super.typeKey,
    super.url,
  }) : super(ruleErrors: [for (final e in errors) e.toRuleError()]);

  /// Rebuilds the typed form from what `AdoClient` already parsed.
  factory WorkItemRuleException.fromValidation(AdoValidationException e) =>
      WorkItemRuleException(
        e.message,
        errors: [
          for (final r in e.ruleErrors) ValidationError.fromRuleError(r),
        ],
        statusCode: e.statusCode,
        typeKey: e.typeKey,
        url: e.url,
      );

  factory WorkItemRuleException.fromBody(
    Map<String, dynamic> body, {
    int? statusCode,
    Uri? url,
  }) => WorkItemRuleException(
    body['message'] as String? ?? 'The work item was refused',
    errors: ValidationError.parseBody(body),
    statusCode: statusCode,
    typeKey: body['typeKey'] as String?,
    url: url,
  );

  final List<ValidationError> errors;

  ValidationError? forField(String referenceName) {
    for (final e in errors) {
      if (e.fieldReferenceName == referenceName) return e;
    }
    return null;
  }

  Set<String> get fields => {for (final e in errors) e.fieldReferenceName};
}

/// A form the user left without saving, kept per project and type so the
/// chooser can offer "Resume draft" (research/11 §4.6). Drafts never enter
/// the pending-writes queue: no temporary ids.
class WorkItemDraft extends Equatable {
  const WorkItemDraft({
    required this.project,
    required this.type,
    required this.savedAt,
    this.values = const {},
    this.relations = const [],
  });

  factory WorkItemDraft.fromJson(Map<String, dynamic> json) => WorkItemDraft(
    project: json['project'] as String? ?? '',
    type: json['type'] as String? ?? '',
    savedAt:
        DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime(1970),
    values:
        (json['values'] as Map?)?.map(
          (k, v) => MapEntry(k.toString(), v as Object?),
        ) ??
        const {},
    relations: [
      for (final r in (json['relations'] as List?) ?? const [])
        if (r is Map) r.cast<String, Object?>(),
    ],
  );

  final String project;
  final String type;
  final DateTime savedAt;

  /// Field reference name → value, as the patch would send it.
  final Map<String, Object?> values;

  /// Raw relation objects (`rel`, `url`, `attributes`) for parent links and
  /// attachments already uploaded.
  final List<Map<String, Object?>> relations;

  String? get title => values['System.Title'] as String?;

  bool get isEmpty =>
      relations.isEmpty &&
      values.values.every(
        (v) => v == null || (v is String && v.trim().isEmpty),
      );

  Map<String, dynamic> toJson() => {
    'project': project,
    'type': type,
    'savedAt': savedAt.toUtc().toIso8601String(),
    'values': {for (final e in values.entries) e.key: _encodable(e.value)},
    'relations': relations,
  };

  static Object? _encodable(Object? value) => value is DateTime
      ? value.toUtc().toIso8601String()
      : value is List
      ? [for (final v in value) _encodable(v)]
      : value;

  @override
  List<Object?> get props => [project, type, savedAt, values, relations];
}

/// An uploaded attachment: what `wit/attachments` answers, plus the file
/// name the relation needs (spike w17).
class AttachmentRef extends Equatable {
  const AttachmentRef({required this.id, required this.url, this.fileName});

  factory AttachmentRef.fromJson(
    Map<String, dynamic> json, {
    String? fileName,
  }) => AttachmentRef(
    id: json['id'] as String? ?? '',
    url: json['url'] as String? ?? '',
    fileName: fileName,
  );

  final String id;
  final String url;
  final String? fileName;

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    if (fileName != null) 'fileName': fileName,
  };

  @override
  List<Object?> get props => [id, url, fileName];
}
