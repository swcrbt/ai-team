import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
    final memberConversation =
        controller.conversationForMember('member-frontend');

    controller.selectConversation(memberConversation.id);
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

    expect(find.text('群聊'), findsOneWidget);
    expect(find.text('私聊'), findsOneWidget);
    expect(find.text('默认开发团队'), findsWidgets);
    expect(find.textContaining('群聊 · 默认开发团队'), findsOneWidget);
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
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('模型'), findsOneWidget);
    expect(find.text('角色'), findsOneWidget);
    expect(find.text('成员'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    expect(find.text('命令'), findsOneWidget);
    expect(find.text('补丁'), findsNothing);
    expect(find.text('模型配置'), findsOneWidget);
    expect(find.text('角色配置'), findsOneWidget);
    expect(find.text('团队成员'), findsOneWidget);
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

    expect(find.text('群聊'), findsOneWidget);
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

    expect(find.byTooltip('继续'), findsNothing);
    expect(find.byTooltip('停止'), findsNothing);
  });

  testWidgets('sidebar team button switches back to the team chat',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.text('前端工程师').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('私聊 · 前端工程师'), findsOneWidget);

    await tester.tap(find.byTooltip('团队'));
    await tester.pumpAndSettle();

    expect(find.textContaining('群聊 · 默认开发团队'), findsOneWidget);
  });

  testWidgets('sidebar project button opens the project settings section',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('项目'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('项目工作区'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('项目工作区')).dy,
      lessThan(320),
    );
  });

  testWidgets('submits a task to the secretary and renders member responses',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.enterText(find.byType(TextField).last, '请实现设置页面');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('请实现设置页面'), findsWidgets);
    expect(find.textContaining('秘书'), findsWidgets);
    expect(find.textContaining('前端工程师'), findsWidgets);
    expect(find.textContaining('群聊 · 默认开发团队'), findsOneWidget);
    expect(find.textContaining('汇总'), findsWidgets);
  });

  testWidgets('send button stops an in-flight chat dispatch', (tester) async {
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

    expect(find.byTooltip('停止生成'), findsOneWidget);

    await tester.tap(find.byTooltip('停止生成'));
    await tester.pumpAndSettle();

    expect(gateway.cancellation!.isCancelled, isTrue);
    expect(find.byTooltip('发送'), findsOneWidget);
    expect(find.textContaining('任务已停止'), findsWidgets);
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
