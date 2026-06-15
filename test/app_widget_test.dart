import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

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
      () {
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

    expect(persisted, isNotNull);
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
      isTrue,
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

  test('controller backfills missing member conversations from old state', () {
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

    expect(controller.conversationForMember('member-frontend').title, '前端工程师');
    expect(controller.conversationForMember('member-tester').title, '测试工程师');
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

  test('controller blocks dispatch while a conversation is paused or stopped',
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
    await controller.dispatch('停止后不应执行');

    expect(controller.currentConversation.messages.length, stoppedCount);
    expect(controller.error, contains('已停止'));
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
    expect(messagePadding.padding, EdgeInsets.zero);
    expect(find.byTooltip('复制消息'), findsNothing);
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

    expect(find.byTooltip('复制消息'), findsOneWidget);
    expect(find.text('09:05'), findsOneWidget);
    expect(
      tester
          .getTopLeft(find.widgetWithText(SelectableText, nextMessageContent)),
      nextMessageTopBeforeHover,
    );

    await mouse.removePointer();
  });

  testWidgets('chat scrolls to the latest message after sending',
      (tester) async {
    final seed = AppState.seed();
    final conversation = seed.conversations.firstWhere(
      (item) => item.id == 'conv-member-secretary',
    );
    final state = seed.copyWith(
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

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: RecordingModelGateway(),
      ),
    );

    final list = find.byKey(const ValueKey('chat-message-list'));
    expect(list, findsOneWidget);
    await tester.drag(list, const Offset(0, 900));
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
