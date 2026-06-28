import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:ai_team/app.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/file_dialogs.dart';
import 'package:ai_team/core/model_gateway.dart';
import 'package:ai_team/core/orchestrator.dart';

void main() {
  const messageBottomThreshold = 24.0;

  test('streaming text partition commits stable lines and keeps live tail', () {
    final partition = StreamingTextPartition();

    var update = partition.apply('第一行\n第二');

    expect(update.reset, isFalse);
    expect(update.newStableSegments, ['第一行\n']);
    expect(update.tailChanged, isTrue);
    expect(partition.stableSegments, ['第一行\n']);
    expect(partition.liveTail, '第二');

    update = partition.apply('第一行\n第二行\n第三');

    expect(update.reset, isFalse);
    expect(update.newStableSegments, ['第二行\n']);
    expect(update.tailChanged, isTrue);
    expect(partition.stableSegments, ['第一行\n', '第二行\n']);
    expect(partition.liveTail, '第三');
  });

  test('streaming text partition rebuilds on non append updates', () {
    final partition = StreamingTextPartition();

    partition.apply('旧第一行\n旧尾巴');
    final update = partition.apply('新第一行\n新尾巴');

    expect(update.reset, isTrue);
    expect(update.newStableSegments, ['新第一行\n']);
    expect(partition.stableSegments, ['新第一行\n']);
    expect(partition.liveTail, '新尾巴');
  });

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
    final request = CommandRequest.pending(
      id: 'command-df',
      memberName: '秘书',
      command: 'df -h /',
      workingDirectory: '/',
      decision: CommandDecision.requiresConfirmation,
      conversationId: 'conv-member-secretary',
      memberId: 'member-secretary',
      toolCallId: 'call-df',
    );
    final gateway = RecordingScriptedWidgetGateway(['根目录已使用 42G']);
    final controller = AppController(
      AppState.seed().copyWith(commandRequests: [request]),
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
    final conversation = controller.conversationById('conv-member-secretary');
    expect(executed.status, CommandRequestStatus.executed);
    expect(executed.output, contains('42Gi'));
    expect(
      conversation.messages.map((message) => message.content),
      contains(contains('命令执行结果')),
    );
    expect(conversation.messages.last.authorName, '秘书');
    expect(conversation.messages.last.content, '根目录已使用 42G');
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
    final gateway = RecordingScriptedWidgetGateway(['不应调用']);
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

  testWidgets('desktop workspace separates chat and settings surfaces',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('群聊'), findsNothing);
    expect(find.text('私聊'), findsNothing);
    expect(find.text('秘书'), findsWidgets);
    expect(find.text('前端工程师'), findsWidgets);
    expect(find.text('测试工程师'), findsWidgets);
    expect(find.text('默认开发团队'), findsOneWidget);
    expect(find.textContaining('群聊 · 默认开发团队'), findsNothing);
    expect(find.byTooltip('模型'), findsOneWidget);
    expect(find.byTooltip('角色'), findsOneWidget);
    expect(find.byTooltip('成员'), findsOneWidget);
    expect(find.byTooltip('审计'), findsOneWidget);
    expect(find.byTooltip('设置'), findsOneWidget);
    expect(find.byTooltip('补丁'), findsNothing);
    expect(find.text('模型配置'), findsNothing);
    expect(find.text('角色配置'), findsNothing);
    expect(find.text('团队成员'), findsNothing);
    expect(find.text('补丁确认'), findsNothing);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('群聊'), findsNothing);
    expect(find.text('私聊'), findsNothing);
    expect(find.textContaining('群聊 · 默认开发团队'), findsNothing);
    expect(find.byTooltip('返回聊天'), findsNothing);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('模型'), findsNothing);
    expect(find.text('角色'), findsNothing);
    expect(find.text('成员'), findsNothing);
    expect(find.text('项目'), findsNothing);
    expect(find.text('命令'), findsOneWidget);
    expect(find.text('审计'), findsNothing);
    expect(find.text('审计日志'), findsNothing);
    expect(find.text('补丁'), findsNothing);
    expect(find.text('模型配置'), findsNothing);
    expect(find.text('角色配置'), findsNothing);
    expect(find.text('团队成员'), findsNothing);
    expect(find.text('项目工作区'), findsNothing);
    expect(find.text('任务轮次'), findsOneWidget);
    expect(find.text('补丁确认'), findsNothing);
  });

  testWidgets('chat workspace shows pending patch confirmations',
      (tester) async {
    final state = AppState.seed().copyWith(
      patchProposals: const [
        PatchProposal(
          id: 'patch-chat',
          filePath: '/tmp/README.md',
          originalContent: 'old docs\n',
          proposedContent: 'new docs\n',
          memberName: '前端工程师',
          diff: '--- README.md\n+++ README.md\n@@\n-old docs\n+new docs\n',
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('待确认修改'), findsOneWidget);
    expect(find.textContaining('+new docs'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '拒绝'));
    await tester.pumpAndSettle();

    expect(find.text('待确认修改'), findsNothing);
  });

  testWidgets('chat workspace shows scoped pending command requests',
      (tester) async {
    final state = AppState.seed().copyWith(
      commandRequests: [
        CommandRequest.pending(
          id: 'command-chat-df',
          memberName: '秘书',
          command: 'df -h /',
          workingDirectory: '/',
          decision: CommandDecision.requiresConfirmation,
          conversationId: 'conv-member-secretary',
          memberId: 'member-secretary',
          toolCallId: 'call-df',
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('待确认命令'), findsOneWidget);
    expect(find.textContaining('df -h /'), findsOneWidget);
    expect(find.textContaining('/'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '批准并执行'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '拒绝'), findsOneWidget);
  });

  testWidgets('chat workspace shows approved command requests without approval',
      (tester) async {
    final state = AppState.seed().copyWith(
      commandRequests: [
        CommandRequest.pending(
          id: 'command-chat-approved',
          memberName: '秘书',
          command: 'df -h /',
          workingDirectory: '/',
          decision: CommandDecision.allowed,
          conversationId: 'conv-member-secretary',
          memberId: 'member-secretary',
          toolCallId: 'call-df',
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('待确认命令'), findsNothing);
    expect(find.text('已允许命令'), findsOneWidget);
    expect(find.textContaining('df -h /'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '执行'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '批准并执行'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '拒绝'), findsNothing);
  });

  testWidgets('legacy unscoped pending commands remain visible in settings',
      (tester) async {
    final state = AppState.seed().copyWith(
      commandRequests: [
        CommandRequest.pending(
          id: 'command-legacy-df',
          memberName: '秘书',
          command: 'df -h /',
          workingDirectory: '/',
          decision: CommandDecision.requiresConfirmation,
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('待确认命令'), findsNothing);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('命令请求'), findsOneWidget);
    expect(find.textContaining('df -h /'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '批准'), findsOneWidget);
  });

  testWidgets(
      'desktop chat sidebar does not show quick avatars above group chat',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('群聊'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_QuickAvatar',
      ),
      findsNothing,
    );
  });

  testWidgets('chat header omits continue and stop controls', (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.byTooltip('暂停'), findsNothing);
    expect(find.byTooltip('继续'), findsNothing);
    expect(find.byTooltip('停止'), findsNothing);
  });

  testWidgets('chat messages show copy action and time on hover',
      (tester) async {
    const messageContent = '可以用鼠标拖拽选择的消息内容';
    const nextMessageContent = '下一条消息不能因为悬停而跳动';
    final seed = AppState.seed();
    final conversation = seed.conversations.firstWhere(
      (item) => item.id == 'conv-member-secretary',
    );
    final state = seed.copyWith(
      conversations: [
        conversation.copyWith(
          messages: [
            ChatMessage(
              id: 'msg-selectable',
              authorName: '秘书',
              content: messageContent,
              createdAt: DateTime(2026, 6, 14, 9, 5),
            ),
            ChatMessage(
              id: 'msg-after-selectable',
              authorName: '秘书',
              content: nextMessageContent,
              createdAt: DateTime(2026, 6, 14, 9, 6),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(
      find.widgetWithText(SelectableText, messageContent),
      findsOneWidget,
    );
    final messageBubble = tester
        .widgetList<Container>(
          find.ancestor(
            of: find.widgetWithText(SelectableText, messageContent),
            matching: find.byType(Container),
          ),
        )
        .firstWhere(
          (container) =>
              container.decoration is BoxDecoration &&
              (container.decoration! as BoxDecoration).border != null,
        );
    final messageBubbleDecoration = messageBubble.decoration! as BoxDecoration;
    expect(messageBubbleDecoration.borderRadius, BorderRadius.zero);
    final messageRegion = tester.widget<MouseRegion>(
      find
          .ancestor(
            of: find.widgetWithText(SelectableText, messageContent),
            matching: find.byType(MouseRegion),
          )
          .first,
    );
    final messagePadding = messageRegion.child! as Padding;
    expect(messagePadding.padding, const EdgeInsets.only(bottom: 10));
    expect(find.byTooltip('复制'), findsNothing);
    expect(find.text('09:05'), findsNothing);

    final nextMessageTopBeforeHover = tester.getTopLeft(
      find.widgetWithText(SelectableText, nextMessageContent),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(
        find.widgetWithText(SelectableText, messageContent),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('复制'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(find.text('09:05'), findsOneWidget);
    expect(
      tester
          .getTopLeft(find.widgetWithText(SelectableText, nextMessageContent)),
      nextMessageTopBeforeHover,
    );
    await tester.tap(find.byTooltip('复制'));
    await tester.pump();

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.text('已复制消息'), findsNothing);

    await mouse.removePointer();
  });

  testWidgets('chat messages show real model thinking content when present',
      (tester) async {
    final seed = AppState.seed();
    final conversation = seed.conversations.firstWhere(
      (item) => item.id == 'conv-member-secretary',
    );
    final state = seed.copyWith(
      conversations: [
        conversation.copyWith(
          messages: [
            ChatMessage(
              id: 'msg-thinking',
              authorName: '秘书',
              content: '正式回复',
              thinkingContent: '供应商返回的真实 reasoning 内容',
              createdAt: DateTime(2026, 6, 15, 9, 5),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    Finder contentBubbleAncestorOf(Finder target) {
      return find.ancestor(
        of: target,
        matching: find.byWidgetPredicate((widget) {
          if (widget is! Container) {
            return false;
          }
          final decoration = widget.decoration;
          return widget.constraints?.maxWidth == 680 &&
              widget.padding == const EdgeInsets.all(14) &&
              decoration is BoxDecoration &&
              decoration.color == Colors.white;
        }),
      );
    }

    expect(find.text('思考过程'), findsOneWidget);
    expect(contentBubbleAncestorOf(find.text('思考过程')), findsNothing);
    expect(find.text('供应商返回的真实 reasoning 内容'), findsNothing);
    expect(find.widgetWithText(SelectableText, '正式回复'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('思考过程')).dy,
      lessThan(tester.getTopLeft(find.text('正式回复')).dy),
    );

    await tester.tap(find.text('思考过程'));
    await tester.pumpAndSettle();

    expect(find.text('供应商返回的真实 reasoning 内容'), findsOneWidget);
    expect(
      contentBubbleAncestorOf(find.text('供应商返回的真实 reasoning 内容')),
      findsNothing,
    );
  });

  testWidgets('model replies render markdown while user messages stay plain',
      (tester) async {
    final seed = AppState.seed();
    final conversation = seed.conversations.firstWhere(
      (item) => item.id == 'conv-member-secretary',
    );
    const userContent = '**用户输入保持原样**';
    const systemContent = '**系统提示保持原样**';
    const modelContent = '''
## 快速判断

这是 **重点结论**。

- 第一项
- 第二项

> 引用内容

---

| 可能性 | 分析 |
| --- | --- |
| 测试输入 | 正常响应 |

`inlineCode`

[安全链接](https://example.com)

```dart
print("safe");
```

![远程图片](https://example.com/image.png)
''';
    final state = seed.copyWith(
      conversations: [
        conversation.copyWith(
          messages: [
            ChatMessage(
              id: 'msg-user-markdown',
              authorName: '我',
              content: userContent,
              createdAt: DateTime(2026, 6, 21, 9),
              isUser: true,
            ),
            ChatMessage(
              id: 'msg-model-markdown',
              authorName: '秘书',
              memberId: 'member-secretary',
              content: modelContent,
              createdAt: DateTime(2026, 6, 21, 9, 1),
            ),
            ChatMessage(
              id: 'msg-system-markdown',
              authorName: '系统',
              content: systemContent,
              createdAt: DateTime(2026, 6, 21, 9, 2),
            ),
          ],
        ),
        ...seed.conversations.where(
          (item) => item.id != conversation.id,
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    final userBody =
        find.byKey(const ValueKey('message-body-msg-user-markdown'));
    final modelBody =
        find.byKey(const ValueKey('message-body-msg-model-markdown'));
    final systemBody = find.byKey(
      const ValueKey('message-body-msg-system-markdown'),
      skipOffstage: false,
    );

    expect(
      find.descendant(
        of: userBody,
        matching: find.widgetWithText(SelectableText, userContent),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: systemBody,
        matching: find.widgetWithText(
          SelectableText,
          systemContent,
          skipOffstage: false,
        ),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: modelBody,
        matching: find.widgetWithText(SelectableText, modelContent),
      ),
      findsNothing,
    );
    for (final renderedText in [
      '快速判断',
      '重点结论',
      '第一项',
      '引用内容',
      '可能性',
      '正常响应',
      'inlineCode',
      '安全链接',
      'print("safe");',
      '远程图片',
    ]) {
      expect(
        find.descendant(
          of: modelBody,
          matching: find.textContaining(renderedText, findRichText: true),
        ),
        findsWidgets,
      );
    }
    expect(
      find.descendant(of: modelBody, matching: find.byType(Image)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: modelBody,
        matching: find.textContaining('##', findRichText: true),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: modelBody,
        matching: find.textContaining('**', findRichText: true),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: userBody,
        matching: find.textContaining('**'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('streaming thinking auto-expands then folds after completion',
      (tester) async {
    final seed = AppState.seed();
    final conversation = seed.conversations.firstWhere(
      (item) => item.id == 'conv-member-secretary',
    );
    final state = seed.copyWith(
      conversations: [
        conversation.copyWith(
          messages: [
            ChatMessage(
              id: 'msg-streaming-thinking',
              authorName: '秘书',
              content: '正在回复',
              thinkingContent: '流式思考内容',
              createdAt: DateTime.now().subtract(const Duration(seconds: 2)),
              generationStatus: ChatMessageGenerationStatus.streaming,
            ),
            ChatMessage(
              id: 'msg-complete-thinking',
              authorName: '秘书',
              content: '完成回复',
              thinkingContent: '完成思考内容',
              createdAt: DateTime(2026, 6, 15, 9, 5),
              generationDurationMs: 11000,
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.textContaining('思考中…'), findsOneWidget);
    expect(find.text('流式思考内容'), findsOneWidget);
    expect(find.text('已完成思考 · 11s'), findsOneWidget);
    expect(find.text('完成思考内容'), findsNothing);

    await tester.tap(find.text('已完成思考 · 11s'));
    await tester.pumpAndSettle();

    expect(find.text('完成思考内容'), findsOneWidget);
  });

  testWidgets('team chat shows member name outside the message bubble',
      (tester) async {
    final seed = AppState.seed();
    final conversation = seed.conversations.firstWhere(
      (item) => item.id == 'conv-team-default',
    );
    final state = seed.copyWith(
      conversations: [
        conversation.copyWith(
          messages: [
            ChatMessage(
              id: 'msg-team-member',
              authorName: '秘书',
              memberId: 'member-secretary',
              content: '群聊消息内容',
              createdAt: DateTime(2026, 6, 17),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    final list = find.byKey(const ValueKey('chat-message-list'));
    final memberName = find.descendant(of: list, matching: find.text('秘书'));
    final content = find.descendant(of: list, matching: find.text('群聊消息内容'));
    expect(memberName, findsOneWidget);
    expect(content, findsOneWidget);
    expect(
      tester.getTopLeft(memberName).dy,
      lessThan(tester.getTopLeft(content).dy),
    );
  });

  testWidgets('private chat does not repeat member name in messages',
      (tester) async {
    final seed = AppState.seed();
    final conversation = seed.conversations.firstWhere(
      (item) => item.id == 'conv-member-secretary',
    );
    final state = seed.copyWith(
      conversations: [
        conversation.copyWith(
          messages: [
            ChatMessage(
              id: 'msg-private-member',
              authorName: '秘书',
              memberId: 'member-secretary',
              content: '私聊消息内容',
              createdAt: DateTime(2026, 6, 17),
            ),
          ],
        ),
        ...seed.conversations.where(
          (item) => item.id != conversation.id,
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    final list = find.byKey(const ValueKey('chat-message-list'));
    expect(
      find.descendant(of: list, matching: find.text('秘书')),
      findsNothing,
    );
    expect(
      find.descendant(of: list, matching: find.text('私聊消息内容')),
      findsOneWidget,
    );
  });

  testWidgets('streaming message suppresses duplicate typing indicator',
      (tester) async {
    final seed = AppState.seed();
    final conversation = seed.conversations.firstWhere(
      (item) => item.id == 'conv-member-secretary',
    );
    final state = seed.copyWith(
      conversations: [
        conversation.copyWith(
          status: ConversationStatus.running,
          messages: [
            ChatMessage(
              id: 'msg-streaming-secretary',
              authorName: '秘书',
              memberId: 'member-secretary',
              content: '',
              createdAt: DateTime.now(),
              generationStatus: ChatMessageGenerationStatus.streaming,
            ),
          ],
        ),
        ...seed.conversations.where(
          (item) => item.id != conversation.id,
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('正在输入中'), findsOneWidget);
    expect(find.textContaining('秘书 正在输入中'), findsNothing);
  });

  testWidgets('streaming thinking without reply content hides message bubble',
      (tester) async {
    final seed = AppState.seed();
    final conversation = seed.conversations.firstWhere(
      (item) => item.id == 'conv-member-secretary',
    );
    final state = seed.copyWith(
      conversations: [
        conversation.copyWith(
          status: ConversationStatus.running,
          messages: [
            ChatMessage(
              id: 'msg-thinking-only',
              authorName: '秘书',
              memberId: 'member-secretary',
              content: '',
              thinkingContent: '正在分析用户的问题',
              createdAt: DateTime.now().subtract(const Duration(seconds: 5)),
              generationStatus: ChatMessageGenerationStatus.streaming,
            ),
          ],
        ),
        ...seed.conversations.where(
          (item) => item.id != conversation.id,
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    final list = find.byKey(const ValueKey('chat-message-list'));
    final replyBubble = find.descendant(
      of: list,
      matching: find.byWidgetPredicate((widget) {
        if (widget is! Container) {
          return false;
        }
        final decoration = widget.decoration;
        return widget.constraints?.maxWidth == 680 &&
            widget.padding == const EdgeInsets.all(14) &&
            decoration is BoxDecoration &&
            decoration.color == Colors.white;
      }),
    );

    expect(find.textContaining('思考中…'), findsOneWidget);
    expect(find.text('正在分析用户的问题'), findsOneWidget);
    expect(find.text('正在输入中'), findsNothing);
    expect(replyBubble, findsNothing);
  });

  testWidgets('chat messages omit thinking section when provider omits it',
      (tester) async {
    final seed = AppState.seed();
    final conversation = seed.conversations.firstWhere(
      (item) => item.id == 'conv-member-secretary',
    );
    final state = seed.copyWith(
      conversations: [
        conversation.copyWith(
          messages: [
            ChatMessage(
              id: 'msg-no-thinking',
              authorName: '秘书',
              content: '普通回复',
              createdAt: DateTime(2026, 6, 15, 9, 5),
            ),
          ],
        ),
        ...seed.conversations.where(
          (item) => item.id != conversation.id,
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('思考过程'), findsNothing);
    expect(find.widgetWithText(SelectableText, '普通回复'), findsOneWidget);
  });

  testWidgets('chat scrolls to the latest message after sending',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: RecordingModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    expect(list, findsOneWidget);
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '滚动到最新消息');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: list,
        matching: find.textContaining('使用 gpt-4.1 回复'),
      ),
      findsOneWidget,
    );
    final listView = tester.widget<ListView>(list);
    expect(
      listView.controller!.offset,
      listView.controller!.position.maxScrollExtent,
    );
  });

  testWidgets('chat auto follow uses an immediate jump instead of animation',
      (tester) async {
    final gateway = BlockingModelGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.enterText(find.byType(TextField).last, '发送后不应启动滚动动画');
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();

    expect(controller.offset, controller.position.maxScrollExtent);

    await gateway.started.future.timeout(const Duration(seconds: 1));
    await tester.tap(find.byTooltip('停止生成'));
    await tester.pumpAndSettle();
  });

  testWidgets('chat keeps manual scroll position when new activity arrives',
      (tester) async {
    final gateway = BlockingModelGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.drag(list, const Offset(0, 900));
    await tester.pumpAndSettle();
    final manualOffset = controller.offset;
    expect(manualOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));

    await tester.enterText(find.byType(TextField).last, '后台活动不应拉到底部');
    await tester.tap(find.byTooltip('发送'));
    await gateway.started.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(controller.offset, manualOffset);

    await tester.tap(find.byTooltip('停止生成'));
    await tester.pumpAndSettle();
  });

  testWidgets('chat cancels pending auto follow after immediate user scroll',
      (tester) async {
    final gateway = BlockingModelGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    controller.jumpTo(controller.position.maxScrollExtent - 48);
    await tester.pump();

    await tester.enterText(find.byType(TextField).last, '发送后马上滚动历史');
    await tester.tap(find.byTooltip('发送'));
    await tester.drag(list, const Offset(0, 900));
    await tester.pump();
    final manualOffset = controller.offset;
    expect(manualOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));

    await gateway.started.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(controller.offset, manualOffset);
    expect(find.byTooltip('回到底部'), findsOneWidget);

    await tester.tap(find.byTooltip('停止生成'));
    await tester.pumpAndSettle();
  });

  testWidgets('chat restores each conversation scroll position after switching',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, 900));
    await tester.pumpAndSettle();

    final secretaryOffset = controller.offset;
    expect(secretaryOffset, greaterThan(0));
    expect(secretaryOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-member-frontend')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-member-secretary')),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, secretaryOffset);
  });

  testWidgets('default secretary chat starts at bottom before group switching',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 1));

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-team-default')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-member-secretary')),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 1));
  });

  testWidgets(
      'chat restores bottom intent after private content grows while away',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongTeamAndSecretaryChats(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
    final savedBottomMax = controller.position.maxScrollExtent;

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-team-default')),
    );
    await tester.pumpAndSettle();

    final homeState = tester.state<State>(find.byType(AiTeamHome));
    final appController = (homeState as dynamic).controller as AppController;
    final currentState = appController.state;
    appController.state = currentState.copyWith(
      conversations: currentState.conversations.map((conversation) {
        if (conversation.id != 'conv-member-secretary') {
          return conversation;
        }
        return conversation.copyWith(
          messages: [
            ...conversation.messages,
            ChatMessage(
              id: 'msg-secretary-grown-while-away',
              authorName: '秘书',
              memberId: 'member-secretary',
              content: '离开期间新增的长回复\n${'长内容 ' * 240}',
              createdAt: DateTime(2026, 6, 20, 12),
            ),
          ],
        );
      }).toList(),
    );
    (appController as dynamic).notifyListeners();
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-member-secretary')),
    );
    await tester.pumpAndSettle();

    expect(controller.position.maxScrollExtent, greaterThan(savedBottomMax));
    expect(controller.offset, closeTo(controller.position.maxScrollExtent, 1));
  });

  testWidgets(
      'chat keeps its live scroll position while another conversation is shown',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, 900));
    await tester.pumpAndSettle();

    final currentOffset = controller.offset + 120;
    controller.jumpTo(currentOffset);
    expect(controller.offset, currentOffset);

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-member-frontend')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-member-secretary')),
    );
    await tester.pumpAndSettle();

    expect(controller.offset, currentOffset);
  });

  testWidgets(
      'chat restores group scroll after opening member chat from members page',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongTeamAndSecretaryChats(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-team-default')),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, 900));
    await tester.pumpAndSettle();
    final teamOffset = controller.offset;
    expect(teamOffset, greaterThan(0));
    expect(teamOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));

    await tester.tap(find.byTooltip('成员'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '发起聊天').at(1));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-team-default')),
    );
    await tester.pumpAndSettle();

    final restoredController = tester.widget<ListView>(list).controller!;
    expect(restoredController.offset, teamOffset);
  });

  testWidgets('chat preserves separate group and private scroll positions',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongTeamAndSecretaryChats(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-team-default')),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final teamController = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, 700));
    await tester.pumpAndSettle();
    final teamOffset = teamController.offset;
    expect(teamOffset, greaterThan(0));

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-member-secretary')),
    );
    await tester.pumpAndSettle();
    final secretaryController = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, 1100));
    await tester.pumpAndSettle();
    final secretaryOffset = secretaryController.offset;
    expect(
      secretaryOffset,
      lessThan(secretaryController.position.maxScrollExtent -
          messageBottomThreshold),
    );
    expect(secretaryOffset, isNot(closeTo(teamOffset, 1)));

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-team-default')),
    );
    await tester.pumpAndSettle();
    expect(teamController.offset, teamOffset);

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-member-secretary')),
    );
    await tester.pumpAndSettle();
    expect(secretaryController.offset, secretaryOffset);
  });

  testWidgets('opened conversations keep independent chat panes and drafts',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongTeamAndSecretaryChats(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final secretaryList = find.descendant(
      of: find.byKey(
        const ValueKey('chat-message-list-conv-member-secretary'),
        skipOffstage: false,
      ),
      matching: find.byType(ListView, skipOffstage: false),
    );
    final teamList = find.descendant(
      of: find.byKey(
        const ValueKey('chat-message-list-conv-team-default'),
        skipOffstage: false,
      ),
      matching: find.byType(ListView, skipOffstage: false),
    );
    expect(secretaryList, findsOneWidget);
    expect(teamList, findsOneWidget);
    expect(
      tester.widget<ListView>(secretaryList).controller,
      isNot(same(tester.widget<ListView>(teamList).controller)),
    );

    final visibleSecretaryInput =
        find.byKey(const ValueKey('chat-input-conv-member-secretary'));
    final visibleTeamInput =
        find.byKey(const ValueKey('chat-input-conv-team-default'));

    await tester.enterText(visibleSecretaryInput, '秘书草稿');
    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-team-default')),
    );
    await tester.pump();
    expect(find.text('秘书草稿'), findsNothing);

    await tester.enterText(visibleTeamInput, '群聊草稿');
    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-member-secretary')),
    );
    await tester.pump();
    expect(tester.widget<TextField>(visibleSecretaryInput).controller!.text,
        '秘书草稿');

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-team-default')),
    );
    await tester.pump();
    expect(tester.widget<TextField>(visibleTeamInput).controller!.text, '群聊草稿');

    await tester.tap(find.byTooltip('设置'));
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-message-list')), findsNothing);
    await tester.tap(find.byTooltip('消息'));
    await tester.pump();
    expect(tester.widget<TextField>(visibleTeamInput).controller!.text, '群聊草稿');
  });

  testWidgets('closing a conversation removes only its kept-alive chat pane',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongTeamAndSecretaryChats(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final secretaryPane = find.byKey(
      const ValueKey('chat-message-list-conv-member-secretary'),
      skipOffstage: false,
    );
    final teamPane = find.byKey(
      const ValueKey('chat-message-list-conv-team-default'),
      skipOffstage: false,
    );
    expect(secretaryPane, findsOneWidget);
    expect(teamPane, findsOneWidget);

    final visibleSecretaryInput =
        find.byKey(const ValueKey('chat-input-conv-member-secretary'));
    await tester.enterText(visibleSecretaryInput, '关闭其他会话时保留的草稿');

    final homeState = tester.state<State>(find.byType(AiTeamHome));
    final appController = (homeState as dynamic).controller as AppController;
    appController.closeConversation('conv-team-default');
    await tester.pumpAndSettle();

    expect(secretaryPane, findsOneWidget);
    expect(teamPane, findsNothing);
    expect(
      tester.widget<TextField>(visibleSecretaryInput).controller!.text,
      '关闭其他会话时保留的草稿',
    );
  });

  testWidgets('rapid chat switches do not overwrite saved scroll positions',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongTeamAndSecretaryChats(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final secretaryController = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, 1100));
    await tester.pumpAndSettle();
    final secretaryOffset = secretaryController.offset;
    expect(secretaryOffset, greaterThan(0));
    expect(
      secretaryOffset,
      lessThan(secretaryController.position.maxScrollExtent -
          messageBottomThreshold),
    );

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-team-default')),
    );
    await tester.pumpAndSettle();
    final teamController = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, 700));
    await tester.pumpAndSettle();
    final teamOffset = teamController.offset;
    expect(teamOffset, greaterThan(0));
    expect(teamOffset, isNot(closeTo(secretaryOffset, 1)));

    for (var index = 0; index < 3; index++) {
      await tester.tap(
        find.byKey(const ValueKey('conversation-row-conv-member-secretary')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('conversation-row-conv-team-default')),
      );
      await tester.pump();
    }

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-member-secretary')),
    );
    await tester.pumpAndSettle();
    expect(secretaryController.offset, closeTo(secretaryOffset, 1));

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-team-default')),
    );
    await tester.pumpAndSettle();
    expect(teamController.offset, closeTo(teamOffset, 1));
  });

  testWidgets('chat shows a back to bottom button after manual scroll',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(find.byTooltip('回到底部'), findsNothing);

    await tester.drag(list, const Offset(0, 900));
    await tester.pumpAndSettle();

    expect(controller.offset, lessThan(controller.position.maxScrollExtent));
    expect(find.byTooltip('回到底部'), findsOneWidget);

    await tester.tap(find.byTooltip('回到底部'));
    await tester.pumpAndSettle();

    expect(controller.offset, controller.position.maxScrollExtent);
    expect(find.byTooltip('回到底部'), findsNothing);
  });

  testWidgets('chat follows streaming content while pinned near bottom',
      (tester) async {
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: [
        const ModelStreamDelta(contentDelta: '流式回复开始\n'),
        ModelStreamDelta(contentDelta: '${'持续输出内容 ' * 24}\n'),
        ModelStreamDelta(contentDelta: '${'更多输出内容 ' * 24}\n'),
        ModelStreamDelta(contentDelta: '${'最后一段输出 ' * 24}\n'),
      ],
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.enterText(find.byType(TextField).last, '请流式输出长回复');
    await tester.tap(find.byTooltip('发送'));
    for (var index = 0; index < gateway.deltas.length + 1; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    await gateway.completed.future;
    await tester.pumpAndSettle();

    expect(find.textContaining('最后一段输出'), findsWidgets);
    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('chat coalesces high frequency streaming scroll follow',
      (tester) async {
    final diagnostics = ChatScrollDiagnostics();
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: [
        for (var index = 0; index < 30; index++)
          ModelStreamDelta(contentDelta: '高频输出 $index ${'内容 ' * 8}\n'),
      ],
      deltaDelay: const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
        chatScrollDiagnostics: diagnostics,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
    diagnostics.reset();

    await tester.enterText(find.byType(TextField).last, '请高频流式输出');
    await tester.tap(find.byTooltip('发送'));
    await _pumpStreamingFrames(tester, count: 16);
    await gateway.completed.future.timeout(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.textContaining('高频输出 29'), findsWidgets);
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(diagnostics.contentUpdateCount, greaterThanOrEqualTo(2));
    expect(
      diagnostics.nearBottomFlipCount,
      0,
      reason: 'Pinned streaming should not bounce between near and away.',
    );
    expect(
      diagnostics.actualJumpCount,
      lessThan(diagnostics.contentUpdateCount),
      reason: 'Streaming body updates should be coalesced instead of jumping '
          'for each publish. contentUpdates=${diagnostics.contentUpdateCount} '
          'schedules=${diagnostics.scrollScheduleCount} '
          'jumps=${diagnostics.actualJumpCount} '
          'samples=${diagnostics.jumpSamples.map((sample) => [
                sample.beforePixels,
                sample.beforeMaxScrollExtent,
                sample.target,
                sample.afterPixels,
                sample.afterMaxScrollExtent,
              ]).toList()}',
    );
  });

  testWidgets('chat keeps pinned streaming drafts at bottom each frame',
      (tester) async {
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: [
        for (var index = 0; index < 12; index++)
          ModelStreamDelta(contentDelta: '贴底输出 $index ${'内容 ' * 6}\n'),
      ],
      deltaDelay: const Duration(milliseconds: 30),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.enterText(find.byType(TextField).last, '请高频贴底输出');
    await tester.tap(find.byTooltip('发送'));

    final observedBottomGaps = <double>[];
    for (var index = 0; index < gateway.deltas.length; index++) {
      await tester.pump(const Duration(milliseconds: 40));
      if (find.textContaining('贴底输出').evaluate().isNotEmpty) {
        observedBottomGaps.add(
          controller.position.maxScrollExtent - controller.offset,
        );
      }
    }
    await gateway.completed.future.timeout(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(observedBottomGaps, isNotEmpty);
    final visibleGaps = observedBottomGaps.where((gap) => gap > 1.0).toList();
    expect(
      visibleGaps,
      isEmpty,
      reason: 'Pinned streaming should correct to the bottom every frame, '
          'not accumulate a visible tail gap. gaps=$observedBottomGaps',
    );
  });

  testWidgets('chat streams drafts without global rebuild per delta',
      (tester) async {
    final diagnostics = ChatScrollDiagnostics();
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: [
        for (var index = 0; index < 20; index++)
          ModelStreamDelta(contentDelta: '局部草稿 $index\n'),
      ],
      pauseAfterDeltaIndex: 9,
      deltaDelay: const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
        chatScrollDiagnostics: diagnostics,
      ),
    );
    await tester.pumpAndSettle();
    diagnostics.reset();

    await tester.enterText(find.byType(TextField).last, '请高频流式输出');
    await tester.tap(find.byTooltip('发送'));
    await _pumpStreamingFrames(tester, count: 8);
    await gateway.paused.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.textContaining('局部草稿 9'), findsWidgets);
    expect(diagnostics.streamingDraftUpdateCount, greaterThanOrEqualTo(10));
    expect(
      diagnostics.globalCommitCount,
      lessThanOrEqualTo(3),
      reason: 'Streaming deltas should update message-local draft state, not '
          'commit/persist the whole AppState for each token.',
    );

    gateway.resume();
    await _pumpStreamingFrames(tester, count: 8);
    await gateway.completed.future.timeout(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('chat does not rebuild history bubbles for streaming drafts',
      (tester) async {
    final diagnostics = ChatScrollDiagnostics();
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: [
        for (var index = 0; index < 12; index++)
          ModelStreamDelta(contentDelta: '只更新当前消息 $index\n'),
      ],
      pauseAfterDeltaIndex: 5,
      deltaDelay: const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
        chatScrollDiagnostics: diagnostics,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    diagnostics.reset();

    await tester.enterText(find.byType(TextField).last, '请高频流式输出');
    await tester.tap(find.byTooltip('发送'));
    await _pumpStreamingFrames(tester, count: 6);
    await gateway.paused.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.textContaining('只更新当前消息 5'), findsWidgets);
    expect(
      diagnostics.messageBubbleBuildCounts['msg-history-44'] ?? 0,
      lessThanOrEqualTo(2),
      reason:
          'Visible history bubbles may build for initial structure changes, '
          'but streaming draft ticks should not keep rebuilding them.',
    );

    gateway.resume();
    await _pumpStreamingFrames(tester, count: 8);
    await gateway.completed.future.timeout(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('chat commits visible streaming draft when generation stops',
      (tester) async {
    AppState? persisted;
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: const [
        ModelStreamDelta(contentDelta: '停止前草稿内容\n'),
        ModelStreamDelta(contentDelta: '不应该继续输出'),
      ],
      pauseAfterDeltaIndex: 0,
      deltaDelay: const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
        onStateChanged: (state) => persisted = state,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '请流式输出后停止');
    await tester.tap(find.byTooltip('发送'));
    await _pumpStreamingFrames(tester, count: 2);
    await gateway.paused.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.textContaining('停止前草稿内容'), findsWidgets);

    await tester.tap(find.byTooltip('停止生成'));
    gateway.resume();
    await _pumpStreamingFrames(tester, count: 4);
    await tester.pumpAndSettle();

    final secretaryConversation = persisted!.conversations.firstWhere(
      (conversation) => conversation.id == 'conv-member-secretary',
    );
    final stoppedMessage = secretaryConversation.messages.firstWhere(
      (message) => message.content.contains('停止前草稿内容'),
    );
    expect(
      stoppedMessage.generationStatus,
      ChatMessageGenerationStatus.stopped,
    );
    expect(find.textContaining('停止前草稿内容'), findsWidgets);
  });

  testWidgets('secretary private dispatch stop clears streaming waiting state',
      (tester) async {
    final gateway = BlockingModelGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).last,
      '分配任务给测试工程师，检查停止按钮',
    );
    await tester.tap(find.byTooltip('发送'));
    await tester.pump();
    await gateway.started.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('已分配给测试工程师，等待回复中'), findsOneWidget);
    expect(find.byTooltip('停止生成'), findsOneWidget);

    await tester.tap(find.byTooltip('停止生成'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    final homeState = tester.state<State>(find.byType(AiTeamHome));
    final appController = (homeState as dynamic).controller as AppController;
    final secretaryConversation =
        appController.conversationById('conv-member-secretary');

    expect(find.byTooltip('发送'), findsOneWidget);
    expect(find.byTooltip('停止生成'), findsNothing);
    expect(secretaryConversation.status, ConversationStatus.stopped);
    expect(
      secretaryConversation.messages
          .where(
            (message) =>
                message.generationStatus ==
                ChatMessageGenerationStatus.streaming,
          )
          .toList(),
      isEmpty,
    );
    expect(
      secretaryConversation.messages.map((message) => message.content),
      contains('任务已停止，本轮未完成的模型请求已取消。'),
    );
  });

  testWidgets('chat renders streaming message without live MarkdownBody',
      (tester) async {
    final diagnostics = ChatScrollDiagnostics();
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: const [
        ModelStreamDelta(contentDelta: '第一行 **markdown**\n第二行仍在输出'),
      ],
      pauseAfterDeltaIndex: 0,
      deltaDelay: const Duration(milliseconds: 80),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
        chatScrollDiagnostics: diagnostics,
      ),
    );
    await tester.pumpAndSettle();
    final streamedMarkdownBody = find.byWidgetPredicate(
      (widget) =>
          widget is MarkdownBody && widget.data.contains('第一行 **markdown**'),
    );

    await tester.enterText(find.byType(TextField).last, '请流式输出 markdown');
    await tester.tap(find.byTooltip('发送'));
    await _pumpStreamingFrames(tester, count: 3);
    await gateway.paused.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.textContaining('第一行'), findsWidgets);
    expect(streamedMarkdownBody, findsNothing);
    expect(diagnostics.streamingBodyBuildCount, greaterThan(0));
    expect(diagnostics.streamingStableSegmentCommitCount, greaterThan(0));
    expect(diagnostics.streamingTailUpdateCount, greaterThan(0));

    gateway.resume();
    await _pumpStreamingFrames(tester, count: 3);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(streamedMarkdownBody, findsOneWidget);
    expect(diagnostics.markdownBodyBuildCount, greaterThan(0));
  });

  testWidgets('chat keeps following a large streaming delta from bottom',
      (tester) async {
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: [
        ModelStreamDelta(contentDelta: '${'单次大段流式输出 ' * 220}\n'),
      ],
      deltaDelay: Duration.zero,
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.enterText(find.byType(TextField).last, '请流式输出很长回复');
    await tester.tap(find.byTooltip('发送'));
    await _pumpStreamingFrames(tester, count: 4);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('单次大段流式输出'), findsWidgets);
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(find.byTooltip('回到底部'), findsNothing);
  });

  testWidgets('chat allows manual scrolling during streaming output',
      (tester) async {
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: [
        const ModelStreamDelta(contentDelta: '流式回复开始\n'),
        ModelStreamDelta(contentDelta: '${'持续输出内容 ' * 24}\n'),
        ModelStreamDelta(contentDelta: '${'更多输出内容 ' * 24}\n'),
        ModelStreamDelta(contentDelta: '${'最后一段输出 ' * 24}\n'),
      ],
      pauseAfterDeltaIndex: 1,
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.enterText(find.byType(TextField).last, '请流式输出长回复');
    await tester.tap(find.byTooltip('发送'));
    for (var index = 0; index < 3; index++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    await gateway.paused.future.timeout(const Duration(seconds: 1));

    await tester.drag(list, const Offset(0, 900));
    await tester.pumpAndSettle();
    final manualOffset = controller.offset;
    expect(manualOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));
    expect(find.byTooltip('回到底部'), findsOneWidget);

    gateway.resume();
    await _pumpStreamingFrames(tester, count: gateway.deltas.length + 1);
    await gateway.completed.future;
    await tester.pumpAndSettle();

    expect(find.textContaining('最后一段输出'), findsWidgets);
    expect(controller.offset, manualOffset);
    expect(find.byTooltip('回到底部'), findsOneWidget);
  });

  testWidgets('chat allows manual scrolling while streaming continues',
      (tester) async {
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: [
        for (var index = 0; index < 12; index++)
          ModelStreamDelta(contentDelta: '持续流式输出 $index ${'内容 ' * 30}\n'),
      ],
      deltaDelay: const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.enterText(find.byType(TextField).last, '请持续流式输出');
    await tester.tap(find.byTooltip('发送'));
    await _pumpStreamingFrames(tester, count: 2);

    await tester.drag(list, const Offset(0, 900));
    await tester.pump();
    final manualOffset = controller.offset;
    expect(manualOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));

    await _pumpStreamingFrames(tester, count: 12);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('持续流式输出 11'), findsWidgets);
    expect(controller.offset, manualOffset);
    expect(find.byTooltip('回到底部'), findsOneWidget);
  });

  testWidgets('chat cancels queued auto follow when user scrolls during stream',
      (tester) async {
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: [
        const ModelStreamDelta(contentDelta: '流式回复开始\n'),
        ModelStreamDelta(contentDelta: '${'继续输出内容 ' * 80}\n'),
        ModelStreamDelta(contentDelta: '${'不会拉回底部 ' * 80}\n'),
      ],
      pauseAfterDeltaIndex: 0,
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.enterText(find.byType(TextField).last, '请流式输出长回复');
    await tester.tap(find.byTooltip('发送'));
    await gateway.paused.future.timeout(const Duration(seconds: 1));

    await tester.drag(list, const Offset(0, 900));
    await tester.pump();
    final manualOffset = controller.offset;
    expect(manualOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));

    gateway.resume();
    await _pumpStreamingFrames(tester, count: gateway.deltas.length + 1);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('不会拉回底部'), findsWidgets);
    expect(controller.offset, manualOffset);
    expect(find.byTooltip('回到底部'), findsOneWidget);
  });

  testWidgets('chat mouse wheel scrolling disables streaming auto follow',
      (tester) async {
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: [
        const ModelStreamDelta(contentDelta: '流式回复开始\n'),
        ModelStreamDelta(contentDelta: '${'滚轮后继续输出 ' * 80}\n'),
      ],
      pauseAfterDeltaIndex: 0,
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.enterText(find.byType(TextField).last, '请流式输出长回复');
    await tester.tap(find.byTooltip('发送'));
    await gateway.paused.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, -900),
      ),
    );
    await tester.pumpAndSettle();
    final wheelOffset = controller.offset;
    expect(wheelOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));
    expect(find.byTooltip('回到底部'), findsOneWidget);

    gateway.resume();
    await _pumpStreamingFrames(tester, count: gateway.deltas.length + 1);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('滚轮后继续输出'), findsWidgets);
    expect(controller.offset, wheelOffset);
  });

  testWidgets(
      'chat small upward wheel scroll stays near bottom during streaming',
      (tester) async {
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: [
        const ModelStreamDelta(contentDelta: '流式回复开始\n'),
        for (var index = 0; index < 8; index++)
          ModelStreamDelta(contentDelta: '小步滚轮后继续输出 $index ${'内容 ' * 30}\n'),
      ],
      deltaDelay: const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.enterText(find.byType(TextField).last, '请持续流式输出');
    await tester.tap(find.byTooltip('发送'));
    await _pumpStreamingFrames(tester, count: 2);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, -20),
      ),
    );
    await tester.pump();
    final wheelOffset = controller.offset;
    expect(
      controller.position.maxScrollExtent - wheelOffset,
      lessThan(messageBottomThreshold),
    );
    expect(find.byTooltip('回到底部'), findsNothing);

    await _pumpStreamingFrames(tester, count: 10);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('小步滚轮后继续输出 7'), findsWidgets);
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(find.byTooltip('回到底部'), findsNothing);
  });

  testWidgets('chat back to bottom resumes follow after small wheel scroll',
      (tester) async {
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: [
        const ModelStreamDelta(contentDelta: '流式回复开始\n'),
        ModelStreamDelta(contentDelta: '${'点击回到底部后继续输出 ' * 60}\n'),
      ],
      pauseAfterDeltaIndex: 0,
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.enterText(find.byType(TextField).last, '请流式输出长回复');
    await tester.tap(find.byTooltip('发送'));
    await gateway.paused.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, -20),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      controller.position.maxScrollExtent - controller.offset,
      lessThan(messageBottomThreshold),
    );
    expect(find.byTooltip('回到底部'), findsNothing);

    gateway.resume();
    await _pumpStreamingFrames(tester, count: gateway.deltas.length + 1);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('点击回到底部后继续输出'), findsWidgets);
    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('chat back to bottom needs one click while stream keeps growing',
      (tester) async {
    final gateway = ScriptedStreamingWidgetGateway(
      deltas: [
        for (var index = 0; index < 12; index++)
          ModelStreamDelta(contentDelta: '点击后继续增长 $index ${'内容 ' * 80}\n'),
      ],
      deltaDelay: const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.enterText(find.byType(TextField).last, '请继续流式输出');
    await tester.tap(find.byTooltip('发送'));
    await _pumpStreamingFrames(tester, count: 2);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, -160),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      controller.position.maxScrollExtent - controller.offset,
      greaterThan(messageBottomThreshold),
    );
    expect(find.byTooltip('回到底部'), findsOneWidget);

    await tester.tap(find.byTooltip('回到底部'));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(find.byTooltip('回到底部'), findsNothing);

    await _pumpStreamingFrames(tester, count: 12);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('点击后继续增长 11'), findsWidgets);
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(find.byTooltip('回到底部'), findsNothing);
  });

  testWidgets('chat keeps back to bottom visible until within bottom threshold',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, -160),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      controller.position.maxScrollExtent - controller.offset,
      greaterThan(messageBottomThreshold),
    );
    expect(find.byTooltip('回到底部'), findsOneWidget);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, 100),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      controller.position.maxScrollExtent - controller.offset,
      greaterThan(messageBottomThreshold),
    );
    expect(find.byTooltip('回到底部'), findsOneWidget);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, 50),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      controller.position.maxScrollExtent - controller.offset,
      lessThanOrEqualTo(messageBottomThreshold),
    );
    expect(find.byTooltip('回到底部'), findsNothing);
  });

  testWidgets('chat keeps back to bottom hidden for small wheel scroll',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, -20),
      ),
    );
    await tester.pump();
    expect(
      controller.position.maxScrollExtent - controller.offset,
      lessThan(messageBottomThreshold),
    );
    expect(find.byTooltip('回到底部'), findsNothing);

    ScrollEndNotification(
      metrics: FixedScrollMetrics(
        minScrollExtent: controller.position.minScrollExtent,
        maxScrollExtent: controller.position.maxScrollExtent,
        pixels: controller.position.maxScrollExtent,
        viewportDimension: controller.position.viewportDimension,
        axisDirection: AxisDirection.down,
        devicePixelRatio: tester.view.devicePixelRatio,
      ),
      context: tester.element(list),
    ).dispatch(tester.element(list));
    await tester.pump();

    expect(find.byTooltip('回到底部'), findsNothing);
  });

  testWidgets('chat hides back to bottom button when metrics settle at bottom',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('chat-message-list'));
    final controller = tester.widget<ListView>(list).controller!;
    await tester.drag(list, const Offset(0, -10000));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(list),
        scrollDelta: const Offset(0, -160),
      ),
    );
    await tester.pump();
    expect(
      controller.position.maxScrollExtent - controller.offset,
      greaterThan(messageBottomThreshold),
    );
    expect(find.byTooltip('回到底部'), findsOneWidget);

    final homeState = tester.state<State>(find.byType(AiTeamHome));
    final appController = (homeState as dynamic).controller as AppController;
    final currentState = appController.state;
    appController.state = currentState.copyWith(
      conversations: currentState.conversations.map((conversation) {
        if (conversation.id != 'conv-member-secretary') {
          return conversation;
        }
        return conversation.copyWith(
          messages: conversation.messages.take(44).toList(),
        );
      }).toList(),
    );
    (appController as dynamic).notifyListeners();
    await tester.pumpAndSettle();

    expect(
      controller.position.maxScrollExtent - controller.offset,
      lessThanOrEqualTo(messageBottomThreshold),
    );
    expect(find.byTooltip('回到底部'), findsNothing);
  });

  testWidgets('left sidebar uses a deep black background', (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    final sidebarBackground = tester.widget<ColoredBox>(
      find
          .ancestor(
            of: find.byTooltip('消息'),
            matching: find.byType(ColoredBox),
          )
          .first,
    );

    expect(sidebarBackground.color, const Color(0xFF050505));
  });

  testWidgets('sidebar team button opens team management', (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('团队'));
    await tester.pumpAndSettle();

    expect(find.text('团队管理'), findsOneWidget);
    expect(find.byTooltip('新增团队'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '发起聊天'), findsOneWidget);
    expect(find.textContaining('群聊 · 默认开发团队'), findsNothing);
  });

  testWidgets(
      'message sidebar preserves private chat history after starting team chat',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('私聊'), findsNothing);
    expect(find.text('秘书'), findsWidgets);
    expect(find.text('前端工程师'), findsWidgets);
    expect(find.text('测试工程师'), findsWidgets);

    await tester.tap(find.byTooltip('团队'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '发起聊天'));
    await tester.pumpAndSettle();

    expect(find.text('群聊'), findsNothing);
    expect(find.text('私聊'), findsNothing);
    expect(find.text('秘书'), findsWidgets);
    expect(find.text('前端工程师'), findsWidgets);
    expect(find.text('测试工程师'), findsWidgets);
    expect(find.textContaining('群聊 · 默认开发团队'), findsOneWidget);

    await tester.tap(find.byTooltip('成员'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '发起聊天').at(1));
    await tester.pumpAndSettle();

    expect(find.text('私聊'), findsNothing);
    expect(find.text('秘书'), findsWidgets);
    expect(find.text('前端工程师'), findsWidgets);
    expect(find.text('测试工程师'), findsWidgets);
    expect(find.textContaining('私聊 · 前端工程师'), findsOneWidget);
  });

  testWidgets('chat header action menu starts a new scoped session',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.byTooltip('会话操作'), findsOneWidget);
    final initialRows = _conversationRowCount(tester);

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    expect(find.text('新增会话'), findsOneWidget);
    expect(find.text('历史会话'), findsOneWidget);

    await tester.tap(find.text('新增会话'));
    await tester.pumpAndSettle();

    expect(find.textContaining('私聊 · 新会话'), findsOneWidget);
    expect(_conversationRowCount(tester), initialRows);
  });

  testWidgets('chat header history menu switches current object sessions',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.textContaining('私聊 · 秘书'), findsOneWidget);

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增会话'));
    await tester.pumpAndSettle();
    expect(find.textContaining('私聊 · 新会话'), findsOneWidget);

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('秘书').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('私聊 · 秘书'), findsOneWidget);
  });

  testWidgets('chat history menu deletes a session after confirmation',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增会话'));
    await tester.pumpAndSettle();
    expect(find.textContaining('私聊 · 新会话'), findsOneWidget);

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('秘书').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('私聊 · 秘书'), findsOneWidget);

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    expect(find.text('新会话 · 秘书'), findsOneWidget);
    expect(find.byTooltip('删除会话'), findsWidgets);

    await tester.tap(find.byTooltip('删除会话').last);
    await tester.pumpAndSettle();
    expect(find.text('确认删除该会话？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    expect(find.text('新会话 · 秘书'), findsOneWidget);

    await tester.tap(find.byTooltip('删除会话').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('私聊 · 秘书'), findsOneWidget);
    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    expect(find.text('新会话 · 秘书'), findsNothing);
  });

  testWidgets('chat header action menu reuses one empty history session',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增会话'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('秘书').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增会话'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    expect(find.text('新会话 · 秘书'), findsOneWidget);
  });

  testWidgets('team chat appears only after starting chat from team management',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('群聊'), findsNothing);

    await tester.tap(find.byTooltip('团队'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '发起聊天'));
    await tester.pumpAndSettle();

    expect(find.text('群聊'), findsNothing);
    expect(find.textContaining('群聊 · 默认开发团队'), findsOneWidget);
  });

  testWidgets('team management creates a named team with selected members',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('团队'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增团队'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '团队名称'), '移动端小队');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('移动端小队'), findsOneWidget);
    expect(find.textContaining('前端工程师、测试工程师'), findsWidgets);
  });

  testWidgets('team dialog defaults to serial mode and can select parallel',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.tap(find.byTooltip('团队'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增团队'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(
        SegmentedButton<TeamCollaborationMode>,
        '串行',
      ),
      findsOneWidget,
    );

    await tester.enterText(find.widgetWithText(TextField, '团队名称'), '并行小队');
    await tester.tap(find.text('并行'));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('并行协同'), findsOneWidget);
  });

  testWidgets('team management edits and deletes a team', (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('团队'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增团队'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '团队名称'), '移动端小队');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑团队').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '团队名称'), '移动端交付组');
    await tester.tap(find.text('并行'));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('移动端交付组'), findsOneWidget);
    expect(find.textContaining('并行协同'), findsOneWidget);

    await tester.tap(find.byTooltip('删除团队').last);
    await tester.pumpAndSettle();

    expect(find.text('移动端交付组'), findsNothing);
  });

  testWidgets('configuration dialogs use the clean shared dialog frame',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    Future<void> expectSharedDialog({
      required String pageTooltip,
      required String actionTooltip,
      required String title,
      required String closeText,
    }) async {
      await tester.tap(find.byTooltip(pageTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(actionTooltip).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('config-dialog-frame')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('config-dialog-header')), findsOneWidget);
      expect(find.byKey(const ValueKey('config-dialog-body')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('config-dialog-actions')), findsOneWidget);
      expect(find.text(title), findsOneWidget);

      await tester.tap(find.text(closeText).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await expectSharedDialog(
      pageTooltip: '团队',
      actionTooltip: '新增团队',
      title: '新增团队',
      closeText: '取消',
    );
    await expectSharedDialog(
      pageTooltip: '模型',
      actionTooltip: '编辑模型',
      title: '编辑模型配置',
      closeText: '取消',
    );
    await expectSharedDialog(
      pageTooltip: '角色',
      actionTooltip: '新增角色',
      title: '新增角色配置',
      closeText: '取消',
    );
    await expectSharedDialog(
      pageTooltip: '成员',
      actionTooltip: '新增成员',
      title: '新增团队成员',
      closeText: '取消',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed().copyWith(
          workspaces: [
            ProjectWorkspace(
              id: 'workspace-dialog-test',
              name: '当前项目',
              path: Directory.current.path,
            ),
          ],
        ),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    await expectSharedDialog(
      pageTooltip: '项目',
      actionTooltip: '创建补丁',
      title: '创建补丁提案',
      closeText: '取消',
    );
    await expectSharedDialog(
      pageTooltip: '项目',
      actionTooltip: '浏览文件',
      title: '工作区文件',
      closeText: '关闭',
    );
    await expectSharedDialog(
      pageTooltip: '设置',
      actionTooltip: '创建命令请求',
      title: '创建命令请求',
      closeText: '取消',
    );
    await expectSharedDialog(
      pageTooltip: '设置',
      actionTooltip: '导入 / 导出配置',
      title: '导入 / 导出配置',
      closeText: '关闭',
    );
  });

  testWidgets('role dialog remains usable in a compact viewport',
      (tester) async {
    tester.view.physicalSize = const Size(720, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增角色'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('config-dialog-body')), findsOneWidget);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('config-dialog-body')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);
  });

  testWidgets('model dialog validation uses the shared error treatment',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑模型').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '温度 0-2'), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('config-dialog-error')), findsOneWidget);
    expect(find.textContaining('温度和最大 Token 必须是数字'), findsOneWidget);
    expect(find.text('编辑模型配置'), findsOneWidget);
  });

  testWidgets('member dialog edits execution priority', (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.tap(find.byTooltip('成员'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑成员').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '执行优先级'), '20');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.textContaining('优先级 20'), findsOneWidget);
  });

  testWidgets('chat shows collapsed queue bar with count and running title',
      (tester) async {
    final state = AppState.seed().copyWith(
      queuedTasks: [
        QueuedTask(
          id: 'task-1',
          conversationId: 'conv-team-default',
          title: '登录任务',
          originalText: '实现登录',
          priority: 0,
          status: QueuedTaskStatus.running,
          createdAt: DateTime(2026, 6, 14),
          updatedAt: DateTime(2026, 6, 14),
        ),
        QueuedTask(
          id: 'task-2',
          conversationId: 'conv-team-default',
          title: '测试任务',
          originalText: '补测试',
          priority: 0,
          status: QueuedTaskStatus.pending,
          createdAt: DateTime(2026, 6, 14, 1),
          updatedAt: DateTime(2026, 6, 14, 1),
        ),
      ],
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.textContaining('队列 2'), findsOneWidget);
    expect(find.textContaining('登录任务'), findsOneWidget);
  });

  testWidgets('history page lists all app tasks and filters by title',
      (tester) async {
    final state = AppState.seed().copyWith(
      queuedTasks: [
        QueuedTask(
          id: 'task-1',
          conversationId: 'conv-team-default',
          title: '登录任务',
          originalText: '实现登录',
          priority: 0,
          status: QueuedTaskStatus.completed,
          createdAt: DateTime(2026, 6, 14),
          updatedAt: DateTime(2026, 6, 14),
        ),
        QueuedTask(
          id: 'task-2',
          conversationId: 'conv-member-secretary',
          title: '文档任务',
          originalText: '写文档',
          priority: 0,
          status: QueuedTaskStatus.completed,
          createdAt: DateTime(2026, 6, 14),
          updatedAt: DateTime(2026, 6, 14),
        ),
      ],
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('历史'));
    await tester.pumpAndSettle();
    expect(find.text('登录任务'), findsOneWidget);
    expect(find.text('文档任务'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '搜索标题'), '登录');
    await tester.pumpAndSettle();
    expect(find.text('登录任务'), findsOneWidget);
    expect(find.text('文档任务'), findsNothing);
  });

  testWidgets('sidebar audit button opens an independent audit page',
      (tester) async {
    final state = AppState.seed().copyWith(
      auditLog: [
        AuditEntry(
          id: 'audit-old',
          action: 'old_action',
          detail: '较早操作',
          createdAt: DateTime(2026, 6, 14, 8, 5, 6),
        ),
        AuditEntry(
          id: 'audit-new',
          action: 'new_action',
          detail:
              'conversation=conv-member-secretary model=model-main streaming=false',
          metadata: const {
            'rawResponse':
                '{"choices":[{"message":{"content":"原始模型返回","reasoning_content":"原始思考字段"}}]}',
            'requestBody': {
              'model': 'reasoning-model',
              'reasoning_effort': 'high',
              'max_completion_tokens': 1600,
              'messages': [
                {'role': 'system', 'content': '系统提示词'},
                {'role': 'user', 'content': '用户消息'},
              ],
            },
            'streaming': false,
            'model': 'model-main',
            'requestUrl': 'https://api.example.test/v1/chat/completions',
          },
          createdAt: DateTime(2026, 6, 15, 9, 6, 7),
        ),
      ],
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('审计'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsNothing);
    expect(find.text('审计日志'), findsOneWidget);
    expect(find.text('操作记录'), findsOneWidget);
    expect(find.text('new_action'), findsOneWidget);
    expect(
      find.text(
        'conversation=conv-member-secretary model=reasoning-model streaming=false',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('model-main'), findsNothing);
    expect(find.text('创建时间：2026-06-15 09:06:07'), findsOneWidget);
    expect(find.text('old_action'), findsOneWidget);
    expect(find.text('较早操作'), findsOneWidget);
    expect(find.text('创建时间：2026-06-14 08:05:06'), findsOneWidget);

    final newActionTop = tester.getTopLeft(find.text('new_action')).dy;
    final oldActionTop = tester.getTopLeft(find.text('old_action')).dy;
    expect(newActionTop, lessThan(oldActionTop));

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('new_action'),
          matching: find.byType(Container),
        ),
        matching: find.byTooltip('查看详情'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('审计详情'), findsOneWidget);
    expect(find.text('请求参数'), findsOneWidget);
    expect(find.textContaining('reasoning_effort'), findsOneWidget);
    expect(find.textContaining('系统提示词'), findsOneWidget);
    expect(find.textContaining('用户消息'), findsOneWidget);
    expect(find.text('原始返回内容'), findsOneWidget);
    expect(find.textContaining('原始模型返回'), findsOneWidget);
    expect(find.textContaining('原始思考字段'), findsOneWidget);
    expect(find.text('model: reasoning-model'), findsOneWidget);
    expect(
        find.text('requestUrl: https://api.example.test/v1/chat/completions'),
        findsOneWidget);
    expect(find.textContaining('model-main'), findsNothing);
  });

  testWidgets('model dialog saves selected reasoning effort', (tester) async {
    AppState? persisted;
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
        onStateChanged: (state) => persisted = state,
      ),
    );

    await tester.tap(find.byTooltip('模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑模型').first);
    await tester.pumpAndSettle();

    expect(find.text('深度思考'), findsOneWidget);

    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('high').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(persisted, isNotNull);
    expect(persisted!.models.first.reasoningEffort, 'high');
    expect(find.textContaining('深度思考: high'), findsOneWidget);
  });

  testWidgets('sidebar model button opens an independent model page',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('模型'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsNothing);
    expect(find.text('模型管理'), findsOneWidget);
    expect(find.text('模型配置'), findsOneWidget);
    expect(find.byTooltip('新增模型'), findsOneWidget);
  });

  testWidgets('sidebar role button opens an independent role page',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('角色'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsNothing);
    expect(find.text('角色管理'), findsOneWidget);
    expect(find.text('角色配置'), findsOneWidget);
    expect(find.byTooltip('新增角色'), findsOneWidget);
  });

  testWidgets('sidebar member button opens an independent member page',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('成员'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsNothing);
    expect(find.text('成员管理'), findsOneWidget);
    expect(find.text('团队成员'), findsOneWidget);
    expect(find.byTooltip('新增成员'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '发起聊天'), findsWidgets);
  });

  testWidgets('sidebar project button opens an independent project page',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('项目'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsNothing);
    expect(find.byTooltip('返回聊天'), findsNothing);
    expect(find.text('项目管理'), findsOneWidget);
    expect(find.text('项目工作区'), findsOneWidget);
    expect(find.byTooltip('添加工作区'), findsOneWidget);
    expect(find.byTooltip('浏览文件'), findsOneWidget);
    expect(find.byTooltip('创建补丁'), findsOneWidget);
  });

  testWidgets('submits a task to the secretary and renders member responses',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('团队'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '发起聊天'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '请实现设置页面');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('请实现设置页面'), findsWidgets);
    expect(find.textContaining('秘书'), findsWidgets);
    expect(find.textContaining('群聊 · 默认开发团队'), findsOneWidget);
    expect(find.textContaining('汇总'), findsWidgets);
    await tester.drag(
      find.byKey(const ValueKey('chat-message-list')),
      const Offset(0, 700),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('前端工程师'), findsWidgets);
  });

  testWidgets(
      'secretary private chat dispatches directly to member private chat',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.enterText(
      find.byType(TextField).last,
      '分配任务给测试工程师，询问 7 年前妈妈年龄是儿子的 6 倍。',
    );
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('私聊 · 秘书'), findsOneWidget);
    expect(find.textContaining('群聊 · 默认开发团队'), findsNothing);
    expect(find.textContaining('测试工程师'), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-member-tester')),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('私聊 · 测试工程师'), findsOneWidget);
    expect(
      find.text('任务分配：分配任务给测试工程师，询问 7 年前妈妈年龄是儿子的 6 倍。'),
      findsOneWidget,
    );
    expect(find.textContaining('测试工程师：'), findsWidgets);
  });

  testWidgets('secretary private dispatch shows full long summary',
      (tester) async {
    final longReply = [
      '测试结论首行：1+1 等于 2。',
      '覆盖场景 A：整数加法。',
      '覆盖场景 B：零值计算。',
      '覆盖场景 C：连续执行。',
      '覆盖场景 D：重复计算时保持稳定输出。',
      '覆盖场景 E：把模型返回的完整正文透传给秘书汇总。',
      '覆盖场景 F：这段内容用于超过摘要截断阈值。',
      '尾部证据：秘书汇总必须展示这句话。',
    ].join('\n');
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: ScriptedWidgetReplyGateway([longReply]),
      ),
    );

    await tester.enterText(
      find.byType(TextField).last,
      '分配任务给测试工程师，验证长回复汇总。',
    );
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('私聊 · 秘书'), findsOneWidget);
    expect(find.textContaining('测试结论首行：1+1 等于 2。'), findsWidgets);
    expect(find.textContaining('尾部证据：秘书汇总必须展示这句话。'), findsWidgets);
    expect(find.textContaining('...'), findsNothing);
  });

  testWidgets('secretary private dispatch shows waiting status for member',
      (tester) async {
    final gateway = BlockingModelGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: gateway,
      ),
    );

    await tester.enterText(
      find.byType(TextField).last,
      '分配任务给测试工程师，先验算问题。',
    );
    await tester.tap(find.byTooltip('发送'));
    await gateway.started.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.textContaining('私聊 · 秘书'), findsOneWidget);
    expect(find.text('已分配给测试工程师，等待回复中'), findsOneWidget);
    expect(find.textContaining('秘书 正在输入中'), findsNothing);

    await tester.tap(find.byTooltip('停止生成'));
    await tester.pumpAndSettle();
  });

  testWidgets('secretary private dispatch replaces waiting bubble with summary',
      (tester) async {
    final gateway = CompletingBlockingModelGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: gateway,
      ),
    );

    await tester.enterText(
      find.byType(TextField).last,
      '分配任务给测试工程师，验证单消息汇总。',
    );
    await tester.tap(find.byTooltip('发送'));
    await gateway.started.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('已分配给测试工程师，等待回复中'), findsOneWidget);
    expect(find.textContaining('秘书 正在输入中'), findsNothing);

    gateway.finish('单消息汇总结果');
    await tester.pumpAndSettle();

    expect(find.text('已分配给测试工程师，等待回复中'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('chat-message-list')),
        matching: find.textContaining(
          '单消息汇总结果',
          findRichText: true,
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('秘书 正在输入中'), findsNothing);
  });

  testWidgets('send button stops an in-flight chat dispatch', (tester) async {
    final gateway = BlockingModelGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: gateway,
      ),
    );
    await tester.tap(find.byTooltip('团队'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '发起聊天'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '请实现长任务');
    await tester.tap(find.byTooltip('发送'));
    await gateway.started.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.byTooltip('停止生成'), findsOneWidget);

    await tester.tap(find.byTooltip('停止生成'));
    await tester.pumpAndSettle();

    expect(gateway.cancellation!.isCancelled, isTrue);
    expect(find.byTooltip('发送'), findsOneWidget);
    expect(find.textContaining('任务已停止'), findsWidgets);
  });

  testWidgets('composer uses taller input and split send button',
      (tester) async {
    final gateway = RecordingModelGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: gateway,
      ),
    );

    expect(find.byTooltip('表情'), findsNothing);
    expect(find.byTooltip('提及'), findsNothing);
    expect(find.text('发送(S)'), findsOneWidget);
    expect(
      tester
          .getSize(
              find.byKey(const ValueKey('chat-input-conv-member-secretary')))
          .height,
      greaterThanOrEqualTo(80),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('chat-send-button'))).height,
      lessThanOrEqualTo(36),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('chat-send-button'))).width,
      lessThanOrEqualTo(96),
    );
    final inputRect = tester.getRect(
      find.byKey(const ValueKey('chat-input-conv-member-secretary')),
    );
    final sendButtonRect =
        tester.getRect(find.byKey(const ValueKey('chat-send-button')));
    expect(inputRect.bottom - sendButtonRect.bottom, lessThanOrEqualTo(12));

    await tester.enterText(find.byType(TextField).last, '使用长方形发送按钮');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('使用长方形发送按钮'), findsWidgets);
    expect(gateway.modelNames, ['gpt-4.1']);
  });

  testWidgets('send options menu can send a message', (tester) async {
    final recordingGateway = RecordingModelGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: recordingGateway,
      ),
    );

    await tester.enterText(find.byType(TextField).last, '通过下拉菜单发送');
    await tester.tap(find.byTooltip('发送选项'));
    await _pumpPopupMenuFrames(tester);
    await tester.tap(find.widgetWithText(MenuItemButton, '发送'));
    await _pumpPopupMenuFrames(tester);

    expect(find.textContaining('通过下拉菜单发送'), findsWidgets);
    expect(recordingGateway.modelNames, ['gpt-4.1']);
  });

  testWidgets('send options menu can stop generation', (tester) async {
    final blockingGateway = BlockingModelGateway();
    addTearDown(() => blockingGateway.cancellation?.cancel());
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: blockingGateway,
      ),
    );

    await tester.enterText(find.byType(TextField).last, '通过下拉菜单停止');
    await tester.tap(find.byTooltip('发送'));
    await blockingGateway.started.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    await tester.tap(find.byTooltip('发送选项'));
    await _pumpPopupMenuFrames(tester);
    await tester.tap(find.widgetWithText(MenuItemButton, '停止生成'));
    await _pumpPopupMenuFrames(tester);

    expect(blockingGateway.cancellation!.isCancelled, isTrue);
    expect(find.textContaining('任务已停止'), findsWidgets);
  });

  testWidgets('chat can send again after stopping generation', (tester) async {
    final gateway = BlockingThenRecordingGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: gateway,
      ),
    );

    await tester.enterText(find.byType(TextField).last, '先停止');
    await tester.tap(find.byTooltip('发送'));
    await gateway.started.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    await tester.tap(find.byTooltip('停止生成'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '停止后继续');
    await tester.tap(find.byTooltip('发送'));
    await tester.pumpAndSettle();

    expect(find.textContaining('当前会话已停止'), findsNothing);
    expect(find.textContaining('停止后继续'), findsWidgets);
    expect(find.textContaining('已恢复回复'), findsWidgets);
  });

  testWidgets('enter submits the focused chat message', (tester) async {
    final gateway = RecordingModelGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: gateway,
      ),
    );

    await tester.enterText(find.byType(TextField).last, '按回车发送');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.textContaining('按回车发送'), findsWidgets);
    expect(gateway.modelNames, ['gpt-4.1']);
    expect(find.textContaining('使用 gpt-4.1 回复'), findsWidgets);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      isEmpty,
    );
  });

  testWidgets('shift enter inserts a newline without sending', (tester) async {
    final gateway = RecordingModelGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: gateway,
      ),
    );

    await tester.enterText(find.byType(TextField).last, '第一行');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(gateway.modelIds, isEmpty);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      '第一行\n',
    );
  });

  testWidgets('escape stops an in-flight chat dispatch', (tester) async {
    final gateway = BlockingModelGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: gateway,
      ),
    );

    await tester.enterText(find.byType(TextField).last, '请实现长任务');
    await tester.tap(find.byTooltip('发送'));
    await gateway.started.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    await tester.tap(find.byType(TextField).last);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(gateway.cancellation!.isCancelled, isTrue);
    expect(find.byTooltip('发送'), findsOneWidget);
    expect(find.textContaining('任务已停止'), findsWidgets);
  });

  testWidgets('shows member avatar and typing state during model requests',
      (tester) async {
    final gateway = BlockingModelGateway();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: gateway,
      ),
    );
    await tester.tap(find.byTooltip('团队'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '发起聊天'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '请实现请求中状态');
    await tester.tap(find.byTooltip('发送'));
    await gateway.started.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text('前'), findsOneWidget);
    expect(find.textContaining('前端工程师 正在输入中'), findsOneWidget);

    await tester.tap(find.byTooltip('停止生成'));
    await tester.pumpAndSettle();
  });
}

