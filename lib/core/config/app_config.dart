import 'package:flutter/foundation.dart' show kReleaseMode;

/// Build-time configuration.
///
/// Values come from `--dart-define` / `--dart-define-from-file=.env` so that
/// nothing tenant- or app-specific is committed. See `.env.example`.
abstract final class AppConfig {
  /// Application (client) ID of the Boardhop registration in the kammcs tenant.
  static const clientId = String.fromEnvironment('BOARDHOP_CLIENT_ID');

  /// Whether the Diagnostics page (the bug icon on the Organizations screen,
  /// the probes, the route and enrichment boxes) exists in this build.
  ///
  /// Local testing only (Kelly, 2026-09-14): debug and profile builds have
  /// it, store builds (TestFlight, Google Play, both `--release`) do not. A
  /// release build can opt back in with `--dart-define=BOARDHOP_DIAGNOSTICS=true`
  /// for a one-off investigation; nothing in the ship scripts sets it.
  /// Demo mode turns it off too, so no test gear shows in a screenshot.
  static const diagnosticsEnabled = bool.fromEnvironment(
    'BOARDHOP_DIAGNOSTICS',
    defaultValue: !kReleaseMode && !demoMode,
  );

  /// Store-screenshot demo mode: no sign-in and no network. Every Azure
  /// DevOps call is answered locally by `lib/demo` with invented data about
  /// Boardhop building itself. Never set by the ship scripts.
  static const demoMode = bool.fromEnvironment('BOARDHOP_DEMO');

  /// Android redirect URI: `msauth://<package>/<url-encoded signature hash>`.
  /// The hash is per signing key, so debug builds on another machine need
  /// their own value (and their own entry on the app registration).
  static const androidRedirectUri = String.fromEnvironment(
    'BOARDHOP_ANDROID_REDIRECT_URI',
    defaultValue:
        'msauth://com.kammcs.boardhop/%2F%2Fksb0DQrePXmmxPydZ%2FUbpze98%3D',
  );

  /// Work and school accounts only; MSA is not supported by Azure DevOps'
  /// Entra OAuth path (research/02-authentication.md).
  static const authority = 'https://login.microsoftonline.com/organizations';

  /// Azure DevOps first-party resource. `.default` returns every delegated
  /// `vso.*` permission consented on the registration.
  static const adoResourceId = '499b84ac-1321-427f-aa17-267ca6975798';
  static const adoScopes = <String>['$adoResourceId/.default'];

  /// Microsoft Graph, own profile only (name, mail, company, photo) for
  /// the account header. Requested silently; never prompts.
  static const graphScopes = <String>['User.Read'];

  /// `CP1` declares Continuous Access Evaluation support: longer-lived
  /// tokens, and 401 claims challenges that `AuthService.resolveChallenge`
  /// answers. Android reads the same flag from `assets/msal_config.json`.
  static const clientCapabilities = <String>['CP1'];

  static bool get isConfigured => demoMode || clientId.isNotEmpty;

  static String authorityFor(String? tenantId) => tenantId == null
      ? authority
      : 'https://login.microsoftonline.com/$tenantId';
}
