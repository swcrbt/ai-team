import 'app_widget_test_support.dart';

void main() {
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
    await pumpPopupMenuFrames(tester);
    await tester.tap(find.widgetWithText(MenuItemButton, '发送'));
    await pumpPopupMenuFrames(tester);

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
    await pumpPopupMenuFrames(tester);
    await tester.tap(find.widgetWithText(MenuItemButton, '停止生成'));
    await pumpPopupMenuFrames(tester);

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
