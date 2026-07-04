import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/domain.dart';
import '../../core/model_gateway.dart';
import '../app_helpers.dart';
import '../dialogs/config_dialogs.dart';
import 'management_components.dart';

class TeamManagementPage extends StatefulWidget {
  const TeamManagementPage({
    super.key,
    required this.controller,
    required this.onStartChat,
  });

  final AppController controller;
  final VoidCallback onStartChat;

  @override
  State<TeamManagementPage> createState() => _TeamManagementPageState();
}

class _TeamManagementPageState extends State<TeamManagementPage> {
  String? selectedTeamId;

  @override
  Widget build(BuildContext context) {
    final teams = widget.controller.state.teams;
    final selected = _selectedTeam(teams);
    return ManagementPageFrame(
      title: '团队管理',
      subtitle: '按开发团队、测试团队等团队对象管理成员组合',
      child: _EntityLayout(
        list: _TeamCardGrid(
          controller: widget.controller,
          teams: teams,
          selectedTeamId: selected?.id,
          onSelectTeam: (teamId) => setState(() => selectedTeamId = teamId),
          onStartChat: widget.onStartChat,
        ),
        detail: selected == null
            ? const _EmptyDetail(title: '暂无团队')
            : _TeamDetail(controller: widget.controller, team: selected),
      ),
    );
  }

  Team? _selectedTeam(List<Team> teams) {
    if (teams.isEmpty) {
      return null;
    }
    for (final team in teams) {
      if (team.id == selectedTeamId) {
        return team;
      }
    }
    return teams.first;
  }
}

class ModelManagementPage extends StatefulWidget {
  const ModelManagementPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ModelManagementPage> createState() => _ModelManagementPageState();
}

class _ModelManagementPageState extends State<ModelManagementPage> {
  String? selectedModelId;

  @override
  Widget build(BuildContext context) {
    final models = widget.controller.state.models;
    final selected = _selectedModel(models);
    return ManagementPageFrame(
      title: '模型管理',
      subtitle: '按模型列表维护 provider、模型名和上下文窗口',
      child: _EntityLayout(
        list: _ObjectList(
          title: '模型列表',
          actionLabel: '新增模型',
          onAdd: () => showModelDialog(context, widget.controller),
          children: [
            for (final model in models)
              _ObjectRow(
                key: ValueKey('model-row-${model.id}'),
                icon: Icons.memory_rounded,
                title: model.name,
                subtitle:
                    '${_providerLabel(model)} · ${model.modelName} · ${model.baseUrl}',
                chips: [
                  _TeamMetaChip(
                    label:
                        '上下文 ${_formatTokenLimit(model.contextWindowTokens)}',
                  ),
                  _TeamMetaChip(label: model.streaming ? '流式 开启' : '流式 关闭'),
                  _TeamMetaChip(
                    label: '温度 ${model.temperature.toStringAsFixed(1)}',
                  ),
                ],
                selected: model.id == selected?.id,
                onTap: () => setState(() => selectedModelId = model.id),
                trailing: IconButton(
                  tooltip: '编辑模型',
                  onPressed: () =>
                      showModelDialog(context, widget.controller, model: model),
                  icon: const Icon(Icons.edit_rounded),
                ),
              ),
          ],
        ),
        detail: selected == null
            ? const _EmptyDetail(title: '暂无模型')
            : _ModelDetail(controller: widget.controller, model: selected),
      ),
    );
  }

  ModelProfile? _selectedModel(List<ModelProfile> models) {
    if (models.isEmpty) {
      return null;
    }
    for (final model in models) {
      if (model.id == selectedModelId) {
        return model;
      }
    }
    return models.first;
  }
}

class RoleManagementPage extends StatefulWidget {
  const RoleManagementPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<RoleManagementPage> createState() => _RoleManagementPageState();
}

class _RoleManagementPageState extends State<RoleManagementPage> {
  String? selectedRoleId;

