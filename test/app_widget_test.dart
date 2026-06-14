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
