import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/domain.dart';
import 'dialog_frame.dart';

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
      builder: (context, setDialogState) => ConfigDialog(
        title: member == null ? '新增团队成员' : '编辑团队成员',
        subtitle: '绑定成员名称、执行优先级、角色和模型。',
        icon: Icons.person_add_alt_1_rounded,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (validationError != null) DialogError(validationError!),
            DialogSection(
              title: '成员信息',
              child: Column(
                children: [
                  DialogField(controller: name, label: '成员名称'),
                  DialogField(controller: priority, label: '执行优先级'),
                  DropdownButtonFormField<String>(
                    initialValue: roleId,
                    decoration: dialogInputDecoration('角色'),
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
                    decoration: dialogInputDecoration('模型'),
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
