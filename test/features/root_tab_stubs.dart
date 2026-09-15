import 'package:boardhop/data/models/project.dart';
import 'package:boardhop/data/repositories/activity_repository.dart';
import 'package:boardhop/data/repositories/project_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';

/// The chrome every root tab's app bar carries since research/21 LB: the
/// project picker button reads the project list for its tile, the Activity
/// bell reads the unread count. Any test that pumps Home, Work, Repos or
/// Pipelines needs both repositories in the tree.
class FakeProjectRepository extends Mock implements ProjectRepository {}

class FakeActivityRepository extends Mock implements ActivityRepository {}

ProjectRepository stubProjects([List<Project> projects = const []]) {
  final repo = FakeProjectRepository();
  when(() => repo.watch(any())).thenAnswer((_) => Stream.value(projects));
  when(() => repo.refresh(any(), tenantId: any(named: 'tenantId')))
      .thenAnswer((_) async => projects);
  return repo;
}

ActivityRepository stubActivity({int unread = 0}) {
  final repo = FakeActivityRepository();
  when(() => repo.unread(any())).thenAnswer((_) => Stream.value(unread));
  return repo;
}

List<RepositoryProvider<Object>> rootChromeProviders({
  ProjectRepository? projects,
  ActivityRepository? activity,
}) => [
  RepositoryProvider<ProjectRepository>.value(
    value: projects ?? stubProjects(),
  ),
  RepositoryProvider<ActivityRepository>.value(
    value: activity ?? stubActivity(),
  ),
];
