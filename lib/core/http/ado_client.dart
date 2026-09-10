import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'ado_exceptions.dart';
import 'ado_host.dart';
import 'rate_limit.dart';

/// Supplies a bearer token for the given tenant (null = home tenant).
typedef TokenProvider = Future<String> Function({String? tenantId});

/// Called once when a request comes back 401. [claims] is the decoded
/// `WWW-Authenticate` claims challenge for Continuous Access Evaluation, or
/// null for a plain rejection. Returns a fresh token to retry with, or throws
/// an [AdoAuthException] to give up.
typedef AuthChallengeHandler = Future<String> Function({
  String? tenantId,
  String? claims,
});

/// Thin, typed wrapper over the Azure DevOps REST API.
///
/// Conventions (from research/05 and the spikes):
/// * every call pins its own `api-version`;
/// * the host is chosen per call (`AdoHost`), never guessed from the path;
/// * `X-TFS-FedAuthRedirect: Suppress` turns HTML sign-in redirects into 401s;
/// * rate-limit headers are recorded on every response;
/// * a 401 is retried exactly once after [AuthChallengeHandler] runs;
/// * failures surface as `AdoException` subtypes.
class AdoClient {
  AdoClient({
    required TokenProvider tokenProvider,
    AuthChallengeHandler? onUnauthorized,
    RateLimitTracker? rateLimits,
    Dio? dio,
  }) : _tokenProvider = tokenProvider, // ignore: prefer_initializing_formals
       _onUnauthorized = onUnauthorized, // ignore: prefer_initializing_formals
       rateLimits = rateLimits ?? RateLimitTracker(),
       _dio = dio ?? Dio() {
    final options = _dio.options;
    options.connectTimeout = const Duration(seconds: 15);
    options.receiveTimeout = const Duration(seconds: 30);
    options.responseType = ResponseType.json;
    // Status mapping happens in sendRaw, so never throw on status here.
    options.validateStatus = (_) => true;
    options.headers['Accept'] = 'application/json';
    options.headers['X-TFS-FedAuthRedirect'] = 'Suppress';
  }

  final TokenProvider _tokenProvider;
  final AuthChallengeHandler? _onUnauthorized;
  final Dio _dio;
  final RateLimitTracker rateLimits;

  static const jsonPatchContentType = 'application/json-patch+json';

  /// Builds `https://{host}/{org}/{project}/{team}/_apis/{path}?api-version=…`.
  static Uri buildUri({
    required AdoHost host,
    required String path,
    required String apiVersion,
    String? org,
    String? project,
    String? team,
    Map<String, String>? query,
  }) {
    assert(
      !host.orgInPath || org != null,
      'Host ${host.hostname} needs an organization',
    );
    final segments = <String>[
      if (host.orgInPath) org!,
      ?project,
      ?team,
      ...path.split('/').where((s) => s.isNotEmpty),
    ];
    return Uri(
      scheme: 'https',
      host: host.hostname,
      pathSegments: segments,
      queryParameters: <String, String>{...?query, 'api-version': apiVersion},
    );
  }

  Future<Map<String, dynamic>> getJson({
    required String path,
    required String apiVersion,
    AdoHost host = AdoHost.core,
    String? org,
    String? project,
    String? team,
    String? tenantId,
    Map<String, String>? query,
    CancelToken? cancelToken,
  }) => send(
    method: 'GET',
    path: path,
    apiVersion: apiVersion,
    host: host,
    org: org,
    project: project,
    team: team,
    tenantId: tenantId,
    query: query,
    cancelToken: cancelToken,
  );

  /// Performs a request and returns the decoded JSON object. A JSON array or
  /// empty body is wrapped as `{'value': …}` so callers see one shape.
  Future<Map<String, dynamic>> send({
    required String method,
    required String path,
    required String apiVersion,
    AdoHost host = AdoHost.core,
    String? org,
    String? project,
    String? team,
    String? tenantId,
    Map<String, String>? query,
    Object? body,
    String? contentType,
    CancelToken? cancelToken,
  }) async {
    final uri = buildUri(
      host: host,
      path: path,
      apiVersion: apiVersion,
      org: org,
      project: project,
      team: team,
      query: query,
    );
    final response = await sendRaw(
      method: method,
      uri: uri,
      tenantId: tenantId,
      body: body,
      contentType: contentType,
      cancelToken: cancelToken,
    );
    final data = response.data;
    if (data == null || (data is String && data.isEmpty)) {
      return const <String, dynamic>{};
    }
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    if (data is List) return <String, dynamic>{'value': data};
    if (data is String) {
      final decoded = jsonDecode(data);
      if (decoded is Map) return decoded.cast<String, dynamic>();
      return <String, dynamic>{'value': decoded};
    }
    throw AdoServerException(
      'Unexpected response type ${data.runtimeType}',
      statusCode: response.statusCode,
      url: uri,
    );
  }

