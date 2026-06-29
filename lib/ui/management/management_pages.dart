part of '../../app.dart';

class _ManagementPage extends StatelessWidget {
  const _ManagementPage({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(subtitle),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _TeamManagementPage extends StatelessWidget {
  const _TeamManagementPage({
    required this.controller,
    required this.onStartChat,
  });

  final AppController controller;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    return _ManagementPage(
      title: '团队管理',
      subtitle: '创建团队、配置成员，并从团队发起群聊',
      child: _Panel(
        title: '团队列表',
        icon: Icons.groups_rounded,
        action: IconButton(
          tooltip: '新增团队',
          onPressed: () => _showTeamDialog(context, controller),
          icon: const Icon(Icons.add_rounded),
        ),
        child: Column(
          children: controller.state.teams
              .map(
                (team) => _TeamCard(
                  controller: controller,
                  team: team,
                  onStartChat: () {
                    controller.startTeamChat(team.id);
                    onStartChat();
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.controller,
    required this.team,
    required this.onStartChat,
  });

  final AppController controller;
  final Team team;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    final members = controller.state.members
        .where((member) => team.memberIds.contains(member.id))
        .toList();
    return _KeyValueRow(
      label: team.name,
      value:
          '${_collaborationModeLabel(team.collaborationMode)}协同 · ${members.map((member) => member.name).join('、')}',
      actions: [
        FilledButton(
          onPressed: onStartChat,
          child: const Text('发起聊天'),
        ),
        IconButton(
          tooltip: '编辑团队',
          onPressed: () => _showTeamDialog(
            context,
            controller,
            team: team,
          ),
          icon: const Icon(Icons.edit_rounded),
        ),
        IconButton(
          tooltip: '删除团队',
          onPressed: controller.state.teams.length <= 1
              ? null
              : () => _runConfigAction(
                    context,
                    () => controller.deleteTeam(team.id),
                  ),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

class _ModelManagementPage extends StatelessWidget {
  const _ModelManagementPage({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _ManagementPage(
      title: '模型管理',
      subtitle: 'OpenAI 兼容模型、请求参数和密钥引用在这里维护',
      child: _ModelConfigPanel(controller: controller),
    );
  }
}

class _RoleManagementPage extends StatelessWidget {
  const _RoleManagementPage({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _ManagementPage(
      title: '角色管理',
      subtitle: '角色提示词、命令策略和项目读取权限在这里维护',
      child: _RoleConfigPanel(controller: controller),
    );
  }
}

class _MemberManagementPage extends StatelessWidget {
  const _MemberManagementPage({
    required this.controller,
    required this.onStartChat,
  });

  final AppController controller;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    return _ManagementPage(
      title: '成员管理',
      subtitle: '团队成员、角色绑定和模型绑定在这里维护',
      child: _MemberConfigPanel(
        controller: controller,
        onStartChat: onStartChat,
      ),
    );
  }
}

class _ProjectPage extends StatelessWidget {
  const _ProjectPage({
    required this.controller,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '项目管理',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('本地工作区、文件浏览和补丁预览集中在这里管理'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _WorkspacePanel(controller: controller),
          ),
        ),
      ],
    );
  }
}

class _HistoryPage extends StatefulWidget {
  const _HistoryPage({required this.controller});

  final AppController controller;

  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage> {
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim();
    final tasks = widget.controller.state.queuedTasks
        .where(
          (task) => query.isEmpty || task.title.contains(query),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(
      children: [
        Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '历史',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('跨会话查看任务历史和关联信息'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              labelText: '搜索标题',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                child: ExpansionTile(
                  title: Text(task.title),
                  subtitle: Text(
                    '${_queuedTaskStatusText(task.status)} · 优先级 ${task.priority}',
                  ),
                  trailing: IconButton(
                    tooltip: '删除历史任务',
                    onPressed: () {
                      widget.controller.deleteTask(task.id);
                      setState(() {});
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(task.originalText),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AuditLogPage extends StatelessWidget {
  const _AuditLogPage({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.state.auditLog.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _ManagementPage(
      title: '审计日志',
      subtitle: '查看本机操作记录和命令执行审计',
      child: _Panel(
        title: '操作记录',
        icon: Icons.receipt_long_rounded,
        child: Column(
          children: entries.isEmpty
              ? [const Text('暂无操作记录')]
              : entries
                  .map(
                    (entry) => _AuditLogRow(entry: entry),
                  )
                  .toList(),
        ),
      ),
    );
  }
}

class _AuditLogRow extends StatelessWidget {
  const _AuditLogRow({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.action,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: entry.metadata == null ? '无详情' : '查看详情',
                onPressed: entry.metadata == null
                    ? null
                    : () => _showAuditLogDetails(context, entry),
                icon: const Icon(Icons.info_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _auditDisplayDetail(entry),
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          Text(
            '创建时间：${_auditLogTimeText(entry.createdAt)}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

void _showAuditLogDetails(BuildContext context, AuditEntry entry) {
  final metadata = entry.metadata ?? const <String, Object?>{};
  final rawResponse = metadata['rawResponse'] as String?;
  final requestBody = metadata['requestBody'];
  final requestModel = _auditRequestModel(requestBody);
  final structuredEntries = _auditStructuredEntries(metadata, requestModel);
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('审计详情'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AuditDetailSection(
                title: '基础信息',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText('action: ${entry.action}'),
                    SelectableText(
                      'createdAt: ${_auditLogTimeText(entry.createdAt)}',
                    ),
                  ],
                ),
              ),
              _AuditDetailSection(
                title: '摘要',
                child: SelectableText(_auditDisplayDetail(entry)),
              ),
              if (structuredEntries.isNotEmpty)
                _AuditDetailSection(
                  title: '结构化字段',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: structuredEntries
                        .map(
                          (item) => SelectableText(
                            '${item.key}: ${_auditMetadataValueText(item.value)}',
                          ),
                        )
                        .toList(),
                  ),
                ),
              if (requestBody != null)
                _AuditDetailSection(
                  title: '请求参数',
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(requestBody),
                    ),
                  ),
                ),
              if (rawResponse != null)
                _AuditDetailSection(
                  title: '原始返回内容',
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(rawResponse),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

String _auditDisplayDetail(AuditEntry entry) {
  final requestModel = _auditRequestModel(entry.metadata?['requestBody']);
  final tokens = entry.detail.split(' ');
  final sanitizedTokens = <String>[];
  for (final token in tokens) {
    if (token.startsWith('model=') || token.startsWith('targetModel=')) {
      final separator = token.indexOf('=');
      final key = token.substring(0, separator);
      final value = token.substring(separator + 1);
      if (_isInternalModelProfileId(value)) {
        if (key == 'model' && requestModel != null) {
          sanitizedTokens.add('$key=$requestModel');
        }
        continue;
      }
    }
    sanitizedTokens.add(token);
  }
  return sanitizedTokens.join(' ');
}

List<MapEntry<String, Object?>> _auditStructuredEntries(
  Map<String, Object?> metadata,
  String? requestModel,
) {
  final entries = <MapEntry<String, Object?>>[];
  var addedRequestModel = false;
  for (final item in metadata.entries) {
    if (item.key == 'rawResponse' || item.key == 'requestBody') {
      continue;
    }
    if (item.key == 'model') {
      if (requestModel != null) {
        entries.add(MapEntry(item.key, requestModel));
        addedRequestModel = true;
      } else if (!_isInternalModelProfileId(item.value)) {
        entries.add(item);
      }
      continue;
    }
    if (item.key == 'modelName') {
      entries.add(MapEntry('modelProfileName', item.value));
      continue;
    }
    if (item.key.toLowerCase().contains('model') &&
        _isInternalModelProfileId(item.value)) {
      continue;
    }
    entries.add(item);
  }
  if (!addedRequestModel &&
      requestModel != null &&
      !metadata.containsKey('model')) {
    entries.add(MapEntry('model', requestModel));
  }
  return entries;
}

String? _auditRequestModel(Object? requestBody) {
  if (requestBody is Map) {
    final model = requestBody['model'];
    if (model is String && model.trim().isNotEmpty) {
      return model;
    }
  }
  return null;
}

bool _isInternalModelProfileId(Object? value) {
  if (value is! String) {
    return false;
  }
  return value == 'model-main' ||
      value == 'model-local' ||
      RegExp(r'^model-\d{10,}$').hasMatch(value);
}

class _AuditDetailSection extends StatelessWidget {
  const _AuditDetailSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

String _auditMetadataValueText(Object? value) {
  if (value is Iterable) {
    return value.join(',');
  }
  return value.toString();
}

String _reasoningEffortLabel(String? value) {
  if (value == null || value.trim().isEmpty) {
    return _reasoningEffortLabels[_reasoningEffortOffValue]!;
  }
  return _reasoningEffortLabels[value] ?? value;
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.controller,
  });

  final AppController controller;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  final scrollController = ScrollController();
  final sectionKeys = {
    '命令请求': GlobalKey(),
    '导入导出': GlobalKey(),
  };

  AppController get controller => widget.controller;

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  void scrollToSection(String title) {
    final context = sectionKeys[title]?.currentContext;
    if (context == null) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '设置',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('命令和导入导出配置保存在本机'),
                  ],
                ),
              ),
            ],
          ),
        ),
        _SettingsCategoryBar(onSelect: scrollToSection),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _Panel(
                  key: sectionKeys['导入导出'],
                  title: '导入导出',
                  icon: Icons.ios_share_rounded,
                  action: IconButton(
                    tooltip: '导入 / 导出配置',
                    onPressed: () => _showExportDialog(context, controller),
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                  child: const Text('配置文件和密钥导出选项集中在这里管理。'),
                ),
                _Panel(
                  title: '任务轮次',
                  icon: Icons.account_tree_rounded,
                  child: Column(
                    children: controller.currentTaskAssignments.isEmpty
                        ? [
                            _KeyValueRow(
                              label: '当前轮次',
                              value:
                                  '第 ${controller.currentConversation.currentRound} 轮',
                            ),
                            const Text('暂无成员任务'),
                          ]
                        : controller.currentTaskAssignments
                            .map(
                              (assignment) =>
                                  _TaskAssignmentCard(assignment: assignment),
                            )
                            .toList(),
                  ),
                ),
                _Panel(
                  key: sectionKeys['命令请求'],
                  title: '命令请求',
                  icon: Icons.terminal_rounded,
                  action: IconButton(
                    tooltip: '创建命令请求',
                    onPressed: () => _showCommandDialog(context, controller),
                    icon: const Icon(Icons.add_rounded),
                  ),
                  child: Column(
                    children: controller.state.commandRequests.isEmpty
                        ? [const Text('暂无命令请求')]
                        : controller.state.commandRequests
                            .map(
                              (request) => _CommandRequestCard(
                                request: request,
                                onApprove: () =>
                                    controller.updateCommandRequestStatus(
                                  request.id,
                                  CommandRequestStatus.approved,
                                ),
                                onDeny: () =>
                                    controller.updateCommandRequestStatus(
                                  request.id,
                                  CommandRequestStatus.denied,
                                ),
                                onExecute: () =>
                                    controller.executeCommandRequest(
                                  request.id,
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsCategoryBar extends StatelessWidget {
  const _SettingsCategoryBar({required this.onSelect});

  final ValueChanged<String> onSelect;

  static const items = [
    (Icons.terminal_rounded, '命令', '命令请求'),
    (Icons.ios_share_rounded, '导入导出', '导入导出'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFB),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final item in items)
            ActionChip(
              onPressed: () => onSelect(item.$3),
              avatar: Icon(item.$1, size: 16),
              label: Text(item.$2),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModelConfigPanel extends StatelessWidget {
  const _ModelConfigPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '模型配置',
      icon: Icons.memory_rounded,
      action: IconButton(
        tooltip: '新增模型',
        onPressed: () => _showModelDialog(context, controller),
        icon: const Icon(Icons.add_rounded),
      ),
      child: Column(
        children: controller.state.models
            .map(
              (model) => _KeyValueRow(
                label: model.name,
                value:
                    '${model.modelName}\n${model.baseUrl}\n流式: ${model.streaming ? '开' : '关'} · 温度: ${model.temperature} · 最大 Token: ${model.maxTokens} · 深度思考: ${_reasoningEffortLabel(model.reasoningEffort)}',
                actions: [
                  IconButton(
                    tooltip: '编辑模型',
                    onPressed: () =>
                        _showModelDialog(context, controller, model: model),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton(
                    tooltip: '删除模型',
                    onPressed: () => _runConfigAction(
                      context,
                      () => controller.deleteModel(model.id),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _RoleConfigPanel extends StatelessWidget {
  const _RoleConfigPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '角色配置',
      icon: Icons.badge_rounded,
      action: IconButton(
        tooltip: '新增角色',
        onPressed: () => _showRoleDialog(context, controller),
        icon: const Icon(Icons.add_rounded),
      ),
      child: Column(
        children: controller.state.roles
            .map(
              (role) => _KeyValueRow(
                label: role.name,
                value:
                    '${role.description}\n命令: ${role.commandPolicy.allowedCommands.join(', ')}',
                actions: [
                  IconButton(
                    tooltip: '编辑角色',
                    onPressed: () =>
                        _showRoleDialog(context, controller, role: role),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton(
                    tooltip: '删除角色',
                    onPressed: () => _runConfigAction(
                      context,
                      () => controller.deleteRole(role.id),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MemberConfigPanel extends StatelessWidget {
  const _MemberConfigPanel({
    required this.controller,
    required this.onStartChat,
  });

  final AppController controller;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '团队成员',
      icon: Icons.groups_rounded,
      action: IconButton(
        tooltip: '新增成员',
        onPressed: () => _showMemberDialog(context, controller),
        icon: const Icon(Icons.add_rounded),
      ),
      child: Column(
        children: controller.currentMembers
            .map(
              (member) => _KeyValueRow(
                label: member.name,
                value:
                    '${_roleName(controller.state, member.roleId)} · ${_modelName(controller.state, member.modelId)} · 优先级 ${member.executionPriority}',
                actions: [
                  FilledButton(
                    onPressed: () {
                      controller.startMemberChat(member.id);
                      onStartChat();
                    },
                    child: const Text('发起聊天'),
                  ),
                  IconButton(
                    tooltip: '编辑成员',
                    onPressed: () => _showMemberDialog(
                      context,
                      controller,
                      member: member,
                    ),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton(
                    tooltip: '删除成员',
                    onPressed: member.isSecretary
                        ? null
                        : () => _runConfigAction(
                              context,
                              () => controller.deleteMember(member.id),
                            ),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _WorkspacePanel extends StatelessWidget {
  const _WorkspacePanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '项目工作区',
      icon: Icons.folder_open_rounded,
      action: Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: '创建补丁',
            onPressed: controller.state.workspaces.isEmpty
                ? null
                : () => _showWorkspacePatchDialog(context, controller),
            icon: const Icon(Icons.difference_rounded),
          ),
          IconButton(
            tooltip: '浏览文件',
            onPressed: controller.state.workspaces.isEmpty
                ? null
                : () => _showWorkspaceFilesDialog(context, controller),
            icon: const Icon(Icons.list_alt_rounded),
          ),
          IconButton(
            tooltip: '添加工作区',
            onPressed: controller.pickAndAddWorkspace,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      child: Column(
        children: controller.state.workspaces.isEmpty
            ? [const Text('还没有选择本地项目目录')]
            : controller.state.workspaces
                .map(
                  (workspace) => _KeyValueRow(
                    label: workspace.name,
                    value: workspace.path,
                  ),
                )
                .toList(),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.action,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (action != null)
            Align(
              alignment: Alignment.centerRight,
              child: action!,
            ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
    this.actions = const [],
  });

  final String label;
  final String value;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (actions.isNotEmpty)
                Wrap(
                  spacing: 2,
                  children: actions,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}

class _TaskAssignmentCard extends StatelessWidget {
  const _TaskAssignmentCard({required this.assignment});

  final TaskAssignment assignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '第 ${assignment.round} 轮 · ${assignment.memberName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _taskStatusText(assignment.status),
                style: TextStyle(
                  color: _taskStatusColor(assignment.status),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            assignment.roleName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          Text(
            assignment.instruction,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (assignment.summary != null) ...[
            const SizedBox(height: 4),
            Text(
              assignment.summary!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskQueueBar extends StatelessWidget {
  const _TaskQueueBar({
    required this.controller,
    required this.conversationId,
  });

  final AppController controller;
  final String conversationId;

  @override
  Widget build(BuildContext context) {
    final tasks = controller.tasksForConversation(conversationId);
    if (tasks.isEmpty) {
      return const SizedBox.shrink();
    }
    final running = _firstTaskWithStatus(tasks, QueuedTaskStatus.running);
    final title = running == null
        ? '队列 ${tasks.length}'
        : '队列 ${tasks.length} · ${running.title}';
    return Material(
      color: const Color(0xFFF8FAFC),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 24),
        initiallyExpanded: false,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Column(
              children: tasks
                  .map(
                    (task) => _TaskQueueTile(
                      controller: controller,
                      task: task,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskQueueTile extends StatefulWidget {
  const _TaskQueueTile({
    required this.controller,
    required this.task,
  });

  final AppController controller;
  final QueuedTask task;

  @override
  State<_TaskQueueTile> createState() => _TaskQueueTileState();
}

class _TaskQueueTileState extends State<_TaskQueueTile> {
  final noteController = TextEditingController();
  late final priorityController = TextEditingController(
    text: widget.task.priority.toString(),
  );

  @override
  void dispose() {
    noteController.dispose();
    priorityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: ExpansionTile(
        title: Text(task.title),
        subtitle: Text(
          '${_queuedTaskStatusText(task.status)} · 优先级 ${task.priority} · 备注 ${task.notes.length}',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            if (task.status == QueuedTaskStatus.running)
              IconButton(
                tooltip: '暂停任务',
                onPressed: () => widget.controller.pauseTask(task.id),
                icon: const Icon(Icons.pause_rounded),
              ),
            if (task.status == QueuedTaskStatus.paused)
              IconButton(
                tooltip: '继续任务',
                onPressed: () => widget.controller.resumeTask(task.id),
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            IconButton(
              tooltip: '删除任务',
              onPressed: () => widget.controller.deleteTask(task.id),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.originalText),
                const SizedBox(height: 8),
                if (task.notes.isNotEmpty) Text('备注：${task.notes.join('；')}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: priorityController,
                        decoration: const InputDecoration(labelText: '优先级'),
                        keyboardType: TextInputType.number,
                        onSubmitted: (value) {
                          final priority = int.tryParse(value.trim());
                          if (priority != null) {
                            widget.controller.updateTaskPriority(
                              task.id,
                              priority,
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: noteController,
                        decoration: const InputDecoration(labelText: '追加备注'),
                        onSubmitted: (_) => _appendNote(),
                      ),
                    ),
                    IconButton(
                      tooltip: '追加备注',
                      onPressed: _appendNote,
                      icon: const Icon(Icons.add_comment_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _appendNote() {
    widget.controller.appendTaskNote(widget.task.id, noteController.text);
    noteController.clear();
  }
}

class _ChatPatchConfirmationCard extends StatelessWidget {
  const _ChatPatchConfirmationCard({
    required this.patch,
    required this.onApply,
    required this.onReject,
  });

  final PatchProposal patch;
  final VoidCallback onApply;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 18,
          backgroundColor: Color(0xFF8B5CF6),
          child: Icon(
            Icons.difference_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 760),
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFC7D2FE)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '待确认修改',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text('${patch.memberName} 提议修改 ${patch.filePath}'),
                const SizedBox(height: 10),
                SelectableText(
                  patch.diff,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: onApply,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('应用修改'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('拒绝'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatCommandRequestCard extends StatelessWidget {
  const _ChatCommandRequestCard({
    required this.request,
    required this.onApproveExecute,
    required this.onReject,
  });

  final CommandRequest request;
  final VoidCallback onApproveExecute;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final title = switch (request.status) {
      CommandRequestStatus.pending => '待确认命令',
      CommandRequestStatus.approved => '已允许命令',
      CommandRequestStatus.executed => '命令已执行',
      CommandRequestStatus.failed => '命令执行失败',
      CommandRequestStatus.denied => '命令已拒绝',
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                request.memberName,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            '${request.workingDirectory}\n\$ ${request.command}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          if (request.status == CommandRequestStatus.pending ||
              request.status == CommandRequestStatus.approved) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onApproveExecute,
                  icon: Icon(
                    request.status == CommandRequestStatus.pending
                        ? Icons.check_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    request.status == CommandRequestStatus.pending
                        ? '批准并执行'
                        : '执行',
                  ),
                ),
                if (request.status == CommandRequestStatus.pending)
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('拒绝'),
                  ),
              ],
            ),
          ],
          if (request.output != null && request.output!.isNotEmpty) ...[
            const SizedBox(height: 12),
            SelectableText(
              request.output!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommandRequestCard extends StatelessWidget {
  const _CommandRequestCard({
    required this.request,
    required this.onApprove,
    required this.onDeny,
    required this.onExecute,
  });

  final CommandRequest request;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback onExecute;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${request.memberName} · ${request.status.name}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          SelectableText(
            '${request.workingDirectory}\n\$ ${request.command}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          if (request.status == CommandRequestStatus.pending) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('批准'),
                ),
                OutlinedButton.icon(
                  onPressed: onDeny,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('拒绝'),
                ),
              ],
            ),
          ],
          if (request.status == CommandRequestStatus.approved) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onExecute,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('执行'),
            ),
          ],
          if (request.output != null && request.output!.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              request.output!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