AppState _stateWithLongSecretaryChat() {
  final seed = AppState.seed();
  final conversation = seed.conversations.firstWhere(
    (item) => item.id == 'conv-member-secretary',
  );
  return seed.copyWith(
    conversations: [
      conversation.copyWith(
        messages: List.generate(
          45,
          (index) => ChatMessage(
            id: 'msg-history-$index',
            authorName: '秘书',
            content: '历史消息 $index\n${'填充内容 ' * 12}',
            createdAt: DateTime(2026, 6, 14, 8).add(
              Duration(minutes: index),
            ),
          ),
        ),
      ),
      ...seed.conversations.where(
        (item) => item.id != conversation.id,
      ),
    ],
  );
}

AppState _stateWithLongTeamAndSecretaryChats() {
  final seed = AppState.seed();
  final teamConversation = seed.conversations.firstWhere(
    (item) => item.id == 'conv-team-default',
  );
  final secretaryConversation = seed.conversations.firstWhere(
    (item) => item.id == 'conv-member-secretary',
  );
  return seed.copyWith(
    conversations: seed.conversations.map((conversation) {
      if (conversation.id == teamConversation.id) {
        return conversation.copyWith(
          messages: List.generate(
            45,
            (index) => ChatMessage(
              id: 'msg-team-history-$index',
              authorName: index.isEven ? '秘书' : '前端工程师',
              memberId: index.isEven ? 'member-secretary' : 'member-frontend',
              content: '群聊历史消息 $index\n${'团队填充内容 ' * 12}',
              createdAt: DateTime(2026, 6, 14, 8).add(
                Duration(minutes: index),
              ),
            ),
          ),
        );
      }
      if (conversation.id == secretaryConversation.id) {
        return conversation.copyWith(
          messages: List.generate(
            45,
            (index) => ChatMessage(
              id: 'msg-secretary-history-$index',
              authorName: '秘书',
              memberId: 'member-secretary',
              content: '秘书历史消息 $index\n${'私聊填充内容 ' * 12}',
              createdAt: DateTime(2026, 6, 14, 9).add(
                Duration(minutes: index),
              ),
            ),
          ),
        );
      }
      return conversation;
    }).toList(),
  );
}

