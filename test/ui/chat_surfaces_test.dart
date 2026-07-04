import 'app_widget_test_support.dart';
import 'package:ai_team/ui/management/chat_status_cards.dart';

void main() {
  testWidgets('desktop workspace separates chat and settings surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.text('群聊'), findsOneWidget);
    expect(find.text('私聊'), findsOneWidget);
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
    expect(find.byKey(const ValueKey('token-usage-meter')), findsOneWidget);
    expect(find.textContaining('members'), findsNothing);
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
    expect(find.text('持久化存储目录'), findsOneWidget);
    expect(find.text('审计'), findsNothing);
    expect(find.text('审计日志'), findsNothing);
    expect(find.text('补丁'), findsNothing);
    expect(find.text('模型配置'), findsNothing);
    expect(find.text('角色配置'), findsNothing);
    expect(find.text('团队成员'), findsNothing);
    expect(find.text('项目工作区'), findsNothing);
    expect(find.text('任务轮次'), findsNothing);
    expect(find.text('补丁确认'), findsNothing);
  });

  testWidgets('chat workspace shows pending patch confirmations', (
    tester,
  ) async {
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
      AiTeamApp(initialState: state, modelGateway: FakeModelGateway()),
    );

    expect(find.text('Diff review · 补丁确认'), findsOneWidget);
    expect(find.text('+1 -1'), findsOneWidget);
    expect(find.text('片段'), findsOneWidget);
    expect(find.text('hunks'), findsNothing);
    expect(find.text('确认应用'), findsOneWidget);
    expect(find.text('new docs'), findsOneWidget);

    final rejectButton = find.widgetWithText(OutlinedButton, '拒绝');
    await tester.ensureVisible(rejectButton);
    await tester.pumpAndSettle();
    await tester.tap(rejectButton);
    await tester.pumpAndSettle();

    expect(find.text('Diff review · 补丁确认'), findsNothing);
  });

  testWidgets('chat workspace shows scoped pending command requests', (
    tester,
  ) async {
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
      AiTeamApp(initialState: state, modelGateway: FakeModelGateway()),
    );

    expect(find.text('命令请求 · 待审批'), findsOneWidget);
    expect(find.text('待审批'), findsWidgets);
    expect(find.text('pending'), findsNothing);
    expect(find.textContaining('df -h /'), findsWidgets);
    expect(find.textContaining('/'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '允许'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '拒绝'), findsOneWidget);
  });

  testWidgets('chat header opens on-demand safety status drawer', (
    tester,
  ) async {
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
      patchProposals: const [
        PatchProposal(
          id: 'patch-chat',
          filePath: 'lib/ui/chat/chat_pane.dart',
          originalContent: 'old',
          proposedContent: 'new',
          memberName: '前端工程师',
          diff: '--- old\n+++ new\n@@\n-old\n+new\n',
        ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(initialState: state, modelGateway: FakeModelGateway()),
    );

    expect(find.text('会话安全状态'), findsNothing);

    await tester.tap(find.byTooltip('安全状态'));
    await tester.pumpAndSettle();

    expect(find.text('会话安全状态'), findsOneWidget);
    expect(find.text('成员状态'), findsOneWidget);
    expect(find.text('3 名'), findsWidgets);
    expect(find.text('命令审批'), findsOneWidget);
    expect(find.text('补丁确认'), findsWidgets);
    expect(find.text('审计摘要'), findsOneWidget);
    expect(find.text('最新'), findsOneWidget);
    expect(find.text('newest'), findsNothing);
    expect(find.textContaining('1 条等待确认'), findsOneWidget);
    expect(find.textContaining('1 个补丁等待确认'), findsOneWidget);
  });

  testWidgets(
    'chat workspace shows approved command requests without approval',
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
        AiTeamApp(initialState: state, modelGateway: FakeModelGateway()),
      );

      expect(find.text('命令请求 · 待审批'), findsNothing);
      expect(find.text('命令已允许'), findsOneWidget);
      expect(find.text('允许中'), findsWidgets);
      expect(find.textContaining('df -h /'), findsWidgets);
      expect(find.widgetWithText(FilledButton, '执行'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '允许'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '拒绝'), findsNothing);
    },
  );

  testWidgets('command state cards use workflow status labels', (tester) async {
    CommandRequest requestWithStatus(String id, CommandRequestStatus status) =>
        CommandRequest.pending(
          id: id,
          memberName: '秘书',
          command: 'pwd',
          workingDirectory: '/',
          decision: CommandDecision.allowed,
          conversationId: 'conv-member-secretary',
          memberId: 'member-secretary',
          toolCallId: 'call-$id',
        ).copyWith(
          status: status,
          output: status == CommandRequestStatus.failed ? '退出码 1' : null,
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                for (final status in [
                  CommandRequestStatus.pending,
                  CommandRequestStatus.executed,
                  CommandRequestStatus.denied,
                  CommandRequestStatus.failed,
                ])
                  ChatCommandRequestCard(
                    request: requestWithStatus(status.name, status),
                    onApproveExecute: () {},
                    onReject: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('待审批'), findsWidgets);
    expect(find.text('已执行'), findsWidgets);
    expect(find.text('已拒绝'), findsWidgets);
    expect(find.text('失败'), findsWidgets);
    expect(find.text('pending'), findsNothing);
    expect(find.text('exit 0'), findsNothing);
    expect(find.text('denied'), findsNothing);
    expect(find.text('failed'), findsNothing);
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
        status: CommandRequestStatus.executed,
        output: 'Filesystem 42Gi /',
      );
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
        AiTeamApp(initialState: state, modelGateway: FakeModelGateway()),
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
    },
  );

  testWidgets('legacy unscoped pending commands remain visible in project', (
    tester,
  ) async {
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
      AiTeamApp(initialState: state, modelGateway: FakeModelGateway()),
    );

    expect(find.text('待确认命令'), findsNothing);

    await tester.tap(find.byTooltip('项目'));
    await tester.pumpAndSettle();

    expect(find.text('命令审批'), findsOneWidget);
    expect(find.textContaining('df -h /'), findsOneWidget);
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
    },
  );

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
}
