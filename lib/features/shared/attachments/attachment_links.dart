/// Azure DevOps attachment URLs: recognising one, writing the Markdown that
/// references one, naming a file so the pull request store accepts it, and
/// repairing the sentinel the comments API puts in front of an image.
///
/// Pure Dart on purpose. The same rules are needed on the read side (which
/// image gets the bearer token, which link opens the share sheet) and by the
/// composers (what is appended to the wire text), and both are worth testing
/// without a widget tree. Every rule here is a measured fact from spikes w32
/// and s50, written up in research/17-attachments.md §1.
library;

/// `dev.azure.com`, and the legacy `{org}.visualstudio.com` that 9 of the 30
/// client comment images still point at (s50 corpus).
const _azureHost = 'dev.azure.com';
const _legacyHostSuffix = '.visualstudio.com';

/// `…/_apis/wit/attachments/{guid}` — the work item store, keyed by GUID.
final _witAttachmentPath = RegExp(r'/_apis/wit/attachments/[^/]+');

/// `…/_apis/git/repositories/{repo}/pullRequests/{id}/attachments/{name}` —
/// the pull request store, keyed by the file name itself (w32 §4).
final _prAttachmentPath = RegExp(
  r'/_apis/git/repositories/[^/]+/pullrequests/\d+/attachments/[^/]+',
);

/// True for an attachment URL of either store on either host.
///
/// One predicate for two rules that must never disagree: an image matching
/// this is fetched with the bearer token (without it the service answers
/// HTTP 203 and a sign-in page, not a 401, so a naive loader renders nothing
/// — w32 §3), and a link matching this opens through the share sheet rather
/// than a browser, which could not authenticate either.
bool isAttachmentUrl(String? url) {
  if (url == null) return false;
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasAuthority) return false;
  final host = uri.host.toLowerCase();
  if (host != _azureHost && !host.endsWith(_legacyHostSuffix)) return false;
  final path = uri.path.toLowerCase();
  return _witAttachmentPath.hasMatch(path) || _prAttachmentPath.hasMatch(path);
}

/// The attachment GUID of a work item attachment URL, and null for anything
/// else — a pull request attachment is keyed by file name, which is unique
/// only inside one pull request and so must never key a shared byte cache.
String? witAttachmentId(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  if (!_witAttachmentPath.hasMatch(uri.path.toLowerCase())) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty);
  return segments.isEmpty ? null : segments.last;
}

/// The file name an attachment URL carries: `?fileName=` where the work item
/// store puts it, otherwise the last path segment, which is where the pull
/// request store puts it. Never empty — a nameless row would draw nothing.
String attachmentFileName(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return 'File';
  final named = uri.queryParameters['fileName'];
  if (named != null && named.trim().isNotEmpty) return named.trim();
  final segments = uri.pathSegments.where((s) => s.isNotEmpty);
  return segments.isEmpty ? 'File' : segments.last;
}

/// The Markdown one attachment is referenced by: `![name](url)` for an image
/// and `[name](url)` for anything else.
///
/// This is the whole write protocol — the service needs no relation and no
/// second registration, and it is byte-for-byte what the web itself stores
/// (w32 §1, decision T8). The name is a label inside `[…]`, so its brackets
/// are escaped; a destination holding brackets or spaces (the pull request
/// store is keyed by the file name, so `report(1).pdf` really does end up in
/// the URL) goes in the angle-bracket form CommonMark provides.
String attachmentMarkdown({
  required String name,
  required String url,
  required bool isImage,
}) {
  final label = name
      .replaceAll(r'\', r'\\')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]')
      .replaceAll(')', r'\)');
  final destination = RegExp(r'[\s()<>]').hasMatch(url) ? '<$url>' : url;
  return '${isImage ? '!' : ''}[$label]($destination)';
}

/// A file name the pull request attachment store will accept.
///
/// That store is keyed by the name, and a name already in the pull request
/// is HTTP 400 with no overwrite (w32 §4), so a second photo called
/// `image.jpg` has to become something else before the upload: the stamp
/// goes before the extension, `image-20260914-173045.jpg`.
String uniqueAttachmentName(String name, {DateTime? now}) {
  final at = name.lastIndexOf('.');
  final stem = at <= 0 ? name : name.substring(0, at);
  final extension = at <= 0 ? '' : name.substring(at);
  final t = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${t.year}${two(t.month)}${two(t.day)}'
      '-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  return '$stem-$stamp$extension';
}

/// The U+0006 the comments API writes in front of an image `src` inside the
/// `renderedText` of an `html`-format comment (w32 §3).
///
/// The rewritten value is `"\x06/{guid}?fileName=…"` — the sentinel, then a
/// base-less path with the scheme, host, organization and
/// `_apis/wit/attachments` stripped. 12 of 33 client comment images look
/// like that, and every one of them renders as nothing.
const attachmentSentinel = '\u0006';

/// `…/_apis/wit/attachments` for the project an `_apis` URL belongs to.
///
/// Everything before `/_apis/` already carries the organization and the
/// project GUID the attachment store is addressed by, so a comment's own
/// `url` is enough to rebuild what the sentinel stripped. Null when the URL
/// is not an `_apis` one.
String? witAttachmentBase(String? apiUrl) {
  if (apiUrl == null) return null;
  final at = apiUrl.toLowerCase().indexOf('/_apis/');
  if (at <= 0) return null;
  return '${apiUrl.substring(0, at)}/_apis/wit/attachments';
}

/// Puts [base] back in front of a sentinel-prefixed URL, and leaves every
/// other URL exactly as it is — including a sentinel one whose base is not
/// known, which is better left visibly broken than guessed at.
String normalizeAttachmentUrl(String url, {String? base}) {
  if (base == null || !url.startsWith('$attachmentSentinel/')) return url;
  return '$base${url.substring(attachmentSentinel.length)}';
}

/// The same repair across a whole HTML body, for the `src` and `href` values
/// inside it. U+0006 is a control character that never appears in real text,
/// so a plain replace cannot damage anything else.
String normalizeAttachmentHtml(String html, {String? base}) {
  if (base == null || !html.contains(attachmentSentinel)) return html;
  return html.replaceAll('$attachmentSentinel/', '$base/');
}