Future<void> _pumpStreamingFrames(
  WidgetTester tester, {
  required int count,
}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _pumpPopupMenuFrames(WidgetTester tester) async {
  for (var index = 0; index < 10; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

int _conversationRowCount(WidgetTester tester) {
  return find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('conversation-row-');
      })
      .evaluate()
      .length;
}

class BlockingModelGateway implements ModelGateway {
  final Completer<void> started = Completer<void>();
  ModelRequestCancellation? cancellation;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    this.cancellation = cancellation;
    if (!started.isCompleted) {
      started.complete();
    }
    await cancellation!.cancelled;
    cancellation.throwIfCancelled();
    return 'unreachable';
  }
}

class CompletingBlockingModelGateway implements ModelGateway {
  final Completer<void> started = Completer<void>();
  final Completer<String> _reply = Completer<String>();

  void finish(String value) {
    if (!_reply.isCompleted) {
      _reply.complete(value);
    }
  }

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    if (!started.isCompleted) {
      started.complete();
    }
    final reply = await _reply.future;
    cancellation?.throwIfCancelled();
    return reply;
  }
}

class BlockingThenRecordingGateway implements ModelGateway {
  final Completer<void> started = Completer<void>();
  ModelRequestCancellation? cancellation;
  var callCount = 0;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    callCount++;
    if (callCount == 1) {
      this.cancellation = cancellation;
      if (!started.isCompleted) {
        started.complete();
      }
      await cancellation!.cancelled;
      cancellation.throwIfCancelled();
    }
    return '已恢复回复';
  }
}

