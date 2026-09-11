import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../auth/auth_service.dart';
import '../../core/http/ado_exceptions.dart';
import '../avatar_store.dart';
import '../db/app_database.dart';
import '../db/json_cache.dart';
import 'org_repository.dart';

/// Who is signed in and which company they belong to, for the header of
/// the organization picker.
class AccountHeader extends Equatable {
  const AccountHeader({
    required this.displayName,
    required this.email,
    this.organizationName,
    this.jobTitle,
  });

  factory AccountHeader.fromJson(Map<String, dynamic> json) => AccountHeader(
    displayName: json['displayName'] as String? ?? '',
    email: json['email'] as String? ?? '',
    organizationName: json['organizationName'] as String?,
    jobTitle: json['jobTitle'] as String?,
  );

  /// Builds the header from Microsoft Graph `/me` and `/organization`.
  factory AccountHeader.fromGraph(
    Map<String, dynamic> me,
    Map<String, dynamic>? organization,
  ) => AccountHeader(
    displayName: me['displayName'] as String? ?? '',
    email: me['mail'] as String? ?? me['userPrincipalName'] as String? ?? '',
    organizationName: organization?['displayName'] as String?,
    jobTitle: me['jobTitle'] as String?,
  );

  final String displayName;
  final String email;

  /// The Entra tenant's display name ("CloudCover IoT, Inc"), null when
  /// Microsoft Graph could not be read.
  final String? organizationName;
  final String? jobTitle;

  Map<String, dynamic> toJson() => {
    'displayName': displayName,
    'email': email,
    'organizationName': ?organizationName,
    'jobTitle': ?jobTitle,
  };

  @override
  List<Object?> get props => [displayName, email, organizationName, jobTitle];
}

/// Reads the signed-in person from Microsoft Graph (`User.Read`: name,
/// mail, company name, photo) with a silently acquired Graph token, and
/// falls back to the Azure DevOps profile when Graph is not consented.
/// Cached so the picker opens offline.
class AccountRepository {
  AccountRepository(
    this._auth,
    this._orgs,
    this._avatars, {
    required String userId,
    AppDatabase? db,
    Dio? dio,
  }) : _userId = userId,
       _cache = JsonCache(db, namespace: userId),
       _dio = dio ?? Dio();

  final AuthService _auth;
  final OrgRepository _orgs;
  final AvatarStore _avatars;
  final String _userId;
  final JsonCache _cache;
  final Dio _dio;

  static const graphBase = 'https://graph.microsoft.com/v1.0';
  static const headerKey = 'account:header';
  String get photoKey => 'account:photo:$_userId';

  Future<AccountHeader?> cached() async {
    final hit = await _cache.get(headerKey);
    final json = hit?.json;
    return json is Map
        ? AccountHeader.fromJson(json.cast<String, dynamic>())
        : null;
  }

  Future<Map<String, dynamic>?> _graph(String token, String path) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$graphBase$path',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
      if (response.statusCode == 200) return response.data;
      debugPrint('graph $path -> ${response.statusCode}');
    } on DioException catch (e) {
      debugPrint('graph $path failed: ${e.message}');
    }
    return null;
  }

  /// Fresh header: Graph when a token can be had without interaction,
  /// otherwise the Azure DevOps profile (no company name).
  Future<AccountHeader> refresh() async {
    final token = await _auth.graphAccessToken(_userId);
    AccountHeader? header;
    if (token != null) {
      final me = await _graph(
        token,
        '/me?\$select=displayName,mail,userPrincipalName,jobTitle',
      );
      if (me != null) {
        final org = await _graph(token, '/organization?\$select=displayName');
        final orgs = org?['value'];
        header = AccountHeader.fromGraph(
          me,
          orgs is List && orgs.isNotEmpty && orgs.first is Map
              ? (orgs.first as Map).cast<String, dynamic>()
              : null,
        );
      }
    }
    if (header == null) {
      try {
        final profile = await _orgs.me();
        header = AccountHeader(
          displayName: profile.displayName,
          email: profile.emailAddress,
        );
      } on AdoException {
        final stale = await cached();
        if (stale != null) return stale;
        rethrow;
      }
    }
    await _cache.put(headerKey, header.toJson());
    return header;
  }

  /// The person's photo from Graph (`/me/photos/120x120`), through the
  /// avatar cache; null without a Graph token or a photo.
  Future<Uint8List?> photo() => _avatars.loadWith(photoKey, () async {
    final token = await _auth.graphAccessToken(_userId);
    if (token == null) return null;
    try {
      final response = await _dio.get<List<int>>(
        '$graphBase/me/photos/120x120/\$value',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
      );
      final data = response.data;
      if (response.statusCode == 200 && data != null && data.isNotEmpty) {
        return Uint8List.fromList(data);
      }
      debugPrint('graph photo -> ${response.statusCode}');
    } on DioException catch (e) {
      debugPrint('graph photo failed: ${e.message}');
    }
    return null;
  });

  Uint8List? cachedPhoto() => _avatars.cachedKey(photoKey);
}
