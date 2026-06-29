// ignore_for_file: use_key_in_widget_constructors

import 'package:flutter/material.dart';

import 'main_view.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    required this.selectedView,
    required this.onChat,
    required this.onTeam,
    required this.onModels,
    required this.onRoles,
    required this.onMembers,
    required this.onHistory,
    required this.onAudit,
    required this.onProject,
    required this.onSettings,
  });

  final MainView selectedView;
  final VoidCallback onChat;
  final VoidCallback onTeam;
  final VoidCallback onModels;
  final VoidCallback onRoles;
  final VoidCallback onMembers;
  final VoidCallback onHistory;
  final VoidCallback onAudit;
  final VoidCallback onProject;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF050505),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF4F7CFF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white70, width: 2),
            ),
            child: const Text(
              'AI',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _SidebarButton(
                    icon: Icons.chat_bubble_rounded,
                    label: '消息',
                    selected: selectedView == MainView.chat,
                    onPressed: onChat,
                  ),
                  _SidebarButton(
                    icon: Icons.groups_rounded,
                    label: '团队',
                    selected: selectedView == MainView.teams,
                    onPressed: onTeam,
                  ),
                  _SidebarButton(
                    icon: Icons.memory_rounded,
                    label: '模型',
                    selected: selectedView == MainView.models,
                    onPressed: onModels,
                  ),
                  _SidebarButton(
                    icon: Icons.badge_rounded,
                    label: '角色',
                    selected: selectedView == MainView.roles,
                    onPressed: onRoles,
                  ),
                  _SidebarButton(
                    icon: Icons.manage_accounts_rounded,
                    label: '成员',
                    selected: selectedView == MainView.members,
                    onPressed: onMembers,
                  ),
                  _SidebarButton(
                    icon: Icons.history_rounded,
                    label: '历史',
                    selected: selectedView == MainView.history,
                    onPressed: onHistory,
                  ),
                  _SidebarButton(
                    icon: Icons.receipt_long_rounded,
                    label: '审计',
                    selected: selectedView == MainView.audit,
                    onPressed: onAudit,
                  ),
                  _SidebarButton(
                    icon: Icons.folder_copy_rounded,
                    label: '项目',
                    selected: selectedView == MainView.project,
                    onPressed: onProject,
                  ),
                ],
              ),
            ),
          ),
          _SidebarButton(
            icon: Icons.settings_rounded,
            label: '设置',
            selected: selectedView == MainView.settings,
            onPressed: onSettings,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: IconButton(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor:
                selected ? const Color(0xFF3B82F6) : Colors.transparent,
            foregroundColor: selected ? Colors.white : const Color(0xFFB8C2D8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: Icon(icon),
        ),
      ),
    );
  }
}
