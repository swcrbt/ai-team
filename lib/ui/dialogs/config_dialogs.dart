import 'dart:io';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/domain.dart';
import '../../core/model_gateway.dart';

Future<void> showTeamDialog(
  BuildContext context,
  AppController controller, {
  Team? team,
}) async {
  final nameController = TextEditingController(text: team?.name ?? '');
  var collaborationMode =
      team?.collaborationMode ?? TeamCollaborationMode.serial;
  final selectedMemberIds = team == null
      ? {
          for (final member in controller.state.members)
            if (!member.isSecretary) member.id,
        }
      : team.memberIds.where((memberId) {
          final member = controller.state.members.firstWhere(
            (item) => item.id == memberId,
          );
          return !member.isSecretary;
        }).toSet();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => _ConfigDialog(
        title: team == null ? '新增团队' : '编辑团队',
        subtitle: '配置团队名称、协同方式和参与成员。',
        icon: Icons.groups_rounded,
        width: 560,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null) _DialogError(error!),
            _DialogSection(
              title: '基础信息',
              child: _DialogField(
                controller: nameController,
                label: '团队名称',
              ),
            ),
            _DialogSection(
              title: '协同模式',
              child: Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<TeamCollaborationMode>(
                  segments: const [
                    ButtonSegment(
                      value: TeamCollaborationMode.serial,
                      label: Text('串行'),
                    ),
                    ButtonSegment(
                      value: TeamCollaborationMode.parallel,
                      label: Text('并行'),
                    ),
                  ],
                  selected: {collaborationMode},
                  onSelectionChanged: (selection) {
                    setDialogState(
                      () => collaborationMode = selection.single,
                    );
                  },
                ),
              ),
            ),
            _DialogSection(
              title: '团队成员',
              child: Column(
                children: [
                  ...controller.state.members
                      .where((member) => !member.isSecretary)
                      .map(
                        (member) => CheckboxListTile(
                          value: selectedMemberIds.contains(member.id),
                          onChanged: (value) {
                            setDialogState(() {
                              if (value ?? false) {
                                selectedMemberIds.add(member.id);
                              } else {
                                selectedMemberIds.remove(member.id);
                              }
                            });
                          },
                          title: Text(member.name),
                          subtitle: Text(
                            '${_roleName(controller.state, member.roleId)} · ${_modelName(controller.state, member.modelId)}',
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '默认秘书会自动加入每个团队。',
                      style: TextStyle(color: Color(0xFF667085)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              try {
                if (team == null) {
                  controller.addTeam(
                    name: nameController.text,
                    memberIds: selectedMemberIds.toList(),
                    collaborationMode: collaborationMode,
                  );
                } else {
                  controller.updateTeam(
                    teamId: team.id,
                    name: nameController.text,
                    memberIds: selectedMemberIds.toList(),
                    collaborationMode: collaborationMode,
                  );
                }
                FocusScope.of(context).unfocus();
                Navigator.of(context).pop();
              } catch (exception) {
                setDialogState(() => error = exception.toString());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showModelDialog(
  BuildContext context,
  AppController controller, {
  ModelProfile? model,
}) async {
  final name = TextEditingController(text: model?.name ?? '');
  final baseUrl = TextEditingController(
    text: model?.baseUrl ?? 'https://api.openai.com/v1',
  );
  final modelName = TextEditingController(text: model?.modelName ?? '');
  final apiKey = TextEditingController(text: model?.apiKey ?? '');
  final temperature = TextEditingController(
    text: (model?.temperature ?? 0.4).toString(),
  );
  final maxTokens = TextEditingController(
    text: (model?.maxTokens ?? 1600).toString(),
  );
  var streaming = model?.streaming ?? true;
  var reasoningEffort = model?.reasoningEffort ?? reasoningEffortOffValue;
  String? validationError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => _ConfigDialog(
        title: model == null ? '新增模型配置' : '编辑模型配置',
        subtitle: '维护 OpenAI 兼容模型、密钥和请求参数。',
        icon: Icons.memory_rounded,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (validationError != null) _DialogError(validationError!),
            _DialogSection(
              title: '基础信息',
              child: Column(
                children: [
                  _DialogField(controller: name, label: '名称'),
                  _DialogField(controller: baseUrl, label: 'Base URL'),
                  _DialogField(controller: modelName, label: '模型名称'),
                  _DialogField(
                    controller: apiKey,
                    label: 'API Key',
                    obscure: true,
                  ),
                ],
              ),
            ),
            _DialogSection(
              title: '请求参数',
              child: Column(
                children: [
                  SwitchListTile(
                    value: streaming,
                    onChanged: (value) =>
                        setDialogState(() => streaming = value),
                    title: const Text('流式输出'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: reasoningEffort,
                    decoration: _dialogInputDecoration('深度思考'),
                    items: [
                      for (final value in [
                        reasoningEffortOffValue,
                        ...reasoningEffortValues,
                      ])
                        DropdownMenuItem(
                          value: value,
                          child: Text(reasoningEffortLabels[value] ?? value),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() => reasoningEffort = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  _DialogField(controller: temperature, label: '温度 0-2'),
                  _DialogField(controller: maxTokens, label: '最大 Token'),
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
                final parsedTemperature = double.tryParse(
                  temperature.text.trim(),
                );
                final parsedMaxTokens = int.tryParse(maxTokens.text.trim());
                if (parsedTemperature == null || parsedMaxTokens == null) {
                  throw ArgumentError('温度和最大 Token 必须是数字');
                }
                final next = ModelProfile(
                  id: model?.id ??
                      'model-${DateTime.now().microsecondsSinceEpoch}',
                  name: name.text.trim(),
                  baseUrl: baseUrl.text.trim(),
                  modelName: modelName.text.trim(),
                  apiKey: apiKey.text.trim(),
                  streaming: streaming,
                  temperature: parsedTemperature,
                  maxTokens: parsedMaxTokens,
                  reasoningEffort: reasoningEffort == reasoningEffortOffValue
                      ? null
                      : reasoningEffort,
                );
                if (model == null) {
                  controller.addModel(next);
                } else {
                  controller.updateModel(next);
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
      builder: (context, setDialogState) => _ConfigDialog(
        title: role == null ? '新增角色配置' : '编辑角色配置',
        subtitle: '定义角色提示词、命令策略和项目权限。',
        icon: Icons.badge_rounded,
        width: 560,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (validationError != null) _DialogError(validationError!),
            _DialogSection(
              title: '角色提示词',
              child: Column(
                children: [
                  _DialogField(controller: name, label: '角色名称'),
                  _DialogField(controller: description, label: '角色描述'),
                  _DialogField(
                    controller: identity,
                    label: '身份提示词',
                    minLines: 2,
                    maxLines: 4,
                  ),
                  _DialogField(
                    controller: goal,
                    label: '目标提示词',
                    minLines: 2,
                    maxLines: 4,
                  ),
                  _DialogField(
                    controller: constraint,
                    label: '约束提示词',
                    minLines: 2,
                    maxLines: 4,
                  ),
                  _DialogField(
                    controller: outputFormat,
                    label: '输出格式提示词',
                    minLines: 2,
                    maxLines: 4,
                  ),
                ],
              ),
            ),
            _DialogSection(
              title: '命令权限',
              child: Column(
                children: [
                  _DialogField(
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
                  _DialogField(
                    controller: blockedCommands,
                    label: '禁止命令（一行一个）',
                    minLines: 2,
                    maxLines: 4,
                  ),
                  _DialogField(
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
                          allowedCommands: _splitLines(allowedCommands.text),
                          blockedCommands: _splitLines(blockedCommands.text),
                          allowedDirectories:
                              _splitLines(allowedDirectories.text),
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
                          allowedCommands: _splitLines(allowedCommands.text),
                          blockedCommands: _splitLines(blockedCommands.text),
                          allowedDirectories:
                              _splitLines(allowedDirectories.text),
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

Future<void> showMemberDialog(
  BuildContext context,
  AppController controller, {
  TeamMember? member,
}) async {
  final name = TextEditingController(text: member?.name ?? '');
  final priority = TextEditingController(
    text: (member?.executionPriority ?? 0).toString(),
  );
  var roleId = member?.roleId ?? controller.state.roles.first.id;
  var modelId = member?.modelId ?? controller.state.models.first.id;
  String? validationError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => _ConfigDialog(
        title: member == null ? '新增团队成员' : '编辑团队成员',
        subtitle: '绑定成员名称、执行优先级、角色和模型。',
        icon: Icons.person_add_alt_1_rounded,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (validationError != null) _DialogError(validationError!),
            _DialogSection(
              title: '成员信息',
              child: Column(
                children: [
                  _DialogField(controller: name, label: '成员名称'),
                  _DialogField(controller: priority, label: '执行优先级'),
                  DropdownButtonFormField<String>(
                    initialValue: roleId,
                    decoration: _dialogInputDecoration('角色'),
                    items: controller.state.roles
                        .map(
                          (role) => DropdownMenuItem(
                            value: role.id,
                            child: Text(role.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() => roleId = value!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: modelId,
                    decoration: _dialogInputDecoration('模型'),
                    items: controller.state.models
                        .map(
                          (model) => DropdownMenuItem(
                            value: model.id,
                            child: Text(model.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => modelId = value!),
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
                final executionPriority = int.tryParse(priority.text.trim());
                if (executionPriority == null) {
                  throw ArgumentError('执行优先级必须是整数');
                }
                final next = TeamMember(
                  id: member?.id ??
                      'member-${DateTime.now().microsecondsSinceEpoch}',
                  name: name.text.trim(),
                  roleId: roleId,
                  modelId: modelId,
                  isSecretary: member?.isSecretary ?? false,
                  executionPriority: executionPriority,
                );
                if (member == null) {
                  controller.addMember(next);
                } else {
                  controller.updateMember(next);
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
      builder: (context, setDialogState) => _ConfigDialog(
        title: '创建补丁提案',
        subtitle: '从本地工作区读取文件并生成受控补丁提案。',
        icon: Icons.difference_rounded,
        width: 580,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (validationError != null) _DialogError(validationError!),
            _DialogSection(
              title: '提案范围',
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: workspaceId,
                    decoration: _dialogInputDecoration('工作区'),
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
                    decoration: _dialogInputDecoration('提案成员'),
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
                  _DialogField(controller: relativePath, label: '相对路径'),
                ],
              ),
            ),
            _DialogSection(
              title: '目标内容',
              child: TextField(
                controller: proposedContent,
                minLines: 8,
                maxLines: 12,
                decoration: _dialogInputDecoration('目标文件内容').copyWith(
                  alignLabelWithHint: true,
                ),
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
      builder: (context, setDialogState) => _ConfigDialog(
        title: '工作区文件',
        subtitle: '浏览当前本地工作区中可用于读取和补丁提案的文件。',
        icon: Icons.folder_open_rounded,
        width: 580,
        body: SizedBox(
          height: 420,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: workspaceId,
                decoration: _dialogInputDecoration('工作区'),
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
                  filesFuture =
                      controller.listWorkspaceFiles(workspaceId: workspaceId);
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
                          child: _DialogError('读取文件列表失败：${snapshot.error}'),
                        );
                      }
                      final files = snapshot.data ?? const [];
                      if (files.isEmpty) {
                        return const Center(child: Text('没有可显示的文件'));
                      }
                      return ListView.separated(
                        itemCount: files.length,
                        separatorBuilder: (context, index) => const Divider(
                          height: 1,
                          color: Color(0xFFE5E7EB),
                        ),
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
      builder: (context, setDialogState) => _ConfigDialog(
        title: '创建命令请求',
        subtitle: '为成员创建需要审批或执行的本地命令请求。',
        icon: Icons.terminal_rounded,
        body: _DialogSection(
          title: '命令信息',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: memberId,
                decoration: _dialogInputDecoration('成员'),
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
              _DialogField(controller: workingDirectory, label: '工作目录'),
              _DialogField(controller: command, label: '命令'),
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
      builder: (context, setDialogState) => _ConfigDialog(
        title: '导入 / 导出配置',
        subtitle: '管理本机配置文件，密钥导出需要明确确认。',
        icon: Icons.ios_share_rounded,
        width: 560,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogSection(
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
                  subtitle: const Text('包含密钥的文件只适合本机迁移，请谨慎保存。'),
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
            const _DialogSection(
              title: '文件操作',
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '导入会读取选择的 JSON 配置；导出会保存当前本机配置。',
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

class _ConfigDialog extends StatelessWidget {
  const _ConfigDialog({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.body,
    required this.actions,
    this.width = 520,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget body;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    final availableHeight = MediaQuery.sizeOf(context).height - 48;
    return Dialog(
      key: const ValueKey('config-dialog-frame'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      elevation: 18,
      shadowColor: const Color(0x331F2937),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFDDE5F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: width,
          maxHeight: availableHeight < 360 ? 360 : availableHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const ValueKey('config-dialog-header'),
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFDDE5F0)),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(icon, color: const Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF667085),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                key: const ValueKey('config-dialog-body'),
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
                child: body,
              ),
            ),
            Container(
              key: const ValueKey('config-dialog-actions'),
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFDDE5F0))),
              ),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                spacing: 10,
                overflowSpacing: 8,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogSection extends StatelessWidget {
  const _DialogSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _DialogError extends StatelessWidget {
  const _DialogError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('config-dialog-error'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        border: Border.all(color: const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: Color(0xFFBE123C),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFBE123C),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void runConfigAction(
  BuildContext context,
  VoidCallback action,
) {
  try {
    action();
  } catch (exception) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(exception.toString())),
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    this.obscure = false,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        minLines: obscure ? 1 : minLines,
        maxLines: obscure ? 1 : maxLines,
        decoration: _dialogInputDecoration(label),
      ),
    );
  }
}

InputDecoration _dialogInputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFDDE5F0)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
    ),
  );
}

List<String> _splitLines(String text) => text
    .split(RegExp(r'[\r\n,]+'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();

String _roleName(AppState state, String roleId) =>
    state.roles.firstWhere((role) => role.id == roleId).name;

String _modelName(AppState state, String modelId) =>
    state.models.firstWhere((model) => model.id == modelId).name;
