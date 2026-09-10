/// `GET app.vssps.visualstudio.com/_apis/profile/profiles/me`.
class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.emailAddress,
    this.publicAlias,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    displayName: json['displayName'] as String? ?? '',
    emailAddress: json['emailAddress'] as String? ?? '',
    publicAlias: json['publicAlias'] as String?,
  );

  final String id;
  final String displayName;
  final String emailAddress;
  final String? publicAlias;
}
