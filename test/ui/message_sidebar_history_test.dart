import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/app.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/model_gateway.dart';
import 'package:ai_team/core/orchestrator.dart';

void main() {
  testWidgets(
    'message sidebar renders grouped chat sections with context menu',
    (tester) async {
      await tester.pumpWidget(
        AiTeamApp(
          initialState: AppState.seed(),
          modelGateway: _NoopModelGateway(),
        ),
      );

      expect(find.text('群聊'), findsOneWidget);
      expect(find.text('私聊'), findsOneWidget);
      expect(find.text('默认开发团队'), findsOneWidget);
      expect(find.text('3 名'), findsOneWidget);
      expect(find.text('BOT'), findsNothing);
      expect(find.text('秘书'), findsWidgets);
      expect(find.text('前端工程师'), findsWidgets);
      expect(find.byTooltip('关闭聊天'), findsNothing);

      expect(
        tester.getTopLeft(find.text('默认开发团队')).dy,
        lessThan(tester.getTopLeft(find.text('秘书').first).dy),
      );

      await tester.tap(find.text('默认开发团队'));
      await tester.pumpAndSettle();

      expect(find.textContaining('名成员'), findsWidgets);
      expect(find.textContaining('位成员'), findsNothing);

      final conversationList = tester.widget<ListView>(
        find.byKey(const ValueKey('conversation-list')),
      );
      expect(
        conversationList.padding,
        const EdgeInsets.symmetric(horizontal: 10),
      );
      final selectedRow = tester.widget<Material>(
        find.descendant(
          of: find.byKey(const ValueKey('conversation-row-conv-team-default')),
          matching: find.byType(Material),
        ),
      );
      expect(selectedRow.color, Colors.white);
      final selectedRowShape = selectedRow.shape! as RoundedRectangleBorder;
      expect(selectedRowShape.borderRadius, BorderRadius.circular(8));
      expect(selectedRowShape.side.color, const Color(0xFFD9DDE2));
      expect(selectedRowShape.side.width, 1);
      final selectedRowPadding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byKey(
                const ValueKey('conversation-row-conv-team-default'),
              ),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(selectedRowPadding.padding, const EdgeInsets.all(10));

      await tester.tap(
        find.byKey(const ValueKey('conversation-row-conv-team-default')),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('删除'), findsOneWidget);

      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('默认开发团队'), findsNothing);
    },
  );

  testWidgets('message sidebar plus starts group or private chats only', (
    tester,
  ) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: _NoopModelGateway(),
      ),
    );

    expect(find.byTooltip('新增成员'), findsNothing);
    expect(find.byTooltip('新增会话'), findsOneWidget);

    await tester.tap(find.byTooltip('新增会话'));
    await tester.pumpAndSettle();

    expect(find.text('新增团队成员'), findsNothing);
    expect(find.text('群聊'), findsWidgets);
    expect(find.text('私聊'), findsWidgets);
    expect(find.text('默认开发团队'), findsWidgets);
    expect(find.text('前端工程师'), findsWidgets);

    await tester.tap(find.text('前端工程师').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('私聊 · 前端工程师'), findsOneWidget);
  });

  testWidgets('starting a chat moves it to the top of the sidebar', (
    tester,
  ) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: _NoopModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('成员'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('member-row-member-frontend')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('打开私聊'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('前端工程师').first).dy,
      lessThan(tester.getTopLeft(find.text('秘书').first).dy),
    );
  });

  testWidgets('context menu pins and unpins chats', (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: _NoopModelGateway(),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-member-frontend')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('前端工程师').first).dy,
      lessThan(tester.getTopLeft(find.text('秘书').first).dy),
    );
    final pinnedRow = tester.widget<Material>(
      find.descendant(
        of: find.byKey(const ValueKey('conversation-row-conv-member-frontend')),
        matching: find.byType(Material),
      ),
    );
    expect(pinnedRow.color, const Color(0xFFE8EBF0));

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-member-frontend')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('取消置顶'), findsOneWidget);
    await tester.tap(find.text('取消置顶'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('秘书').first).dy,
      lessThan(tester.getTopLeft(find.text('前端工程师').first).dy),
    );
  });

  testWidgets('message sidebar lists every team chat', (tester) async {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(_NoopModelGateway()),
    );
    addTearDown(controller.dispose);
    controller.addTeam(
      name: '移动端小队',
      memberIds: const ['member-frontend', 'member-tester'],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: controller.state,
        modelGateway: _NoopModelGateway(),
      ),
    );

    expect(find.text('群聊'), findsOneWidget);
    expect(find.text('私聊'), findsOneWidget);
    expect(find.text('默认开发团队'), findsOneWidget);
    expect(find.text('移动端小队'), findsOneWidget);
  });

  testWidgets('message sidebar does not invent member chats after restart', (
    tester,
  ) async {
    final seed = AppState.seed();
    const persistedTeam = Team(
      id: 'team-aa',
      name: 'aa',
      memberIds: ['member-secretary', 'member-frontend', 'member-tester'],
      secretaryMemberId: 'member-secretary',
    );
    final persistedState = seed.copyWith(
      teams: [...seed.teams, persistedTeam],
      conversations: [
        ...seed.conversations,
        Conversation(
          id: 'conv-team-aa',
          title: '团队会话',
          teamId: persistedTeam.id,
          messages: [
            ChatMessage(
              id: 'msg-aa',
              authorName: '秘书',
              memberId: 'member-secretary',
              content: '请重新分工。',
              createdAt: DateTime(2026, 6, 15),
            ),
          ],
        ),
        for (final member in seed.members)
          Conversation(
            id: 'conv-team-aa-${member.id}',
            title: member.name,
            teamId: persistedTeam.id,
            memberId: member.id,
            messages: [
              ChatMessage(
                id: 'msg-welcome-team-aa-${member.id}',
                authorName: member.name,
                memberId: member.id,
                content: '这里是和${member.name}的独立会话。',
                createdAt: DateTime(2026, 6, 15),
              ),
            ],
          ),
      ],
    );

    await tester.pumpWidget(
      AiTeamApp(
        initialState: persistedState,
        modelGateway: _NoopModelGateway(),
      ),
    );

    expect(find.text('aa'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-row-conv-team-aa')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('conversation-row-conv-team-aa-member-secretary'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey('conversation-row-conv-team-aa-member-frontend'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('conversation-row-conv-team-aa-member-tester')),
      findsNothing,
    );
  });

  testWidgets('message sidebar can close a chat without deleting history', (
    tester,
  ) async {
    final seed = AppState.seed();
    final teamConversation = seed.conversations.firstWhere(
      (conversation) =>
          conversation.teamId == 'team-default' &&
          conversation.memberId == null,
    );

    await tester.pumpWidget(
      AiTeamApp(initialState: seed, modelGateway: _NoopModelGateway()),
    );

    expect(find.text('默认开发团队'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('conversation-row-conv-team-default')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('默认开发团队'), findsNothing);
    expect(find.text('秘书'), findsWidgets);

    await tester.tap(find.byTooltip('团队'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '发起聊天'));
    await tester.pumpAndSettle();

    expect(find.text('默认开发团队'), findsOneWidget);
    expect(
      find.textContaining(teamConversation.messages.last.content),
      findsWidgets,
    );
  });

  testWidgets('private chats remain listed after selecting another team chat', (
    tester,
  ) async {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(_NoopModelGateway()),
    );
    addTearDown(controller.dispose);
    final aaTeam = controller.addTeam(
      name: 'aa',
      memberIds: const ['member-secretary'],
    );
    controller.startTeamChat(aaTeam.id);
    controller.addMember(
      const TeamMember(
        id: 'member-aa-engineer',
        name: 'AA工程师',
        roleId: 'role-frontend',
        modelId: 'model-main',
      ),
    );
    controller.startMemberChat('member-aa-engineer');
    await controller.dispatch('和AA工程师同步');

    await tester.pumpWidget(
      AiTeamApp(
        initialState: controller.state,
        modelGateway: _NoopModelGateway(),
      ),
    );

    await tester.tap(find.text('aa'));
    await tester.pumpAndSettle();
    expect(find.text('AA工程师'), findsWidgets);

    await tester.tap(find.text('默认开发团队'));
    await tester.pumpAndSettle();

    expect(find.text('默认开发团队'), findsOneWidget);
    expect(find.text('AA工程师'), findsWidgets);
    expect(find.text('私聊'), findsOneWidget);
  });

  testWidgets(
    'message sidebar keeps all private chats after team chat starts',
    (tester) async {
      await tester.pumpWidget(
        AiTeamApp(
          initialState: AppState.seed(),
          modelGateway: _NoopModelGateway(),
        ),
      );

      expect(find.text('私聊'), findsOneWidget);
      expect(find.text('秘书'), findsWidgets);
      expect(find.text('前端工程师'), findsWidgets);
      expect(find.text('测试工程师'), findsWidgets);

      await tester.tap(find.byTooltip('团队'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '发起聊天'));
      await tester.pumpAndSettle();

      expect(find.text('群聊'), findsOneWidget);
      expect(find.text('私聊'), findsOneWidget);
      expect(find.text('秘书'), findsWidgets);
      expect(find.text('前端工程师'), findsWidgets);
      expect(find.text('测试工程师'), findsWidgets);
      expect(
        find.byKey(const ValueKey('conversation-row-conv-team-default')),
        findsOneWidget,
      );
    },
  );

  testWidgets('message sidebar keeps scroll after private and group switches', (
    tester,
  ) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: _stateWithLongConversationSidebar(),
        modelGateway: _NoopModelGateway(),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('conversation-list'));
    const targetGroupRow = ValueKey(
      'conversation-row-conv-team-sidebar-target',
    );
    const targetPrivateRow = ValueKey(
      'conversation-row-conv-team-sidebar-target-member-sidebar',
    );

    await tester.scrollUntilVisible(
      find.byKey(targetGroupRow),
      120,
      scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    await tester.pumpAndSettle();

    final listView = tester.widget<ListView>(list);
    expect(listView.controller, isNotNull);
    final scrollController = listView.controller!;
    final scrolledOffset = scrollController.offset;
    expect(scrolledOffset, greaterThan(0));

    await tester.tap(find.byKey(targetGroupRow));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(targetPrivateRow));
    await tester.pumpAndSettle();

    final restoredListView = tester.widget<ListView>(list);
    expect(restoredListView.controller!.offset, scrolledOffset);
  });
}

