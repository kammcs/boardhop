import 'package:equatable/equatable.dart';

import 'work_item.dart' show AvatarSize, AvatarSource;

class Project extends Equatable {
  const Project({
    required this.id,
    required this.name,
    this.description,
    this.state,
    this.lastUpdateTime,
    this.defaultTeamId,
    this.defaultTeamDescriptor,
  });

  /// From `GET {org}/_apis/projects?api-version=7.1`; the single-project
  /// form of the same call adds `defaultTeam`.
  factory Project.fromJson(Map<String, dynamic> json) {
    final team = json['defaultTeam'];
    return Project(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      state: json['state'] as String?,
      lastUpdateTime: DateTime.tryParse(
        json['lastUpdateTime'] as String? ?? '',
      ),
      defaultTeamId: team is Map ? team['id'] as String? : null,
    );
  }

  final String id;
  final String name;
  final String? description;
  final String? state;
  final DateTime? lastUpdateTime;

  /// The project's picture lives on its default team (spike s16). Null
  /// until the single-project read has run.
  final String? defaultTeamId;

  /// Graph descriptor (`vssgp.…`) of that team, the key for its avatar.
  final String? defaultTeamDescriptor;

  Project withDefaultTeam({String? id, String? descriptor}) => Project(
    id: this.id,
    name: name,
    description: description,
    state: state,
    lastUpdateTime: lastUpdateTime,
    defaultTeamId: id ?? defaultTeamId,
    defaultTeamDescriptor: descriptor ?? defaultTeamDescriptor,
  );

  /// The project's picture, when one has been set: the default team's
  /// avatar, pictures only, so that without one the tile keeps the web's
  /// color and initials drawn by the app (`AdoTiles`).
  AvatarSource? tileSource(String org) {
    final descriptor = defaultTeamDescriptor;
    if (descriptor == null) return null;
    return AvatarSource.graph(
      org: org,
      descriptor: descriptor,
      size: AvatarSize.large,
      picturesOnly: true,
    );
  }

  @override
  List<Object?> get props => [id];
}
