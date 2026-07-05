import 'app_widget_test_support.dart';

void main() {
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
        modelGateway: ScriptedReplyGateway([longReply]),
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
}
