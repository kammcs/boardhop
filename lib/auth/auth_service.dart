import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:msal_auth/msal_auth.dart';

import '../core/config/app_config.dart';
import '../core/http/ado_exceptions.dart';

/// Wraps `msal_auth` (native MSAL with the Authenticator broker) in
/// multiple-account mode: several Entra identities can be signed in at
/// once, each of which may hold access to several tenants.
///
/// Tokens are requested per account and tenant by naming the account and
/// overriding the authority on the silent call, so a guest user in a
/// customer tenant gets a token issued by that tenant. Results are cached
/// in memory and refreshed via MSAL shortly before `expiresOn`.
///
/// The app declares the `CP1` client capability (Continuous Access
/// Evaluation): tokens live longer and the service can revoke them in near
/// real time by answering 401 with a claims challenge, which
/// [resolveChallenge] feeds back into MSAL.
class AuthService {
  AuthService._(this._pca);

  /// Creates the public client application. Returns an unconfigured service
  /// (every auth call throws `AdoAuthException`) when `BOARDHOP_CLIENT_ID`
  /// is missing, so the app can still start and explain the problem.
  static Future<AuthService> create() async {
    if (!AppConfig.isConfigured) {
      debugPrint(
        'AuthService: BOARDHOP_CLIENT_ID is not set; '
        'run with --dart-define-from-file=.env',
      );
      return AuthService._(null);
    }
    final pca = await MultipleAccountPca.create(
      clientId: AppConfig.clientId,
      androidConfig: AndroidConfig(
        // Declares client_capabilities CP1, account_mode MULTIPLE, the
        // authority and the broker.
        configFilePath: 'assets/msal_config.json',
        redirectUri: AppConfig.androidRedirectUri,
      ),
      appleConfig: AppleConfig(
        authority: AppConfig.authority,
        authorityType: AuthorityType.aad,
        broker: Broker.msAuthenticator,
        clientCapabilities: AppConfig.clientCapabilities,
      ),
    );
    return AuthService._(pca);
  }

  final MultipleAccountPca? _pca;

  /// Access tokens by `accountId|tenantId` (tenant null = home tenant).
  final Map<String, AuthenticationResult> _tokens = {};
  final Map<String, AuthenticationResult> _graphTokens = {};
  List<Account> _accounts = const [];

  /// Refresh this long before expiry to avoid racing the clock.
  static const _expirySlack = Duration(minutes: 3);

  bool get isConfigured => _pca != null;

  /// Most recent token result per account and tenant; diagnostics only.
  Map<String, AuthenticationResult> get cachedResults =>
      Map.unmodifiable(_tokens);

  /// Accounts as of the last [accounts] call (no I/O).
  List<Account> get knownAccounts => _accounts;

