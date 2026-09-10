// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $OrganizationsTable extends Organizations
    with TableInfo<$OrganizationsTable, OrgRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrganizationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uriMeta = const VerificationMeta('uri');
  @override
  late final GeneratedColumn<String> uri = GeneratedColumn<String>(
    'uri',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _accountIdMeta = const VerificationMeta(
    'accountId',
  );
  @override
  late final GeneratedColumn<String> accountId = GeneratedColumn<String>(
    'account_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tenantIdMeta = const VerificationMeta(
    'tenantId',
  );
  @override
  late final GeneratedColumn<String> tenantId = GeneratedColumn<String>(
    'tenant_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastOpenedAtMeta = const VerificationMeta(
    'lastOpenedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastOpenedAt = GeneratedColumn<DateTime>(
    'last_opened_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    name,
    uri,
    accountId,
    tenantId,
    lastOpenedAt,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'organizations';
  @override
  VerificationContext validateIntegrity(
    Insertable<OrgRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('uri')) {
      context.handle(
        _uriMeta,
        uri.isAcceptableOrUnknown(data['uri']!, _uriMeta),
      );
    } else if (isInserting) {
      context.missing(_uriMeta);
    }
    if (data.containsKey('account_id')) {
      context.handle(
        _accountIdMeta,
        accountId.isAcceptableOrUnknown(data['account_id']!, _accountIdMeta),
      );
    } else if (isInserting) {
      context.missing(_accountIdMeta);
    }
    if (data.containsKey('tenant_id')) {
      context.handle(
        _tenantIdMeta,
        tenantId.isAcceptableOrUnknown(data['tenant_id']!, _tenantIdMeta),
      );
    }
    if (data.containsKey('last_opened_at')) {
      context.handle(
        _lastOpenedAtMeta,
        lastOpenedAt.isAcceptableOrUnknown(
          data['last_opened_at']!,
          _lastOpenedAtMeta,
        ),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  OrgRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OrgRow(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      uri: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uri'],
      )!,
      accountId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}account_id'],
      )!,
      tenantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tenant_id'],
      ),
      lastOpenedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_opened_at'],
      ),
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $OrganizationsTable createAlias(String alias) {
    return $OrganizationsTable(attachedDatabase, alias);
  }
}