  @override
  Widget build(BuildContext context) {
    final roles = widget.controller.state.roles;
    final selected = _selectedRole(roles);
    return ManagementPageFrame(
      title: '角色管理',
      subtitle: '按角色列表维护职责、提示词和命令策略',
      child: _EntityLayout(
        list: _ObjectList(
          title: '角色列表',
          actionLabel: '新增角色',
          onAdd: () => showRoleDialog(context, widget.controller),
          children: [
            for (final role in roles)
              _ObjectRow(
                key: ValueKey('role-row-${role.id}'),
                icon: Icons.badge_outlined,
                title: role.name,
                subtitle: role.description,
                chips: [
                  _TeamMetaChip(
                    label: role.canReadProject ? '读项目 允许' : '读项目 禁止',
                  ),
                  _TeamMetaChip(
                    label: role.canProposePatch ? '补丁 允许' : '补丁 禁止',
                  ),
                  _TeamMetaChip(
                    label: role.commandPolicy.requiresConfirmation
                        ? '命令 需确认'
                        : '命令 允许',
                  ),
                ],
                selected: role.id == selected?.id,
                onTap: () => setState(() => selectedRoleId = role.id),
                trailing: IconButton(
                  tooltip: '编辑角色',
                  onPressed: () =>
                      showRoleDialog(context, widget.controller, role: role),
                  icon: const Icon(Icons.edit_rounded),
                ),
              ),
          ],
        ),
        detail: selected == null
            ? const _EmptyDetail(title: '暂无角色')
            : _RoleDetail(controller: widget.controller, role: selected),
      ),
    );
  }

  RoleTemplate? _selectedRole(List<RoleTemplate> roles) {
    if (roles.isEmpty) {
      return null;
    }
    for (final role in roles) {
      if (role.id == selectedRoleId) {
        return role;
      }
    }
    return roles.first;
  }
}

class MemberManagementPage extends StatefulWidget {
  const MemberManagementPage({
    super.key,
    required this.controller,
    required this.onStartChat,
  });

  final AppController controller;
  final VoidCallback onStartChat;

  @override
  State<MemberManagementPage> createState() => _MemberManagementPageState();
}

class _MemberManagementPageState extends State<MemberManagementPage> {
  String? selectedMemberId;

  @override
  Widget build(BuildContext context) {
    final members = widget.controller.currentMembers;
    final selected = _selectedMember(members);
    return ManagementPageFrame(
      title: '成员管理',
      subtitle: '按成员列表维护模型与角色绑定',
      child: _EntityLayout(
        list: _ObjectList(
          title: '成员列表',
          actionLabel: '新增成员',
          onAdd: () => showMemberDialog(context, widget.controller),
          children: [
            for (final member in members)
              _ObjectRow(
                key: ValueKey('member-row-${member.id}'),
                icon: Icons.person_outline_rounded,
                title: member.name,
                subtitle:
                    '${roleName(widget.controller.state, member.roleId)} · ${modelName(widget.controller.state, member.modelId)} · ${_memberTeamNames(widget.controller.state, member)}',
                chips: [
                  _TeamMetaChip(label: member.isSecretary ? '秘书成员' : '私聊入口'),
                  _TeamMetaChip(
                    label:
                        '角色 ${roleName(widget.controller.state, member.roleId)}',
                  ),
                  _TeamMetaChip(
                    label:
                        '模型 ${modelName(widget.controller.state, member.modelId)}',
                  ),
                ],
                selected: member.id == selected?.id,
                onTap: () => setState(() => selectedMemberId = member.id),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: '打开私聊',
                      onPressed: () {
                        widget.controller.startMemberChat(member.id);
                        widget.onStartChat();
                      },
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                    ),
                    IconButton(
                      tooltip: '编辑成员',
                      onPressed: () => showMemberDialog(
                        context,
                        widget.controller,
                        member: member,
                      ),
                      icon: const Icon(Icons.edit_rounded),
                    ),
                  ],
                ),
              ),
          ],
        ),
        detail: selected == null
            ? const _EmptyDetail(title: '暂无成员')
            : _MemberDetail(controller: widget.controller, member: selected),
      ),
    );
  }

  TeamMember? _selectedMember(List<TeamMember> members) {
    if (members.isEmpty) {
      return null;
    }
    for (final member in members) {
      if (member.id == selectedMemberId) {
        return member;
      }
    }
    return members.first;
  }
}

class ProjectPage extends StatelessWidget {
  const ProjectPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ManagementPageFrame(
      title: '项目管理',
      subtitle: '项目列表、边界、命令审批和补丁确认',
      child: _ProjectSafetySurface(controller: controller),
    );
  }
}

