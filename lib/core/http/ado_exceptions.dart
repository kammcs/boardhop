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
        fieldStatus: json['fieldStatus'] as String?,
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
