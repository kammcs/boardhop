import 'package:equatable/equatable.dart';

class Project extends Equatable {
  const Project({
    required this.id,
    required this.name,
    this.description,
    this.state,
    this.lastUpdateTime,
  });

  /// From `GET {org}/_apis/projects?api-version=7.1`.
  factory Project.fromJson(Map<String, dynamic> json) => Project(
    id: json['id'] as String,
    name: json['name'] as String,
    description: json['description'] as String?,
    state: json['state'] as String?,
    lastUpdateTime: DateTime.tryParse(json['lastUpdateTime'] as String? ?? ''),
  );

  final String id;
  final String name;
  final String? description;
  final String? state;
  final DateTime? lastUpdateTime;

  @override
  List<Object?> get props => [id];
}
