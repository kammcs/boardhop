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
    final pca = await SingleAccountPca.create(
      clientId: AppConfig.clientId,
      androidConfig: AndroidConfig(
        // Declares client_capabilities CP1 alongside authority and broker.
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
  /// [claims] carries a claims challenge when re-authenticating for CAE.
  Future<AuthenticationResult> signIn({
    String? loginHint,
    String? claims,
  }) async {
    try {
      final result = await _client.acquireToken(
        scopes: AppConfig.adoScopes,
        prompt: claims == null ? Prompt.selectAccount : Prompt.whenRequired,
        loginHint: loginHint,
        claims: claims,
      );
      _remember(null, result);
      return result;
    } on MsalUserCancelException {
      throw const AdoAuthException('Sign-in cancelled');
    } on MsalException catch (e) {
      throw AdoAuthException('${e.runtimeType}: ${e.message}');
    }
  }

  /// Silent acquisition for a tenant (null = home tenant). Throws
  /// `AuthInteractionRequiredException` when MSAL needs the user.
  Future<AuthenticationResult> acquireSilent({
    String? tenantId,
    String? claims,
    bool forceRefresh = false,
    List<String> scopes = AppConfig.adoScopes,
  }) async {
    try {
      final result = await _client.acquireTokenSilent(
        scopes: scopes,
        authority: tenantId == null ? null : AppConfig.authorityFor(tenantId),
        claims: claims,
        forceRefresh: forceRefresh,
      );
      _remember(tenantId, result);
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

  /// Microsoft Graph token (`User.Read`) for the signed-in person's own
  /// name, mail, company and photo. Silent only: null when the tenant has
  /// not consented or MSAL would need the user, so callers fall back to
  /// the Azure DevOps profile instead of prompting.
  Future<String?> graphAccessToken() async {
    final cached = _graphToken;
    if (cached != null &&
        cached.expiresOn.isAfter(DateTime.now().add(_expirySlack))) {
      return cached.accessToken;
    }
    try {
      final result = await acquireSilent(scopes: AppConfig.graphScopes);
      _graphToken = result;
      return result.accessToken;
    } on AdoException catch (e) {
      debugPrint('Graph token unavailable: ${e.message}');
      return null;
    }
  }

  AuthenticationResult? _graphToken;

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

  /// `AuthChallengeHandler` for `AdoClient`, called once after a 401.
  ///
  /// With [claims] (CAE challenge) MSAL must go to the token endpoint with
  /// the claims request; without, the cached token was rejected for another
  /// reason and a forced refresh is the right move. If MSAL needs the user
  /// (revoked refresh token, new MFA requirement), fall back to an
  /// interactive prompt carrying the same claims.
  Future<String> resolveChallenge({String? tenantId, String? claims}) async {
    try {
      final result = await acquireSilent(
        tenantId: tenantId,
        claims: claims,
        forceRefresh: claims == null,
      );
      return result.accessToken;
    } on AuthInteractionRequiredException {
      final result = await signIn(claims: claims);
      return result.accessToken;
    }
  }

  Future<void> signOut() async {
    _byTenant.clear();
    _graphToken = null;
    if (_pca == null) return;
    try {
      await _client.signOut();
    } on MsalNoCurrentAccountException {
      // Already signed out.
    } on MsalException catch (e) {
      debugPrint('signOut: ${e.runtimeType}: ${e.message}');
    }
  }

  void _remember(String? tenantId, AuthenticationResult result) {
    _byTenant[tenantId] = result;
    if (result.tenantId != null) _byTenant[result.tenantId] = result;
  }

  static String get platformLabel => Platform.isIOS
      ? 'iOS'
      : Platform.isAndroid
      ? 'Android'
      : Platform.operatingSystem;
}
