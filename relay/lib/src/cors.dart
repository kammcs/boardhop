import 'package:shelf/shelf.dart';

import 'responses.dart';

/// CORS for the org-key provisioning routes — and for nothing else.
///
/// The Marketplace extension's hub (`extension/` in the repo) is a browser page
/// Azure DevOps serves from a gallery CDN origin, so the calls it makes to
/// `/v1/orgs/{org}/…` are cross-origin and preflighted. Every other route is
/// talked to by the app or by curl on the box, where CORS means nothing, so the
/// middleware leaves them completely alone: no header is added, no `OPTIONS` is
/// intercepted.
///
/// The allow-list is exact. `*` is never sent, and the echoed origin is only
/// ever one that matched, so a page on any other origin gets a response its
/// browser refuses to read.
const corsPathPrefix = '/v1/orgs/';

const _allowMethods = 'GET, PUT, DELETE, OPTIONS';
const _allowHeaders = 'Authorization, Content-Type';

/// Ten minutes. Long enough that the hub's burst of writes preflights once,
/// short enough that widening or narrowing the list takes effect the same day.
const _maxAge = '600';

/// True for the origins the hub can legitimately run at:
///
/// * `https://*.vsassets.io` at any depth — `kammcs.gallerycdn.vsassets.io` is
///   where a published extension's static files are served from;
/// * `https://dev.azure.com`;
/// * `https://*.visualstudio.com` — the older per-org host, still in use;
/// * `http://localhost` and `https://localhost` on any port, for `tfx` serving
///   the hub locally while it is being built.
///
/// Anything else — including a missing origin, the opaque `null` origin, a
/// non-default port on a real host, and an origin with a path on it — is false.
bool isAllowedHubOrigin(String? origin) {
  if (origin == null || origin.isEmpty || origin == 'null' || origin.length > 255) return false;

  final uri = Uri.tryParse(origin);
  if (uri == null) return false;
  // An origin is scheme + host + optional port and nothing else; a value with a
  // path, a query, a fragment or user info on it is not one.
  if (uri.path.isNotEmpty || uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) return false;

  final host = uri.host;
  if (host.isEmpty) return false;

  // Local development is the only place plain http is allowed, and only on
  // localhost, where the port is whatever the dev server picked.
  if (host == 'localhost') return uri.scheme == 'http' || uri.scheme == 'https';
  if (uri.scheme != 'https' || uri.port != 443) return false;

  return host == 'dev.azure.com' || host.endsWith('.vsassets.io') || host.endsWith('.visualstudio.com');
}

/// Adds the CORS headers to responses under [corsPathPrefix] whose request came
/// from an allowed origin, and answers the preflight.
///
/// Wrap it *outside* the error handler so a 500 carries the headers too: a hub
/// that cannot read the failure is a hub that reports "network error" for
/// everything.
Middleware hubCors() {
  return (Handler inner) {
    return (Request request) async {
      if (!'/${request.url.path}'.startsWith(corsPathPrefix)) return inner(request);

      final origin = request.headers['origin'];
      final allowed = isAllowedHubOrigin(origin);

      if (request.method == 'OPTIONS') {
        // An origin the relay does not know gets the same answer as everything
        // else it refuses, and learns nothing about which paths exist.
        if (!allowed) return jsonResponse(404, const <String, Object?>{});
        return Response(
          204,
          headers: {
            'access-control-allow-origin': origin!,
            'access-control-allow-methods': _allowMethods,
            'access-control-allow-headers': _allowHeaders,
            'access-control-max-age': _maxAge,
            'vary': 'Origin',
          },
        );
      }

      final response = await inner(request);
      // The 404 wall and the 400s carry them as well: the hub has to be able to
      // read its own errors. No `Access-Control-Allow-Credentials` — the hub
      // sends the org key in an Authorization header it sets itself, and the
      // relay has no cookies to protect.
      if (!allowed) return response;
      return response.change(headers: {'access-control-allow-origin': origin!, 'vary': 'Origin'});
    };
  };
}
