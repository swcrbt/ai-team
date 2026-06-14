import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/app.dart';
import 'package:ai_team/core/domain.dart';
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
    expect(await file.readAsString(), 'old docs\n');
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

  testWidgets('desktop workspace exposes chat, model, role, and team surfaces',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('AI Team'), findsOneWidget);
    expect(find.text('团队会话'), findsOneWidget);
    expect(find.text('模型配置'), findsOneWidget);
    expect(find.text('角色配置'), findsOneWidget);
    expect(find.text('团队成员'), findsOneWidget);
    expect(find.text('补丁确认'), findsOneWidget);
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
    expect(find.textContaining('汇总'), findsWidgets);
  });
}