AppState _stateWithLongConversationSidebar() {
  final seed = AppState.seed();
  const targetMember = TeamMember(
    id: 'member-sidebar',
    name: '侧栏私聊成员',
    roleId: 'role-frontend',
    modelId: 'model-main',
  );
  final targetTeam = Team(
    id: 'team-sidebar-target',
    name: '侧栏定位团队',
    memberIds: ['member-secretary', targetMember.id],
    secretaryMemberId: 'member-secretary',
  );
  final fillerTeams = List.generate(
    18,
    (index) => Team(
      id: 'team-sidebar-filler-$index',
      name: '侧栏填充团队 $index',
      memberIds: const ['member-secretary'],
      secretaryMemberId: 'member-secretary',
    ),
  );
  final fillerConversations = [
    for (final team in fillerTeams)
      Conversation(
        id: 'conv-${team.id}',
        title: '团队会话',
        teamId: team.id,
        messages: [
          ChatMessage(
            id: 'msg-${team.id}',
            authorName: '秘书',
            memberId: 'member-secretary',
            content: '侧栏填充消息',
            createdAt: DateTime(2026, 6, 20),
          ),
        ],
      ),
  ];
  return seed.copyWith(
    members: [...seed.members, targetMember],
    teams: [...fillerTeams, targetTeam, ...seed.teams],
    conversations: [
      ...fillerConversations,
      Conversation(
        id: 'conv-team-sidebar-target',
        title: '团队会话',
        teamId: targetTeam.id,
        messages: [
          ChatMessage(
            id: 'msg-team-sidebar-target',
            authorName: '秘书',
            memberId: 'member-secretary',
            content: '目标群聊消息',
            createdAt: DateTime(2026, 6, 20, 9),
          ),
        ],
      ),
      Conversation(
        id: 'conv-team-sidebar-target-member-sidebar',
        title: targetMember.name,
        teamId: targetTeam.id,
        memberId: targetMember.id,
        messages: [
          ChatMessage(
            id: 'msg-team-sidebar-target-member-sidebar',
            authorName: targetMember.name,
            memberId: targetMember.id,
            content: '目标私聊消息',
            createdAt: DateTime(2026, 6, 20, 9, 1),
          ),
        ],
      ),
      ...seed.conversations,
    ],
  );
}

class _NoopModelGateway implements ModelGateway {
  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    return '';
  }
}
