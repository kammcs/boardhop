/// Typed failures from the Azure DevOps REST API.
///
/// The mapping from HTTP status and body to these types lives in
/// `AdoClient`; feature code should catch these, never `DioException`.
sealed class AdoException implements Exception {
  const AdoException(this.message, {this.statusCode, this.typeKey, this.url});

  final String message;
  final int? statusCode;

  /// Azure DevOps `typeKey` from the JSON error body, e.g.
  /// `WorkItemRevisionMismatchException`.
  final String? typeKey;
  final Uri? url;

  @override
  String toString() =>
      '$runtimeType(${statusCode ?? '-'} ${typeKey ?? ''}: $message)';
}

/// No usable token, or the service rejected it. The caller should fall back
/// to interactive sign-in.
class AdoAuthException extends AdoException {
  const AdoAuthException(
    super.message, {
    super.statusCode,
    super.typeKey,
    super.url,
  });
}

/// MSAL cannot refresh silently (revoked refresh token, new MFA policy,
/// no account). The user has to go through interactive sign-in.
class AuthInteractionRequiredException extends AdoAuthException {
  const AuthInteractionRequiredException(super.message, {super.url});
}

/// 401 carrying an `insufficient_claims` challenge (Continuous Access
/// Evaluation). `claims` must be passed to MSAL on the next interactive or
/// silent acquisition. Spike F2 decides how, since `msal_auth` 3.5 has no
/// `claims` parameter (see NEXT-STEPS.md).
class ClaimsChallengeException extends AdoAuthException {
  const ClaimsChallengeException(
    super.message, {
    required this.claims,
    super.statusCode,
    super.url,
  });

  /// Raw `claims="..."` value from `WWW-Authenticate`, usually base64 JSON.
  final String claims;
}

/// 429 or 503 with `Retry-After`, or `X-RateLimit-Delay` above zero.
class AdoRateLimitedException extends AdoException {
  const AdoRateLimitedException(
    super.message, {
    required this.retryAfter,
    super.statusCode,
    super.url,
  });

  final Duration retryAfter;
}

/// 412 from a JSON Patch whose `test /rev` failed: the item changed under us.
class AdoStaleRevisionException extends AdoException {
  const AdoStaleRevisionException(
    super.message, {
    super.statusCode,
    super.typeKey,
    super.url,
  });
}

/// 400 with `RuleValidationErrors` (field rules, required fields, states).
class AdoValidationException extends AdoException {
  const AdoValidationException(
    super.message, {
    required this.ruleErrors,
    super.statusCode,
    super.typeKey,
    super.url,
  });

  final List<RuleValidationError> ruleErrors;
}

class RuleValidationError {
  const RuleValidationError({
    required this.fieldReferenceName,
    required this.errorCode,
    required this.errorMessage,
    this.fieldStatus,
  });

  factory RuleValidationError.fromJson(Map<String, dynamic> json) =>
      RuleValidationError(
        fieldReferenceName: json['fieldReferenceName'] as String? ?? '',
        errorCode: json['errorCode'] as String? ?? '',
        errorMessage: json['errorMessage'] as String? ?? '',
        // The wire calls it `fieldStatusFlags` (`required, invalidEmpty`);
        // `fieldStatus` is the name in the reference (spike w16).
        fieldStatus:
            json['fieldStatus'] as String? ??
            json['fieldStatusFlags'] as String?,
      );

  final String fieldReferenceName;
  final String errorCode;
  final String errorMessage;
  final String? fieldStatus;
}

/// 403: the token is valid but lacks a scope or the user lacks permission.
class AdoForbiddenException extends AdoException {
  const AdoForbiddenException(
    super.message, {
    super.statusCode,
    super.typeKey,
    super.url,
  });
}

class AdoNotFoundException extends AdoException {
  const AdoNotFoundException(
    super.message, {
    super.statusCode,
    super.typeKey,
    super.url,
  });
}

/// The Code Search extension is not installed in this organization.
///
/// `almsearch` answers a code search with 404 when the extension is missing,
/// which as a plain "not found" reads like the repository or the term is
/// wrong. It is a subtype of [AdoNotFoundException] so existing `on
/// AdoNotFoundException` handlers keep working; search catches it first to
/// say what is actually wrong (research/15 §4).
class CodeSearchUnavailable extends AdoNotFoundException {
  const CodeSearchUnavailable({super.statusCode, super.url})
    : super(
        'Code search is not available in this organization. '
        'An administrator can install the Code Search extension from the '
        'Marketplace.',
      );
}

/// The Analytics OData host refused the app's token, or the organization
/// has no Analytics.
///
/// `analytics.dev.azure.com` is a different host from `dev.azure.com` and
/// grants `vso.analytics` separately, so a token that reads work items fine
/// can still be rejected there (research/18 §1, the S6 gate). It is a
/// subtype of [AdoForbiddenException] and deliberately **not** of
/// [AdoAuthException]: a page that met it must say the burndown is
/// unavailable, not throw the user into interactive sign-in.
class AnalyticsUnavailable extends AdoForbiddenException {
  const AnalyticsUnavailable({super.statusCode, super.typeKey, super.url})
    : super(
        'The Analytics service did not accept this sign-in. A project or '
        'organization administrator can check that Analytics is enabled and '
        'that you have access to it.',
      );
}

/// The wiki resource refused this sign-in (`401 TF400813`).
///
/// The Dashboard API taught this lesson on 2026-09-15 (NEXT-STEPS 26): a
/// resource can answer `401 InvalidIdentityException: TF400813` to a token
/// every other resource in the same session accepts, because the
/// registration lacks that resource's scope. Raising sign-in there puts the
/// person in a loop — the sheet opens, they sign in, the same call refuses
/// again.
///
/// So a *wiki* refusal is its own type, a subtype of [AdoForbiddenException]
/// and deliberately **not** of [AdoAuthException], and the page shows it
/// inline. Every other 401 on the wiki routes still raises sign-in.
class WikiUnavailable extends AdoForbiddenException {
  const WikiUnavailable({super.statusCode, super.typeKey, super.url})
    : super(
        'This sign-in cannot read this project\u2019s wiki. A project or '
        'organization administrator can check that the Wiki is enabled and '
        'that you have access to it.',
      );

  /// True for the refusal above: a 401 the wiki routes answer with
  /// `TF400813` / `InvalidIdentityException`, rather than an expired token.
  static bool refuses(AdoException e) {
    if (e.statusCode != 401) return false;
    final key = e.typeKey ?? '';
    return e.message.contains('TF400813') ||
        key.contains('InvalidIdentity') ||
        e.message.contains('InvalidIdentity');
  }
}

/// Any other non-success status.
class AdoServerException extends AdoException {
  const AdoServerException(
    super.message, {
    super.statusCode,
    super.typeKey,
    super.url,
  });
}

/// Transport-level failure (DNS, timeout, TLS, offline).
class AdoNetworkException extends AdoException {
  const AdoNetworkException(super.message, {super.url, this.cause});

  final Object? cause;
}
