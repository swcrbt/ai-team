import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/domain.dart';
import '../dialogs/config_dialogs.dart';
import 'management_components.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
  });

  final AppController controller;

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
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
                ManagementPanel(
                  key: sectionKeys['导入导出'],
                  title: '导入导出',
                  icon: Icons.ios_share_rounded,
                  action: IconButton(
                    tooltip: '导入 / 导出配置',
                    onPressed: () => showExportDialog(context, controller),
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                  child: const Text('配置文件和密钥导出选项集中在这里管理。'),
                ),
                ManagementPanel(
                  title: '任务轮次',
                  icon: Icons.account_tree_rounded,
                  child: Column(
                    children: controller.currentTaskAssignments.isEmpty
                        ? [
                            ManagementKeyValueRow(
                              label: '当前轮次',
                              value:
                                  '第 ${controller.currentConversation.currentRound} 轮',
                            ),
                            const Text('暂无成员任务'),
                          ]
                        : controller.currentTaskAssignments
                            .map(
                              (assignment) =>
                                  TaskAssignmentCard(assignment: assignment),
                            )
                            .toList(),
                  ),
                ),
                ManagementPanel(
                  key: sectionKeys['命令请求'],
                  title: '命令请求',
                  icon: Icons.terminal_rounded,
                  action: IconButton(
                    tooltip: '创建命令请求',
                    onPressed: () => showCommandDialog(context, controller),
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