class _TeamCardGrid extends StatelessWidget {
  const _TeamCardGrid({
    required this.controller,
    required this.teams,
    required this.selectedTeamId,
    required this.onSelectTeam,
    required this.onStartChat,
  });

  final AppController controller;
  final List<Team> teams;
  final String? selectedTeamId;
  final ValueChanged<String> onSelectTeam;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    return _ObjectList(
      title: '团队列表',
      actionLabel: '新增团队',
      onAdd: () => showTeamDialog(context, controller),
      children: [
        const _TeamObjectHint(),
        for (final team in teams)
          _TeamObjectCard(
            key: ValueKey('team-row-${team.id}'),
            controller: controller,
            team: team,
            selected: team.id == selectedTeamId,
            onSelect: () => onSelectTeam(team.id),
            onStartChat: () {
              controller.startTeamChat(team.id);
              onStartChat();
            },
          ),
      ],
    );
  }
}

class _TeamObjectHint extends StatelessWidget {
  const _TeamObjectHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Text(
        '按开发、测试、文档、发布这类团队对象管理成员组合。',
        style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
      ),
    );
  }
}

class _TeamObjectCard extends StatelessWidget {
  const _TeamObjectCard({
    super.key,
    required this.controller,
    required this.team,
    required this.selected,
    required this.onSelect,
    required this.onStartChat,
  });

  final AppController controller;
  final Team team;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    final members = controller.state.members
        .where((member) => team.memberIds.contains(member.id))
        .toList();
    final secretary = members.firstWhere(
      (member) => member.id == team.secretaryMemberId,
      orElse: () =>
          members.isEmpty ? controller.state.members.first : members.first,
    );
    final spec = _teamCardSpec(team);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? const Color(0xFFEFF6FF) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            team.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            spec.purpose,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _TeamObjectBadge(label: '对象：${spec.objectName}'),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _TeamMetaChip(label: '成员 ${members.length}'),
                    _TeamMetaChip(
                      label:
                          '模式 ${collaborationModeLabel(team.collaborationMode)}协作',
                    ),
                    _TeamMetaChip(label: '默认秘书 ${secretary.name}'),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.groups_2_outlined,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        members.map((member) => member.name).join('、'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF475569)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      onPressed: onStartChat,
                      child: const Text('发起聊天'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '编辑团队',
                      onPressed: () =>
                          showTeamDialog(context, controller, team: team),
                      icon: const Icon(Icons.edit_rounded),
                    ),
                    IconButton(
                      tooltip: '删除团队',
                      onPressed: controller.state.teams.length <= 1
                          ? null
                          : () => runConfigAction(
                              context,
                              () => controller.deleteTeam(team.id),
                            ),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamObjectBadge extends StatelessWidget {
  const _TeamObjectBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TeamMetaChip extends StatelessWidget {
  const _TeamMetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF475569),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CapabilityItem {
  const _CapabilityItem({required this.label, required this.value});

  final String label;
  final String value;
}

class _CapabilityGrid extends StatelessWidget {
  const _CapabilityGrid({required this.rows});

  final List<_CapabilityItem> rows;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 3.4,
      children: [
        for (final row in rows)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    row.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PromptPreview extends StatelessWidget {
  const _PromptPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFFE2E8F0),
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.35,
        ),
      ),
    );
  }
}

class _TeamCardSpec {
  const _TeamCardSpec({required this.objectName, required this.purpose});

  final String objectName;
  final String purpose;
}

_TeamCardSpec _teamCardSpec(Team team) {
  final name = team.name;
  if (name.contains('测试') || name.toLowerCase().contains('qa')) {
    return const _TeamCardSpec(
      objectName: '测试团队',
      purpose: '负责回归验证、失败复现、测试报告。',
    );
  }
  if (name.contains('文档') || name.toLowerCase().contains('doc')) {
    return const _TeamCardSpec(
      objectName: '文档团队',
      purpose: '负责设计文档、变更摘要、发布说明。',
    );
  }
  if (name.contains('发布') || name.toLowerCase().contains('release')) {
    return const _TeamCardSpec(
      objectName: '发布团队',
      purpose: '负责发布检查、审计确认、风险复核。',
    );
  }
  if (name.contains('开发') ||
      name.contains('默认') ||
      name.toLowerCase().contains('dev')) {
    return const _TeamCardSpec(
      objectName: '开发团队',
      purpose: '负责方案拆解、代码修改、补丁提交。',
    );
  }
  return const _TeamCardSpec(objectName: '协作团队', purpose: '按成员组合执行当前协作流程。');
}

