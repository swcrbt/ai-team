import 'app_widget_test_support.dart';

void main() {
  const messageBottomThreshold = 24.0;

  testWidgets('chat scrolls to the latest message after sending',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: stateWithLongSecretaryChat(),
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
        initialState: stateWithLongSecretaryChat(),
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
        initialState: stateWithLongSecretaryChat(),
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
        initialState: stateWithLongSecretaryChat(),
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
        initialState: stateWithLongSecretaryChat(),
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
        initialState: stateWithLongSecretaryChat(),
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
        initialState: stateWithLongTeamAndSecretaryChats(),
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
        initialState: stateWithLongSecretaryChat(),
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
        initialState: stateWithLongTeamAndSecretaryChats(),
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
    await tester.tap(
      find.byKey(const ValueKey('member-row-member-frontend')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('打开私聊'));
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
        initialState: stateWithLongTeamAndSecretaryChats(),
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
        initialState: stateWithLongTeamAndSecretaryChats(),
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
        initialState: stateWithLongTeamAndSecretaryChats(),
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
        initialState: stateWithLongTeamAndSecretaryChats(),
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
}
