import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/domain.dart';
import '../../core/model_gateway.dart';
import '../app_helpers.dart';
import '../dialogs/config_dialogs.dart';
import 'management_components.dart';

class TeamManagementPage extends StatelessWidget {
  const TeamManagementPage({
    super.key,
    required this.controller,
    required this.onStartChat,
  });

  final AppController controller;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    final teams = controller.state.teams;
    final selected = teams.isEmpty ? null : teams.first;
    return ManagementPageFrame(
      title: '团队管理',
      subtitle: '按开发团队、测试团队等团队对象管理成员组合',
      child: _EntityLayout(
        list: _TeamCardGrid(
          controller: controller,
          teams: teams,
          onStartChat: onStartChat,
        ),
        detail: selected == null
            ? const _EmptyDetail(title: '暂无团队')
            : _TeamDetail(controller: controller, team: selected),
      ),
    );
  }
}

class ModelManagementPage extends StatelessWidget {
  const ModelManagementPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final models = controller.state.models;
    final selected = models.isEmpty ? null : models.first;
    return ManagementPageFrame(
      title: '模型管理',
      subtitle: '按模型列表维护 provider、模型名和上下文窗口',
      child: _EntityLayout(
        list: _ObjectList(
          title: '模型列表',
          actionLabel: '新增模型',
          onAdd: () => showModelDialog(context, controller),
          children: [
            for (final model in models)
              _ObjectRow(
                title: model.name,
                subtitle:
                    '${model.modelName} · ${model.baseUrl} · context ${model.contextWindowTokens}',
                trailing: IconButton(
                  tooltip: '编辑模型',
                  onPressed: () =>
                      showModelDialog(context, controller, model: model),
                  icon: const Icon(Icons.edit_rounded),
                ),
              ),
          ],
        ),
        detail: selected == null
            ? const _EmptyDetail(title: '暂无模型')
            : _ModelDetail(controller: controller, model: selected),
      ),
    );
  }
}

class RoleManagementPage extends StatelessWidget {
  const RoleManagementPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final roles = controller.state.roles;
    final selected = roles.isEmpty ? null : roles.first;
    return ManagementPageFrame(
      title: '角色管理',
      subtitle: '按角色列表维护职责、提示词和命令策略',
      child: _EntityLayout(
        list: _ObjectList(
          title: '角色列表',
          actionLabel: '新增角色',
          onAdd: () => showRoleDialog(context, controller),
          children: [
            for (final role in roles)
              _ObjectRow(
                title: role.name,
                subtitle: role.description,
                trailing: IconButton(
                  tooltip: '编辑角色',
                  onPressed: () =>
                      showRoleDialog(context, controller, role: role),
                  icon: const Icon(Icons.edit_rounded),
                ),
              ),
          ],
        ),
        detail: selected == null
            ? const _EmptyDetail(title: '暂无角色')
            : _RoleDetail(controller: controller, role: selected),
      ),
    );
  }
}

class MemberManagementPage extends StatelessWidget {
  const MemberManagementPage({
    super.key,
    required this.controller,
    required this.onStartChat,
  });

  final AppController controller;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    final members = controller.currentMembers;
    final selected = members.isEmpty ? null : members.first;
    return ManagementPageFrame(
      title: '成员管理',
      subtitle: '按成员列表维护模型与角色绑定',
      child: _EntityLayout(
        list: _ObjectList(
          title: '成员列表',
          actionLabel: '新增成员',
          onAdd: () => showMemberDialog(context, controller),
          children: [
            for (final member in members)
              _ObjectRow(
                title: member.name,
                subtitle:
                    '${roleName(controller.state, member.roleId)} · ${modelName(controller.state, member.modelId)}',
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: '打开私聊',
                      onPressed: () {
                        controller.startMemberChat(member.id);
                        onStartChat();
                      },
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                    ),
                    IconButton(
                      tooltip: '编辑成员',
                      onPressed: () => showMemberDialog(
                        context,
                        controller,
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
            : _MemberDetail(controller: controller, member: selected),
      ),
    );
  }
}

class ProjectPage extends StatelessWidget {
  const ProjectPage({
    super.key,
    required this.controller,
  });

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
    required this.onStartChat,
  });

  final AppController controller;
  final List<Team> teams;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    return _ObjectList(
      title: '团队列表',
      actionLabel: '新增团队',
      onAdd: () => showTeamDialog(context, controller),
      children: [
        for (final team in teams)
          _TeamObjectCard(
            controller: controller,
            team: team,
            onStartChat: () {
              controller.startTeamChat(team.id);
              onStartChat();
            },
          ),
      ],
    );
  }
}