  /// Sends a request to an absolute URI, attaches the token, records rate
  /// limit headers, retries once through the challenge handler on 401, and
  /// maps non-success statuses to `AdoException`s.
  Future<Response<dynamic>> sendRaw({
    required String method,
    required Uri uri,
    String? tenantId,
    Object? body,
    String? contentType,
    CancelToken? cancelToken,
  }) async {
    final String token;
    try {
      token = await _tokenProvider(tenantId: tenantId);
    } on AdoException {
      rethrow;
    } catch (e) {
      throw AdoAuthException('Could not acquire a token: $e', url: uri);
    }

    final first = await _dispatch(
      method: method,
      uri: uri,
      token: token,
      body: body,
      contentType: contentType,
      cancelToken: cancelToken,
    );
    if (_isSuccess(first)) return first;

    final error = _mapError(first, uri);
    final handler = _onUnauthorized;
    if (error is! AdoAuthException || handler == null) throw error;

    // One retry: CAE claims challenge or a token the service no longer
    // accepts. The handler either returns a new token or throws.
    final claims = error is ClaimsChallengeException ? error.claims : null;
    final fresh = await handler(tenantId: tenantId, claims: claims);
    final second = await _dispatch(
      method: method,
      uri: uri,
      token: fresh,
      body: body,
      contentType: contentType,
      cancelToken: cancelToken,
    );
    if (_isSuccess(second)) return second;
    throw _mapError(second, uri);
  }

  Future<Response<dynamic>> _dispatch({
    required String method,
    required Uri uri,
    required String token,
    Object? body,
    String? contentType,
    CancelToken? cancelToken,
  }) async {
    final Response<dynamic> response;
    try {
      response = await _dio.requestUri<dynamic>(
        uri,
        data: body,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          headers: <String, String>{'Authorization': 'Bearer $token'},
          contentType:
              contentType ?? (body == null ? null : Headers.jsonContentType),
        ),
      );
    } on DioException catch (e) {
      // Dio's connection messages quote library internals; the user needs
      // to know it is the network, not the service.
      final offline = switch (e.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => true,
        _ => e.error is SocketException,
      };
      throw AdoNetworkException(
        offline
            ? 'No connection. Check your network and try again.'
            : e.message ?? e.type.name,
        url: uri,
        cause: e,
      );
    }
    rateLimits.record(
      RateLimitInfo.fromHeaders(
        headers: response.headers.map,
        statusCode: response.statusCode ?? 0,
        path: uri.path,
      ),
    );
    return response;
  }

  static bool _isSuccess(Response<dynamic> r) {
    final status = r.statusCode ?? 0;
    return status >= 200 && status < 300 && status != 203;
  }

  AdoException _mapError(Response<dynamic> response, Uri uri) {
    final status = response.statusCode ?? 0;
    final headers = response.headers;
    final body = response.data;
    final json = body is Map ? body.cast<String, dynamic>() : null;
    final typeKey = json?['typeKey'] as String?;
    final message =
        json?['message'] as String? ??
        (body is String && body.isNotEmpty
            ? _shorten(body)
            : response.statusMessage ?? 'HTTP $status');

    switch (status) {
      case 203:
        // Anonymous/expired token: the service answers with its HTML sign-in page.
        return AdoAuthException(
          'Not authenticated (203 sign-in page)',
          statusCode: status,
          url: uri,
        );
      case 401:
        final challenge = headers.value('www-authenticate') ?? '';
        final claims = parseClaimsChallenge(challenge);
        if (claims != null) {
          return ClaimsChallengeException(
            message,
            claims: claims,
            statusCode: status,
            url: uri,
          );
        }
        return AdoAuthException(
          message,
          statusCode: status,
          typeKey: typeKey,
          url: uri,
        );
      case 403:
        return AdoForbiddenException(
          message,
          statusCode: status,
          typeKey: typeKey,
          url: uri,
        );
      case 404:
        return AdoNotFoundException(
          message,
          statusCode: status,
          typeKey: typeKey,
          url: uri,
        );
      case 412:
        return AdoStaleRevisionException(
          message,
          statusCode: status,
          typeKey: typeKey,
          url: uri,
        );
      case 429:
      case 503:
        final retryAfter = double.tryParse(headers.value('retry-after') ?? '');
        return AdoRateLimitedException(
          message,
          retryAfter: Duration(seconds: retryAfter?.round() ?? 30),
          statusCode: status,
          url: uri,
        );
      case 400:
        final rules =
            json?['customProperties']?['RuleValidationErrors'] ??
            json?['RuleValidationErrors'];
        if (rules is List) {
          return AdoValidationException(
            message,
            ruleErrors: rules
                .whereType<Map>()
                .map(
                  (m) =>
                      RuleValidationError.fromJson(m.cast<String, dynamic>()),
                )
                .toList(),
            statusCode: status,
            typeKey: typeKey,
            url: uri,
          );
        }
        return AdoServerException(
          message,
          statusCode: status,
          typeKey: typeKey,
          url: uri,
        );
      default:
        return AdoServerException(
          message,
          statusCode: status,
          typeKey: typeKey,
          url: uri,
        );
    }
  }

  /// Extracts the claims challenge from a `WWW-Authenticate: Bearer …`
  /// header when the error is `insufficient_claims`. The value is returned
  /// decoded to the JSON MSAL expects (Entra sends it base64url-encoded, but
  /// some proxies pass it through as plain JSON). Null for ordinary 401s.
  static String? parseClaimsChallenge(String header) {
    if (!header.toLowerCase().contains('insufficient_claims')) return null;
    // Documented form: base64url. Some gateways forward the raw JSON, whose
    // own quotes would stop a naive match, so take a `{…}` block greedily.
    final encoded = RegExp(r'claims="([A-Za-z0-9_\-+/=]+)"').firstMatch(header);
    if (encoded != null) {
      final value = encoded.group(1)!;
      try {
        return utf8.decode(base64Url.decode(base64Url.normalize(value)));
      } on FormatException {
        return value;
      }
    }
    final raw = RegExp(r'claims="(\{.*\})"').firstMatch(header);
    return raw?.group(1);
  }

  static String _shorten(String s) =>
      s.length <= 200 ? s : '${s.substring(0, 200)}…';
}
