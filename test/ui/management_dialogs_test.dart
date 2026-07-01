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
}
