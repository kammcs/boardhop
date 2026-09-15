import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/routes.dart';
import '../../core/text/wiki_link.dart';
import '../shared/account_scope.dart';

/// Opens a wiki web URL in the in-app reader instead of the browser (K5).
///
/// Every comment body and every HTML field goes through this before its
/// links fall through to wherever they were going: Azure DevOps has no
/// wiki mention syntax, so a page is referenced in a comment by its web
/// URL, in either of the two forms and with the wiki named by GUID or by
/// name (research/20 §1). Both carry the organization and the project, so
/// a link into another project's wiki opens in **that** project.
///
/// Returns true when [href] was a wiki URL and the reader was pushed, and
/// false when it was anything else — including a wiki artifact URI, which
/// carries no organization and can only be opened by a host that knows one
/// ([pushWikiLink], used by the Related tab).
bool openWikiLink(BuildContext context, String? href) {
  if (href == null || href.trim().isEmpty) return false;
  final link = WikiLink.parse(href);
  if (link == null) return false;
  if ((link.org ?? '').isEmpty || (link.project ?? '').isEmpty) return false;
  return pushWikiLink(context, link);
}

/// Pushes the reader for an already-parsed [link], with [org] and [project]
/// filling in whatever the link itself did not carry.
///
/// False when there is nothing to push with — no account in scope (a widget
/// test that built the view on its own), or no organization anywhere.
bool pushWikiLink(
  BuildContext context,
  WikiLink link, {
  String? org,
  String? project,
}) {
  final account = AccountScope.maybeOf(context);
  final organization = _first(link.org, org);
  // The artifact URI's project is the project **GUID**; every wiki route
  // takes one in place of the name.
  final owner = _first(link.project, project);
  if (account == null || organization == null || owner == null) return false;
  context.push(
    Routes.wikiPage(
      account,
      organization,
      owner,
      link.wikiIdOrName,
      path: link.path,
      id: link.pageId?.toString(),
      version: link.version,
      anchor: link.anchor,
    ),
  );
  return true;
}

String? _first(String? a, String? b) {
  if (a != null && a.isNotEmpty) return a;
  if (b != null && b.isNotEmpty) return b;
  return null;
}
