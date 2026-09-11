import 'package:boardhop/data/repositories/repo_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('branch names come from the alias and the file stem', () {
    final name = RepoRepository.branchNameFor(
      'kkamm',
      '/docs/Deploy Guide.md',
      now: DateTime(2026, 9, 11, 22, 5),
    );
    expect(name, 'kkamm/deploy-guide-0911-2205');
  });

  test('sanitizeBranchName strips what Git refuses', () {
    expect(
      RepoRepository.sanitizeBranchName('  Feature: fix it? '),
      'feature-fix-it',
    );
    expect(RepoRepository.sanitizeBranchName('a..b'), 'a.b');
    expect(RepoRepository.sanitizeBranchName('/lead/-trail-/'), 'lead/trail');
    expect(RepoRepository.sanitizeBranchName('x.lock'), 'x');
    expect(RepoRepository.sanitizeBranchName('~^:'), '');
    expect(RepoRepository.sanitizeBranchName('ok/branch_1'), 'ok/branch_1');
  });
}
