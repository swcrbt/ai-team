import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/orchestration/assignment_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replacement selection prefers same-role priority before execution',
      () {
    final seed = AppState.seed();
    const backupFrontend = TeamMember(
      id: 'member-frontend-backup',
      name: '前端备援',
      roleId: 'role-frontend',
      modelId: 'model-main',
      executionPriority: 9,
    );
    const executedFrontend = TeamMember(
      id: 'member-frontend-executed',
      name: '前端已执行',
      roleId: 'role-frontend',
      modelId: 'model-main',
      executionPriority: 10,
    );
    final team = seed.teams.single.copyWith(
      memberIds: [
        ...seed.teams.single.memberIds,
        backupFrontend.id,
        executedFrontend.id,
      ],
    );
    final state = seed.copyWith(
      teams: [team],
      members: [
        ...seed.members,
        backupFrontend,
        executedFrontend,
      ],
    );

    final replacement = findReplacementMember(
      state: state,
      team: team,
      failedMember: seed.members.firstWhere(
        (member) => member.id == 'member-frontend',
      ),
      executedMemberIds: {executedFrontend.id},
    );

    expect(replacement?.id, executedFrontend.id);
  });

  test('replacement selection prefers unexecuted member when priority ties', () {
    final seed = AppState.seed();
    const backupFrontend = TeamMember(
      id: 'member-frontend-backup',
      name: '前端备援',
      roleId: 'role-frontend',
      modelId: 'model-main',
      executionPriority: 10,
    );
    const executedFrontend = TeamMember(
      id: 'member-frontend-executed',
      name: '前端已执行',
      roleId: 'role-frontend',
      modelId: 'model-main',
      executionPriority: 10,
    );
    final team = seed.teams.single.copyWith(
      memberIds: [
        ...seed.teams.single.memberIds,
        executedFrontend.id,
        backupFrontend.id,
      ],
    );
    final state = seed.copyWith(
      teams: [team],
      members: [
        ...seed.members,
        backupFrontend,
        executedFrontend,
      ],
    );

    final replacement = findReplacementMember(
      state: state,
      team: team,
      failedMember: seed.members.firstWhere(
        (member) => member.id == 'member-frontend',
      ),
      executedMemberIds: {executedFrontend.id},
    );

    expect(replacement?.id, backupFrontend.id);
  });
}
