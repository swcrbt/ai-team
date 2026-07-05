import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/domain.dart';
import 'dialog_frame.dart';
import 'dialog_helpers.dart';

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
      builder: (context, setDialogState) => ConfigDialog(
        title: team == null ? '新增团队' : '编辑团队',
        subtitle: '配置团队名称、协同方式和参与成员。',
        icon: Icons.groups_rounded,
        width: 560,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null) DialogError(error!),
            DialogSection(
              title: '基础信息',
              child: DialogField(
                controller: nameController,
                label: '团队名称',
              ),
            ),
            DialogSection(
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
            DialogSection(
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
                            '${dialogRoleName(controller.state, member.roleId)} · ${dialogModelName(controller.state, member.modelId)}',
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
