import 'app_widget_test_support.dart';

void main() {
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
}