class _TeamObjectCard extends StatelessWidget {
  const _TeamObjectCard({
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
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
                  team.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                collaborationModeLabel(team.collaborationMode),
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            members.map((member) => member.name).join('、'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF475569)),
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
                onPressed: () => showTeamDialog(
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
    );
  }
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
          return Column(
            children: [
              list,
              const SizedBox(height: 12),
              detail,
            ],
          );
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
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
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
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
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
      title: '编辑团队',
      action: IconButton(
        tooltip: '编辑团队',
        onPressed: () => showTeamDialog(context, controller, team: team),
        icon: const Icon(Icons.edit_rounded),
      ),
      child: Column(
        children: [
          _DetailRow(label: '团队名称', value: team.name),
          _DetailRow(
            label: '协作模式',
            value: collaborationModeLabel(team.collaborationMode),
          ),
          _DetailRow(label: '秘书成员', value: secretary.name),
          _DetailRow(label: '最大轮次', value: team.maxRounds.toString()),
          _DetailRow(
            label: '成员数量',
            value: team.memberIds.length.toString(),
          ),
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
      title: '编辑模型',
      action: IconButton(
        tooltip: '编辑模型',
        onPressed: () => showModelDialog(context, controller, model: model),
        icon: const Icon(Icons.edit_rounded),
      ),
      child: Column(
        children: [
          _DetailRow(label: '名称', value: model.name),
          _DetailRow(label: '模型名', value: model.modelName),
          _DetailRow(label: 'Base URL', value: model.baseUrl),
          _DetailRow(
            label: '流式输出',
            value: model.streaming ? '开启' : '关闭',
          ),
          _DetailRow(label: '最大 Token', value: model.maxTokens.toString()),
          _DetailRow(
            label: '上下文窗口',
            value: model.contextWindowTokens.toString(),
          ),
          _DetailRow(
            label: '深度思考',
            value: reasoningEffortLabel(model.reasoningEffort),
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
          _DetailRow(
            label: '读取项目',
            value: role.canReadProject ? '允许' : '禁止',
          ),
          _DetailRow(
            label: '生成补丁',
            value: role.canProposePatch ? '允许' : '禁止',
          ),
          _DetailRow(
            label: '命令策略',
            value: role.commandPolicy.requiresConfirmation ? '需确认' : '允许',
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
    return _Panel(
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
            label: '成员类型',
            value: member.isSecretary ? '秘书' : '普通成员',
          ),
          const _DetailRow(label: '私聊入口', value: '可打开'),
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
        label: commandRequests.any(
          (request) => request.status == CommandRequestStatus.pending,
        )
            ? '等待确认'
            : '无待处理',
        tone: commandRequests.any(
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
                  ),
              ],
            ),
    );
  }
}

class _CommandApprovalRow extends StatelessWidget {
  const _CommandApprovalRow({required this.request, required this.onAllow});

  final CommandRequest request;
  final VoidCallback? onAllow;

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
          if (request.status == CommandRequestStatus.pending)
            FilledButton(onPressed: onAllow, child: const Text('允许'))
          else
            OutlinedButton(
              onPressed: null,
              child: Text(_commandStatusText(request.status)),
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
    final stats = patch == null ? null : _projectDiffStats(patch.diff);
    return _Panel(
      title: '补丁确认',
      action: Text(
        stats == null ? '0 pending' : '+${stats.additions} -${stats.deletions}',
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      child: patch == null
          ? const _EmptyState(
              icon: Icons.difference_rounded,
              title: '暂无待确认补丁',
              subtitle: '模型生成的 diff 会先停在这里等待确认。',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
        'newest first',
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
                child: _AuditKpi(value: auditLog.length, label: 'events'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AuditKpi(
                  value: modelCalls.length,
                  label: 'model calls',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _AuditKpi(value: blocked.length, label: 'blocked'),
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

String _commandStatusText(CommandRequestStatus status) {
  return switch (status) {
    CommandRequestStatus.pending => '等待确认',
    CommandRequestStatus.approved => '允许中',
    CommandRequestStatus.denied => '已拒绝',
    CommandRequestStatus.executed => '已执行',
    CommandRequestStatus.failed => '失败',
  };
}

_ProjectDiffStats _projectDiffStats(String diff) {
  var additions = 0;
  var deletions = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      additions++;
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      deletions++;
    }
  }
  return _ProjectDiffStats(additions: additions, deletions: deletions);
}

class _ProjectDiffStats {
  const _ProjectDiffStats({required this.additions, required this.deletions});

  final int additions;
  final int deletions;
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});

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
