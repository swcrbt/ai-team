import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/application/app_controller.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/file_dialogs.dart';
import 'package:ai_team/core/local_store.dart';
import 'package:ai_team/core/orchestrator.dart';

import '../support/model_gateway_fakes.dart';

void main() {
  test('controller notifies persistence callback after configuration changes',
      () async {
    AppState? persisted;
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
      onStateChanged: (state) => persisted = state,
    );
    addTearDown(controller.dispose);

    controller.addModel(
      const ModelProfile(
        id: 'model-extra',
        name: 'Extra',
        baseUrl: 'https://example.com/v1',
        modelName: 'example-model',
        apiKey: 'secret',
      ),
    );
    await controller.flushPersistence();

    expect(persisted, isNotNull);
    expect(persisted!.models.map((model) => model.id), contains('model-extra'));
  });

  test('controller flushes async persistence before shutdown', () async {
    AppState? persisted;
    final saveCompleter = Completer<void>();
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
      onStateChanged: (state) async {
        await saveCompleter.future;
        persisted = state;
      },
    );
    addTearDown(controller.dispose);

    controller.addModel(
      const ModelProfile(
        id: 'model-extra',
        name: 'Extra',
        baseUrl: 'https://example.com/v1',
        modelName: 'example-model',
        apiKey: 'secret',
      ),
    );
    final flushed = controller.flushPersistence();
    await Future<void>.delayed(Duration.zero);

    expect(persisted, isNull);
    saveCompleter.complete();
    await flushed;

    expect(persisted!.models.map((model) => model.id), contains('model-extra'));
  });

  test('controller edits and protects model role member configuration', () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);

    const model = ModelProfile(
      id: 'model-extra',
      name: 'Extra',
      baseUrl: 'https://example.com/v1',
      modelName: 'example-model',
      apiKey: 'secret',
    );
    const role = RoleTemplate(
      id: 'role-extra',
      name: 'Reviewer',
      description: 'Review role',
      identityPrompt: '你是代码审查员。',
      goalPrompt: '检查风险。',
      constraintPrompt: '只读。',
      outputFormatPrompt: '列出问题。',
      commandPolicy: CommandPolicy(
        allowedCommands: ['rg'],
        blockedCommands: ['rm'],
        allowedDirectories: [],
        requiresConfirmation: true,
      ),
    );
    const member = TeamMember(
      id: 'member-extra',
      name: '代码审查员',
      roleId: 'role-extra',
      modelId: 'model-extra',
    );

    controller.addModel(model);
    controller.addRole(role);
    controller.addMember(member);
    controller.updateModel(model.copyWith(name: 'Extra Updated'));
    controller.updateRole(role.copyWith(name: 'Reviewer Updated'));
    controller.updateMember(member.copyWith(name: '审查员'));

    expect(controller.state.models.last.name, 'Extra Updated');
    expect(controller.state.roles.last.name, 'Reviewer Updated');
    expect(controller.state.members.last.name, '审查员');
    expect(() => controller.deleteModel('model-extra'), throwsStateError);
    expect(() => controller.deleteRole('role-extra'), throwsStateError);
    expect(() => controller.deleteMember('member-secretary'), throwsStateError);

    controller.deleteMember('member-extra');
    controller.deleteRole('role-extra');
    controller.deleteModel('model-extra');

    expect(controller.state.members.map((item) => item.id),
        isNot(contains('member-extra')));
    expect(controller.state.roles.map((item) => item.id),
        isNot(contains('role-extra')));
    expect(controller.state.models.map((item) => item.id),
        isNot(contains('model-extra')));
  });

  test('controller edits and deletes team configuration', () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);

    final team = controller.addTeam(
      name: '移动端小队',
      memberIds: const ['member-frontend'],
      collaborationMode: TeamCollaborationMode.serial,
    );

    controller.updateTeam(
      teamId: team.id,
      name: '移动端交付组',
      memberIds: const ['member-tester'],
      collaborationMode: TeamCollaborationMode.parallel,
    );

    final edited = controller.state.teams.firstWhere(
      (item) => item.id == team.id,
    );
    expect(edited.name, '移动端交付组');
    expect(edited.memberIds, ['member-secretary', 'member-tester']);
    expect(edited.collaborationMode, TeamCollaborationMode.parallel);
    expect(
      controller.state.conversations.any(
        (conversation) =>
            conversation.teamId == team.id &&
            conversation.memberId == 'member-tester',
      ),
      isFalse,
    );
    expect(
      controller.state.conversations.any(
        (conversation) =>
            conversation.teamId == team.id &&
            conversation.memberId == 'member-frontend',
      ),
      isFalse,
    );

    controller.startTeamChat(team.id);
    controller.startMemberChat('member-tester');
    expect(
      controller.state.conversations.any(
        (conversation) =>
            conversation.teamId == team.id &&
            conversation.memberId == 'member-tester',
      ),
      isTrue,
    );
    controller.deleteTeam(team.id);

    expect(controller.state.teams.map((item) => item.id),
        isNot(contains(team.id)));
    expect(
      controller.state.conversations.map((conversation) => conversation.teamId),
      isNot(contains(team.id)),
    );
    expect(controller.currentTeam.id, 'team-default');
    expect(
        controller.state.auditLog.map((entry) => entry.action),
        containsAll([
          'team_updated',
          'team_deleted',
        ]));
    expect(() => controller.deleteTeam('team-default'), throwsStateError);
  });

  test('controller rejects invalid model configuration', () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);

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
    expect(
      () => controller.addModel(
        const ModelProfile(
          id: 'model-hot',
          name: 'Too Hot',
          baseUrl: 'https://example.com/v1',
          modelName: 'example-model',
          apiKey: 'secret',
          temperature: 3,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => controller.addModel(
        const ModelProfile(
          id: 'model-zero-token',
          name: 'No Tokens',
          baseUrl: 'https://example.com/v1',
          modelName: 'example-model',
          apiKey: 'secret',
          maxTokens: 0,
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
      'controller enqueues titled tasks by priority without preempting running work',
      () async {
    final gateway = ScriptedTitleGateway(title: '登录任务');
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(gateway),
    );
    addTearDown(controller.dispose);
    controller.startTeamChat('team-default');

    await controller.enqueueCurrentConversationTask('低优先级', priority: 0);
    await controller.enqueueCurrentConversationTask('高优先级', priority: 10);
    await controller.enqueueCurrentConversationTask('同优先级', priority: 10);

    expect(
      controller.pendingTasksForCurrentConversation
          .map((task) => task.originalText),
      ['高优先级', '同优先级', '低优先级'],
    );
  });

  test('controller creates a scoped new private session for current member',
      () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);
    controller.startMemberChat('member-frontend');
    final originalConversationId = controller.selectedConversationId;
    final visibleCount = controller.visibleConversations.length;

    final created = controller.createConversationLikeCurrent();

    expect(created.id, isNot(originalConversationId));
    expect(created.teamId, 'team-default');
    expect(created.memberId, 'member-frontend');
    expect(created.title, isEmpty);
    expect(created.messages, isEmpty);
    expect(controller.selectedConversationId, created.id);
    expect(controller.visibleConversations, hasLength(visibleCount));
    expect(
      controller.visibleConversations.where((conversation) =>
          conversation.teamId == 'team-default' &&
          conversation.memberId == 'member-frontend'),
      hasLength(1),
    );
    expect(
      controller.conversationHistory.map((conversation) => conversation.id),
      containsAll([originalConversationId, created.id]),
    );
    expect(
      controller.conversationById(originalConversationId).messages,
      isNotEmpty,
    );
  });

  test('controller creates a scoped new team session without affecting members',
      () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);
    controller.startTeamChat('team-default');
    final originalTeamConversationId = controller.selectedConversationId;
    controller.startMemberChat('member-frontend');
    final memberConversationId = controller.selectedConversationId;
    controller.startTeamChat('team-default');

    final created = controller.createConversationLikeCurrent();

    expect(created.id, isNot(originalTeamConversationId));
    expect(created.teamId, 'team-default');
    expect(created.memberId, isNull);
    expect(created.messages, isEmpty);
    expect(controller.selectedConversationId, created.id);
    expect(
      controller.conversationHistory.map((conversation) => conversation.id),
      containsAll([originalTeamConversationId, created.id]),
    );
    expect(
      controller.conversationHistory
          .every((conversation) => conversation.memberId == null),
      isTrue,
    );

    controller.startMemberChat('member-frontend');

    expect(controller.selectedConversationId, memberConversationId);
  });

  test('controller reuses the current empty session when creating again', () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);
    controller.startMemberChat('member-frontend');

    final created = controller.createConversationLikeCurrent();
    final scopedSessionCount = controller.state.conversations
        .where((conversation) =>
            conversation.teamId == 'team-default' &&
            conversation.memberId == 'member-frontend')
        .length;
    final reused = controller.createConversationLikeCurrent();

    expect(reused.id, created.id);
    expect(
      controller.state.conversations
          .where((conversation) =>
              conversation.teamId == 'team-default' &&
              conversation.memberId == 'member-frontend')
          .length,
      scopedSessionCount,
    );
  });

  test('controller reuses an existing empty session for the same object', () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);
    controller.startMemberChat('member-frontend');
    final originalConversationId = controller.selectedConversationId;
    final emptySession = controller.createConversationLikeCurrent();
    controller.selectConversation(originalConversationId);
    final scopedSessionCount = controller.state.conversations
        .where((conversation) =>
            conversation.teamId == 'team-default' &&
            conversation.memberId == 'member-frontend')
        .length;

    final reused = controller.createConversationLikeCurrent();

    expect(reused.id, emptySession.id);
    expect(controller.selectedConversationId, emptySession.id);
    expect(
      controller.state.conversations
          .where((conversation) =>
              conversation.teamId == 'team-default' &&
              conversation.memberId == 'member-frontend')
          .length,
      scopedSessionCount,
    );
    expect(
      controller.state.conversations
          .where((conversation) =>
              conversation.teamId == 'team-default' &&
              conversation.memberId == 'member-frontend' &&
              conversation.messages.isEmpty)
          .length,
      1,
    );
  });

  test('controller deletes a non-current session and cleans linked state', () {
    final now = DateTime(2026, 6, 28);
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);
    controller.startMemberChat('member-frontend');
    final currentConversationId = controller.selectedConversationId;
    final emptySession = controller.createConversationLikeCurrent();
    controller.selectConversation(currentConversationId);
    controller.openedConversationIds.add(emptySession.id);
    controller.hiddenConversationIds.add(emptySession.id);
    controller.pinnedConversationIds.add(emptySession.id);
    controller.pinnedConversationOrderIds.add(emptySession.id);
    controller.conversationOrderIds.add(emptySession.id);
    controller.state = controller.state.copyWith(
      queuedTasks: [
        QueuedTask(
          id: 'task-delete-session',
          conversationId: emptySession.id,
          title: '删除目标任务',
          originalText: '删除目标任务',
          priority: 0,
          status: QueuedTaskStatus.pending,
          createdAt: now,
          updatedAt: now,
        ),
      ],
      taskAssignments: [
        TaskAssignment(
          id: 'assignment-delete-session',
          conversationId: emptySession.id,
          round: 1,
          memberId: 'member-frontend',
          memberName: '前端工程师',
          roleName: '前端',
          instruction: '删除目标分配',
          status: TaskAssignmentStatus.pending,
          createdAt: now,
        ),
      ],
    );

    controller.deleteConversationSession(emptySession.id);

    expect(controller.selectedConversationId, currentConversationId);
    expect(
      controller.state.conversations.map((conversation) => conversation.id),
      isNot(contains(emptySession.id)),
    );
    expect(controller.state.queuedTasks, isEmpty);
    expect(controller.state.taskAssignments, isEmpty);
    expect(controller.openedConversationIds, isNot(contains(emptySession.id)));
    expect(controller.hiddenConversationIds, isNot(contains(emptySession.id)));
    expect(controller.pinnedConversationIds, isNot(contains(emptySession.id)));
    expect(
      controller.pinnedConversationOrderIds,
      isNot(contains(emptySession.id)),
    );
    expect(controller.conversationOrderIds, isNot(contains(emptySession.id)));
  });

  test('controller deletes current session and stays on the same object', () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);
    controller.startMemberChat('member-frontend');
    final originalConversationId = controller.selectedConversationId;
    final emptySession = controller.createConversationLikeCurrent();

    controller.deleteConversationSession(emptySession.id);

    expect(controller.selectedConversationId, originalConversationId);
    expect(
      controller.currentConversation.memberId,
      'member-frontend',
    );

    controller.deleteConversationSession(originalConversationId);

    expect(controller.currentConversation.memberId, 'member-frontend');
    expect(controller.currentConversation.messages, isEmpty);
    expect(
      controller.state.conversations
          .where((conversation) =>
              conversation.teamId == 'team-default' &&
              conversation.memberId == 'member-frontend')
          .length,
      1,
    );
  });

  test('conversation history is scoped to the current member or team', () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);
    controller.startMemberChat('member-frontend');
    final frontendSession = controller.createConversationLikeCurrent();
    controller.startMemberChat('member-tester');
    final testerSession = controller.createConversationLikeCurrent();
    controller.startTeamChat('team-default');
    final teamSession = controller.createConversationLikeCurrent();

    controller.selectConversation(frontendSession.id);

    expect(
      controller.conversationHistory
          .every((conversation) => conversation.memberId == 'member-frontend'),
      isTrue,
    );
    expect(
      controller.conversationHistory.map((conversation) => conversation.id),
      isNot(contains(testerSession.id)),
    );
    expect(
      controller.conversationHistory.map((conversation) => conversation.id),
      isNot(contains(teamSession.id)),
    );
  });

  test('first user message generates a Codex-style conversation title',
      () async {
    final gateway = ConversationTitleGateway(
      title: '登录修复',
      reply: '前端完成',
    );
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(gateway),
    );
    addTearDown(controller.dispose);
    controller.startMemberChat('member-frontend');
    final created = controller.createConversationLikeCurrent();

    await controller.dispatchConversation(created.id, '修复登录表单的校验');

    final updated = controller.conversationById(created.id);
    expect(updated.title, '登录修复');
    expect(updated.messages.where((message) => message.isUser), hasLength(1));
    expect(updated.messages.last.content, '前端完成');
  });

  test('conversation title generation failure does not block the reply',
      () async {
    final gateway = ConversationTitleGateway(
      title: '不会使用',
      reply: '普通回复',
      failTitle: true,
    );
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(gateway),
    );
    addTearDown(controller.dispose);
    controller.startMemberChat('member-frontend');
    final created = controller.createConversationLikeCurrent();

    await controller.dispatchConversation(created.id, '继续实现新增会话');

    final updated = controller.conversationById(created.id);
    expect(updated.title, isEmpty);
    expect(updated.messages.last.content, '普通回复');
    expect(controller.error, isNull);
  });

  test('conversation title matching preview stays as preview fallback',
      () async {
    final gateway = ConversationTitleGateway(
      title: '修复登录表单',
      reply: '已处理',
    );
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(gateway),
    );
    addTearDown(controller.dispose);
    controller.startMemberChat('member-frontend');
    final created = controller.createConversationLikeCurrent();

    await controller.dispatchConversation(created.id, '修复登录表单');

    expect(controller.conversationById(created.id).title, isEmpty);
  });

  test('controller appends task notes and links the system message', () {
    final controller = AppController(
      AppState.seed().copyWith(
        queuedTasks: [
          QueuedTask(
            id: 'task-1',
            conversationId: 'conv-team-default',
            title: '登录任务',
            originalText: '实现登录',
            priority: 0,
            status: QueuedTaskStatus.pending,
            createdAt: DateTime(2026, 6, 14),
            updatedAt: DateTime(2026, 6, 14),
          ),
        ],
      ),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);
    controller.startTeamChat('team-default');

    controller.appendTaskNote('task-1', '补充移动端');

    final task = controller.state.queuedTasks.single;
    expect(task.notes, ['补充移动端']);
    expect(controller.currentConversation.messages.last.content, '已为任务追加备注');
    expect(controller.currentConversation.messages.last.taskIds, ['task-1']);
    expect(
      task.messageIds,
      contains(controller.currentConversation.messages.last.id),
    );
  });

  test(
      'controller deletes a queued task and associated messages after confirmation path',
      () {
    final message = ChatMessage(
      id: 'msg-task',
      authorName: '我',
      content: '实现登录',
      createdAt: DateTime(2026, 6, 14),
      isUser: true,
      taskIds: const ['task-1'],
    );
    final seed = AppState.seed();
    final state = seed.copyWith(
      queuedTasks: [
        QueuedTask(
          id: 'task-1',
          conversationId: 'conv-team-default',
          title: '登录任务',
          originalText: '实现登录',
          priority: 0,
          status: QueuedTaskStatus.pending,
          createdAt: DateTime(2026, 6, 14),
          updatedAt: DateTime(2026, 6, 14),
          messageIds: const ['msg-task'],
        ),
      ],
      conversations: [
        seed.conversations
            .firstWhere(
          (conversation) => conversation.id == 'conv-team-default',
        )
            .copyWith(messages: [message]),
        ...seed.conversations.where(
          (conversation) => conversation.id != 'conv-team-default',
        ),
      ],
    );
    final controller =
        AppController(state, TeamOrchestrator(FakeModelGateway()));
    addTearDown(controller.dispose);
    controller.startTeamChat('team-default');

    controller.deleteTask('task-1');

    expect(controller.state.queuedTasks, isEmpty);
    expect(controller.currentConversation.messages, isEmpty);
  });

  test('team pause cancels active request and resume reruns unfinished task',
      () async {
    final gateway = BlockingModelGateway();
    final controller = AppController(
      AppState.seed().copyWith(
        queuedTasks: [
          QueuedTask(
            id: 'task-1',
            conversationId: 'conv-team-default',
            title: '长任务',
            originalText: '执行长任务',
            priority: 0,
            status: QueuedTaskStatus.pending,
            createdAt: DateTime(2026, 6, 14),
            updatedAt: DateTime(2026, 6, 14),
          ),
        ],
      ),
      TeamOrchestrator(gateway),
    );
    addTearDown(controller.dispose);
    controller.startTeamChat('team-default');

    final run = controller.runNextQueuedTask();
    await gateway.started.future.timeout(const Duration(seconds: 1));
    controller.pauseTask('task-1');
    await run;

    expect(gateway.cancellation!.isCancelled, isTrue);
    expect(controller.state.queuedTasks.single.status, QueuedTaskStatus.paused);
  });

  test(
      'controller starts member chat in the active team without conversation id collisions',
      () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);

    final mobileTeam = controller.addTeam(
      name: '移动端小队',
      memberIds: const ['member-frontend', 'member-tester'],
      collaborationMode: TeamCollaborationMode.serial,
    );

    controller.startTeamChat(mobileTeam.id);
    controller.startMemberChat('member-frontend');

    expect(controller.currentConversation.teamId, mobileTeam.id);
    expect(controller.currentConversation.memberId, 'member-frontend');
    expect(
      controller.state.conversations
          .map((conversation) => conversation.id)
          .toSet()
          .length,
      controller.state.conversations.length,
    );
  });

  test('controller rejects incomplete role prompt configuration', () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);

    expect(
      () => controller.addRole(
        const RoleTemplate(
          id: 'role-invalid',
          name: 'Invalid',
          description: 'Bad role',
          identityPrompt: '你是一个角色。',
          goalPrompt: '',
          constraintPrompt: '遵守限制。',
          outputFormatPrompt: '输出结果。',
          commandPolicy: CommandPolicy(
            allowedCommands: ['rg'],
            blockedCommands: ['rm'],
            allowedDirectories: [],
            requiresConfirmation: true,
          ),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => controller.addRole(
        const RoleTemplate(
          id: 'role-no-command',
          name: 'No command',
          description: 'Bad role',
          identityPrompt: '你是一个角色。',
          goalPrompt: '完成任务。',
          constraintPrompt: '遵守限制。',
          outputFormatPrompt: '输出结果。',
          commandPolicy: CommandPolicy(
            allowedCommands: [],
            blockedCommands: ['rm'],
            allowedDirectories: [],
            requiresConfirmation: true,
          ),
        ),
      ),
      throwsArgumentError,
    );
  });

  test('controller applies updated role command policy', () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);
    final role =
        controller.state.roles.firstWhere((item) => item.id == 'role-frontend');

    controller.updateRole(
      role.copyWith(
        commandPolicy: const CommandPolicy(
          allowedCommands: ['dart test'],
          blockedCommands: ['flutter test'],
          allowedDirectories: ['/workspace/app'],
          requiresConfirmation: false,
        ),
      ),
    );
    final updated =
        controller.state.roles.firstWhere((item) => item.id == 'role-frontend');

    expect(
      updated.commandPolicy.evaluate(
        'dart test',
        workingDirectory: '/workspace/app',
      ),
      CommandDecision.allowed,
    );
    expect(
      updated.commandPolicy.evaluate(
        'flutter test',
        workingDirectory: '/workspace/app',
      ),
      CommandDecision.denied,
    );
  });

  test('controller dispatches messages to a selected member conversation',
      () async {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);
    final teamMessageCount = controller.teamConversation.messages.length;

    controller.startMemberChat('member-frontend');
    await controller.dispatch('请只实现前端面板');

    final updatedMemberConversation =
        controller.conversationForMember('member-frontend');
    expect(updatedMemberConversation.messages.map((message) => message.content),
        contains('请只实现前端面板'));
    expect(
      updatedMemberConversation.messages
          .any((message) => message.authorName == '前端工程师'),
      isTrue,
    );
    expect(controller.teamConversation.messages.length, teamMessageCount);
    expect(controller.state.auditLog.last.action, 'member_chat_dispatched');
  });

  test('controller lets secretary privately dispatch to mentioned members',
      () async {
    final gateway = RecordingModelGateway();
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(gateway),
    );
    addTearDown(controller.dispose);

    controller.startMemberChat('member-secretary');
    await controller.dispatch('分配任务给测试工程师，询问 7 年前妈妈年龄是儿子的 6 倍。');

    expect(controller.selectedConversationId, 'conv-member-secretary');
    expect(gateway.modelIds, ['model-local']);
    final testerConversation =
        controller.conversationForMember('member-tester');
    expect(
      testerConversation.messages.map((message) => message.content),
      contains(
        contains('任务分配：分配任务给测试工程师，询问 7 年前妈妈年龄是儿子的 6 倍。'),
      ),
    );
    expect(testerConversation.messages.last.authorName, '测试工程师');
    expect(testerConversation.messages.last.content, contains('qwen2.5-coder'));
    expect(controller.currentConversation.messages.last.authorName, '秘书');
    expect(
      controller.currentConversation.messages.last.content,
      contains('测试工程师'),
    );
    expect(
      controller.state.auditLog.map((entry) => entry.action),
      contains('secretary_private_member_dispatch'),
    );
  });

  test('controller keeps ordinary secretary private chat unchanged', () async {
    final gateway = RecordingModelGateway();
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(gateway),
    );
    addTearDown(controller.dispose);

    controller.startMemberChat('member-secretary');
    await controller.dispatch('帮我解释一下这个数学题');

    expect(gateway.modelIds, ['model-main']);
    expect(controller.currentConversation.messages.last.authorName, '秘书');
    expect(
      controller.state.auditLog.map((entry) => entry.action),
      isNot(contains('secretary_private_member_dispatch')),
    );
    expect(controller.state.auditLog.last.action, 'member_chat_dispatched');
  });

  test('controller dispatches selected member chat with the configured model',
      () async {
    final gateway = RecordingModelGateway();
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(gateway),
    );
    addTearDown(controller.dispose);
    const doubao = ModelProfile(
      id: 'model-doubao',
      name: 'Doubao',
      baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
      modelName: 'doubao-test-endpoint',
      apiKey: 'secret',
    );

    controller.addModel(doubao);
    final tester = controller.state.members.firstWhere(
      (member) => member.id == 'member-tester',
    );
    controller.updateMember(tester.copyWith(modelId: doubao.id));
    controller.startMemberChat('member-tester');
    await controller.dispatch('请验证模型绑定');

    expect(gateway.modelIds, ['model-doubao']);
    expect(gateway.modelNames, ['doubao-test-endpoint']);
    expect(
      controller.conversationForMember('member-tester').messages.last.content,
      contains('doubao-test-endpoint'),
    );
  });

  test('controller creates teams and starts team chat explicitly', () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);

    final team = controller.addTeam(
      name: '移动端小队',
      memberIds: const ['member-frontend', 'member-tester'],
    );

    expect(team.name, '移动端小队');
    expect(team.memberIds, [
      'member-secretary',
      'member-frontend',
      'member-tester',
    ]);
    expect(controller.activeTeamId, isNull);
    expect(
      controller.state.conversations
          .where(
            (conversation) =>
                conversation.teamId == team.id && conversation.memberId == null,
          )
          .single
          .title,
      '团队会话',
    );

    controller.startTeamChat(team.id);

    expect(controller.activeTeamId, team.id);
    expect(controller.currentTeam.id, team.id);
    expect(controller.currentConversation.memberId, isNull);
    expect(controller.currentConversation.teamId, team.id);
  });

  test('controller creates missing member conversation when starting chat', () {
    final oldState = AppState.seed().copyWith(
      conversations: [
        AppState.seed().conversations.firstWhere(
              (conversation) => conversation.memberId == null,
            ),
      ],
    );
    final controller = AppController(
      oldState,
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);

    expect(
      controller.state.conversations
          .where((conversation) => conversation.memberId != null),
      isEmpty,
    );
    controller.startMemberChat('member-frontend');

    expect(controller.conversationForMember('member-frontend').title, '前端工程师');
    expect(controller.currentConversation.memberId, 'member-frontend');
  });

  test('controller registers workspace and creates patch proposal from file',
      () async {
    final temp = await Directory.systemTemp.createTemp('ai_team_workspace_');
    addTearDown(() async => temp.delete(recursive: true));
    final file = File('${temp.path}/README.md');
    await file.writeAsString('old docs\n');
    AppState? persisted;
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
      onStateChanged: (state) => persisted = state,
    );
    addTearDown(controller.dispose);

    controller.addWorkspacePath(temp.path);
    await controller.flushPersistence();
    final preview = await controller.readWorkspaceFile(
      workspaceId: persisted!.workspaces.single.id,
      relativePath: 'README.md',
    );
    await controller.proposeWorkspacePatch(
      workspaceId: persisted!.workspaces.single.id,
      relativePath: 'README.md',
      proposedContent: 'new docs\n',
      memberName: '前端工程师',
    );
    await controller.flushPersistence();

    expect(preview, 'old docs\n');
    expect(controller.patchProposals.single.diff, contains('+new docs'));
    expect(persisted!.patchProposals.single.diff, contains('+new docs'));
    expect(await file.readAsString(), 'old docs\n');
  });

  test('controller lists workspace files as safe relative paths', () async {
    final temp = await Directory.systemTemp.createTemp('ai_team_list_');
    addTearDown(() async => temp.delete(recursive: true));
    await Directory('${temp.path}/lib').create();
    await Directory('${temp.path}/.git').create();
    await File('${temp.path}/README.md').writeAsString('docs\n');
    await File('${temp.path}/lib/main.dart').writeAsString('void main() {}\n');
    await File('${temp.path}/.git/config').writeAsString('private\n');
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);

    controller.addWorkspacePath(temp.path);
    final files = await controller.listWorkspaceFiles(
      workspaceId: controller.state.workspaces.single.id,
    );

    expect(files, ['README.md', 'lib/main.dart']);
  });

  test('controller adds workspace through file dialog service', () async {
    final temp = await Directory.systemTemp.createTemp('ai_team_pick_');
    addTearDown(() async => temp.delete(recursive: true));
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
      fileDialogs: FakeFileDialogService(directoryPath: temp.path),
    );
    addTearDown(controller.dispose);

    final added = await controller.pickAndAddWorkspace();

    expect(added, isTrue);
    expect(controller.state.workspaces.single.path, temp.absolute.path);
  });

  test('controller exports configuration through file dialog service',
      () async {
    final temp = await Directory.systemTemp.createTemp('ai_team_export_');
    addTearDown(() async => temp.delete(recursive: true));
    final target = File('${temp.path}/config.json');
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
      fileDialogs: FakeFileDialogService(savePath: target.path),
    );
    addTearDown(controller.dispose);

    final exported =
        await controller.exportConfiguration(includeSecrets: false);

    expect(exported, isTrue);
    expect(await target.readAsString(), isNot(contains('"apiKey"')));
  });

  test('controller preserves local api keys when importing redacted config',
      () async {
    final temp = await Directory.systemTemp.createTemp('ai_team_import_');
    addTearDown(() async => temp.delete(recursive: true));
    final source = File('${temp.path}/config.json');
    final imported = AppState.seed().copyWith(
      models: [
        AppState.seed().models.first.copyWith(
              name: 'Imported model',
              apiKey: '',
            ),
      ],
    );
    await source.writeAsString(jsonEncode(
      ConfigExporter.exportState(imported, includeSecrets: false),
    ));
    final controller = AppController(
      AppState.seed().copyWith(
        models: [
          AppState.seed().models.first.copyWith(apiKey: 'kept-secret'),
        ],
      ),
      TeamOrchestrator(FakeModelGateway()),
      fileDialogs: FakeFileDialogService(openPath: source.path),
    );
    addTearDown(controller.dispose);

    final result = await controller.importConfiguration();

    expect(result, isTrue);
    expect(controller.state.models.single.name, 'Imported model');
    expect(controller.state.models.single.apiKey, 'kept-secret');
  });

  test('controller preserves an existing model api key on empty update', () {
    final controller = AppController(
      AppState.seed().copyWith(
        models: [
          AppState.seed().models.first.copyWith(apiKey: 'kept-secret'),
        ],
      ),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);

    controller.updateModel(
      controller.state.models.first.copyWith(
        name: 'Renamed model',
        apiKey: '',
      ),
    );

    expect(controller.state.models.first.name, 'Renamed model');
    expect(controller.state.models.first.apiKey, 'kept-secret');
  });

  test('controller keeps current state when configuration import fails',
      () async {
    final temp = await Directory.systemTemp.createTemp('ai_team_import_bad_');
    addTearDown(() async => temp.delete(recursive: true));
    final source = File('${temp.path}/bad.json');
    await source.writeAsString('{bad json');
    final original = AppState.seed();
    final controller = AppController(
      original,
      TeamOrchestrator(FakeModelGateway()),
      fileDialogs: FakeFileDialogService(openPath: source.path),
    );
    addTearDown(controller.dispose);

    final imported = await controller.importConfiguration();

    expect(imported, isFalse);
    expect(controller.state.models.length, original.models.length);
    expect(controller.error, contains('导入配置失败'));
  });

  test(
      'controller creates command confirmation requests and audits denied commands',
      () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);

    final pending = controller.requestCommand(
      memberId: 'member-frontend',
      command: 'flutter test',
      workingDirectory: '/tmp/project',
    );
    final denied = controller.requestCommand(
      memberId: 'member-frontend',
      command: 'rm -rf .',
      workingDirectory: '/tmp/project',
    );

    expect(pending.status, CommandRequestStatus.pending);
    expect(denied.status, CommandRequestStatus.denied);
    expect(controller.state.commandRequests.length, 2);
    expect(controller.state.auditLog.last.action, 'command_denied');
    expect(
      () => controller.updateCommandRequestStatus(
        denied.id,
        CommandRequestStatus.approved,
      ),
      throwsStateError,
    );
  });

  test('controller executes only approved command requests', () async {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);
    final request = controller.requestCommand(
      memberId: 'member-frontend',
      command: 'flutter test',
      workingDirectory: Directory.current.path,
    );

    await expectLater(
      controller.executeCommandRequest(
        request.id,
        runner: (_, __) async => ProcessResult(1, 0, 'ok', ''),
      ),
      throwsStateError,
    );

    controller.updateCommandRequestStatus(
      request.id,
      CommandRequestStatus.approved,
    );
    final executed = await controller.executeCommandRequest(
      request.id,
      runner: (_, __) async => ProcessResult(1, 0, 'ok', ''),
    );

    expect(executed.status, CommandRequestStatus.executed);
    expect(executed.output, 'ok');
    expect(controller.state.auditLog.last.action, 'command_executed');
  });

  test('controller manual allowed command requests wait for explicit execution',
      () {
    final state = AppState.seed().copyWith(
      roles: AppState.seed()
          .roles
          .map(
            (role) => role.id == 'role-frontend'
                ? role.copyWith(
                    commandPolicy: const CommandPolicy(
                      allowedCommands: ['*'],
                      blockedCommands: [],
                      allowedDirectories: [],
                      requiresConfirmation: false,
                    ),
                  )
                : role,
          )
          .toList(),
    );
    final controller = AppController(
      state,
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);

    final request = controller.requestCommand(
      memberId: 'member-frontend',
      command: 'df -h /',
      workingDirectory: '/',
    );

    expect(request.decision, CommandDecision.allowed);
    expect(request.status, CommandRequestStatus.approved);
    expect(request.output, isNull);
    expect(controller.state.auditLog.last.action, 'command_requested');
  });

  test(
      'controller executes scoped command request and continues member reply with output',
      () async {
    final toolMessage = ChatMessage(
      id: 'msg-tool',
      authorName: '秘书',
      memberId: 'member-secretary',
      content: '我先申请执行命令',
      createdAt: DateTime(2026, 6, 29),
      contentBlocks: const [
        ChatMessageContentBlock.text('我先申请执行命令'),
      ],
    );
    final request = CommandRequest.pending(
      id: 'command-df',
      memberName: '秘书',
      command: 'df -h /',
      workingDirectory: '/',
      decision: CommandDecision.requiresConfirmation,
      conversationId: 'conv-member-secretary',
      memberId: 'member-secretary',
      toolCallId: 'call-df',
      messageId: 'msg-tool',
    );
    final gateway = RecordingScriptedGateway(['根目录已使用 42G']);
    final seed = AppState.seed();
    final conversation = seed.conversations.firstWhere(
      (conversation) => conversation.id == 'conv-member-secretary',
    );
    final controller = AppController(
      seed.copyWith(
        conversations: seed.conversations
            .map(
              (item) => item.id == conversation.id
                  ? conversation.copyWith(messages: [toolMessage])
                  : item,
            )
            .toList(),
        commandRequests: [request],
      ),
      TeamOrchestrator(gateway),
    );
    addTearDown(controller.dispose);

    await controller.approveExecuteCommandRequestAndContinue(
      request.id,
      runner: (_, __) async => ProcessResult(
        7,
        0,
        'Filesystem      Size   Used  Avail Capacity Mounted on\n'
            '/dev/disk3s1s1  460Gi   42Gi  100Gi    30% /',
        '',
      ),
    );

    final executed = controller.state.commandRequests.single;
    final updatedConversation =
        controller.conversationById('conv-member-secretary');
    final updatedMessage = updatedConversation.messages.single;
    expect(executed.status, CommandRequestStatus.executed);
    expect(executed.output, contains('42Gi'));
    expect(updatedConversation.messages, hasLength(1));
    expect(updatedMessage.authorName, '秘书');
    expect(updatedMessage.content, contains('我先申请执行命令'));
    expect(updatedMessage.content, contains('根目录已使用 42G'));
    expect(updatedMessage.contentBlocks, hasLength(3));
    expect(updatedMessage.contentBlocks.first.text, '我先申请执行命令');
    expect(updatedMessage.contentBlocks[1].commandResult?.output,
        contains('42Gi'));
    expect(updatedMessage.contentBlocks.last.text, '根目录已使用 42G');
    expect(gateway.calls, 1);
    expect(
      gateway.recordedMessages.single.map((message) => message.content).join(
            '\n',
          ),
      contains('42Gi'),
    );
  });

  test('controller rejects scoped command request without continuing model',
      () async {
    final request = CommandRequest.pending(
      id: 'command-reject',
      memberName: '秘书',
      command: 'df -h /',
      workingDirectory: '/',
      decision: CommandDecision.requiresConfirmation,
      conversationId: 'conv-member-secretary',
      memberId: 'member-secretary',
      toolCallId: 'call-df',
    );
    final gateway = RecordingScriptedGateway(['不应调用']);
    final controller = AppController(
      AppState.seed().copyWith(commandRequests: [request]),
      TeamOrchestrator(gateway),
    );
    addTearDown(controller.dispose);
    final initialMessages =
        controller.conversationById('conv-member-secretary').messages.length;

    controller.updateCommandRequestStatus(
      request.id,
      CommandRequestStatus.denied,
    );

    expect(controller.state.commandRequests.single.status,
        CommandRequestStatus.denied);
    expect(gateway.calls, 0);
    expect(
      controller.conversationById('conv-member-secretary').messages.length,
      initialMessages,
    );
  });

  test('controller stops an in-flight team task by cancelling model requests',
      () async {
    final gateway = BlockingModelGateway();
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(gateway),
    );
    addTearDown(controller.dispose);
    controller.startTeamChat('team-default');

    final dispatch = controller.dispatch('请实现大型功能');
    await gateway.started.future;
    controller.stopConversation();
    await dispatch;

    expect(gateway.cancellation!.isCancelled, isTrue);
    expect(controller.isDispatching, isFalse);
    expect(controller.currentConversation.status, ConversationStatus.stopped);
    expect(
      controller.currentTaskAssignments.map((assignment) => assignment.status),
      contains(TaskAssignmentStatus.cancelled),
    );
    expect(
      controller.currentConversation.messages.map((message) => message.content),
      contains('任务已停止，本轮未完成的模型请求已取消。'),
    );
    expect(controller.state.auditLog.last.action, 'team_task_stopped');
  });

  test('controller blocks dispatch while paused but allows restart after stop',
      () async {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(FakeModelGateway()),
    );
    addTearDown(controller.dispose);
    controller.startTeamChat('team-default');
    final messageCount = controller.currentConversation.messages.length;

    controller.pauseConversation();
    await controller.dispatch('暂停时不应执行');

    expect(controller.currentConversation.messages.length, messageCount);
    expect(controller.error, contains('已暂停'));

    controller.resumeConversation();
    await controller.dispatch('继续后可以执行');

    expect(controller.currentConversation.messages.length,
        greaterThan(messageCount));

    controller.stopConversation();
    final stoppedCount = controller.currentConversation.messages.length;
    await controller.dispatch('停止后可以重新发送');

    expect(
      controller.currentConversation.messages.length,
      greaterThan(stoppedCount),
    );
    expect(controller.error, isNull);
    expect(controller.currentConversation.status, ConversationStatus.idle);
  });
}