String _providerLabel(ModelProfile model) {
  final baseUrl = model.baseUrl.toLowerCase();
  if (baseUrl.contains('localhost') || baseUrl.contains('127.0.0.1')) {
    return '兼容端点';
  }
  return 'OpenAI-compatible';
}

String _formatTokenLimit(int tokens) {
  if (tokens >= 1000 && tokens % 1000 == 0) {
    return '${tokens ~/ 1000}k';
  }
  return tokens.toString();
}

String _memberTeamNames(AppState state, TeamMember member) {
  final names = state.teams
      .where((team) => team.memberIds.contains(member.id))
      .map((team) => _teamCardSpec(team).objectName)
      .toList();
  if (names.isEmpty) {
    return '未加入团队';
  }
  return names.join('、');
}

RoleTemplate _roleFor(AppState state, TeamMember member) {
  return state.roles.firstWhere(
    (role) => role.id == member.roleId,
    orElse: () => state.roles.first,
  );
}

class _EntityLayout extends StatelessWidget {
  const _EntityLayout({required this.list, required this.detail});

  final Widget list;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 880;
        if (!wide) {
          return Column(children: [list, const SizedBox(height: 12), detail]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: list),
            const SizedBox(width: 14),
            Expanded(flex: 2, child: detail),
          ],
        );
      },
    );
  }
}

class _ObjectList extends StatelessWidget {
  const _ObjectList({
    required this.title,
    required this.actionLabel,
    required this.onAdd,
    required this.children,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAdd;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      action: Tooltip(
        message: actionLabel,
        child: FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
          label: Text(actionLabel),
        ),
      ),
      child: children.isEmpty ? const Text('暂无数据') : Column(children: children),
    );
  }
}

class _ObjectRow extends StatelessWidget {
  const _ObjectRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.chips = const [],
    this.selected = false,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> chips;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: selected ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFDBEAFE)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: const Color(0xFF2563EB)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(spacing: 6, runSpacing: 6, children: chips),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamDetail extends StatelessWidget {
  const _TeamDetail({required this.controller, required this.team});

  final AppController controller;
  final Team team;

  @override
  Widget build(BuildContext context) {
    final secretary = controller.state.members.firstWhere(
      (member) => member.id == team.secretaryMemberId,
      orElse: () => controller.state.members.first,
    );
    return _Panel(
      key: ValueKey('team-detail-${team.id}'),
      title: '编辑团队',
      action: IconButton(
        tooltip: '编辑团队',
        onPressed: () => showTeamDialog(context, controller, team: team),
        icon: const Icon(Icons.edit_rounded),
      ),
      child: Column(
        children: [
          _DetailRow(label: '团队对象', value: _teamCardSpec(team).objectName),
          _DetailRow(label: '团队名称', value: team.name),
          _DetailRow(label: '团队用途', value: _teamCardSpec(team).purpose),
          _DetailRow(
            label: '协作模式',
            value: collaborationModeLabel(team.collaborationMode),
          ),
          _DetailRow(label: '秘书成员', value: secretary.name),
          _DetailRow(label: '最大轮次', value: team.maxRounds.toString()),
          _DetailRow(label: '成员数量', value: team.memberIds.length.toString()),
        ],
      ),
    );
  }
}

class _ModelDetail extends StatelessWidget {
  const _ModelDetail({required this.controller, required this.model});

