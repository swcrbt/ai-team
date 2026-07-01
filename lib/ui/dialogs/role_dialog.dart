import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/domain.dart';
import 'dialog_frame.dart';
import 'dialog_helpers.dart';

Future<void> showRoleDialog(
  BuildContext context,
  AppController controller, {
  RoleTemplate? role,
}) async {
  final name = TextEditingController(text: role?.name ?? '');
  final description = TextEditingController(
    text: role?.description ?? '自定义角色',
  );
  final identity = TextEditingController(text: role?.identityPrompt ?? '');
  final goal = TextEditingController(
    text: role?.goalPrompt ?? '按团队目标完成任务。',
  );
  final constraint = TextEditingController(
    text: role?.constraintPrompt ?? '遵守权限配置，不直接写入文件。',
  );
  final outputFormat = TextEditingController(
    text: role?.outputFormatPrompt ?? '输出结论、证据和下一步。',
  );
  final allowedCommands = TextEditingController(
    text: (role?.commandPolicy.allowedCommands ??
            const ['flutter test', 'dart analyze'])
        .join('\n'),
  );
  final blockedCommands = TextEditingController(
    text: (role?.commandPolicy.blockedCommands ?? const ['rm', 'sudo'])
        .join('\n'),
  );
  final allowedDirectories = TextEditingController(
    text: (role?.commandPolicy.allowedDirectories ?? const []).join('\n'),
  );
  var canReadProject = role?.canReadProject ?? true;
  var canProposePatch = role?.canProposePatch ?? true;
  var requiresConfirmation = role?.commandPolicy.requiresConfirmation ?? true;
  String? validationError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => ConfigDialog(
        title: role == null ? '新增角色配置' : '编辑角色配置',
        subtitle: '定义角色提示词、命令策略和项目权限。',
        icon: Icons.badge_rounded,
        width: 560,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (validationError != null) DialogError(validationError!),
            DialogSection(
              title: '角色提示词',
              child: Column(
                children: [
                  DialogField(controller: name, label: '角色名称'),
                  DialogField(controller: description, label: '角色描述'),
                  DialogField(
                    controller: identity,
                    label: '身份提示词',
                    minLines: 2,
                    maxLines: 4,
                  ),
                  DialogField(
                    controller: goal,
                    label: '目标提示词',
                    minLines: 2,
                    maxLines: 4,
                  ),
                  DialogField(
                    controller: constraint,
                    label: '约束提示词',
                    minLines: 2,
                    maxLines: 4,
                  ),
                  DialogField(
                    controller: outputFormat,
                    label: '输出格式提示词',
                    minLines: 2,
                    maxLines: 4,
                  ),
                ],
              ),
            ),
            DialogSection(
              title: '命令权限',
              child: Column(
                children: [
                  DialogField(
                    controller: allowedCommands,
                    label: '允许命令（一行一个）',
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        '* 表示允许所有通过安全语法、禁止命令和目录检查的命令；仍受确认开关约束。',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  DialogField(
                    controller: blockedCommands,
                    label: '禁止命令（一行一个）',
                    minLines: 2,
                    maxLines: 4,
                  ),
                  DialogField(
                    controller: allowedDirectories,
                    label: '允许目录（一行一个，留空不限）',
                    minLines: 2,
                    maxLines: 4,
                  ),
                  CheckboxListTile(
                    value: requiresConfirmation,
                    onChanged: (value) =>
                        setDialogState(() => requiresConfirmation = value!),
                    title: const Text('命令需要确认'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    value: canReadProject,
                    onChanged: (value) =>
                        setDialogState(() => canReadProject = value!),
                    title: const Text('允许读取项目'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    value: canProposePatch,
                    onChanged: (value) =>
                        setDialogState(() => canProposePatch = value!),
                    title: const Text('允许生成补丁'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final next = role == null
                    ? RoleTemplate(
                        id: 'role-${DateTime.now().microsecondsSinceEpoch}',
                        name: name.text.trim(),
                        description: description.text.trim(),
                        identityPrompt: identity.text.trim(),
                        goalPrompt: goal.text.trim(),
                        constraintPrompt: constraint.text.trim(),
                        outputFormatPrompt: outputFormat.text.trim(),
                        commandPolicy: CommandPolicy(
                          allowedCommands:
                              splitDialogLines(allowedCommands.text),
                          blockedCommands:
                              splitDialogLines(blockedCommands.text),
                          allowedDirectories:
                              splitDialogLines(allowedDirectories.text),
                          requiresConfirmation: requiresConfirmation,
                        ),
                        canReadProject: canReadProject,
                        canProposePatch: canProposePatch,
                      )
                    : role.copyWith(
                        name: name.text.trim(),
                        description: description.text.trim(),
                        identityPrompt: identity.text.trim(),
                        goalPrompt: goal.text.trim(),
                        constraintPrompt: constraint.text.trim(),
                        outputFormatPrompt: outputFormat.text.trim(),
                        commandPolicy: CommandPolicy(
                          allowedCommands:
                              splitDialogLines(allowedCommands.text),
                          blockedCommands:
                              splitDialogLines(blockedCommands.text),
                          allowedDirectories:
                              splitDialogLines(allowedDirectories.text),
                          requiresConfirmation: requiresConfirmation,
                        ),
                        canReadProject: canReadProject,
                        canProposePatch: canProposePatch,
                      );
                if (role == null) {
                  controller.addRole(next);
                } else {
                  controller.updateRole(next);
                }
                Navigator.pop(context);
              } catch (exception) {
                setDialogState(() => validationError = exception.toString());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}