class RecordingModelGateway implements ModelGateway {
  final List<String> modelIds = [];
  final List<String> modelNames = [];

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    modelIds.add(model.id);
    modelNames.add(model.modelName);
    return '使用 ${model.modelName} 回复';
  }
}

class ScriptedWidgetReplyGateway implements ModelGateway {
  ScriptedWidgetReplyGateway(this.responses);

  final List<String> responses;
  var _index = 0;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    return responses[_index++];
  }
}

class RecordingScriptedWidgetGateway implements ModelGateway {
  RecordingScriptedWidgetGateway(this.responses);

  final List<String> responses;
  final List<List<ChatMessage>> recordedMessages = [];
  var _index = 0;
  var calls = 0;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    calls++;
    recordedMessages.add([...messages]);
    return responses[_index++];
  }
}

class ScriptedStreamingWidgetGateway implements MetadataModelGateway {
  ScriptedStreamingWidgetGateway({
    required this.deltas,
    this.pauseAfterDeltaIndex,
    this.deltaDelay = const Duration(milliseconds: 60),
  });

  final List<ModelStreamDelta> deltas;
  final int? pauseAfterDeltaIndex;
  final Duration deltaDelay;
  final Completer<void> completed = Completer<void>();
  final Completer<void> paused = Completer<void>();
  final Completer<void> _resume = Completer<void>();