  final AppController controller;
  final ModelProfile model;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      key: ValueKey('model-detail-${model.id}'),
      title: '编辑模型',
      action: IconButton(
        tooltip: '编辑模型',
        onPressed: () => showModelDialog(context, controller, model: model),
        icon: const Icon(Icons.edit_rounded),
      ),
      child: Column(
        children: [
          _DetailRow(label: '名称', value: model.name),
          _DetailRow(label: 'Provider', value: _providerLabel(model)),
          _DetailRow(label: '模型名', value: model.modelName),
          _DetailRow(label: 'Base URL', value: model.baseUrl),
          _DetailRow(
            label: '上下文上限',
            value: _formatTokenLimit(model.contextWindowTokens),
          ),
          _DetailRow(label: '最大 Token', value: model.maxTokens.toString()),
          _DetailRow(
            label: '深度思考',
            value: reasoningEffortLabel(model.reasoningEffort),
          ),
          const SizedBox(height: 10),
          _CapabilityGrid(
            rows: [
              _CapabilityItem(
                label: '流式输出',
                value: model.streaming ? '开启' : '关闭',
              ),
              const _CapabilityItem(label: '工具调用', value: '按角色权限'),
              const _CapabilityItem(label: '返回思考区', value: '仅真实字段'),
              const _CapabilityItem(label: '审计诊断', value: '写入'),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleDetail extends StatelessWidget {
  const _RoleDetail({required this.controller, required this.role});

  final AppController controller;
  final RoleTemplate role;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      key: ValueKey('role-detail-${role.id}'),
      title: '编辑角色',
      action: IconButton(
        tooltip: '编辑角色',
        onPressed: () => showRoleDialog(context, controller, role: role),
        icon: const Icon(Icons.edit_rounded),
      ),
      child: Column(
        children: [
          _DetailRow(label: '角色名称', value: role.name),
          _DetailRow(label: '用途', value: role.description),
          _DetailRow(label: '输出格式', value: role.outputFormatPrompt),
          const SizedBox(height: 10),
          _PromptPreview(text: role.identityPrompt),
          const SizedBox(height: 10),
          _CapabilityGrid(
            rows: [
              _CapabilityItem(
                label: '读取项目文件',
                value: role.canReadProject ? '允许' : '禁止',
              ),
              _CapabilityItem(
                label: '请求命令',
                value: role.commandPolicy.requiresConfirmation ? '需确认' : '允许',
              ),
              _CapabilityItem(
                label: '应用补丁',
                value: role.canProposePatch ? '生成后确认' : '禁止',
              ),
              const _CapabilityItem(label: '私聊可见', value: '按成员'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberDetail extends StatelessWidget {
  const _MemberDetail({required this.controller, required this.member});

  final AppController controller;
  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    final role = _roleFor(controller.state, member);
    return _Panel(
      key: ValueKey('member-detail-${member.id}'),
      title: '编辑成员',
      action: IconButton(
        tooltip: '编辑成员',
        onPressed: () => showMemberDialog(context, controller, member: member),
        icon: const Icon(Icons.edit_rounded),
      ),
      child: Column(
        children: [
          _DetailRow(label: '显示名称', value: member.name),
          _DetailRow(
            label: '绑定角色',
            value: roleName(controller.state, member.roleId),
          ),
          _DetailRow(
            label: '绑定模型',
            value: modelName(controller.state, member.modelId),
          ),
          _DetailRow(
            label: '所属团队',
            value: _memberTeamNames(controller.state, member),
          ),
          _DetailRow(label: '成员类型', value: member.isSecretary ? '秘书' : '普通成员'),
          const _DetailRow(label: '私聊入口', value: '成员页 / 会话栏'),
          const SizedBox(height: 10),
          _CapabilityGrid(
            rows: [
              _CapabilityItem(
                label: '读取文件',
                value: role.canReadProject ? '允许' : '禁止',
              ),
              _CapabilityItem(
                label: '请求命令',
                value: role.commandPolicy.requiresConfirmation ? '需确认' : '允许',
              ),
              const _CapabilityItem(label: '代表用户发送', value: '禁止'),
              _CapabilityItem(
                label: '参与群聊',
                value: _memberTeamNames(controller.state, member) == '未加入团队'
                    ? '未加入'
                    : '允许',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectSafetySurface extends StatelessWidget {
  const _ProjectSafetySurface({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final commandRequests = controller.state.commandRequests;
    final patchProposals = controller.state.patchProposals
        .where((patch) => patch.status == PatchStatus.pending)
        .toList();
    final auditLog = controller.state.auditLog.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final panels = [
          _ProjectManagementPanel(controller: controller),
          _CommandApprovalPanel(
            controller: controller,
            commandRequests: commandRequests,
          ),
          _PatchConfirmationPanel(
            controller: controller,
            patchProposals: patchProposals,
          ),
          _ProjectBoundaryPanel(controller: controller),
          _AuditSummaryPanel(auditLog: auditLog),
        ];
        if (!wide) {
          return Column(
            children: [
              for (final panel in panels) ...[
                panel,
                const SizedBox(height: 12),
              ],
            ],
          );
        }
        return GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: panels,
        );
      },
    );
  }
}

class _ProjectManagementPanel extends StatelessWidget {
  const _ProjectManagementPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final workspaces = controller.state.workspaces;
    return _Panel(
      title: '项目管理列表',
      action: IconButton(
        tooltip: '添加项目',
        onPressed: controller.pickAndAddWorkspace,
        icon: const Icon(Icons.add_rounded),
      ),
      child: workspaces.isEmpty
          ? const _EmptyState(
              icon: Icons.folder_open_rounded,
              title: '还没有添加项目',
              subtitle: '添加项目后会在这里显示边界和补丁策略。',
            )
          : Column(
              children: [
                for (final indexed in workspaces.indexed)
                  _ProjectCard(
                    workspace: indexed.$2,
                    selected: indexed.$1 == 0,
                  ),
              ],
            ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.workspace, required this.selected});

  final ProjectWorkspace workspace;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
        border: Border.all(
          color: selected ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  workspace.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _ProjectStatusPill(
                label: selected ? '边界复核' : '可用',
                tone: selected ? _ProjectTone.amber : _ProjectTone.green,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            workspace.path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            selected ? '当前项目 · 补丁需确认' : '项目 · 只读默认',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _CommandApprovalPanel extends StatelessWidget {
  const _CommandApprovalPanel({
    required this.controller,
    required this.commandRequests,
  });

  final AppController controller;
  final List<CommandRequest> commandRequests;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '命令审批',
      action: _ProjectStatusPill(
        label:
            commandRequests.any(
              (request) => request.status == CommandRequestStatus.pending,
            )
            ? '等待确认'
            : '无待处理',
        tone:
            commandRequests.any(
              (request) => request.status == CommandRequestStatus.pending,
            )
            ? _ProjectTone.amber
            : _ProjectTone.green,
      ),
      child: commandRequests.isEmpty
          ? const _EmptyState(
              icon: Icons.terminal_rounded,
              title: '暂无命令请求',
              subtitle: '成员请求命令后会在这里集中审批。',
            )
          : Column(
              children: [
                for (final request in commandRequests)
                  _CommandApprovalRow(
                    request: request,
                    onAllow: request.status == CommandRequestStatus.pending
                        ? () => controller.updateCommandRequestStatus(
                            request.id,
                            CommandRequestStatus.approved,
                          )
                        : null,
                    onBlock: request.status == CommandRequestStatus.pending
                        ? () => controller.updateCommandRequestStatus(
                            request.id,
                            CommandRequestStatus.denied,
                          )
                        : null,
                  ),
              ],
            ),
    );
  }
}

class _CommandApprovalRow extends StatelessWidget {
  const _CommandApprovalRow({
    required this.request,
    required this.onAllow,
    required this.onBlock,
  });

  final CommandRequest request;
  final VoidCallback? onAllow;
  final VoidCallback? onBlock;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.command,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${request.memberName} 申请 · ${_commandStatusText(request.status)} · ${request.workingDirectory}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _ProjectStatusPill(
            label: _commandStatusText(request.status),
            tone: _commandStatusTone(request.status),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (request.status == CommandRequestStatus.pending) ...[
                FilledButton(onPressed: onAllow, child: const Text('允许')),
                OutlinedButton(onPressed: onBlock, child: const Text('阻断')),
              ] else
                OutlinedButton(
                  onPressed: () => _showCommandRequestDetails(context, request),
                  child: const Text('查看'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PatchConfirmationPanel extends StatelessWidget {
  const _PatchConfirmationPanel({
    required this.controller,
    required this.patchProposals,
  });

  final AppController controller;
  final List<PatchProposal> patchProposals;

  @override
  Widget build(BuildContext context) {
    final patch = patchProposals.isEmpty ? null : patchProposals.first;
    if (patch == null) {
      return const _Panel(
        title: '补丁确认',
        action: Text(
          '0 待确认',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        child: _EmptyState(
          icon: Icons.difference_rounded,
          title: '暂无待确认补丁',
          subtitle: '模型生成的 Diff 会先停在这里等待确认。',
        ),
      );
    }
    final stats = _projectDiffStats(patch.diff);
    return _Panel(
      title: '补丁确认',
      action: Text(
        '+${stats.additions} -${stats.deletions}',
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _PatchMetric(
                  value: '+${stats.additions} -${stats.deletions}',
                  label: '变更量',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PatchMetric(value: stats.files.toString(), label: '文件'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PatchMetric(value: stats.hunks.toString(), label: '片段'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _PatchFileLabel(filePath: patch.filePath),
          const SizedBox(height: 8),
          _ProjectDiffBox(diff: patch.diff),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () => controller.applyPatch(patch),
                child: const Text('确认补丁'),
              ),
              OutlinedButton(
                onPressed: () => _showPatchDiffDialog(context, patch),
                child: const Text('展开文件'),
              ),
              OutlinedButton(
                onPressed: () => controller.rejectPatch(patch),
                child: const Text('拒绝'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PatchMetric extends StatelessWidget {
  const _PatchMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PatchFileLabel extends StatelessWidget {
  const _PatchFileLabel({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        filePath,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProjectDiffBox extends StatelessWidget {
  const _ProjectDiffBox({required this.diff});

  final String diff;

  @override
  Widget build(BuildContext context) {
    final lines = diff
        .split('\n')
        .where((line) => line.isNotEmpty)
        .where(
          (line) =>
              line.startsWith('+') ||
              line.startsWith('-') ||
              line.startsWith('@@'),
        )
        .take(6)
        .toList();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (final line in lines) _ProjectDiffLine(line: line)],
      ),
    );
  }
}

class _ProjectDiffLine extends StatelessWidget {
  const _ProjectDiffLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final added = line.startsWith('+') && !line.startsWith('+++');
    final deleted = line.startsWith('-') && !line.startsWith('---');
    final background = added
        ? const Color(0xFFECFDF3)
        : deleted
        ? const Color(0xFFFFF1F2)
        : Colors.white;
    final foreground = added
        ? const Color(0xFF047857)
        : deleted
        ? const Color(0xFFBE123C)
        : const Color(0xFF64748B);
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: background,
      child: Text(
        line,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ProjectBoundaryPanel extends StatelessWidget {
  const _ProjectBoundaryPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final workspaces = controller.state.workspaces;
    return _Panel(
      title: '项目边界',
      action: const _ProjectStatusPill(
        label: 'enforced',
        tone: _ProjectTone.green,
      ),
      child: Column(
        children: [
          if (workspaces.isEmpty)
            const _BoundaryRow(
              label: 'root',
              value: '未选择',
              status: '未配置',
              tone: _ProjectTone.amber,
            )
          else
            for (final workspace in workspaces)
              _BoundaryRow(
                label: workspace.name,
                value: workspace.path,
                status: 'write',
                tone: _ProjectTone.green,
              ),
          const _BoundaryRow(
            label: 'patch',
            value: '统一 diff 确认后应用',
            status: 'confirm',
            tone: _ProjectTone.amber,
          ),
          const _BoundaryRow(
            label: 'outside',
            value: '仓库外路径',
            status: 'blocked',
            tone: _ProjectTone.red,
          ),
        ],
      ),
    );
  }
}

class _BoundaryRow extends StatelessWidget {
  const _BoundaryRow({
    required this.label,
    required this.value,
    required this.status,
    required this.tone,
  });

  final String label;
  final String value;
  final String status;
  final _ProjectTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _ProjectStatusPill(label: status, tone: tone),
        ],
      ),
    );
  }
}

class _AuditSummaryPanel extends StatelessWidget {
  const _AuditSummaryPanel({required this.auditLog});

  final List<AuditEntry> auditLog;

  @override
  Widget build(BuildContext context) {
    final modelCalls = auditLog.where(
      (entry) =>
          entry.action.contains('model') || entry.action.contains('diagnostic'),
    );
    final blocked = auditLog.where(
      (entry) =>
          entry.action.contains('denied') ||
          entry.action.contains('blocked') ||
          entry.detail.contains('blocked'),
    );
    return _Panel(
      title: '审计摘要',
      action: const Text(
        '最新优先',
        style: TextStyle(
          color: Color(0xFF64748B),
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _AuditKpi(value: auditLog.length, label: '事件'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AuditKpi(value: modelCalls.length, label: '模型调用'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AuditKpi(value: blocked.length, label: '阻断'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (auditLog.isEmpty)
            const _EmptyState(
              icon: Icons.receipt_long_rounded,
              title: '暂无审计记录',
              subtitle: '命令、补丁和模型诊断会按最新优先写入。',
            )
          else
            for (final entry in auditLog.take(3))
              _AuditSummaryRow(entry: entry),
        ],
      ),
    );
  }
}

class _AuditKpi extends StatelessWidget {
  const _AuditKpi({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.toString(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AuditSummaryRow extends StatelessWidget {
  const _AuditSummaryRow({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Text(
            messageTimeText(entry.createdAt),
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${entry.action} · ${entry.detail}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const _ProjectStatusPill(label: '写入', tone: _ProjectTone.blue),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF64748B), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectStatusPill extends StatelessWidget {
  const _ProjectStatusPill({required this.label, required this.tone});

  final String label;
  final _ProjectTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _ProjectTone.green => const Color(0xFF047857),
      _ProjectTone.amber => const Color(0xFFB45309),
      _ProjectTone.blue => const Color(0xFF2563EB),
      _ProjectTone.red => const Color(0xFFBE123C),
    };
    final background = switch (tone) {
      _ProjectTone.green => const Color(0xFFECFDF3),
      _ProjectTone.amber => const Color(0xFFFFFBEB),
      _ProjectTone.blue => const Color(0xFFEFF6FF),
      _ProjectTone.red => const Color(0xFFFFF1F2),
    };
    final border = switch (tone) {
      _ProjectTone.green => const Color(0xFFA7F3D0),
      _ProjectTone.amber => const Color(0xFFFDE68A),
      _ProjectTone.blue => const Color(0xFFBFDBFE),
      _ProjectTone.red => const Color(0xFFFECDD3),
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

enum _ProjectTone { green, amber, blue, red }

_ProjectTone _commandStatusTone(CommandRequestStatus status) {
  return switch (status) {
    CommandRequestStatus.pending => _ProjectTone.amber,
    CommandRequestStatus.approved => _ProjectTone.blue,
    CommandRequestStatus.denied => _ProjectTone.red,
    CommandRequestStatus.executed => _ProjectTone.green,
    CommandRequestStatus.failed => _ProjectTone.red,
  };
}

String _commandStatusText(CommandRequestStatus status) {
  return switch (status) {
    CommandRequestStatus.pending => '等待确认',
    CommandRequestStatus.approved => '允许中',
    CommandRequestStatus.denied => '已拒绝',
    CommandRequestStatus.executed => '已执行',
    CommandRequestStatus.failed => '失败',
  };
}

void _showCommandRequestDetails(BuildContext context, CommandRequest request) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('命令请求'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              request.command,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            _DetailRow(label: '申请成员', value: request.memberName),
            _DetailRow(label: '状态', value: _commandStatusText(request.status)),
            _DetailRow(label: '工作目录', value: request.workingDirectory),
            if (request.output != null)
              _DetailRow(label: '输出摘要', value: request.output!),
          ],
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

void _showPatchDiffDialog(BuildContext context, PatchProposal patch) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('补丁文件'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(label: '文件', value: patch.filePath),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  patch.diff,
                  style: const TextStyle(
                    color: Color(0xFFE2E8F0),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
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

_ProjectDiffStats _projectDiffStats(String diff) {
  var additions = 0;
  var deletions = 0;
  var gitFileHeaders = 0;
  var plusFileHeaders = 0;
  var hunks = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      additions++;
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      deletions++;
    }
    if (line.startsWith('diff --git ')) {
      gitFileHeaders++;
    }
    if (line.startsWith('+++ ') && !line.startsWith('+++ /dev/null')) {
      plusFileHeaders++;
    }
    if (line.startsWith('@@')) {
      hunks++;
    }
  }
  return _ProjectDiffStats(
    additions: additions,
    deletions: deletions,
    files: gitFileHeaders > 0
        ? gitFileHeaders
        : plusFileHeaders == 0
        ? 1
        : plusFileHeaders,
    hunks: hunks == 0 ? 1 : hunks,
  );
}

class _ProjectDiffStats {
  const _ProjectDiffStats({
    required this.additions,
    required this.deletions,
    required this.files,
    required this.hunks,
  });

  final int additions;
  final int deletions;
  final int files;
  final int hunks;
}

class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return _Panel(title: title, child: const Text('请选择或新增一个对象'));
  }
}
