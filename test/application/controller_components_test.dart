import 'package:ai_team/application/conversation_sessions.dart';
import 'package:ai_team/application/configuration_controller.dart';
import 'package:ai_team/application/streaming_draft_registry.dart';
import 'package:ai_team/application/task_queue_controller.dart';
import 'package:ai_team/application/workspace_command_controller.dart';
import 'package:ai_team/core/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/model_gateway_fakes.dart';

void main() {
  group('StreamingDraftRegistry', () {
    test('publishes and clears per-conversation draft listenables', () {
      final registry = StreamingDraftRegistry();
      final listenable = registry.listenable('msg-stream');

      registry.update(
        conversationId: 'conv-1',
        message: ChatMessage(
          id: 'msg-stream',
          authorName: '成员',
          content: 'draft',
          createdAt: DateTime(2026, 1, 1),
          generationStatus: ChatMessageGenerationStatus.streaming,
        ),
      );

      expect(listenable.value?.conversationId, 'conv-1');
      expect(listenable.value?.message.content, 'draft');

      registry.clearConversation('conv-1');

      expect(listenable.value, isNull);
      registry.dispose();
    });
  });

  group('ConversationSessionStore', () {
    test('keeps conversation visibility and pin ordering outside controller',
        () {
      final state = AppState.seed();
      final store = ConversationSessionStore()..sync(state);

      expect(
        store
            .visibleConversations(state,
                selectedConversationId: 'conv-team-default')
            .map((conversation) => conversation.id),
        contains('conv-team-default'),
      );
      store.activate(state, 'conv-member-frontend');
      store.togglePinned(state, 'conv-member-frontend');

      final visibleIds = store
          .visibleConversations(state,
              selectedConversationId: 'conv-member-frontend')
          .map((conversation) => conversation.id)
          .toList();

      expect(visibleIds.first, 'conv-member-frontend');
      expect(store.isPinned('conv-member-frontend'), isTrue);
    });
  });

  group('WorkspaceCommandController', () {
    test('owns command request state transitions outside AppController', () {
      var state = AppState.seed();
      final controller = WorkspaceCommandController(
        readState: () => state,
        commit: (nextState) => state = nextState,
      );

      final request = controller.requestCommand(
        memberId: 'member-frontend',
        command: 'flutter test',
        workingDirectory: '/tmp',
      );

      expect(state.commandRequests.single.id, request.id);

      controller.updateCommandRequestStatus(
        request.id,
        CommandRequestStatus.approved,
      );

      expect(
        state.commandRequests.single.status,
        CommandRequestStatus.approved,
      );
    });
  });

  group('ConfigurationController', () {
    test('owns configuration validation and state mutation outside controller',
        () {
      var state = AppState.seed();
      var selectedId = 'conv-team-default';
      String? activeId = 'team-default';
      var notified = false;
      final controller = ConfigurationController(
        readState: () => state,
        commit: (nextState) => state = nextState,
        currentTeam: () =>
            state.teams.firstWhere((team) => team.id == activeId),
        activeTeamId: () => activeId,
        selectedConversationId: () => selectedId,
        updateSelection: ({
          required activeTeamId,
          required selectedConversationId,
        }) {
          activeId = activeTeamId;
          selectedId = selectedConversationId;
        },
        notify: () => notified = true,
      );

      expect(
        () => controller.addModel(
          const ModelProfile(
            id: 'model-invalid',
            name: '',
            baseUrl: 'not-a-url',
            modelName: '',
            apiKey: '',
          ),
        ),
        throwsArgumentError,
      );

      final team = controller.addTeam(
        name: '  移动端小队  ',
        memberIds: const ['member-frontend', 'member-secretary'],
      );

      expect(team.name, '移动端小队');
      expect(team.memberIds, ['member-secretary', 'member-frontend']);
      expect(
        state.conversations.map((conversation) => conversation.teamId),
        contains(team.id),
      );

      controller.deleteTeam(team.id);

      expect(
        state.teams.map((item) => item.id),
        isNot(contains(team.id)),
      );
      expect(notified, isFalse);
    });
  });

  group('TaskQueueController', () {
    test('owns queue creation and task note mutation outside AppController',
        () async {
      var state = AppState.seed();
      final controller = TaskQueueController(
        readState: () => state,
        commit: (nextState) => state = nextState,
        gateway: ScriptedTitleGateway(title: '登录页修复'),
      );

      await controller.enqueueConversationTask(
        'conv-team-default',
        '修复登录页',
        priority: 3,
      );

      final task = state.queuedTasks.single;
      expect(task.title, '登录页修复');
      expect(task.priority, 3);
      expect(
        state.conversations
            .firstWhere(
                (conversation) => conversation.id == task.conversationId)
            .messages
            .where((message) => message.isUser),
        hasLength(1),
      );

      controller.appendTaskNote(task.id, '补充移动端');
      controller.updateTaskStatus(task.id, QueuedTaskStatus.running);

      final updated = state.queuedTasks.single;
      expect(updated.notes, ['补充移动端']);
      expect(updated.status, QueuedTaskStatus.running);
    });
  });
}
