import 'package:ai_team/application/conversation_sessions.dart';
import 'package:ai_team/application/conversation_controller.dart';
import 'package:ai_team/application/configuration_controller.dart';
import 'package:ai_team/application/conversation_title_generator.dart';
import 'package:ai_team/application/dispatch_controller.dart';
import 'package:ai_team/application/streaming_draft_registry.dart';
import 'package:ai_team/application/task_queue_controller.dart';
import 'package:ai_team/application/workspace_command_controller.dart';
import 'package:ai_team/core/commands.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/orchestrator.dart';
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

  group('ConversationController', () {
    test('owns member chat session creation and selection', () {
      var state = AppState.seed().copyWith(
        conversations: AppState.seed()
            .conversations
            .where((conversation) => conversation.memberId != 'member-frontend')
            .toList(),
      );
      var selectedId = 'conv-team-default';
      String? activeId = 'team-default';
      var notified = false;
      final controller = ConversationController(
        readState: () => state,
        commit: (nextState) => state = nextState,
        sessions: ConversationSessionStore(),
        selectedConversationId: () => selectedId,
        activeTeamId: () => activeId,
        updateSelection: ({
          required selectedConversationId,
          required activeTeamId,
        }) {
          selectedId = selectedConversationId;
          activeId = activeTeamId;
        },
        notify: () => notified = true,
        clearDraftsForConversation: (_) {},
      );

      controller.startMemberChat(
        state.teams.firstWhere((team) => team.id == 'team-default'),
        'member-frontend',
      );

      final created = state.conversations.firstWhere(
        (conversation) => conversation.memberId == 'member-frontend',
      );
      expect(created.title, '前端工程师');
      expect(selectedId, created.id);
      expect(activeId, 'team-default');
      expect(notified, isTrue);
    });

    test('can close the selected conversation object when alternatives remain',
        () {
      var state = AppState.seed();
      var selectedId = 'conv-member-frontend';
      String? activeId = 'team-default';
      var notified = false;
      final sessions = ConversationSessionStore()..sync(state);
      final controller = ConversationController(
        readState: () => state,
        commit: (nextState) => state = nextState,
        sessions: sessions,
        selectedConversationId: () => selectedId,
        activeTeamId: () => activeId,
        updateSelection: ({
          required selectedConversationId,
          required activeTeamId,
        }) {
          selectedId = selectedConversationId;
          activeId = activeTeamId;
        },
        notify: () => notified = true,
        clearDraftsForConversation: (_) {},
      );

      controller.closeConversation('conv-member-frontend');

      expect(sessions.hiddenConversationIds, contains('conv-member-frontend'));
      expect(selectedId, isNot('conv-member-frontend'));
      expect(activeId, 'team-default');
      expect(notified, isTrue);
    });
  });

  group('DispatchController', () {
    test('owns paused-conversation dispatch gate and error state', () async {
      var state = AppState.seed().copyWith(
        conversations: AppState.seed()
            .conversations
            .map((conversation) => conversation.id == 'conv-team-default'
                ? conversation.copyWith(status: ConversationStatus.paused)
                : conversation)
            .toList(),
      );
      var notifyCount = 0;
      final taskQueue = TaskQueueController(
        readState: () => state,
        commit: (nextState) => state = nextState,
        gateway: FakeModelGateway(),
      );
      final workspaceCommands = WorkspaceCommandController(
        readState: () => state,
        commit: (nextState) => state = nextState,
      );
      final titleGenerator = ConversationTitleGenerator(
        readState: () => state,
        commit: (nextState) => state = nextState,
        gateway: FakeModelGateway(),
      );
      final controller = DispatchController(
        readState: () => state,
        commit: (nextState) => state = nextState,
        taskQueue: taskQueue,
        workspaceCommands: workspaceCommands,
        titleGenerator: titleGenerator,
        orchestrator: TeamOrchestrator(FakeModelGateway()),
        commandService: const CommandService(),
        selectedConversationId: () => 'conv-team-default',
        notify: () => notifyCount++,
        onStreamingDraft: ({required conversationId, required message}) {},
        clearStreamingDraftsForConversation: (_) {},
      );

      await controller.dispatch('不应发起模型调用');

      expect(controller.isDispatching, isFalse);
      expect(controller.error, contains('已暂停'));
      expect(notifyCount, 1);
      expect(
        state.conversations
            .firstWhere(
                (conversation) => conversation.id == 'conv-team-default')
            .messages,
        hasLength(1),
      );
    });
  });

  group('ConversationTitleGenerator', () {
    test('owns first-message title generation outside AppController', () async {
      var state = AppState.seed().copyWith(
        conversations: AppState.seed()
            .conversations
            .map((conversation) => conversation.id == 'conv-team-default'
                ? conversation.copyWith(title: '', messages: const [])
                : conversation)
            .toList(),
      );
      final generator = ConversationTitleGenerator(
        readState: () => state,
        commit: (nextState) => state = nextState,
        gateway: ScriptedTitleGateway(title: '登录修复'),
      );

      final conversation = state.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-team-default',
      );

      expect(generator.shouldGenerateAfterFirstUserMessage(conversation), true);

      await generator.generateAfterFirstUserMessage(
        conversationId: conversation.id,
        firstUserMessage: '修复登录页',
      );

      expect(
        state.conversations
            .firstWhere(
                (conversation) => conversation.id == 'conv-team-default')
            .title,
        '登录修复',
      );
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
