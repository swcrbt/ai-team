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
    return ManagementPageFrame(
      title: '团队管理',
      subtitle: '创建团队、配置成员，并从团队发起群聊',
      child: ManagementPanel(
        title: '团队列表',
        icon: Icons.groups_rounded,
        action: IconButton(
          tooltip: '新增团队',
          onPressed: () => showTeamDialog(context, controller),
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
    return ManagementKeyValueRow(
      label: team.name,
      value:
          '${collaborationModeLabel(team.collaborationMode)}协同 · ${members.map((member) => member.name).join('、')}',
      actions: [
        FilledButton(
          onPressed: onStartChat,
          child: const Text('发起聊天'),
        ),
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
    );
  }
}

class ModelManagementPage extends StatelessWidget {
  const ModelManagementPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ManagementPageFrame(
      title: '模型管理',
      subtitle: 'OpenAI 兼容模型、请求参数和密钥引用在这里维护',
      child: _ModelConfigPanel(controller: controller),
    );
  }
}

class RoleManagementPage extends StatelessWidget {
  const RoleManagementPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ManagementPageFrame(
      title: '角色管理',
      subtitle: '角色提示词、命令策略和项目读取权限在这里维护',
      child: _RoleConfigPanel(controller: controller),
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
    return ManagementPageFrame(
      title: '成员管理',
      subtitle: '团队成员、角色绑定和模型绑定在这里维护',
      child: _MemberConfigPanel(
        controller: controller,
        onStartChat: onStartChat,
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

class _ModelConfigPanel extends StatelessWidget {
  const _ModelConfigPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ManagementPanel(
      title: '模型配置',
      icon: Icons.memory_rounded,
      action: IconButton(
        tooltip: '新增模型',
        onPressed: () => showModelDialog(context, controller),
        icon: const Icon(Icons.add_rounded),
      ),
      child: Column(
        children: controller.state.models
            .map(
              (model) => ManagementKeyValueRow(
                label: model.name,
                value:
                    '${model.modelName}\n${model.baseUrl}\n流式: ${model.streaming ? '开' : '关'} · 温度: ${model.temperature} · 最大 Token: ${model.maxTokens} · 深度思考: ${reasoningEffortLabel(model.reasoningEffort)}',
                actions: [
                  IconButton(
                    tooltip: '编辑模型',
                    onPressed: () =>
                        showModelDialog(context, controller, model: model),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton(
                    tooltip: '删除模型',
                    onPressed: () => runConfigAction(
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
    return ManagementPanel(
      title: '角色配置',
      icon: Icons.badge_rounded,
      action: IconButton(
        tooltip: '新增角色',
        onPressed: () => showRoleDialog(context, controller),
        icon: const Icon(Icons.add_rounded),
      ),
      child: Column(
        children: controller.state.roles
            .map(
              (role) => ManagementKeyValueRow(
                label: role.name,
                value:
                    '${role.description}\n命令: ${role.commandPolicy.allowedCommands.join(', ')}',
                actions: [
                  IconButton(
                    tooltip: '编辑角色',
                    onPressed: () =>
                        showRoleDialog(context, controller, role: role),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton(
                    tooltip: '删除角色',
                    onPressed: () => runConfigAction(
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
    return ManagementPanel(
      title: '团队成员',
      icon: Icons.groups_rounded,
      action: IconButton(
        tooltip: '新增成员',
        onPressed: () => showMemberDialog(context, controller),
        icon: const Icon(Icons.add_rounded),
      ),
      child: Column(
        children: controller.currentMembers
            .map(
              (member) => ManagementKeyValueRow(
                label: member.name,
                value:
                    '${roleName(controller.state, member.roleId)} · ${modelName(controller.state, member.modelId)} · 优先级 ${member.executionPriority}',
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
                    onPressed: () => showMemberDialog(
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
                        : () => runConfigAction(
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
    return ManagementPanel(
      title: '项目工作区',
      icon: Icons.folder_open_rounded,
      action: Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: '创建补丁',
            onPressed: controller.state.workspaces.isEmpty
                ? null
                : () => showWorkspacePatchDialog(context, controller),
            icon: const Icon(Icons.difference_rounded),
          ),
          IconButton(
            tooltip: '浏览文件',
            onPressed: controller.state.workspaces.isEmpty
                ? null
                : () => showWorkspaceFilesDialog(context, controller),
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
                  (workspace) => ManagementKeyValueRow(
                    label: workspace.name,
                    value: workspace.path,
                  ),
                )
                .toList(),
      ),
    );
  }
}
