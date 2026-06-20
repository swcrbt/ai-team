import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/app.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/file_dialogs.dart';
import 'package:ai_team/core/model_gateway.dart';
import 'package:ai_team/core/orchestrator.dart';

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

    expect(find.text('思考过程'), findsOneWidget);
    expect(find.text('供应商返回的真实 reasoning 内容'), findsNothing);
    expect(find.widgetWithText(SelectableText, '正式回复'), findsOneWidget);

    await tester.tap(find.text('思考过程'));
    await tester.pumpAndSettle();

    expect(find.text('供应商返回的真实 reasoning 内容'), findsOneWidget);
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
    expect(manualOffset, lessThan(controller.position.maxScrollExtent - 96));

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
    expect(manualOffset, lessThan(controller.position.maxScrollExtent - 96));

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
    await tester.drag(list, const Offset(0, -900));
    await tester.pumpAndSettle();

    final secretaryOffset = controller.offset;
    expect(secretaryOffset, greaterThan(0));
    expect(secretaryOffset, lessThan(controller.position.maxScrollExtent - 96));

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
    expect(manualOffset, lessThan(controller.position.maxScrollExtent - 96));
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
    expect(manualOffset, lessThan(controller.position.maxScrollExtent - 96));

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
    expect(manualOffset, lessThan(controller.position.maxScrollExtent - 96));

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
    expect(wheelOffset, lessThan(controller.position.maxScrollExtent - 96));
    expect(find.byTooltip('回到底部'), findsOneWidget);

    gateway.resume();
    await _pumpStreamingFrames(tester, count: gateway.deltas.length + 1);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('滚轮后继续输出'), findsWidgets);
    expect(controller.offset, wheelOffset);
  });

  testWidgets('chat small upward wheel scroll disables streaming auto follow',
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
      lessThan(96),
    );

    await _pumpStreamingFrames(tester, count: 10);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('小步滚轮后继续输出 7'), findsWidgets);
    expect(controller.offset, wheelOffset);
    expect(find.byTooltip('回到底部'), findsOneWidget);
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
    expect(find.byTooltip('回到底部'), findsOneWidget);

    await tester.tap(find.byTooltip('回到底部'));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
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
        scrollDelta: const Offset(0, -20),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('回到底部'), findsOneWidget);

    await tester.tap(find.byTooltip('回到底部'));
    await tester.pump();
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(find.byTooltip('回到底部'), findsNothing);

    await _pumpStreamingFrames(tester, count: 12);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('点击后继续增长 11'), findsWidgets);
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(find.byTooltip('回到底部'), findsNothing);
  });

  testWidgets('chat resumes auto follow after scrolling back near bottom',
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
      greaterThan(96),
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
      lessThanOrEqualTo(96),
    );
    expect(find.byTooltip('回到底部'), findsNothing);
  });

  testWidgets('chat restores follow when a manual scroll ends at bottom',
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
    expect(find.byTooltip('回到底部'), findsOneWidget);

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
          detail: '较新操作',
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
    expect(find.text('较新操作'), findsOneWidget);
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
    expect(find.text('model: model-main'), findsOneWidget);
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

    await tester.tap(find.text('关闭').last);
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
    await tester.tap(find.byIcon(Icons.send_rounded));
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
    expect(find.textContaining('已发送给测试工程师，等待回复'), findsWidgets);

    await tester.tap(find.byTooltip('停止生成'));
    await tester.pumpAndSettle();
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

Future<void> _pumpStreamingFrames(
  WidgetTester tester, {
  required int count,
}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
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
