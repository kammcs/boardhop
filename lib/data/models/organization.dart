import 'package:equatable/equatable.dart';

/// An Azure DevOps organization ("account" in the Accounts API).
class Organization extends Equatable {
  const Organization({
    required this.name,
    required this.uri,
    required this.accountId,
    this.tenantId,
  });

  /// From `GET app.vssps.visualstudio.com/_apis/accounts?memberId=…`.
  factory Organization.fromAccountJson(Map<String, dynamic> json) {
    final props = json['properties'];
    String? tenantId;
    if (props is Map) {
      final tenant = props['Microsoft.VisualStudio.Services.Account.TenantId'];
      if (tenant is Map) tenantId = tenant['\$value'] as String?;
    }
    final name = json['accountName'] as String;
    return Organization(
      name: name,
      uri: json['accountUri'] as String? ?? 'https://dev.azure.com/$name/',
      accountId: json['accountId'] as String,
      tenantId: tenantId,
    );
  }

  final String name;
  final String uri;
  final String accountId;
  final String? tenantId;

  /// Canonical `dev.azure.com` base, regardless of the legacy
  /// `{org}.visualstudio.com` form returned by the Accounts API.
  String get baseUrl => 'https://dev.azure.com/$name';

  @override
  List<Object?> get props => [name, accountId];
}
