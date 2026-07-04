import 'dart:io';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import 'dialog_frame.dart';

Future<void> showWorkspacePatchDialog(
  BuildContext context,
  AppController controller,
) async {
  var workspaceId = controller.state.workspaces.first.id;
  var memberName = controller.currentMembers
      .firstWhere(
        (member) => !member.isSecretary,
        orElse: () => controller.currentMembers.first,
      )
      .name;
  final relativePath = TextEditingController();
  final proposedContent = TextEditingController();
  String? validationError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => ConfigDialog(
        title: '创建补丁提案',
        subtitle: '从项目中读取文件并生成受控补丁提案。',
        icon: Icons.difference_rounded,
        width: 580,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (validationError != null) DialogError(validationError!),
            DialogSection(
              title: '提案范围',
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: workspaceId,
                    decoration: dialogInputDecoration('项目'),
                    items: controller.state.workspaces
                        .map(
                          (workspace) => DropdownMenuItem(
                            value: workspace.id,
                            child: Text(workspace.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => workspaceId = value!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: memberName,
                    decoration: dialogInputDecoration('提案成员'),
                    items: controller.currentMembers
                        .map(
                          (member) => DropdownMenuItem(
                            value: member.name,
                            child: Text(member.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => memberName = value!),
                  ),
                  const SizedBox(height: 12),
                  DialogField(controller: relativePath, label: '相对路径'),
                ],
              ),
            ),
            DialogSection(
              title: '目标内容',
              child: TextField(
                controller: proposedContent,
                minLines: 8,
                maxLines: 12,
                decoration: dialogInputDecoration(
                  '目标文件内容',
                ).copyWith(alignLabelWithHint: true),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton.icon(
            onPressed: () async {
              try {
                final content = await controller.readWorkspaceFile(
                  workspaceId: workspaceId,
                  relativePath: relativePath.text.trim(),
                );
                proposedContent.text = content;
                setDialogState(() => validationError = null);
              } catch (exception) {
                setDialogState(() => validationError = exception.toString());
              }
            },
            icon: const Icon(Icons.file_open_rounded),
            label: const Text('读取文件'),
          ),
          FilledButton.icon(
            onPressed: () async {
              try {
                await controller.proposeWorkspacePatch(
                  workspaceId: workspaceId,
                  relativePath: relativePath.text.trim(),
                  proposedContent: proposedContent.text,
                  memberName: memberName,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                }
              } catch (exception) {
                setDialogState(() => validationError = exception.toString());
              }
            },
            icon: const Icon(Icons.difference_rounded),
            label: const Text('创建补丁'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showWorkspaceFilesDialog(
  BuildContext context,
  AppController controller,
) async {
  var workspaceId = controller.state.workspaces.first.id;
  var filesFuture = controller.listWorkspaceFiles(workspaceId: workspaceId);
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => ConfigDialog(
        title: '项目文件',
        subtitle: '浏览当前项目中可用于读取和补丁提案的文件。',
        icon: Icons.folder_open_rounded,
        width: 580,
        body: SizedBox(
          height: 420,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: workspaceId,
                decoration: dialogInputDecoration('项目'),
                items: controller.state.workspaces
                    .map(
                      (workspace) => DropdownMenuItem(
                        value: workspace.id,
                        child: Text(workspace.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() {
                  workspaceId = value!;
                  filesFuture = controller.listWorkspaceFiles(
                    workspaceId: workspaceId,
                  );
                }),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFDDE5F0)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: FutureBuilder<List<String>>(
                    future: filesFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: DialogError('读取文件列表失败：${snapshot.error}'),
                        );
                      }
                      final files = snapshot.data ?? const [];
                      if (files.isEmpty) {
                        return const Center(child: Text('没有可显示的文件'));
                      }
                      return ListView.separated(
                        itemCount: files.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1, color: Color(0xFFE5E7EB)),
                        itemBuilder: (context, index) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.description_rounded),
                          title: SelectableText(files[index]),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showCommandDialog(
  BuildContext context,
  AppController controller,
) async {
  final command = TextEditingController(text: 'flutter test');
  final workingDirectory = TextEditingController(
    text: controller.state.workspaces.isEmpty
        ? Directory.current.path
        : controller.state.workspaces.first.path,
  );
  var memberId = controller.currentMembers
      .firstWhere(
        (member) => !member.isSecretary,
        orElse: () => controller.currentMembers.first,
      )
      .id;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => ConfigDialog(
        title: '创建命令请求',
        subtitle: '为成员创建需要审批或执行的命令请求。',
        icon: Icons.terminal_rounded,
        body: DialogSection(
          title: '命令信息',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: memberId,
                decoration: dialogInputDecoration('成员'),
                items: controller.currentMembers
                    .map(
                      (member) => DropdownMenuItem(
                        value: member.id,
                        child: Text(member.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => memberId = value!),
              ),
              const SizedBox(height: 12),
              DialogField(controller: workingDirectory, label: '工作目录'),
              DialogField(controller: command, label: '命令'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              controller.requestCommand(
                memberId: memberId,
                command: command.text.trim(),
                workingDirectory: workingDirectory.text.trim(),
              );
              Navigator.pop(context);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showExportDialog(
  BuildContext context,
  AppController controller,
) async {
  var includeSecrets = false;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => ConfigDialog(
        title: '导入 / 导出配置',
        subtitle: '管理应用配置文件，密钥导出需要明确确认。',
        icon: Icons.ios_share_rounded,
        width: 560,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DialogSection(
              title: '导出选项',
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFDDE5F0)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CheckboxListTile(
                  value: includeSecrets,
                  onChanged: (value) =>
                      setDialogState(() => includeSecrets = value!),
                  title: const Text('导出时包含 API Key'),
                  subtitle: const Text('包含密钥的文件只适合受控迁移，请谨慎保存。'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 18),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                border: Border.all(color: const Color(0xFFFED7AA)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '密钥风险提示：启用后导出的 JSON 会包含可用凭证。',
                style: TextStyle(color: Color(0xFF9A3412), height: 1.35),
              ),
            ),
            const DialogSection(
              title: '文件操作',
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '导入会读取选择的 JSON 配置；导出会保存当前应用配置。',
                  style: TextStyle(color: Color(0xFF667085)),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await controller.importConfiguration();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.file_open_rounded),
            label: const Text('从 import.json 导入'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await controller.exportConfiguration(
                includeSecrets: includeSecrets,
              );
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(includeSecrets ? '确认导出密钥' : '导出脱敏配置'),
          ),
        ],
      ),
    ),
  );
}
