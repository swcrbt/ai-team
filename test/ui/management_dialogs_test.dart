import 'package:ai_team/ui/sidebar.dart';

import 'app_widget_test_support.dart';

void main() {
  testWidgets('left sidebar uses a deep black background', (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    final sidebarBackground = tester.widget<ColoredBox>(
      find
          .ancestor(of: find.byTooltip('消息'), matching: find.byType(ColoredBox))
          .first,
    );

    expect(sidebarBackground.color, const Color(0xFF050505));
  });

  testWidgets('left sidebar keeps all primary entries in design order', (
    tester,
  ) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    final labels = ['消息', '团队', '模型', '角色', '成员', '项目', '审计', '设置'];
    for (var index = 0; index < labels.length - 1; index++) {
      expect(
        tester.getTopLeft(find.byTooltip(labels[index])).dy,
        lessThan(tester.getTopLeft(find.byTooltip(labels[index + 1])).dy),
      );
    }
  });

  testWidgets('left sidebar renders custom semantic icons and states', (
    tester,
  ) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    final icons = tester
        .widgetList<SidebarLinearIcon>(find.byType(SidebarLinearIcon))
        .toList();
    expect(
      icons.map((icon) => icon.kind),
      orderedEquals(SidebarIconKind.values),
    );
    expect(icons.map((icon) => icon.size), everyElement(20));
    expect(icons.first.state, SidebarIconVisualState.active);
    expect(
      icons.skip(1).map((icon) => icon.state),
      everyElement(SidebarIconVisualState.normal),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.byTooltip('团队')));
    await tester.pump();

    final hoveredIcons = tester
        .widgetList<SidebarLinearIcon>(find.byType(SidebarLinearIcon))
        .toList();
    final teamIcon = hoveredIcons.singleWhere(
      (icon) => icon.kind == SidebarIconKind.teams,
    );
    expect(teamIcon.state, SidebarIconVisualState.hover);

    await gesture.removePointer();
  });

  testWidgets('sidebar icon component covers eight semantics and four states', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Wrap(
          children: [
            for (final kind in SidebarIconKind.values)
              for (final state in SidebarIconVisualState.values)
                SidebarLinearIcon(kind, state: state),
          ],
        ),
      ),
    );

    final icons = tester
        .widgetList<SidebarLinearIcon>(find.byType(SidebarLinearIcon))
        .toList();
    expect(icons.length, SidebarIconKind.values.length * 4);
    for (final kind in SidebarIconKind.values) {
      for (final state in SidebarIconVisualState.values) {
        expect(
          icons.where((icon) => icon.kind == kind && icon.state == state),
          hasLength(1),
        );
      }
    }
    expect(icons.map((icon) => icon.size), everyElement(20));
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
    expect(find.text('对象：开发团队'), findsOneWidget);
    expect(find.text('负责方案拆解、代码修改、补丁提交。'), findsWidgets);
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
      expect(find.textContaining('群聊 · 默认开发团队'), findsOneWidget);

      await tester.tap(find.byTooltip('成员'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('打开私聊').at(1));
      await tester.pumpAndSettle();

      expect(find.text('私聊'), findsOneWidget);
      expect(find.text('秘书'), findsWidgets);
      expect(find.text('前端工程师'), findsWidgets);
      expect(find.text('测试工程师'), findsWidgets);
      expect(find.textContaining('私聊 · 前端工程师'), findsOneWidget);
    },
  );

  testWidgets('chat header action menu starts a new scoped session', (
    tester,
  ) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.byTooltip('会话操作'), findsOneWidget);
    final initialRows = conversationRowCount(tester);

    await tester.tap(find.byTooltip('会话操作'));
    await tester.pumpAndSettle();
    expect(find.text('新增会话'), findsOneWidget);
    expect(find.text('历史会话'), findsOneWidget);

    await tester.tap(find.text('新增会话'));
    await tester.pumpAndSettle();

    expect(find.textContaining('私聊 · 新会话'), findsOneWidget);
    expect(conversationRowCount(tester), initialRows);
  });

  testWidgets('chat header history menu switches current object sessions', (
    tester,
  ) async {
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

  testWidgets('chat history menu deletes a session after confirmation', (
    tester,
  ) async {
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

  testWidgets('chat header action menu reuses one empty history session', (
    tester,
  ) async {
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

  testWidgets(
    'team chat appears only after starting chat from team management',
    (tester) async {
      await tester.pumpWidget(
        AiTeamApp(
          initialState: AppState.seed(),
          modelGateway: FakeModelGateway(),
        ),
      );

      expect(find.text('群聊'), findsOneWidget);

      await tester.tap(find.byTooltip('团队'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '发起聊天'));
      await tester.pumpAndSettle();

      expect(find.text('群聊'), findsOneWidget);
      expect(find.textContaining('群聊 · 默认开发团队'), findsOneWidget);
    },
  );

  testWidgets('team management creates a named team with selected members', (
    tester,
  ) async {
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

  testWidgets('team dialog defaults to serial mode and can select parallel', (
    tester,
  ) async {
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
      find.widgetWithText(SegmentedButton<TeamCollaborationMode>, '串行'),
      findsOneWidget,
    );

    await tester.enterText(find.widgetWithText(TextField, '团队名称'), '并行小队');
    await tester.tap(find.text('并行'));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('模式 并行协作'), findsWidgets);
  });

  testWidgets('team management edits a team', (tester) async {
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

    final editTeamButton = find.byTooltip('编辑团队').last;
    await tester.ensureVisible(editTeamButton);
    await tester.pumpAndSettle();
    await tester.tap(editTeamButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '团队名称'), '移动端交付组');
    await tester.tap(find.text('并行'));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('移动端交付组'), findsWidgets);
    expect(find.text('并行'), findsWidgets);
  });

  testWidgets('configuration dialogs use the clean shared dialog frame', (
    tester,
  ) async {
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
        find.byKey(const ValueKey('config-dialog-header')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('config-dialog-body')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('config-dialog-actions')),
        findsOneWidget,
      );
      expect(find.text(title), findsWidgets);

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

    await expectSharedDialog(
      pageTooltip: '设置',
      actionTooltip: '导入 / 导出配置',
      title: '导入 / 导出配置',
      closeText: '关闭',
    );
  });

  testWidgets('role dialog remains usable in a compact viewport', (
    tester,
  ) async {
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

  testWidgets('model dialog validation uses the shared error treatment', (
    tester,
  ) async {
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
    expect(find.textContaining('温度和 Token 必须是数字'), findsOneWidget);
    expect(find.text('编辑模型配置'), findsOneWidget);
  });

  testWidgets('member dialog edits role and model binding', (tester) async {
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

    expect(find.text('角色'), findsOneWidget);
    expect(find.text('模型'), findsOneWidget);
    expect(find.text('执行优先级'), findsNothing);
  });

  testWidgets('chat does not show task queue bar', (tester) async {
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
      AiTeamApp(initialState: state, modelGateway: FakeModelGateway()),
    );

    expect(find.textContaining('队列 2'), findsNothing);
    expect(find.textContaining('登录任务'), findsNothing);
    expect(find.textContaining('优先级'), findsNothing);
    expect(find.byTooltip('删除历史任务'), findsNothing);
  });

  testWidgets('main sidebar no longer exposes task history', (tester) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    expect(find.byTooltip('历史'), findsNothing);
  });

  testWidgets('sidebar audit button opens an independent audit page', (
    tester,
  ) async {
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
      AiTeamApp(initialState: state, modelGateway: FakeModelGateway()),
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

    await tester.tap(find.widgetWithText(ChoiceChip, '模型'));
    await tester.pumpAndSettle();

    expect(find.text('new_action'), findsOneWidget);
    expect(find.text('old_action'), findsNothing);
    expect(find.text('1 条'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
    await tester.pumpAndSettle();

    expect(find.text('old_action'), findsOneWidget);
    await tester.tap(find.byTooltip('查看详情'));
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
      findsOneWidget,
    );
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

    expect(find.text('深度思考'), findsWidgets);

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
    expect(find.textContaining('深度思考'), findsWidgets);
  });

  testWidgets('sidebar model button opens an independent model page', (
    tester,
  ) async {
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
    expect(find.text('模型列表'), findsOneWidget);
    expect(find.byTooltip('新增模型'), findsOneWidget);
    expect(find.text('上下文 32k'), findsWidgets);
    expect(find.text('流式 开启'), findsWidgets);
    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('返回思考区'), findsOneWidget);
    expect(find.text('仅真实字段'), findsOneWidget);
  });

  testWidgets('sidebar role button opens an independent role page', (
    tester,
  ) async {
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
    expect(find.text('角色列表'), findsOneWidget);
    expect(find.byTooltip('新增角色'), findsOneWidget);
    expect(find.text('读项目 允许'), findsWidgets);
    expect(find.text('补丁 允许'), findsWidgets);
    expect(find.text('命令 需确认'), findsWidgets);
    expect(find.text('输出格式'), findsOneWidget);
    expect(find.text('应用补丁'), findsOneWidget);
    expect(find.text('生成后确认'), findsOneWidget);
  });

  testWidgets('sidebar member button opens an independent member page', (
    tester,
  ) async {
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
    expect(find.text('成员列表'), findsOneWidget);
    expect(find.byTooltip('新增成员'), findsOneWidget);
    expect(find.byTooltip('打开私聊'), findsWidgets);
    expect(find.text('秘书成员'), findsOneWidget);
    expect(find.text('私聊已启用'), findsNothing);
    expect(find.text('私聊入口'), findsWidgets);
    expect(find.textContaining('优先级'), findsNothing);
    expect(find.text('角色 秘书'), findsOneWidget);
    expect(find.text('模型 OpenAI Compatible'), findsWidgets);
    expect(find.text('所属团队'), findsOneWidget);
    expect(find.text('开发团队'), findsOneWidget);
    expect(find.text('成员页 / 会话栏'), findsOneWidget);
    expect(find.text('代表用户发送'), findsOneWidget);
    expect(find.text('参与群聊'), findsOneWidget);
  });

  testWidgets('settings storage panel exposes directory actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      AiTeamApp(
        initialState: AppState.seed(),
        modelGateway: FakeModelGateway(),
      ),
    );

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.text('持久化存储、导入导出和应用级配置'), findsOneWidget);
    expect(find.text('本机配置、持久化目录和导入导出'), findsNothing);
    expect(find.text('持久化存储目录'), findsOneWidget);
    expect(find.text('用于 state、审计、会话与缓存；保存前会确认迁移。'), findsOneWidget);
    expect(find.byTooltip('选择目录'), findsNWidgets(4));
    expect(find.byTooltip('打开目录'), findsNWidgets(4));
    expect(find.byTooltip('清空目录'), findsNWidgets(4));
    expect(find.widgetWithText(OutlinedButton, '恢复默认'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存目录'), findsOneWidget);
    expect(find.text('导入导出'), findsOneWidget);
    expect(find.text('导入配置'), findsOneWidget);
    expect(find.text('脱敏导出'), findsOneWidget);
    expect(find.text('密钥导出'), findsOneWidget);
    expect(find.text('包含密钥时必须在弹窗中显式确认。'), findsOneWidget);
  });

  testWidgets('management object lists drive the selected detail panel', (
    tester,
  ) async {
    final seed = AppState.seed();
    final state = seed.copyWith(
      teams: [
        ...seed.teams,
        const Team(
          id: 'team-test',
          name: '测试团队',
          memberIds: ['member-secretary', 'member-tester'],
          secretaryMemberId: 'member-secretary',
          maxRounds: 7,
        ),
      ],
    );
    await tester.pumpWidget(
      AiTeamApp(initialState: state, modelGateway: FakeModelGateway()),
    );

    await tester.tap(find.byTooltip('团队'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('team-detail-team-default')),
      findsOneWidget,
    );
    await tester.tap(find.text('测试团队'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('team-detail-team-test')), findsOneWidget);

    await tester.tap(find.byTooltip('模型'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('model-detail-model-main')),
      findsOneWidget,
    );
    await tester.tap(find.text('Local Compatible'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('model-detail-model-local')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('角色'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('role-detail-role-secretary')),
      findsOneWidget,
    );
    await tester.tap(find.text('测试工程师').first);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('role-detail-role-tester')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('成员'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('member-detail-member-secretary')),
      findsOneWidget,
    );
    await tester.tap(find.text('测试工程师').first);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('member-detail-member-tester')),
      findsOneWidget,
    );
  });

  testWidgets('sidebar project button opens an independent project page', (
    tester,
  ) async {
    final state = AppState.seed().copyWith(
      commandRequests: [
        CommandRequest.pending(
          id: 'command-project-test',
          memberName: '秘书',
          command: 'flutter test test/app_widget_test.dart',
          workingDirectory: '/repo/ai-team',
          decision: CommandDecision.requiresConfirmation,
          conversationId: 'conv-member-secretary',
          memberId: 'member-secretary',
        ),
        CommandRequest.pending(
          id: 'command-project-diff',
          memberName: '前端工程师',
          command: 'git diff -- lib/ui/chat_view.dart',
          workingDirectory: '/repo/ai-team',
          decision: CommandDecision.allowed,
          conversationId: 'conv-member-frontend',
          memberId: 'member-frontend',
        ),
      ],
      patchProposals: const [
        PatchProposal(
          id: 'patch-project',
          filePath: 'lib/ui/chat_view.dart',
          originalContent: 'old',
          proposedContent: 'new',
          memberName: '前端工程师',
          diff: '--- lib/ui/chat_view.dart\n'
              '+++ lib/ui/chat_view.dart\n'
              '@@\n'
              '-old composer\n'
              '+fixed composer\n'
              '+token meter\n',
        ),
      ],
    );
    await tester.pumpWidget(
      AiTeamApp(initialState: state, modelGateway: FakeModelGateway()),
    );

    await tester.tap(find.byTooltip('项目'));
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsNothing);
    expect(find.byTooltip('返回聊天'), findsNothing);
    expect(find.text('项目管理'), findsOneWidget);
    expect(find.text('项目管理列表'), findsOneWidget);
    expect(find.byTooltip('添加项目'), findsOneWidget);
    expect(find.text('命令审批'), findsOneWidget);
    expect(find.text('补丁确认'), findsOneWidget);
    expect(find.text('项目边界'), findsOneWidget);
    expect(find.text('审计摘要'), findsOneWidget);
    expect(find.text('最新优先'), findsOneWidget);
    expect(find.text('事件'), findsOneWidget);
    expect(find.text('模型调用'), findsOneWidget);
    expect(find.text('阻断'), findsWidgets);
    expect(find.text('newest first'), findsNothing);
    expect(find.text('model calls'), findsNothing);
    expect(find.text('等待确认'), findsWidgets);
    expect(find.widgetWithText(FilledButton, '允许'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '阻断'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '查看'), findsOneWidget);
    expect(find.text('变更量'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('片段'), findsOneWidget);
    expect(find.text('hunks'), findsNothing);
    expect(find.text('lib/ui/chat_view.dart'), findsWidgets);
    expect(find.widgetWithText(OutlinedButton, '展开文件'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '拒绝'), findsOneWidget);

    final expandFiles = find.widgetWithText(OutlinedButton, '展开文件');
    await tester.ensureVisible(expandFiles);
    await tester.pumpAndSettle();
    await tester.tap(expandFiles);
    await tester.pumpAndSettle();
    expect(find.text('补丁文件'), findsOneWidget);
    expect(find.textContaining('fixed composer'), findsWidgets);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });
}