  void resume() {
    if (!_resume.isCompleted) {
      _resume.complete();
    }
  }

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    final completion = await completeWithMetadata(
      model: model,
      systemPrompt: systemPrompt,
      messages: messages,
      cancellation: cancellation,
    );
    return completion.content;
  }

  @override
  Future<ModelCompletion> completeWithMetadata({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
    ModelStreamDeltaHandler? onDelta,
    List<ModelToolDefinition> tools = const [],
    ModelToolChoice toolChoice = ModelToolChoice.auto,
    List<ModelToolRound> toolRounds = const [],
  }) async {
    final content = StringBuffer();
    for (var index = 0; index < deltas.length; index++) {
      final delta = deltas[index];
      cancellation?.throwIfCancelled();
      onDelta?.call(delta);
      if (delta.contentDelta != null) {
        content.write(delta.contentDelta);
      }
      if (pauseAfterDeltaIndex == index) {
        if (!paused.isCompleted) {
          paused.complete();
        }
        await _resume.future;
      }
      await Future<void>.delayed(deltaDelay);
    }
    if (!completed.isCompleted) {
      completed.complete();
    }
    return ModelCompletion(content: content.toString());
  }
}

class ScriptedTitleGateway implements ModelGateway {
  ScriptedTitleGateway({required this.title, this.fail = false});

  final String title;
  final bool fail;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    if (fail) {
      throw const ModelGatewayException('标题生成失败');
    }
    return title;
  }
}

class ConversationTitleGateway implements ModelGateway {
  ConversationTitleGateway({
    required this.title,
    required this.reply,
    this.failTitle = false,
  });

  final String title;
  final String reply;
  final bool failTitle;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final prompt = messages.map((message) => message.content).join('\n');
    if (prompt.contains('会话标题')) {
      if (failTitle) {
        throw const ModelGatewayException('标题生成失败');
      }
      return title;
    }
    return reply;
  }
}
