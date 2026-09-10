/// Azure DevOps Services is split across several hosts. Each API call names
/// the host it belongs to; the client builds the URL from that plus the
/// organization and optional project/team segments.
///
/// Reference: research/01-api-coverage.md.
enum AdoHost {
  /// Work items, boards, git, pipelines, core (projects, teams).
  core('dev.azure.com', orgInPath: true),

  /// Identities, org-scoped profile, tokens.
  vssps('vssps.dev.azure.com', orgInPath: true),

  /// Cross-org profile and account (organization) discovery. Entra-token only.
  appVssps('app.vssps.visualstudio.com', orgInPath: false),

  /// Classic release management.
  release('vsrm.dev.azure.com', orgInPath: true),

  /// Code and work item search.
  search('almsearch.dev.azure.com', orgInPath: true),

  /// Artifacts feeds.
  feeds('feeds.dev.azure.com', orgInPath: true),

  /// Audit log.
  audit('auditservice.dev.azure.com', orgInPath: true);

  const AdoHost(this.hostname, {required this.orgInPath});

  final String hostname;

  /// Whether the organization name is the first path segment
  /// (`https://host/{org}/...`) or absent (`app.vssps`).
  final bool orgInPath;
}
