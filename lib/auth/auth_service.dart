import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:msal_auth/msal_auth.dart';

import '../core/config/app_config.dart';
import '../core/http/ado_exceptions.dart';

/// Wraps `msal_auth` (native MSAL with the Authenticator broker) for one
/// signed-in Entra identity that may hold access to several tenants.
///
/// Tokens are requested per tenant by overriding the authority on the silent
/// call, so a guest user in a customer tenant gets a token issued by that
/// tenant. Results are cached in memory and refreshed via MSAL shortly before
/// `expiresOn`.
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
    final pca = await SingleAccountPca.create(
      clientId: AppConfig.clientId,
      androidConfig: AndroidConfig(
        configFilePath: 'assets/msal_config.json',
        redirectUri: AppConfig.androidRedirectUri,
      ),
      appleConfig: AppleConfig(
        authority: AppConfig.authority,
        authorityType: AuthorityType.aad,
        broker: Broker.msAuthenticator,
      ),
    );
    return AuthService._(pca);
  }

  final SingleAccountPca? _pca;
  final Map<String?, AuthenticationResult> _byTenant =
      <String?, AuthenticationResult>{};

  /// Refresh this long before expiry to avoid racing the clock.
  static const _expirySlack = Duration(minutes: 3);

  bool get isConfigured => _pca != null;

  /// Most recent result for each tenant; for diagnostics only.
  Map<String?, AuthenticationResult> get cachedResults =>
      Map.unmodifiable(_byTenant);

  SingleAccountPca get _client {
    final pca = _pca;
    if (pca == null) {
      throw const AdoAuthException(
        'Boardhop is not configured: BOARDHOP_CLIENT_ID is missing',
      );
    }
    return pca;
  }

  /// The cached account, or null when nobody is signed in.
  Future<Account?> currentAccount() async {
    if (_pca == null) return null;
    try {
      return await _client.currentAccount;
    } on MsalNoCurrentAccountException {
      return null;
    } on MsalException catch (e) {
      debugPrint('currentAccount: ${e.runtimeType}: ${e.message}');
      return null;
    }
  }

  /// Interactive sign-in through the broker (falls back to browser).
  Future<AuthenticationResult> signIn({String? loginHint}) async {
    try {
      final result = await _client.acquireToken(
        scopes: AppConfig.adoScopes,
        prompt: Prompt.selectAccount,
        loginHint: loginHint,
      );
      _byTenant[null] = result;
      if (result.tenantId != null) _byTenant[result.tenantId] = result;
      return result;
    } on MsalUserCancelException {
      throw const AdoAuthException('Sign-in cancelled');
    } on MsalException catch (e) {
      throw AdoAuthException('${e.runtimeType}: ${e.message}');
    }
  }

  /// Silent acquisition for a tenant (null = home tenant). Throws
  /// `AdoAuthException` when interaction is required.
  Future<AuthenticationResult> acquireSilent({String? tenantId}) async {
    try {
      final result = await _client.acquireTokenSilent(
        scopes: AppConfig.adoScopes,
        authority: tenantId == null ? null : AppConfig.authorityFor(tenantId),
      );
      _byTenant[tenantId] = result;
      return result;
    } on MsalUiRequiredException catch (e) {
      throw AdoAuthException('Interactive sign-in required: ${e.message}');
    } on MsalNoCurrentAccountException {
      throw const AdoAuthException('No signed-in account');
    } on MsalException catch (e) {
      throw AdoAuthException('${e.runtimeType}: ${e.message}');
    }
  }

  /// `TokenProvider` for `AdoClient`: cached token if fresh, else silent.
  Future<String> accessToken({String? tenantId}) async {
    final cached = _byTenant[tenantId];
    if (cached != null &&
        cached.expiresOn.isAfter(DateTime.now().add(_expirySlack))) {
      return cached.accessToken;
    }
    final result = await acquireSilent(tenantId: tenantId);
    return result.accessToken;
  }

  Future<void> signOut() async {
    _byTenant.clear();
    if (_pca == null) return;
    try {
      await _client.signOut();
    } on MsalNoCurrentAccountException {
      // Already signed out.
    } on MsalException catch (e) {
      debugPrint('signOut: ${e.runtimeType}: ${e.message}');
    }
  }

  static String get platformLabel => Platform.isIOS
      ? 'iOS'
      : Platform.isAndroid
      ? 'Android'
      : Platform.operatingSystem;
}
