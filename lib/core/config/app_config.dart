/// Build-time configuration.
///
/// Values come from `--dart-define` / `--dart-define-from-file=.env` so that
/// nothing tenant- or app-specific is committed. See `.env.example`.
abstract final class AppConfig {
  /// Application (client) ID of the Boardhop registration in the kammcs tenant.
  static const clientId = String.fromEnvironment('BOARDHOP_CLIENT_ID');

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

  static bool get isConfigured => clientId.isNotEmpty;

  static String authorityFor(String? tenantId) => tenantId == null
      ? authority
      : 'https://login.microsoftonline.com/$tenantId';
}