class OrgRow extends DataClass implements Insertable<OrgRow> {
  final String name;
  final String uri;
  final String accountId;
  final String? tenantId;
  final DateTime? lastOpenedAt;
  final DateTime fetchedAt;
  const OrgRow({
    required this.name,
    required this.uri,
    required this.accountId,
    this.tenantId,
    this.lastOpenedAt,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['uri'] = Variable<String>(uri);
    map['account_id'] = Variable<String>(accountId);
    if (!nullToAbsent || tenantId != null) {
      map['tenant_id'] = Variable<String>(tenantId);
    }
    if (!nullToAbsent || lastOpenedAt != null) {
      map['last_opened_at'] = Variable<DateTime>(lastOpenedAt);
    }
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  OrganizationsCompanion toCompanion(bool nullToAbsent) {
    return OrganizationsCompanion(
      name: Value(name),
      uri: Value(uri),
      accountId: Value(accountId),
      tenantId: tenantId == null && nullToAbsent
          ? const Value.absent()
          : Value(tenantId),
      lastOpenedAt: lastOpenedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastOpenedAt),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory OrgRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OrgRow(
      name: serializer.fromJson<String>(json['name']),
      uri: serializer.fromJson<String>(json['uri']),
      accountId: serializer.fromJson<String>(json['accountId']),
      tenantId: serializer.fromJson<String?>(json['tenantId']),
      lastOpenedAt: serializer.fromJson<DateTime?>(json['lastOpenedAt']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'uri': serializer.toJson<String>(uri),
      'accountId': serializer.toJson<String>(accountId),
      'tenantId': serializer.toJson<String?>(tenantId),
      'lastOpenedAt': serializer.toJson<DateTime?>(lastOpenedAt),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  OrgRow copyWith({
    String? name,
    String? uri,
    String? accountId,
    Value<String?> tenantId = const Value.absent(),
    Value<DateTime?> lastOpenedAt = const Value.absent(),
    DateTime? fetchedAt,
  }) => OrgRow(
    name: name ?? this.name,
    uri: uri ?? this.uri,
    accountId: accountId ?? this.accountId,
    tenantId: tenantId.present ? tenantId.value : this.tenantId,
    lastOpenedAt: lastOpenedAt.present ? lastOpenedAt.value : this.lastOpenedAt,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  OrgRow copyWithCompanion(OrganizationsCompanion data) {
    return OrgRow(
      name: data.name.present ? data.name.value : this.name,
      uri: data.uri.present ? data.uri.value : this.uri,
      accountId: data.accountId.present ? data.accountId.value : this.accountId,
      tenantId: data.tenantId.present ? data.tenantId.value : this.tenantId,
      lastOpenedAt: data.lastOpenedAt.present
          ? data.lastOpenedAt.value
          : this.lastOpenedAt,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OrgRow(')
          ..write('name: $name, ')
          ..write('uri: $uri, ')
          ..write('accountId: $accountId, ')
          ..write('tenantId: $tenantId, ')
          ..write('lastOpenedAt: $lastOpenedAt, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(name, uri, accountId, tenantId, lastOpenedAt, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrgRow &&
          other.name == this.name &&
          other.uri == this.uri &&
          other.accountId == this.accountId &&
          other.tenantId == this.tenantId &&
          other.lastOpenedAt == this.lastOpenedAt &&
          other.fetchedAt == this.fetchedAt);
}

class OrganizationsCompanion extends UpdateCompanion<OrgRow> {
  final Value<String> name;
  final Value<String> uri;
  final Value<String> accountId;
  final Value<String?> tenantId;
  final Value<DateTime?> lastOpenedAt;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const OrganizationsCompanion({
    this.name = const Value.absent(),
    this.uri = const Value.absent(),
    this.accountId = const Value.absent(),
    this.tenantId = const Value.absent(),
    this.lastOpenedAt = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OrganizationsCompanion.insert({
    required String name,
    required String uri,
    required String accountId,
    this.tenantId = const Value.absent(),
    this.lastOpenedAt = const Value.absent(),
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       uri = Value(uri),
       accountId = Value(accountId),
       fetchedAt = Value(fetchedAt);
  static Insertable<OrgRow> custom({
    Expression<String>? name,
    Expression<String>? uri,
    Expression<String>? accountId,
    Expression<String>? tenantId,
    Expression<DateTime>? lastOpenedAt,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (uri != null) 'uri': uri,
      if (accountId != null) 'account_id': accountId,
      if (tenantId != null) 'tenant_id': tenantId,
      if (lastOpenedAt != null) 'last_opened_at': lastOpenedAt,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OrganizationsCompanion copyWith({
    Value<String>? name,
    Value<String>? uri,
    Value<String>? accountId,
    Value<String?>? tenantId,
    Value<DateTime?>? lastOpenedAt,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return OrganizationsCompanion(
      name: name ?? this.name,
      uri: uri ?? this.uri,
      accountId: accountId ?? this.accountId,
      tenantId: tenantId ?? this.tenantId,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (uri.present) {
      map['uri'] = Variable<String>(uri.value);
    }
    if (accountId.present) {
      map['account_id'] = Variable<String>(accountId.value);
    }
    if (tenantId.present) {
      map['tenant_id'] = Variable<String>(tenantId.value);
    }
    if (lastOpenedAt.present) {
      map['last_opened_at'] = Variable<DateTime>(lastOpenedAt.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrganizationsCompanion(')
          ..write('name: $name, ')
          ..write('uri: $uri, ')
          ..write('accountId: $accountId, ')
          ..write('tenantId: $tenantId, ')
          ..write('lastOpenedAt: $lastOpenedAt, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProjectsTable extends Projects
    with TableInfo<$ProjectsTable, ProjectRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgNameMeta = const VerificationMeta(
    'orgName',
  );
  @override
  late final GeneratedColumn<String> orgName = GeneratedColumn<String>(
    'org_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastUpdateTimeMeta = const VerificationMeta(
    'lastUpdateTime',
  );
  @override
  late final GeneratedColumn<DateTime> lastUpdateTime =
      GeneratedColumn<DateTime>(
        'last_update_time',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    orgName,
    name,
    description,
    state,
    lastUpdateTime,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'projects';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProjectRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('org_name')) {
      context.handle(
        _orgNameMeta,
        orgName.isAcceptableOrUnknown(data['org_name']!, _orgNameMeta),
      );
    } else if (isInserting) {
      context.missing(_orgNameMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('last_update_time')) {
      context.handle(
        _lastUpdateTimeMeta,
        lastUpdateTime.isAcceptableOrUnknown(
          data['last_update_time']!,
          _lastUpdateTimeMeta,
        ),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {orgName, id};
  @override
  ProjectRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProjectRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      orgName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_name'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      ),
      lastUpdateTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_update_time'],
      ),
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $ProjectsTable createAlias(String alias) {
    return $ProjectsTable(attachedDatabase, alias);
  }
}

class ProjectRow extends DataClass implements Insertable<ProjectRow> {
  final String id;
  final String orgName;
  final String name;
  final String? description;
  final String? state;
  final DateTime? lastUpdateTime;
  final DateTime fetchedAt;
  const ProjectRow({
    required this.id,
    required this.orgName,
    required this.name,
    this.description,
    this.state,
    this.lastUpdateTime,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['org_name'] = Variable<String>(orgName);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || state != null) {
      map['state'] = Variable<String>(state);
    }
    if (!nullToAbsent || lastUpdateTime != null) {
      map['last_update_time'] = Variable<DateTime>(lastUpdateTime);
    }
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  ProjectsCompanion toCompanion(bool nullToAbsent) {
    return ProjectsCompanion(
      id: Value(id),
      orgName: Value(orgName),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      state: state == null && nullToAbsent
          ? const Value.absent()
          : Value(state),
      lastUpdateTime: lastUpdateTime == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUpdateTime),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory ProjectRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProjectRow(
      id: serializer.fromJson<String>(json['id']),
      orgName: serializer.fromJson<String>(json['orgName']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      state: serializer.fromJson<String?>(json['state']),
      lastUpdateTime: serializer.fromJson<DateTime?>(json['lastUpdateTime']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'orgName': serializer.toJson<String>(orgName),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'state': serializer.toJson<String?>(state),
      'lastUpdateTime': serializer.toJson<DateTime?>(lastUpdateTime),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  ProjectRow copyWith({
    String? id,
    String? orgName,
    String? name,
    Value<String?> description = const Value.absent(),
    Value<String?> state = const Value.absent(),
    Value<DateTime?> lastUpdateTime = const Value.absent(),
    DateTime? fetchedAt,
  }) => ProjectRow(
    id: id ?? this.id,
    orgName: orgName ?? this.orgName,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    state: state.present ? state.value : this.state,
    lastUpdateTime: lastUpdateTime.present
        ? lastUpdateTime.value
        : this.lastUpdateTime,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  ProjectRow copyWithCompanion(ProjectsCompanion data) {
    return ProjectRow(
      id: data.id.present ? data.id.value : this.id,
      orgName: data.orgName.present ? data.orgName.value : this.orgName,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      state: data.state.present ? data.state.value : this.state,
      lastUpdateTime: data.lastUpdateTime.present
          ? data.lastUpdateTime.value
          : this.lastUpdateTime,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProjectRow(')
          ..write('id: $id, ')
          ..write('orgName: $orgName, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('state: $state, ')
          ..write('lastUpdateTime: $lastUpdateTime, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    orgName,
    name,
    description,
    state,
    lastUpdateTime,
    fetchedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProjectRow &&
          other.id == this.id &&
          other.orgName == this.orgName &&
          other.name == this.name &&
          other.description == this.description &&
          other.state == this.state &&
          other.lastUpdateTime == this.lastUpdateTime &&
          other.fetchedAt == this.fetchedAt);
}

class ProjectsCompanion extends UpdateCompanion<ProjectRow> {
  final Value<String> id;
  final Value<String> orgName;
  final Value<String> name;
  final Value<String?> description;
  final Value<String?> state;
  final Value<DateTime?> lastUpdateTime;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const ProjectsCompanion({
    this.id = const Value.absent(),
    this.orgName = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.state = const Value.absent(),
    this.lastUpdateTime = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectsCompanion.insert({
    required String id,
    required String orgName,
    required String name,
    this.description = const Value.absent(),
    this.state = const Value.absent(),
    this.lastUpdateTime = const Value.absent(),
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       orgName = Value(orgName),
       name = Value(name),
       fetchedAt = Value(fetchedAt);
  static Insertable<ProjectRow> custom({
    Expression<String>? id,
    Expression<String>? orgName,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? state,
    Expression<DateTime>? lastUpdateTime,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (orgName != null) 'org_name': orgName,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (state != null) 'state': state,
      if (lastUpdateTime != null) 'last_update_time': lastUpdateTime,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectsCompanion copyWith({
    Value<String>? id,
    Value<String>? orgName,
    Value<String>? name,
    Value<String?>? description,
    Value<String?>? state,
    Value<DateTime?>? lastUpdateTime,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return ProjectsCompanion(
      id: id ?? this.id,
      orgName: orgName ?? this.orgName,
      name: name ?? this.name,
      description: description ?? this.description,
      state: state ?? this.state,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (orgName.present) {
      map['org_name'] = Variable<String>(orgName.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (lastUpdateTime.present) {
      map['last_update_time'] = Variable<DateTime>(lastUpdateTime.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsCompanion(')
          ..write('id: $id, ')
          ..write('orgName: $orgName, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('state: $state, ')
          ..write('lastUpdateTime: $lastUpdateTime, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkItemsTable extends WorkItems
    with TableInfo<$WorkItemsTable, WorkItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _orgNameMeta = const VerificationMeta(
    'orgName',
  );
  @override
  late final GeneratedColumn<String> orgName = GeneratedColumn<String>(
    'org_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectMeta = const VerificationMeta(
    'project',
  );
  @override
  late final GeneratedColumn<String> project = GeneratedColumn<String>(
    'project',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revMeta = const VerificationMeta('rev');
  @override
  late final GeneratedColumn<int> rev = GeneratedColumn<int>(
    'rev',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _changedDateMeta = const VerificationMeta(
    'changedDate',
  );
  @override
  late final GeneratedColumn<DateTime> changedDate = GeneratedColumn<DateTime>(
    'changed_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    orgName,
    id,
    project,
    rev,
    json,
    changedDate,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'work_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkItemRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('org_name')) {
      context.handle(
        _orgNameMeta,
        orgName.isAcceptableOrUnknown(data['org_name']!, _orgNameMeta),
      );
    } else if (isInserting) {
      context.missing(_orgNameMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project')) {
      context.handle(
        _projectMeta,
        project.isAcceptableOrUnknown(data['project']!, _projectMeta),
      );
    } else if (isInserting) {
      context.missing(_projectMeta);
    }
    if (data.containsKey('rev')) {
      context.handle(
        _revMeta,
        rev.isAcceptableOrUnknown(data['rev']!, _revMeta),
      );
    } else if (isInserting) {
      context.missing(_revMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('changed_date')) {
      context.handle(
        _changedDateMeta,
        changedDate.isAcceptableOrUnknown(
          data['changed_date']!,
          _changedDateMeta,
        ),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {orgName, id};
  @override
  WorkItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkItemRow(
      orgName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_name'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      project: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project'],
      )!,
      rev: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rev'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      changedDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}changed_date'],
      ),
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $WorkItemsTable createAlias(String alias) {
    return $WorkItemsTable(attachedDatabase, alias);
  }
}

class WorkItemRow extends DataClass implements Insertable<WorkItemRow> {
  final String orgName;
  final int id;
  final String project;
  final int rev;
  final String json;
  final DateTime? changedDate;
  final DateTime fetchedAt;
  const WorkItemRow({
    required this.orgName,
    required this.id,
    required this.project,
    required this.rev,
    required this.json,
    this.changedDate,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['org_name'] = Variable<String>(orgName);
    map['id'] = Variable<int>(id);
    map['project'] = Variable<String>(project);
    map['rev'] = Variable<int>(rev);
    map['json'] = Variable<String>(json);
    if (!nullToAbsent || changedDate != null) {
      map['changed_date'] = Variable<DateTime>(changedDate);
    }
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  WorkItemsCompanion toCompanion(bool nullToAbsent) {
    return WorkItemsCompanion(
      orgName: Value(orgName),
      id: Value(id),
      project: Value(project),
      rev: Value(rev),
      json: Value(json),
      changedDate: changedDate == null && nullToAbsent
          ? const Value.absent()
          : Value(changedDate),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory WorkItemRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkItemRow(
      orgName: serializer.fromJson<String>(json['orgName']),
      id: serializer.fromJson<int>(json['id']),
      project: serializer.fromJson<String>(json['project']),
      rev: serializer.fromJson<int>(json['rev']),
      json: serializer.fromJson<String>(json['json']),
      changedDate: serializer.fromJson<DateTime?>(json['changedDate']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'orgName': serializer.toJson<String>(orgName),
      'id': serializer.toJson<int>(id),
      'project': serializer.toJson<String>(project),
      'rev': serializer.toJson<int>(rev),
      'json': serializer.toJson<String>(json),
      'changedDate': serializer.toJson<DateTime?>(changedDate),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  WorkItemRow copyWith({
    String? orgName,
    int? id,
    String? project,
    int? rev,
    String? json,
    Value<DateTime?> changedDate = const Value.absent(),
    DateTime? fetchedAt,
  }) => WorkItemRow(
    orgName: orgName ?? this.orgName,
    id: id ?? this.id,
    project: project ?? this.project,
    rev: rev ?? this.rev,
    json: json ?? this.json,
    changedDate: changedDate.present ? changedDate.value : this.changedDate,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  WorkItemRow copyWithCompanion(WorkItemsCompanion data) {
    return WorkItemRow(
      orgName: data.orgName.present ? data.orgName.value : this.orgName,
      id: data.id.present ? data.id.value : this.id,
      project: data.project.present ? data.project.value : this.project,
      rev: data.rev.present ? data.rev.value : this.rev,
      json: data.json.present ? data.json.value : this.json,
      changedDate: data.changedDate.present
          ? data.changedDate.value
          : this.changedDate,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkItemRow(')
          ..write('orgName: $orgName, ')
          ..write('id: $id, ')
          ..write('project: $project, ')
          ..write('rev: $rev, ')
          ..write('json: $json, ')
          ..write('changedDate: $changedDate, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(orgName, id, project, rev, json, changedDate, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkItemRow &&
          other.orgName == this.orgName &&
          other.id == this.id &&
          other.project == this.project &&
          other.rev == this.rev &&
          other.json == this.json &&
          other.changedDate == this.changedDate &&
          other.fetchedAt == this.fetchedAt);
}

class WorkItemsCompanion extends UpdateCompanion<WorkItemRow> {
  final Value<String> orgName;
  final Value<int> id;
  final Value<String> project;
  final Value<int> rev;
  final Value<String> json;
  final Value<DateTime?> changedDate;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const WorkItemsCompanion({
    this.orgName = const Value.absent(),
    this.id = const Value.absent(),
    this.project = const Value.absent(),
    this.rev = const Value.absent(),
    this.json = const Value.absent(),
    this.changedDate = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkItemsCompanion.insert({
    required String orgName,
    required int id,
    required String project,
    required int rev,
    required String json,
    this.changedDate = const Value.absent(),
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : orgName = Value(orgName),
       id = Value(id),
       project = Value(project),
       rev = Value(rev),
       json = Value(json),
       fetchedAt = Value(fetchedAt);
  static Insertable<WorkItemRow> custom({
    Expression<String>? orgName,
    Expression<int>? id,
    Expression<String>? project,
    Expression<int>? rev,
    Expression<String>? json,
    Expression<DateTime>? changedDate,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (orgName != null) 'org_name': orgName,
      if (id != null) 'id': id,
      if (project != null) 'project': project,
      if (rev != null) 'rev': rev,
      if (json != null) 'json': json,
      if (changedDate != null) 'changed_date': changedDate,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkItemsCompanion copyWith({
    Value<String>? orgName,
    Value<int>? id,
    Value<String>? project,
    Value<int>? rev,
    Value<String>? json,
    Value<DateTime?>? changedDate,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return WorkItemsCompanion(
      orgName: orgName ?? this.orgName,
      id: id ?? this.id,
      project: project ?? this.project,
      rev: rev ?? this.rev,
      json: json ?? this.json,
      changedDate: changedDate ?? this.changedDate,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (orgName.present) {
      map['org_name'] = Variable<String>(orgName.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (project.present) {
      map['project'] = Variable<String>(project.value);
    }
    if (rev.present) {
      map['rev'] = Variable<int>(rev.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (changedDate.present) {
      map['changed_date'] = Variable<DateTime>(changedDate.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkItemsCompanion(')
          ..write('orgName: $orgName, ')
          ..write('id: $id, ')
          ..write('project: $project, ')
          ..write('rev: $rev, ')
          ..write('json: $json, ')
          ..write('changedDate: $changedDate, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkItemListEntriesTable extends WorkItemListEntries
    with TableInfo<$WorkItemListEntriesTable, WorkItemListEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkItemListEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _orgNameMeta = const VerificationMeta(
    'orgName',
  );
  @override
  late final GeneratedColumn<String> orgName = GeneratedColumn<String>(
    'org_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectMeta = const VerificationMeta(
    'project',
  );
  @override
  late final GeneratedColumn<String> project = GeneratedColumn<String>(
    'project',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _listKeyMeta = const VerificationMeta(
    'listKey',
  );
  @override
  late final GeneratedColumn<String> listKey = GeneratedColumn<String>(
    'list_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workItemIdMeta = const VerificationMeta(
    'workItemId',
  );
  @override
  late final GeneratedColumn<int> workItemId = GeneratedColumn<int>(
    'work_item_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    orgName,
    project,
    listKey,
    workItemId,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'work_item_list_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkItemListEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('org_name')) {
      context.handle(
        _orgNameMeta,
        orgName.isAcceptableOrUnknown(data['org_name']!, _orgNameMeta),
      );
    } else if (isInserting) {
      context.missing(_orgNameMeta);
    }
    if (data.containsKey('project')) {
      context.handle(
        _projectMeta,
        project.isAcceptableOrUnknown(data['project']!, _projectMeta),
      );
    } else if (isInserting) {
      context.missing(_projectMeta);
    }
    if (data.containsKey('list_key')) {
      context.handle(
        _listKeyMeta,
        listKey.isAcceptableOrUnknown(data['list_key']!, _listKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_listKeyMeta);
    }
    if (data.containsKey('work_item_id')) {
      context.handle(
        _workItemIdMeta,
        workItemId.isAcceptableOrUnknown(
          data['work_item_id']!,
          _workItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workItemIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    orgName,
    project,
    listKey,
    workItemId,
  };
  @override
  WorkItemListEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkItemListEntryRow(
      orgName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_name'],
      )!,
      project: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project'],
      )!,
      listKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}list_key'],
      )!,
      workItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}work_item_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $WorkItemListEntriesTable createAlias(String alias) {
    return $WorkItemListEntriesTable(attachedDatabase, alias);
  }
}

class WorkItemListEntryRow extends DataClass
    implements Insertable<WorkItemListEntryRow> {
  final String orgName;
  final String project;
  final String listKey;
  final int workItemId;
  final int position;
  const WorkItemListEntryRow({
    required this.orgName,
    required this.project,
    required this.listKey,
    required this.workItemId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['org_name'] = Variable<String>(orgName);
    map['project'] = Variable<String>(project);
    map['list_key'] = Variable<String>(listKey);
    map['work_item_id'] = Variable<int>(workItemId);
    map['position'] = Variable<int>(position);
    return map;
  }

  WorkItemListEntriesCompanion toCompanion(bool nullToAbsent) {
    return WorkItemListEntriesCompanion(
      orgName: Value(orgName),
      project: Value(project),
      listKey: Value(listKey),
      workItemId: Value(workItemId),
      position: Value(position),
    );
  }

  factory WorkItemListEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkItemListEntryRow(
      orgName: serializer.fromJson<String>(json['orgName']),
      project: serializer.fromJson<String>(json['project']),
      listKey: serializer.fromJson<String>(json['listKey']),
      workItemId: serializer.fromJson<int>(json['workItemId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'orgName': serializer.toJson<String>(orgName),
      'project': serializer.toJson<String>(project),
      'listKey': serializer.toJson<String>(listKey),
      'workItemId': serializer.toJson<int>(workItemId),
      'position': serializer.toJson<int>(position),
    };
  }

  WorkItemListEntryRow copyWith({
    String? orgName,
    String? project,
    String? listKey,
    int? workItemId,
    int? position,
  }) => WorkItemListEntryRow(
    orgName: orgName ?? this.orgName,
    project: project ?? this.project,
    listKey: listKey ?? this.listKey,
    workItemId: workItemId ?? this.workItemId,
    position: position ?? this.position,
  );
  WorkItemListEntryRow copyWithCompanion(WorkItemListEntriesCompanion data) {
    return WorkItemListEntryRow(
      orgName: data.orgName.present ? data.orgName.value : this.orgName,
      project: data.project.present ? data.project.value : this.project,
      listKey: data.listKey.present ? data.listKey.value : this.listKey,
      workItemId: data.workItemId.present
          ? data.workItemId.value
          : this.workItemId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkItemListEntryRow(')
          ..write('orgName: $orgName, ')
          ..write('project: $project, ')
          ..write('listKey: $listKey, ')
          ..write('workItemId: $workItemId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(orgName, project, listKey, workItemId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkItemListEntryRow &&
          other.orgName == this.orgName &&
          other.project == this.project &&
          other.listKey == this.listKey &&
          other.workItemId == this.workItemId &&
          other.position == this.position);
}

class WorkItemListEntriesCompanion
    extends UpdateCompanion<WorkItemListEntryRow> {
  final Value<String> orgName;
  final Value<String> project;
  final Value<String> listKey;
  final Value<int> workItemId;
  final Value<int> position;
  final Value<int> rowid;
  const WorkItemListEntriesCompanion({
    this.orgName = const Value.absent(),
    this.project = const Value.absent(),
    this.listKey = const Value.absent(),
    this.workItemId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkItemListEntriesCompanion.insert({
    required String orgName,
    required String project,
    required String listKey,
    required int workItemId,
    required int position,
    this.rowid = const Value.absent(),
  }) : orgName = Value(orgName),
       project = Value(project),
       listKey = Value(listKey),
       workItemId = Value(workItemId),
       position = Value(position);
  static Insertable<WorkItemListEntryRow> custom({
    Expression<String>? orgName,
    Expression<String>? project,
    Expression<String>? listKey,
    Expression<int>? workItemId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (orgName != null) 'org_name': orgName,
      if (project != null) 'project': project,
      if (listKey != null) 'list_key': listKey,
      if (workItemId != null) 'work_item_id': workItemId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkItemListEntriesCompanion copyWith({
    Value<String>? orgName,
    Value<String>? project,
    Value<String>? listKey,
    Value<int>? workItemId,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return WorkItemListEntriesCompanion(
      orgName: orgName ?? this.orgName,
      project: project ?? this.project,
      listKey: listKey ?? this.listKey,
      workItemId: workItemId ?? this.workItemId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (orgName.present) {
      map['org_name'] = Variable<String>(orgName.value);
    }
    if (project.present) {
      map['project'] = Variable<String>(project.value);
    }
    if (listKey.present) {
      map['list_key'] = Variable<String>(listKey.value);
    }
    if (workItemId.present) {
      map['work_item_id'] = Variable<int>(workItemId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkItemListEntriesCompanion(')
          ..write('orgName: $orgName, ')
          ..write('project: $project, ')
          ..write('listKey: $listKey, ')
          ..write('workItemId: $workItemId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingWritesTable extends PendingWrites
    with TableInfo<$PendingWritesTable, PendingWriteRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingWritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _orgNameMeta = const VerificationMeta(
    'orgName',
  );
  @override
  late final GeneratedColumn<String> orgName = GeneratedColumn<String>(
    'org_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    orgName,
    targetId,
    payload,
    createdAt,
    attempts,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_writes';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingWriteRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('org_name')) {
      context.handle(
        _orgNameMeta,
        orgName.isAcceptableOrUnknown(data['org_name']!, _orgNameMeta),
      );
    } else if (isInserting) {
      context.missing(_orgNameMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PendingWriteRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingWriteRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      orgName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}org_name'],
      )!,
      targetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $PendingWritesTable createAlias(String alias) {
    return $PendingWritesTable(attachedDatabase, alias);
  }
}

class PendingWriteRow extends DataClass implements Insertable<PendingWriteRow> {
  final int id;
  final String kind;
  final String orgName;
  final String targetId;
  final String payload;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  const PendingWriteRow({
    required this.id,
    required this.kind,
    required this.orgName,
    required this.targetId,
    required this.payload,
    required this.createdAt,
    required this.attempts,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['kind'] = Variable<String>(kind);
    map['org_name'] = Variable<String>(orgName);
    map['target_id'] = Variable<String>(targetId);
    map['payload'] = Variable<String>(payload);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  PendingWritesCompanion toCompanion(bool nullToAbsent) {
    return PendingWritesCompanion(
      id: Value(id),
      kind: Value(kind),
      orgName: Value(orgName),
      targetId: Value(targetId),
      payload: Value(payload),
      createdAt: Value(createdAt),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory PendingWriteRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingWriteRow(
      id: serializer.fromJson<int>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      orgName: serializer.fromJson<String>(json['orgName']),
      targetId: serializer.fromJson<String>(json['targetId']),
      payload: serializer.fromJson<String>(json['payload']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'kind': serializer.toJson<String>(kind),
      'orgName': serializer.toJson<String>(orgName),
      'targetId': serializer.toJson<String>(targetId),
      'payload': serializer.toJson<String>(payload),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  PendingWriteRow copyWith({
    int? id,
    String? kind,
    String? orgName,
    String? targetId,
    String? payload,
    DateTime? createdAt,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) => PendingWriteRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    orgName: orgName ?? this.orgName,
    targetId: targetId ?? this.targetId,
    payload: payload ?? this.payload,
    createdAt: createdAt ?? this.createdAt,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  PendingWriteRow copyWithCompanion(PendingWritesCompanion data) {
    return PendingWriteRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      orgName: data.orgName.present ? data.orgName.value : this.orgName,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      payload: data.payload.present ? data.payload.value : this.payload,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingWriteRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('orgName: $orgName, ')
          ..write('targetId: $targetId, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    kind,
    orgName,
    targetId,
    payload,
    createdAt,
    attempts,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingWriteRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.orgName == this.orgName &&
          other.targetId == this.targetId &&
          other.payload == this.payload &&
          other.createdAt == this.createdAt &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class PendingWritesCompanion extends UpdateCompanion<PendingWriteRow> {
  final Value<int> id;
  final Value<String> kind;
  final Value<String> orgName;
  final Value<String> targetId;
  final Value<String> payload;
  final Value<DateTime> createdAt;
  final Value<int> attempts;
  final Value<String?> lastError;
  const PendingWritesCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.orgName = const Value.absent(),
    this.targetId = const Value.absent(),
    this.payload = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  PendingWritesCompanion.insert({
    this.id = const Value.absent(),
    required String kind,
    required String orgName,
    required String targetId,
    required String payload,
    required DateTime createdAt,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  }) : kind = Value(kind),
       orgName = Value(orgName),
       targetId = Value(targetId),
       payload = Value(payload),
       createdAt = Value(createdAt);
  static Insertable<PendingWriteRow> custom({
    Expression<int>? id,
    Expression<String>? kind,
    Expression<String>? orgName,
    Expression<String>? targetId,
    Expression<String>? payload,
    Expression<DateTime>? createdAt,
    Expression<int>? attempts,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (orgName != null) 'org_name': orgName,
      if (targetId != null) 'target_id': targetId,
      if (payload != null) 'payload': payload,
      if (createdAt != null) 'created_at': createdAt,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
    });
  }

  PendingWritesCompanion copyWith({
    Value<int>? id,
    Value<String>? kind,
    Value<String>? orgName,
    Value<String>? targetId,
    Value<String>? payload,
    Value<DateTime>? createdAt,
    Value<int>? attempts,
    Value<String?>? lastError,
  }) {
    return PendingWritesCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      orgName: orgName ?? this.orgName,
      targetId: targetId ?? this.targetId,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (orgName.present) {
      map['org_name'] = Variable<String>(orgName.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingWritesCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('orgName: $orgName, ')
          ..write('targetId: $targetId, ')
          ..write('payload: $payload, ')
          ..write('createdAt: $createdAt, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $CacheEntriesTable extends CacheEntries
    with TableInfo<$CacheEntriesTable, CacheEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, json, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CacheEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  CacheEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CacheEntryRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $CacheEntriesTable createAlias(String alias) {
    return $CacheEntriesTable(attachedDatabase, alias);
  }
}

class CacheEntryRow extends DataClass implements Insertable<CacheEntryRow> {
  final String key;
  final String json;
  final DateTime fetchedAt;
  const CacheEntryRow({
    required this.key,
    required this.json,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['json'] = Variable<String>(json);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  CacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return CacheEntriesCompanion(
      key: Value(key),
      json: Value(json),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory CacheEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CacheEntryRow(
      key: serializer.fromJson<String>(json['key']),
      json: serializer.fromJson<String>(json['json']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'json': serializer.toJson<String>(json),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  CacheEntryRow copyWith({String? key, String? json, DateTime? fetchedAt}) =>
      CacheEntryRow(
        key: key ?? this.key,
        json: json ?? this.json,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
  CacheEntryRow copyWithCompanion(CacheEntriesCompanion data) {
    return CacheEntryRow(
      key: data.key.present ? data.key.value : this.key,
      json: data.json.present ? data.json.value : this.json,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntryRow(')
          ..write('key: $key, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, json, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CacheEntryRow &&
          other.key == this.key &&
          other.json == this.json &&
          other.fetchedAt == this.fetchedAt);
}

class CacheEntriesCompanion extends UpdateCompanion<CacheEntryRow> {
  final Value<String> key;
  final Value<String> json;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const CacheEntriesCompanion({
    this.key = const Value.absent(),
    this.json = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CacheEntriesCompanion.insert({
    required String key,
    required String json,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       json = Value(json),
       fetchedAt = Value(fetchedAt);
  static Insertable<CacheEntryRow> custom({
    Expression<String>? key,
    Expression<String>? json,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (json != null) 'json': json,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CacheEntriesCompanion copyWith({
    Value<String>? key,
    Value<String>? json,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return CacheEntriesCompanion(
      key: key ?? this.key,
      json: json ?? this.json,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CacheEntriesCompanion(')
          ..write('key: $key, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $OrganizationsTable organizations = $OrganizationsTable(this);
  late final $ProjectsTable projects = $ProjectsTable(this);
  late final $WorkItemsTable workItems = $WorkItemsTable(this);
  late final $WorkItemListEntriesTable workItemListEntries =
      $WorkItemListEntriesTable(this);
  late final $PendingWritesTable pendingWrites = $PendingWritesTable(this);
  late final $CacheEntriesTable cacheEntries = $CacheEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    organizations,
    projects,
    workItems,
    workItemListEntries,
    pendingWrites,
    cacheEntries,
  ];
}

typedef $$OrganizationsTableCreateCompanionBuilder =
    OrganizationsCompanion Function({
      required String name,
      required String uri,
      required String accountId,
      Value<String?> tenantId,
      Value<DateTime?> lastOpenedAt,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$OrganizationsTableUpdateCompanionBuilder =
    OrganizationsCompanion Function({
      Value<String> name,
      Value<String> uri,
      Value<String> accountId,
      Value<String?> tenantId,
      Value<DateTime?> lastOpenedAt,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$OrganizationsTableFilterComposer
    extends Composer<_$AppDatabase, $OrganizationsTable> {
  $$OrganizationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uri => $composableBuilder(
    column: $table.uri,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OrganizationsTableOrderingComposer
    extends Composer<_$AppDatabase, $OrganizationsTable> {
  $$OrganizationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uri => $composableBuilder(
    column: $table.uri,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get accountId => $composableBuilder(
    column: $table.accountId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tenantId => $composableBuilder(
    column: $table.tenantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OrganizationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OrganizationsTable> {
  $$OrganizationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get uri =>
      $composableBuilder(column: $table.uri, builder: (column) => column);

  GeneratedColumn<String> get accountId =>
      $composableBuilder(column: $table.accountId, builder: (column) => column);

  GeneratedColumn<String> get tenantId =>
      $composableBuilder(column: $table.tenantId, builder: (column) => column);

  GeneratedColumn<DateTime> get lastOpenedAt => $composableBuilder(
    column: $table.lastOpenedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$OrganizationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OrganizationsTable,
          OrgRow,
          $$OrganizationsTableFilterComposer,
          $$OrganizationsTableOrderingComposer,
          $$OrganizationsTableAnnotationComposer,
          $$OrganizationsTableCreateCompanionBuilder,
          $$OrganizationsTableUpdateCompanionBuilder,
          (OrgRow, BaseReferences<_$AppDatabase, $OrganizationsTable, OrgRow>),
          OrgRow,
          PrefetchHooks Function()
        > {
  $$OrganizationsTableTableManager(_$AppDatabase db, $OrganizationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrganizationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrganizationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrganizationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> name = const Value.absent(),
                Value<String> uri = const Value.absent(),
                Value<String> accountId = const Value.absent(),
                Value<String?> tenantId = const Value.absent(),
                Value<DateTime?> lastOpenedAt = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OrganizationsCompanion(
                name: name,
                uri: uri,
                accountId: accountId,
                tenantId: tenantId,
                lastOpenedAt: lastOpenedAt,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String name,
                required String uri,
                required String accountId,
                Value<String?> tenantId = const Value.absent(),
                Value<DateTime?> lastOpenedAt = const Value.absent(),
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => OrganizationsCompanion.insert(
                name: name,
                uri: uri,
                accountId: accountId,
                tenantId: tenantId,
                lastOpenedAt: lastOpenedAt,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OrganizationsTable, OrgRow>(table),
                  BaseReferences<_$AppDatabase, $OrganizationsTable, OrgRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OrganizationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OrganizationsTable,
      OrgRow,
      $$OrganizationsTableFilterComposer,
      $$OrganizationsTableOrderingComposer,
      $$OrganizationsTableAnnotationComposer,
      $$OrganizationsTableCreateCompanionBuilder,
      $$OrganizationsTableUpdateCompanionBuilder,
      (OrgRow, BaseReferences<_$AppDatabase, $OrganizationsTable, OrgRow>),
      OrgRow,
      PrefetchHooks Function()
    >;
typedef $$ProjectsTableCreateCompanionBuilder = ProjectsCompanion Function({
  required String id,
  required String orgName,
  required String name,
  Value<String?> description,
  Value<String?> state,
  Value<DateTime?> lastUpdateTime,
  required DateTime fetchedAt,
  Value<int> rowid,
});
typedef $$ProjectsTableUpdateCompanionBuilder = ProjectsCompanion Function({
  Value<String> id,
  Value<String> orgName,
  Value<String> name,
  Value<String?> description,
  Value<String?> state,
  Value<DateTime?> lastUpdateTime,
  Value<DateTime> fetchedAt,
  Value<int> rowid,
});

class $$ProjectsTableFilterComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orgName => $composableBuilder(
    column: $table.orgName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUpdateTime => $composableBuilder(
    column: $table.lastUpdateTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProjectsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orgName => $composableBuilder(
    column: $table.orgName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUpdateTime => $composableBuilder(
    column: $table.lastUpdateTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProjectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get orgName =>
      $composableBuilder(column: $table.orgName, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUpdateTime => $composableBuilder(
    column: $table.lastUpdateTime,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$ProjectsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProjectsTable,
          ProjectRow,
          $$ProjectsTableFilterComposer,
          $$ProjectsTableOrderingComposer,
          $$ProjectsTableAnnotationComposer,
          $$ProjectsTableCreateCompanionBuilder,
          $$ProjectsTableUpdateCompanionBuilder,
          (
            ProjectRow,
            BaseReferences<_$AppDatabase, $ProjectsTable, ProjectRow>,
          ),
          ProjectRow,
          PrefetchHooks Function()
        > {
  $$ProjectsTableTableManager(_$AppDatabase db, $ProjectsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProjectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProjectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProjectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> orgName = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> state = const Value.absent(),
                Value<DateTime?> lastUpdateTime = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion(
                id: id,
                orgName: orgName,
                name: name,
                description: description,
                state: state,
                lastUpdateTime: lastUpdateTime,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String orgName,
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String?> state = const Value.absent(),
                Value<DateTime?> lastUpdateTime = const Value.absent(),
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProjectsCompanion.insert(
                id: id,
                orgName: orgName,
                name: name,
                description: description,
                state: state,
                lastUpdateTime: lastUpdateTime,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProjectsTable, ProjectRow>(table),
                  BaseReferences<_$AppDatabase, $ProjectsTable, ProjectRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProjectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProjectsTable,
      ProjectRow,
      $$ProjectsTableFilterComposer,
      $$ProjectsTableOrderingComposer,
      $$ProjectsTableAnnotationComposer,
      $$ProjectsTableCreateCompanionBuilder,
      $$ProjectsTableUpdateCompanionBuilder,
      (ProjectRow, BaseReferences<_$AppDatabase, $ProjectsTable, ProjectRow>),
      ProjectRow,
      PrefetchHooks Function()
    >;
typedef $$WorkItemsTableCreateCompanionBuilder = WorkItemsCompanion Function({
  required String orgName,
  required int id,
  required String project,
  required int rev,
  required String json,
  Value<DateTime?> changedDate,
  required DateTime fetchedAt,
  Value<int> rowid,
});
typedef $$WorkItemsTableUpdateCompanionBuilder = WorkItemsCompanion Function({
  Value<String> orgName,
  Value<int> id,
  Value<String> project,
  Value<int> rev,
  Value<String> json,
  Value<DateTime?> changedDate,
  Value<DateTime> fetchedAt,
  Value<int> rowid,
});

class $$WorkItemsTableFilterComposer
    extends Composer<_$AppDatabase, $WorkItemsTable> {
  $$WorkItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get orgName => $composableBuilder(
    column: $table.orgName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get project => $composableBuilder(
    column: $table.project,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get changedDate => $composableBuilder(
    column: $table.changedDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkItemsTable> {
  $$WorkItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get orgName => $composableBuilder(
    column: $table.orgName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get project => $composableBuilder(
    column: $table.project,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rev => $composableBuilder(
    column: $table.rev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get changedDate => $composableBuilder(
    column: $table.changedDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkItemsTable> {
  $$WorkItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get orgName =>
      $composableBuilder(column: $table.orgName, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get project =>
      $composableBuilder(column: $table.project, builder: (column) => column);

  GeneratedColumn<int> get rev =>
      $composableBuilder(column: $table.rev, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get changedDate => $composableBuilder(
    column: $table.changedDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$WorkItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorkItemsTable,
          WorkItemRow,
          $$WorkItemsTableFilterComposer,
          $$WorkItemsTableOrderingComposer,
          $$WorkItemsTableAnnotationComposer,
          $$WorkItemsTableCreateCompanionBuilder,
          $$WorkItemsTableUpdateCompanionBuilder,
          (
            WorkItemRow,
            BaseReferences<_$AppDatabase, $WorkItemsTable, WorkItemRow>,
          ),
          WorkItemRow,
          PrefetchHooks Function()
        > {
  $$WorkItemsTableTableManager(_$AppDatabase db, $WorkItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> orgName = const Value.absent(),
                Value<int> id = const Value.absent(),
                Value<String> project = const Value.absent(),
                Value<int> rev = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<DateTime?> changedDate = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkItemsCompanion(
                orgName: orgName,
                id: id,
                project: project,
                rev: rev,
                json: json,
                changedDate: changedDate,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String orgName,
                required int id,
                required String project,
                required int rev,
                required String json,
                Value<DateTime?> changedDate = const Value.absent(),
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => WorkItemsCompanion.insert(
                orgName: orgName,
                id: id,
                project: project,
                rev: rev,
                json: json,
                changedDate: changedDate,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorkItemsTable, WorkItemRow>(table),
                  BaseReferences<_$AppDatabase, $WorkItemsTable, WorkItemRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorkItemsTable,
      WorkItemRow,
      $$WorkItemsTableFilterComposer,
      $$WorkItemsTableOrderingComposer,
      $$WorkItemsTableAnnotationComposer,
      $$WorkItemsTableCreateCompanionBuilder,
      $$WorkItemsTableUpdateCompanionBuilder,
      (
        WorkItemRow,
        BaseReferences<_$AppDatabase, $WorkItemsTable, WorkItemRow>,
      ),
      WorkItemRow,
      PrefetchHooks Function()
    >;
typedef $$WorkItemListEntriesTableCreateCompanionBuilder =
    WorkItemListEntriesCompanion Function({
      required String orgName,
      required String project,
      required String listKey,
      required int workItemId,
      required int position,
      Value<int> rowid,
    });
typedef $$WorkItemListEntriesTableUpdateCompanionBuilder =
    WorkItemListEntriesCompanion Function({
      Value<String> orgName,
      Value<String> project,
      Value<String> listKey,
      Value<int> workItemId,
      Value<int> position,
      Value<int> rowid,
    });

class $$WorkItemListEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $WorkItemListEntriesTable> {
  $$WorkItemListEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get orgName => $composableBuilder(
    column: $table.orgName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get project => $composableBuilder(
    column: $table.project,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get listKey => $composableBuilder(
    column: $table.listKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get workItemId => $composableBuilder(
    column: $table.workItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WorkItemListEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkItemListEntriesTable> {
  $$WorkItemListEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get orgName => $composableBuilder(
    column: $table.orgName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get project => $composableBuilder(
    column: $table.project,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get listKey => $composableBuilder(
    column: $table.listKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get workItemId => $composableBuilder(
    column: $table.workItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WorkItemListEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkItemListEntriesTable> {
  $$WorkItemListEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get orgName =>
      $composableBuilder(column: $table.orgName, builder: (column) => column);

  GeneratedColumn<String> get project =>
      $composableBuilder(column: $table.project, builder: (column) => column);

  GeneratedColumn<String> get listKey =>
      $composableBuilder(column: $table.listKey, builder: (column) => column);

  GeneratedColumn<int> get workItemId => $composableBuilder(
    column: $table.workItemId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);
}

class $$WorkItemListEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WorkItemListEntriesTable,
          WorkItemListEntryRow,
          $$WorkItemListEntriesTableFilterComposer,
          $$WorkItemListEntriesTableOrderingComposer,
          $$WorkItemListEntriesTableAnnotationComposer,
          $$WorkItemListEntriesTableCreateCompanionBuilder,
          $$WorkItemListEntriesTableUpdateCompanionBuilder,
          (
            WorkItemListEntryRow,
            BaseReferences<
              _$AppDatabase,
              $WorkItemListEntriesTable,
              WorkItemListEntryRow
            >,
          ),
          WorkItemListEntryRow,
          PrefetchHooks Function()
        > {
  $$WorkItemListEntriesTableTableManager(
    _$AppDatabase db,
    $WorkItemListEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkItemListEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkItemListEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$WorkItemListEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> orgName = const Value.absent(),
                Value<String> project = const Value.absent(),
                Value<String> listKey = const Value.absent(),
                Value<int> workItemId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkItemListEntriesCompanion(
                orgName: orgName,
                project: project,
                listKey: listKey,
                workItemId: workItemId,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String orgName,
                required String project,
                required String listKey,
                required int workItemId,
                required int position,
                Value<int> rowid = const Value.absent(),
              }) => WorkItemListEntriesCompanion.insert(
                orgName: orgName,
                project: project,
                listKey: listKey,
                workItemId: workItemId,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorkItemListEntriesTable, WorkItemListEntryRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $WorkItemListEntriesTable,
                    WorkItemListEntryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WorkItemListEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WorkItemListEntriesTable,
      WorkItemListEntryRow,
      $$WorkItemListEntriesTableFilterComposer,
      $$WorkItemListEntriesTableOrderingComposer,
      $$WorkItemListEntriesTableAnnotationComposer,
      $$WorkItemListEntriesTableCreateCompanionBuilder,
      $$WorkItemListEntriesTableUpdateCompanionBuilder,
      (
        WorkItemListEntryRow,
        BaseReferences<
          _$AppDatabase,
          $WorkItemListEntriesTable,
          WorkItemListEntryRow
        >,
      ),
      WorkItemListEntryRow,
      PrefetchHooks Function()
    >;
typedef $$PendingWritesTableCreateCompanionBuilder =
    PendingWritesCompanion Function({
      Value<int> id,
      required String kind,
      required String orgName,
      required String targetId,
      required String payload,
      required DateTime createdAt,
      Value<int> attempts,
      Value<String?> lastError,
    });
typedef $$PendingWritesTableUpdateCompanionBuilder =
    PendingWritesCompanion Function({
      Value<int> id,
      Value<String> kind,
      Value<String> orgName,
      Value<String> targetId,
      Value<String> payload,
      Value<DateTime> createdAt,
      Value<int> attempts,
      Value<String?> lastError,
    });

class $$PendingWritesTableFilterComposer
    extends Composer<_$AppDatabase, $PendingWritesTable> {
  $$PendingWritesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get orgName => $composableBuilder(
    column: $table.orgName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingWritesTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingWritesTable> {
  $$PendingWritesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get orgName => $composableBuilder(
    column: $table.orgName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingWritesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingWritesTable> {
  $$PendingWritesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get orgName =>
      $composableBuilder(column: $table.orgName, builder: (column) => column);

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$PendingWritesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingWritesTable,
          PendingWriteRow,
          $$PendingWritesTableFilterComposer,
          $$PendingWritesTableOrderingComposer,
          $$PendingWritesTableAnnotationComposer,
          $$PendingWritesTableCreateCompanionBuilder,
          $$PendingWritesTableUpdateCompanionBuilder,
          (
            PendingWriteRow,
            BaseReferences<_$AppDatabase, $PendingWritesTable, PendingWriteRow>,
          ),
          PendingWriteRow,
          PrefetchHooks Function()
        > {
  $$PendingWritesTableTableManager(_$AppDatabase db, $PendingWritesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingWritesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingWritesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingWritesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> orgName = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => PendingWritesCompanion(
                id: id,
                kind: kind,
                orgName: orgName,
                targetId: targetId,
                payload: payload,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String kind,
                required String orgName,
                required String targetId,
                required String payload,
                required DateTime createdAt,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
              }) => PendingWritesCompanion.insert(
                id: id,
                kind: kind,
                orgName: orgName,
                targetId: targetId,
                payload: payload,
                createdAt: createdAt,
                attempts: attempts,
                lastError: lastError,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingWritesTable, PendingWriteRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PendingWritesTable,
                    PendingWriteRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingWritesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingWritesTable,
      PendingWriteRow,
      $$PendingWritesTableFilterComposer,
      $$PendingWritesTableOrderingComposer,
      $$PendingWritesTableAnnotationComposer,
      $$PendingWritesTableCreateCompanionBuilder,
      $$PendingWritesTableUpdateCompanionBuilder,
      (
        PendingWriteRow,
        BaseReferences<_$AppDatabase, $PendingWritesTable, PendingWriteRow>,
      ),
      PendingWriteRow,
      PrefetchHooks Function()
    >;
typedef $$CacheEntriesTableCreateCompanionBuilder =
    CacheEntriesCompanion Function({
      required String key,
      required String json,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$CacheEntriesTableUpdateCompanionBuilder =
    CacheEntriesCompanion Function({
      Value<String> key,
      Value<String> json,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$CacheEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CacheEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CacheEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CacheEntriesTable> {
  $$CacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$CacheEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CacheEntriesTable,
          CacheEntryRow,
          $$CacheEntriesTableFilterComposer,
          $$CacheEntriesTableOrderingComposer,
          $$CacheEntriesTableAnnotationComposer,
          $$CacheEntriesTableCreateCompanionBuilder,
          $$CacheEntriesTableUpdateCompanionBuilder,
          (
            CacheEntryRow,
            BaseReferences<_$AppDatabase, $CacheEntriesTable, CacheEntryRow>,
          ),
          CacheEntryRow,
          PrefetchHooks Function()
        > {
  $$CacheEntriesTableTableManager(_$AppDatabase db, $CacheEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CacheEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion(
                key: key,
                json: json,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String json,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => CacheEntriesCompanion.insert(
                key: key,
                json: json,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CacheEntriesTable, CacheEntryRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CacheEntriesTable,
                    CacheEntryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CacheEntriesTable,
      CacheEntryRow,
      $$CacheEntriesTableFilterComposer,
      $$CacheEntriesTableOrderingComposer,
      $$CacheEntriesTableAnnotationComposer,
      $$CacheEntriesTableCreateCompanionBuilder,
      $$CacheEntriesTableUpdateCompanionBuilder,
      (
        CacheEntryRow,
        BaseReferences<_$AppDatabase, $CacheEntriesTable, CacheEntryRow>,
      ),
      CacheEntryRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$OrganizationsTableTableManager get organizations =>
      $$OrganizationsTableTableManager(_db, _db.organizations);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db, _db.projects);
  $$WorkItemsTableTableManager get workItems =>
      $$WorkItemsTableTableManager(_db, _db.workItems);
  $$WorkItemListEntriesTableTableManager get workItemListEntries =>
      $$WorkItemListEntriesTableTableManager(_db, _db.workItemListEntries);
  $$PendingWritesTableTableManager get pendingWrites =>
      $$PendingWritesTableTableManager(_db, _db.pendingWrites);
  $$CacheEntriesTableTableManager get cacheEntries =>
      $$CacheEntriesTableTableManager(_db, _db.cacheEntries);
}
