import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/local_store.dart';

void main() {
  group('configuration export', () {
    test('exports model metadata without api keys by default', () {
      final state = AppState.seed();

      final exported = ConfigExporter.exportState(state, includeSecrets: false);

      expect(exported['models'], hasLength(2));
      expect(exported['models'].first, isNot(contains('apiKey')));
      expect(exported['roles'], isNotEmpty);
      expect(exported['teams'], isNotEmpty);
    });

    test('exports api keys only when explicitly requested', () {
      final state = AppState.seed();

      final exported = ConfigExporter.exportState(state, includeSecrets: true);

      expect(exported['models'].first['apiKey'], isNotEmpty);
    });

    test('round trips workspaces, command requests, and patch proposals', () {
      final state = AppState.seed().copyWith(
        workspaces: const [
          ProjectWorkspace(
            id: 'workspace-1',
            name: 'App',
            path: '/workspace/app',
          ),
        ],
        taskAssignments: [
          TaskAssignment(
            id: 'task-1',
            conversationId: 'conv-team-default',
            round: 1,
            memberId: 'member-frontend',
            memberName: '前端工程师',
            roleName: '前端工程师',
            instruction: '实现登录页面',
            status: TaskAssignmentStatus.completed,
            createdAt: DateTime(2026, 1, 2),
            summary: '已完成界面建议',
            completedAt: DateTime(2026, 1, 2, 0, 1),
          ),
        ],
        commandRequests: [
          CommandRequest.pending(
            id: 'command-1',
            memberName: '测试工程师',
            command: 'flutter test',
            workingDirectory: '/workspace/app',
            decision: CommandDecision.requiresConfirmation,
            conversationId: 'conv-member-tester',
            memberId: 'member-tester',
            toolCallId: 'call-command-1',
          ),
        ],
        patchProposals: const [
          PatchProposal(
            id: 'patch-1',
            filePath: '/workspace/app/lib/main.dart',
            originalContent: 'old',
            proposedContent: 'new',
            memberName: '前端工程师',
            diff: '--- file\n+++ file\n@@\n-old\n+new\n',
          ),
        ],
      );

      final exported = ConfigExporter.exportState(state, includeSecrets: false);
      final imported = ConfigExporter.importState(exported);

      expect(imported.workspaces.single.path, '/workspace/app');
      expect(imported.taskAssignments.single.memberName, '前端工程师');
      expect(
        imported.taskAssignments.single.status,
        TaskAssignmentStatus.completed,
      );
      expect(imported.commandRequests.single.command, 'flutter test');
      expect(
          imported.commandRequests.single.status, CommandRequestStatus.pending);
      expect(
        imported.commandRequests.single.conversationId,
        'conv-member-tester',
      );
      expect(imported.commandRequests.single.memberId, 'member-tester');
      expect(imported.commandRequests.single.toolCallId, 'call-command-1');
      expect(imported.patchProposals.single.memberName, '前端工程师');
      expect(imported.patchProposals.single.status, PatchStatus.pending);
      expect(
        ConfigExporter.importState(
          ConfigExporter.exportState(AppState.seed(), includeSecrets: false),
        ).conversations.any(
              (conversation) => conversation.memberId == 'member-frontend',
            ),
        isTrue,
      );
      expect(
        AppState.fromJson(
          ConfigExporter.exportState(AppState.seed(), includeSecrets: false)
            ..remove('taskAssignments'),
        ).taskAssignments,
        isEmpty,
      );
    });

    test('loads legacy command requests without source metadata', () {
      final request = CommandRequest.fromJson({
        'id': 'command-legacy',
        'memberName': '秘书',
        'command': 'df -h /',
        'workingDirectory': '/',
        'decision': 'requiresConfirmation',
        'status': 'pending',
        'createdAt': DateTime(2026, 6, 28).toIso8601String(),
      });

      expect(request.conversationId, isNull);
      expect(request.memberId, isNull);
      expect(request.toolCallId, isNull);
    });
  });
}