  Account? accountById(String id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  MultipleAccountPca get _client {
    final pca = _pca;
    if (pca == null) {
      throw const AdoAuthException(
        'Boardhop is not configured: BOARDHOP_CLIENT_ID is missing',
      );
    }
    return pca;
  }

  static String _key(String accountId, String? tenantId) =>
      '$accountId|${tenantId ?? ''}';

  /// Every signed-in account, by username.
  Future<List<Account>> accounts() async {
    if (_pca == null) return const [];
    try {
      final list = await _client.getAccounts();
      list.sort(
        (a, b) => (a.username ?? '').toLowerCase().compareTo(
          (b.username ?? '').toLowerCase(),
        ),
      );
      return _accounts = List.unmodifiable(list);
    } on MsalException catch (e) {
      debugPrint('getAccounts: ${e.runtimeType}: ${e.message}');
      return _accounts;
    }
  }

  /// Interactive sign-in through the broker (falls back to browser). Adds
  /// the chosen account, or refreshes it when it was already signed in.
  /// [claims] carries a claims challenge when re-authenticating for CAE.
  Future<AuthenticationResult> signIn({
    String? loginHint,
    String? claims,
  }) async {
    try {
      final result = await _client.acquireToken(
        scopes: AppConfig.adoScopes,
        prompt: claims == null && loginHint == null
            ? Prompt.selectAccount
            : Prompt.whenRequired,
        loginHint: loginHint,
        claims: claims,
      );
      _remember(result.account.id, null, result);
      await accounts();
      return result;
    } on MsalUserCancelException {
      throw const AdoAuthException('Sign-in cancelled');
    } on MsalException catch (e) {
      throw AdoAuthException('${e.runtimeType}: ${e.message}');
    }
  }

  /// Silent acquisition for an account and tenant (null = home tenant).
  /// Throws `AuthInteractionRequiredException` when MSAL needs the user.
  Future<AuthenticationResult> acquireSilent({
    required String accountId,
    String? tenantId,
    String? claims,
    bool forceRefresh = false,
    List<String> scopes = AppConfig.adoScopes,
  }) async {
    try {
      final result = await _client.acquireTokenSilent(
        scopes: scopes,
        identifier: accountId,
        authority: tenantId == null ? null : AppConfig.authorityFor(tenantId),
        claims: claims,
        forceRefresh: forceRefresh,
      );
      if (scopes == AppConfig.adoScopes) {
        _remember(accountId, tenantId, result);
      }
      return result;
    } on MsalUiRequiredException catch (e) {
      throw AuthInteractionRequiredException(
        'Interactive sign-in required: ${e.message}',
      );
    } on MsalNoCurrentAccountException {
      throw const AuthInteractionRequiredException('No signed-in account');
    } on MsalException catch (e) {
      throw AdoAuthException('${e.runtimeType}: ${e.message}');
    }
  }

  /// Microsoft Graph token (`User.Read`) for the account's own name, mail,
  /// company and photo. Silent only: null when the tenant has not consented
  /// or MSAL would need the user, so callers fall back to the Azure DevOps
  /// profile instead of prompting.
  Future<String?> graphAccessToken(String accountId) async {
    final cached = _graphTokens[accountId];
    if (cached != null &&
        cached.expiresOn.isAfter(DateTime.now().add(_expirySlack))) {
      return cached.accessToken;
    }
    try {
      final result = await acquireSilent(
        accountId: accountId,
        scopes: AppConfig.graphScopes,
      );
      _graphTokens[accountId] = result;
      return result.accessToken;
    } on AdoException catch (e) {
      debugPrint('Graph token unavailable: ${e.message}');
      return null;
    }
  }

  /// The account a call without an explicit one acts as: the first signed
  /// in. Only diagnostics and probes take that path; every org route binds
  /// its client to an account.
  Future<String> _defaultAccountId() async {
    if (_accounts.isEmpty) await accounts();
    if (_accounts.isEmpty) {
      throw const AuthInteractionRequiredException('No signed-in account');
    }
    return _accounts.first.id;
  }

  /// `TokenProvider` for `AdoClient`: cached token if fresh, else silent.
  Future<String> accessToken({String? tenantId, String? accountId}) async {
    final account = accountId ?? await _defaultAccountId();
    final cached = _tokens[_key(account, tenantId)];
    if (cached != null &&
        cached.expiresOn.isAfter(DateTime.now().add(_expirySlack))) {
      return cached.accessToken;
    }
    final result = await acquireSilent(accountId: account, tenantId: tenantId);
    return result.accessToken;
  }

  /// `AuthChallengeHandler` for `AdoClient`, called once after a 401.
  ///
  /// With [claims] (CAE challenge) MSAL must go to the token endpoint with
  /// the claims request; without, the cached token was rejected for another
  /// reason and a forced refresh is the right move. If MSAL needs the user
  /// (revoked refresh token, new MFA requirement), fall back to an
  /// interactive prompt for that same account carrying the same claims.
  Future<String> resolveChallenge({
    String? tenantId,
    String? accountId,
    String? claims,
  }) async {
    final account = accountId ?? await _defaultAccountId();
    try {
      final result = await acquireSilent(
        accountId: account,
        tenantId: tenantId,
        claims: claims,
        forceRefresh: claims == null,
      );
      return result.accessToken;
    } on AuthInteractionRequiredException {
      final result = await signIn(
        loginHint: accountById(account)?.username,
        claims: claims,
      );
      return result.accessToken;
    }
  }

  /// Signs one account out: its tokens leave MSAL's cache and this one.
  Future<void> removeAccount(String accountId) async {
    _tokens.removeWhere((k, _) => k.startsWith('$accountId|'));
    _graphTokens.remove(accountId);
    if (_pca == null) return;
    try {
      await _client.removeAccount(identifier: accountId);
    } on MsalException catch (e) {
      debugPrint('removeAccount: ${e.runtimeType}: ${e.message}');
    }
    await accounts();
  }

  /// Signs every account out.
  Future<void> signOut() async {
    for (final a in await accounts()) {
      await removeAccount(a.id);
    }
    _tokens.clear();
    _graphTokens.clear();
  }

  void _remember(
    String accountId,
    String? tenantId,
    AuthenticationResult result,
  ) {
    _tokens[_key(accountId, tenantId)] = result;
    if (result.tenantId != null) {
      _tokens[_key(accountId, result.tenantId)] = result;
    }
  }

  static String get platformLabel => Platform.isIOS
      ? 'iOS'
      : Platform.isAndroid
      ? 'Android'
      : Platform.operatingSystem;
}
