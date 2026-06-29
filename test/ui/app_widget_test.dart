import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:ai_team/app.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/model_gateway.dart';
import 'package:ai_team/core/orchestrator.dart';

import '../support/model_gateway_fakes.dart';

void main() {
  const messageBottomThreshold = 24.0;

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

  testWidgets('chat workspace shows scoped pending command requests',
      (tester) async {
    final state = AppState.seed().copyWith(
      commandRequests: [
        CommandRequest.pending(
          id: 'command-chat-df',
          memberName: '秘书',
          command: 'df -h /',
          workingDirectory: '/',
          decision: CommandDecision.requiresConfirmation,
          conversationId: 'conv-member-secretary',
          memberId: 'member-secretary',
          toolCallId: 'call-df',
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('待确认命令'), findsOneWidget);
    expect(find.textContaining('df -h /'), findsWidgets);
    expect(find.textContaining('/'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '批准并执行'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '拒绝'), findsOneWidget);
  });

  testWidgets('chat workspace shows approved command requests without approval',
      (tester) async {
    final state = AppState.seed().copyWith(
      commandRequests: [
        CommandRequest.pending(
          id: 'command-chat-approved',
          memberName: '秘书',
          command: 'df -h /',
          workingDirectory: '/',
          decision: CommandDecision.allowed,
          conversationId: 'conv-member-secretary',
          memberId: 'member-secretary',
          toolCallId: 'call-df',
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('待确认命令'), findsNothing);
    expect(find.text('已允许命令'), findsOneWidget);
    expect(find.textContaining('df -h /'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '执行'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '批准并执行'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, '拒绝'), findsNothing);
  });

  testWidgets(
      'chat message renders command result collapsed in the same bubble',
      (tester) async {
    final message = ChatMessage(
      id: 'msg-command-result',
      authorName: '秘书',
      memberId: 'member-secretary',
      content: '我先查看一下\n根目录已使用 42G',
      createdAt: DateTime(2026, 6, 29),
      contentBlocks: const [
        ChatMessageContentBlock.text('我先查看一下'),
        ChatMessageContentBlock.commandResult(
          CommandResultAttachment(
            requestId: 'command-df',
            status: CommandRequestStatus.executed,
            workingDirectory: '/',
            command: 'df -h /',
            output: 'Filesystem 42Gi /',
          ),
        ),
        ChatMessageContentBlock.text('根目录已使用 42G'),
      ],
    );
    final request = CommandRequest.pending(
      id: 'command-df',
      memberName: '秘书',
      command: 'df -h /',
      workingDirectory: '/',
      decision: CommandDecision.allowed,
      conversationId: 'conv-member-secretary',
      memberId: 'member-secretary',
      toolCallId: 'call-df',
      messageId: 'msg-command-result',
    ).copyWith(
        status: CommandRequestStatus.executed, output: 'Filesystem 42Gi /');
    final seed = AppState.seed();
    final conversation = seed.conversations.firstWhere(
      (conversation) => conversation.id == 'conv-member-secretary',
    );
    final state = seed.copyWith(
      conversations: seed.conversations
          .map(
            (item) => item.id == conversation.id
                ? conversation.copyWith(messages: [message])
                : item,
          )
          .toList(),
      commandRequests: [request],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('我先查看一下'), findsOneWidget);
    expect(find.text('根目录已使用 42G'), findsOneWidget);
    expect(find.text('命令执行结果'), findsOneWidget);
    expect(find.textContaining('Filesystem 42Gi'), findsNothing);
    expect(find.text('命令已执行'), findsNothing);

    await tester.tap(find.text('命令执行结果'));
    await tester.pumpAndSettle();

    expect(find.textContaining('df -h /'), findsWidgets);
    expect(find.textContaining('Filesystem 42Gi'), findsOneWidget);
  });

  testWidgets('legacy unscoped pending commands remain visible in settings',
      (tester) async {
    final state = AppState.seed().copyWith(
      commandRequests: [
        CommandRequest.pending(
          id: 'command-legacy-df',
          memberName: '秘书',
          command: 'df -h /',
          workingDirectory: '/',
          decision: CommandDecision.requiresConfirmation,
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: state,
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('待确认命令'), findsNothing);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('命令请求'), findsOneWidget);
    expect(find.textContaining('df -h /'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '批准'), findsOneWidget);
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
        initialState: _stateWithLongSecretaryChat(),
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
        initialState: _stateWithLongSecretaryChat(),
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
        initialState: _stateWithLongTeamAndSecretaryChats(),
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
        initialState: _stateWithLongSecretaryChat(),
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
        initialState: _stateWithLongTeamAndSecretaryChats(),
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
    await tester.tap(find.widgetWithText(FilledButton, '发起聊天').at(1));
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
        initialState: _stateWithLongTeamAndSecretaryChats(),
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
        initialState: _stateWithLongTeamAndSecretaryChats(),
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
        initialState: _stateWithLongTeamAndSecretaryChats(),
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
        initialState: _stateWithLongTeamAndSecretaryChats(),
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
        initialState: _stateWithLongSecretaryChat(),
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
    await _pumpStreamingFrames(tester, count: 16);
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
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
        chatScrollDiagnostics: diagnostics,
      ),
    );
    await tester.pumpAndSettle();
    diagnostics.reset();

    await tester.enterText(find.byType(TextField).last, '请高频流式输出');
    await tester.tap(find.byTooltip('发送'));
    await _pumpStreamingFrames(tester, count: 8);
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
    await _pumpStreamingFrames(tester, count: 8);
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
        initialState: _stateWithLongSecretaryChat(),
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
    await _pumpStreamingFrames(tester, count: 6);
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
    await _pumpStreamingFrames(tester, count: 8);
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
        initialState: _stateWithLongSecretaryChat(),
        modelGateway: gateway,
        onStateChanged: (state) => persisted = state,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '请流式输出后停止');
    await tester.tap(find.byTooltip('发送'));
    await _pumpStreamingFrames(tester, count: 2);
    await gateway.paused.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.textContaining('停止前草稿内容'), findsWidgets);

    await tester.tap(find.byTooltip('停止生成'));
    gateway.resume();
    await _pumpStreamingFrames(tester, count: 4);
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
        initialState: _stateWithLongSecretaryChat(),
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
    await _pumpStreamingFrames(tester, count: 3);
    await gateway.paused.future.timeout(const Duration(seconds: 1));
    await tester.pump();

    expect(find.textContaining('第一行'), findsWidgets);
    expect(streamedMarkdownBody, findsNothing);
    expect(diagnostics.streamingBodyBuildCount, greaterThan(0));
    expect(diagnostics.streamingStableSegmentCommitCount, greaterThan(0));
    expect(diagnostics.streamingTailUpdateCount, greaterThan(0));

    gateway.resume();
    await _pumpStreamingFrames(tester, count: 3);
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
    expect(manualOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));
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
    final gateway = ScriptedStreamingGateway(
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
    expect(manualOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));

    await _pumpStreamingFrames(tester, count: 12);
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
    expect(manualOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));

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
    final gateway = ScriptedStreamingGateway(
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
    expect(wheelOffset,
        lessThan(controller.position.maxScrollExtent - messageBottomThreshold));
    expect(find.byTooltip('回到底部'), findsOneWidget);

    gateway.resume();
    await _pumpStreamingFrames(tester, count: gateway.deltas.length + 1);
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
      lessThan(messageBottomThreshold),
    );
    expect(find.byTooltip('回到底部'), findsNothing);

    await _pumpStreamingFrames(tester, count: 10);
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
    expect(
      controller.position.maxScrollExtent - controller.offset,
      lessThan(messageBottomThreshold),
    );
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
    final gateway = ScriptedStreamingGateway(
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

    await _pumpStreamingFrames(tester, count: 12);
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

  testWidgets('chat header action menu starts a new scoped session',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.byTooltip('会话操作'), findsOneWidget);
    final initialRows = _conversationRowCount(tester);

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    expect(find.text('新增会话'), findsOneWidget);
    expect(find.text('历史会话'), findsOneWidget);

    await tester.tap(find.text('新增会话'));
    await tester.pumpAndSettle();

    expect(find.textContaining('私聊 · 新会话'), findsOneWidget);
    expect(_conversationRowCount(tester), initialRows);
  });

  testWidgets('chat header history menu switches current object sessions',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.textContaining('私聊 · 秘书'), findsOneWidget);

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增会话'));
    await tester.pumpAndSettle();
    expect(find.textContaining('私聊 · 新会话'), findsOneWidget);

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('秘书').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('私聊 · 秘书'), findsOneWidget);
  });

  testWidgets('chat history menu deletes a session after confirmation',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增会话'));
    await tester.pumpAndSettle();
    expect(find.textContaining('私聊 · 新会话'), findsOneWidget);

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('秘书').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('私聊 · 秘书'), findsOneWidget);

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    expect(find.text('新会话 · 秘书'), findsOneWidget);
    expect(find.byTooltip('删除会话'), findsWidgets);

    await tester.tap(find.byTooltip('删除会话').last);
    await tester.pumpAndSettle();
    expect(find.text('确认删除该会话？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    expect(find.text('新会话 · 秘书'), findsOneWidget);

    await tester.tap(find.byTooltip('删除会话').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('私聊 · 秘书'), findsOneWidget);
    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    expect(find.text('新会话 · 秘书'), findsNothing);
  });

  testWidgets('chat header action menu reuses one empty history session',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增会话'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('秘书').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增会话'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    expect(find.text('新会话 · 秘书'), findsOneWidget);
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

  testWidgets('configuration dialogs use the clean shared dialog frame',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    Future<void> expectSharedDialog({
      required String pageTooltip,
      required String actionTooltip,
      required String title,
      required String closeText,
    }) async {
      await tester.tap(find.byTooltip(pageTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(actionTooltip).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('config-dialog-frame')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('config-dialog-header')), findsOneWidget);
      expect(find.byKey(const ValueKey('config-dialog-body')), findsOneWidget);
      expect(
          find.byKey(const ValueKey('config-dialog-actions')), findsOneWidget);
      expect(find.text(title), findsOneWidget);

      await tester.tap(find.text(closeText).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await expectSharedDialog(
      pageTooltip: '团队',
      actionTooltip: '新增团队',
      title: '新增团队',
      closeText: '取消',
    );
    await expectSharedDialog(
      pageTooltip: '模型',
      actionTooltip: '编辑模型',
      title: '编辑模型配置',
      closeText: '取消',
    );
    await expectSharedDialog(
      pageTooltip: '角色',
      actionTooltip: '新增角色',
      title: '新增角色配置',
      closeText: '取消',
    );
    await expectSharedDialog(
      pageTooltip: '成员',
      actionTooltip: '新增成员',
      title: '新增团队成员',
      closeText: '取消',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed().copyWith(
          workspaces: [
            ProjectWorkspace(
              id: 'workspace-dialog-test',
              name: '当前项目',
              path: Directory.current.path,
            ),
          ],
        ),
        modelGateway: FakeModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    await expectSharedDialog(
      pageTooltip: '项目',
      actionTooltip: '创建补丁',
      title: '创建补丁提案',
      closeText: '取消',
    );
    await expectSharedDialog(
      pageTooltip: '项目',
      actionTooltip: '浏览文件',
      title: '工作区文件',
      closeText: '关闭',
    );
    await expectSharedDialog(
      pageTooltip: '设置',
      actionTooltip: '创建命令请求',
      title: '创建命令请求',
      closeText: '取消',
    );
    await expectSharedDialog(
      pageTooltip: '设置',
      actionTooltip: '导入 / 导出配置',
      title: '导入 / 导出配置',
      closeText: '关闭',
    );
  });

  testWidgets('role dialog remains usable in a compact viewport',
      (tester) async {
    tester.view.physicalSize = const Size(720, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('角色'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('新增角色'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('config-dialog-body')), findsOneWidget);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('config-dialog-body')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(TextButton, '取消'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);
  });

  testWidgets('model dialog validation uses the shared error treatment',
      (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('模型'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑模型').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '温度 0-2'), 'abc');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('config-dialog-error')), findsOneWidget);
    expect(find.textContaining('温度和最大 Token 必须是数字'), findsOneWidget);
    expect(find.text('编辑模型配置'), findsOneWidget);
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
          detail:
              'conversation=conv-member-secretary model=model-main streaming=false',
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
            'requestUrl': 'https://api.example.test/v1/chat/completions',
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
    expect(
      find.text(
        'conversation=conv-member-secretary model=reasoning-model streaming=false',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('model-main'), findsNothing);
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
    expect(find.text('model: reasoning-model'), findsOneWidget);
    expect(
        find.text('requestUrl: https://api.example.test/v1/chat/completions'),
        findsOneWidget);
    expect(find.textContaining('model-main'), findsNothing);
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

    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
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
    await _pumpPopupMenuFrames(tester);
    await tester.tap(find.widgetWithText(MenuItemButton, '发送'));
    await _pumpPopupMenuFrames(tester);

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
    await _pumpPopupMenuFrames(tester);
    await tester.tap(find.widgetWithText(MenuItemButton, '停止生成'));
    await _pumpPopupMenuFrames(tester);

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

AppState _stateWithLongTeamAndSecretaryChats() {
  final seed = AppState.seed();
  final teamConversation = seed.conversations.firstWhere(
    (item) => item.id == 'conv-team-default',
  );
  final secretaryConversation = seed.conversations.firstWhere(
    (item) => item.id == 'conv-member-secretary',
  );
  return seed.copyWith(
    conversations: seed.conversations.map((conversation) {
      if (conversation.id == teamConversation.id) {
        return conversation.copyWith(
          messages: List.generate(
            45,
            (index) => ChatMessage(
              id: 'msg-team-history-$index',
              authorName: index.isEven ? '秘书' : '前端工程师',
              memberId: index.isEven ? 'member-secretary' : 'member-frontend',
              content: '群聊历史消息 $index\n${'团队填充内容 ' * 12}',
              createdAt: DateTime(2026, 6, 14, 8).add(
                Duration(minutes: index),
              ),
            ),
          ),
        );
      }
      if (conversation.id == secretaryConversation.id) {
        return conversation.copyWith(
          messages: List.generate(
            45,
            (index) => ChatMessage(
              id: 'msg-secretary-history-$index',
              authorName: '秘书',
              memberId: 'member-secretary',
              content: '秘书历史消息 $index\n${'私聊填充内容 ' * 12}',
              createdAt: DateTime(2026, 6, 14, 9).add(
                Duration(minutes: index),
              ),
            ),
          ),
        );
      }
      return conversation;
    }).toList(),
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

Future<void> _pumpPopupMenuFrames(WidgetTester tester) async {
  for (var index = 0; index < 10; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

int _conversationRowCount(WidgetTester tester) {
  return find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('conversation-row-');
      })
      .evaluate()
      .length;
}
