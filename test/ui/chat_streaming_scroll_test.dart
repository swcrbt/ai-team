import 'app_widget_test_support.dart';

void main() {
  const messageBottomThreshold = 24.0;

  testWidgets('chat shows a back to bottom button after manual scroll',
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
    final gateway = ScriptedStreamingGateway(
      deltas: [
        const ModelStreamDelta(contentDelta: '流式回复开始\n'),
        ModelStreamDelta(contentDelta: '${'持续输出内容 ' * 24}\n'),
        ModelStreamDelta(contentDelta: '${'更多输出内容 ' * 24}\n'),
        ModelStreamDelta(contentDelta: '${'最后一段输出 ' * 24}\n'),
      ],
    );
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
    final gateway = ScriptedStreamingGateway(
      deltas: [
        for (var index = 0; index < 30; index++)
          ModelStreamDelta(contentDelta: '高频输出 $index ${'内容 ' * 8}\n'),
      ],
      deltaDelay: const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: stateWithLongSecretaryChat(),
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
    await pumpStreamingFrames(tester, count: 16);
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
    final gateway = ScriptedStreamingGateway(
      deltas: [
        for (var index = 0; index < 12; index++)
          ModelStreamDelta(contentDelta: '贴底输出 $index ${'内容 ' * 6}\n'),
      ],
      deltaDelay: const Duration(milliseconds: 30),
    );
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
    final gateway = ScriptedStreamingGateway(
      deltas: [
        for (var index = 0; index < 20; index++)
          ModelStreamDelta(contentDelta: '局部草稿 $index\n'),
      ],
      pauseAfterDeltaIndex: 9,
      deltaDelay: const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: stateWithLongSecretaryChat(),
        modelGateway: gateway,
        chatScrollDiagnostics: diagnostics,
      ),
    );
    await tester.pumpAndSettle();
    diagnostics.reset();

    await tester.enterText(find.byType(TextField).last, '请高频流式输出');
    await tester.tap(find.byTooltip('发送'));
    await pumpStreamingFrames(tester, count: 8);
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
    await pumpStreamingFrames(tester, count: 8);
    await gateway.completed.future.timeout(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('chat does not rebuild history bubbles for streaming drafts',
      (tester) async {
    final diagnostics = ChatScrollDiagnostics();
    final gateway = ScriptedStreamingGateway(
      deltas: [
        for (var index = 0; index < 12; index++)
          ModelStreamDelta(contentDelta: '只更新当前消息 $index\n'),
      ],
      pauseAfterDeltaIndex: 5,
      deltaDelay: const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: stateWithLongSecretaryChat(),
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
    await pumpStreamingFrames(tester, count: 6);
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
    await pumpStreamingFrames(tester, count: 8);
    await gateway.completed.future.timeout(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('chat commits visible streaming draft when generation stops',
      (tester) async {
    AppState? persisted;
    final gateway = ScriptedStreamingGateway(
      deltas: const [
        ModelStreamDelta(contentDelta: '停止前草稿内容\n'),
        ModelStreamDelta(contentDelta: '不应该继续输出'),
      ],
      pauseAfterDeltaIndex: 0,
      deltaDelay: const Duration(milliseconds: 20),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: stateWithLongSecretaryChat(),
        modelGateway: gateway,
        onStateChanged: (state) => persisted = state,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '请流式输出后停止');
    await tester.tap(find.byTooltip('发送'));
    await pumpStreamingFrames(tester, count: 2);
    await gateway.paused.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.textContaining('停止前草稿内容'), findsWidgets);

    await tester.tap(find.byTooltip('停止生成'));
    gateway.resume();
    await pumpStreamingFrames(tester, count: 4);
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
    final gateway = ScriptedStreamingGateway(
      deltas: const [
        ModelStreamDelta(contentDelta: '第一行 **markdown**\n第二行仍在输出'),
      ],
      pauseAfterDeltaIndex: 0,
      deltaDelay: const Duration(milliseconds: 80),
    );
    await tester.pumpWidget(
      AiTeamApp(
        initialState: stateWithLongSecretaryChat(),
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
    await pumpStreamingFrames(tester, count: 3);
    await gateway.paused.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.textContaining('第一行'), findsWidgets);
    expect(streamedMarkdownBody, findsNothing);
    expect(diagnostics.streamingBodyBuildCount, greaterThan(0));
    expect(diagnostics.streamingStableSegmentCommitCount, greaterThan(0));
    expect(diagnostics.streamingTailUpdateCount, greaterThan(0));

    gateway.resume();
    await pumpStreamingFrames(tester, count: 3);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(streamedMarkdownBody, findsOneWidget);
    expect(diagnostics.markdownBodyBuildCount, greaterThan(0));
  });

  testWidgets('chat keeps following a large streaming delta from bottom',
      (tester) async {
    final gateway = ScriptedStreamingGateway(
      deltas: [
        ModelStreamDelta(contentDelta: '${'单次大段流式输出 ' * 220}\n'),
      ],
      deltaDelay: Duration.zero,
    );
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

    await tester.enterText(find.byType(TextField).last, '请流式输出很长回复');
    await tester.tap(find.byTooltip('发送'));
    await pumpStreamingFrames(tester, count: 4);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('单次大段流式输出'), findsWidgets);
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(find.byTooltip('回到底部'), findsNothing);
  });

  testWidgets('chat allows manual scrolling during streaming output',
      (tester) async {
    final gateway = ScriptedStreamingGateway(
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
    await pumpStreamingFrames(tester, count: gateway.deltas.length + 1);
    await gateway.completed.future;
    await tester.pumpAndSettle();

    expect(find.textContaining('最后一段输出'), findsWidgets);
    expect(controller.offset, manualOffset);
    expect(find.byTooltip('回到底部'), findsOneWidget);
  });

  testWidgets('chat allows manual scrolling while streaming continues',
      (tester) async {
    final gateway = ScriptedStreamingGateway(
      deltas: [
        for (var index = 0; index < 12; index++)
          ModelStreamDelta(contentDelta: '持续流式输出 $index ${'内容 ' * 30}\n'),
      ],
      deltaDelay: const Duration(milliseconds: 20),
    );
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

    await tester.enterText(find.byType(TextField).last, '请持续流式输出');
    await tester.tap(find.byTooltip('发送'));
    await pumpStreamingFrames(tester, count: 2);

    await tester.drag(list, const Offset(0, 900));
    await tester.pump();
    final manualOffset = controller.offset;
    expect(manualOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));

    await pumpStreamingFrames(tester, count: 12);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('持续流式输出 11'), findsWidgets);
    expect(controller.offset, manualOffset);
    expect(find.byTooltip('回到底部'), findsOneWidget);
  });

  testWidgets('chat cancels queued auto follow when user scrolls during stream',
      (tester) async {
    final gateway = ScriptedStreamingGateway(
      deltas: [
        const ModelStreamDelta(contentDelta: '流式回复开始\n'),
        ModelStreamDelta(contentDelta: '${'继续输出内容 ' * 80}\n'),
        ModelStreamDelta(contentDelta: '${'不会拉回底部 ' * 80}\n'),
      ],
      pauseAfterDeltaIndex: 0,
    );
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

    await tester.enterText(find.byType(TextField).last, '请流式输出长回复');
    await tester.tap(find.byTooltip('发送'));
    await gateway.paused.future.timeout(const Duration(seconds: 1));

    await tester.drag(list, const Offset(0, 900));
    await tester.pump();
    final manualOffset = controller.offset;
    expect(manualOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));

    gateway.resume();
    await pumpStreamingFrames(tester, count: gateway.deltas.length + 1);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('不会拉回底部'), findsWidgets);
    expect(controller.offset, manualOffset);
    expect(find.byTooltip('回到底部'), findsOneWidget);
  });

  testWidgets('chat mouse wheel scrolling disables streaming auto follow',
      (tester) async {
    final gateway = ScriptedStreamingGateway(
      deltas: [
        const ModelStreamDelta(contentDelta: '流式回复开始\n'),
        ModelStreamDelta(contentDelta: '${'滚轮后继续输出 ' * 80}\n'),
      ],
      pauseAfterDeltaIndex: 0,
    );
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
    await pumpStreamingFrames(tester, count: gateway.deltas.length + 1);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('滚轮后继续输出'), findsWidgets);
    expect(controller.offset, wheelOffset);
  });

  testWidgets(
      'chat small upward wheel scroll stays near bottom during streaming',
      (tester) async {
    final gateway = ScriptedStreamingGateway(
      deltas: [
        const ModelStreamDelta(contentDelta: '流式回复开始\n'),
        for (var index = 0; index < 8; index++)
          ModelStreamDelta(contentDelta: '小步滚轮后继续输出 $index ${'内容 ' * 30}\n'),
      ],
      deltaDelay: const Duration(milliseconds: 20),
    );
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

    await tester.enterText(find.byType(TextField).last, '请持续流式输出');
    await tester.tap(find.byTooltip('发送'));
    await pumpStreamingFrames(tester, count: 2);

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

    await pumpStreamingFrames(tester, count: 10);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('小步滚轮后继续输出 7'), findsWidgets);
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(find.byTooltip('回到底部'), findsNothing);
  });

  testWidgets('chat back to bottom resumes follow after small wheel scroll',
      (tester) async {
    final gateway = ScriptedStreamingGateway(
      deltas: [
        const ModelStreamDelta(contentDelta: '流式回复开始\n'),
        ModelStreamDelta(contentDelta: '${'点击回到底部后继续输出 ' * 60}\n'),
      ],
      pauseAfterDeltaIndex: 0,
    );
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
    await pumpStreamingFrames(tester, count: gateway.deltas.length + 1);
    await gateway.completed.future.timeout(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.textContaining('点击回到底部后继续输出'), findsWidgets);
    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('chat back to bottom needs one click while stream keeps growing',
      (tester) async {
    final gateway = ScriptedStreamingGateway(
      deltas: [
        for (var index = 0; index < 12; index++)
          ModelStreamDelta(contentDelta: '点击后继续增长 $index ${'内容 ' * 80}\n'),
      ],
      deltaDelay: const Duration(milliseconds: 20),
    );
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

    await tester.enterText(find.byType(TextField).last, '请继续流式输出');
    await tester.tap(find.byTooltip('发送'));
    await pumpStreamingFrames(tester, count: 2);

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

    await pumpStreamingFrames(tester, count: 12);
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
        initialState: stateWithLongSecretaryChat(),
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
        initialState: stateWithLongSecretaryChat(),
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
        initialState: stateWithLongSecretaryChat(),
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
}
