import 'dart:collection';

import '../core/domain.dart';
import '../core/model/reasoning_effort.dart';
import 'app_controller_helpers.dart';
import 'state_lookup.dart';

typedef ConfigurationStateReader = AppState Function();
typedef ConfigurationStateCommitter = void Function(AppState state);
typedef CurrentTeamReader = Team Function();
typedef SelectionReader = String? Function();
typedef SelectionUpdater = void Function({
  required String activeTeamId,
  required String selectedConversationId,
});
typedef ConfigurationNotifier = void Function();

class ConfigurationController {
  const ConfigurationController({
    required this.readState,
    required this.commit,
    required this.currentTeam,
    required this.activeTeamId,
    required this.selectedConversationId,
    required this.updateSelection,
    required this.notify,
  });

  final ConfigurationStateReader readState;
  final ConfigurationStateCommitter commit;
  final CurrentTeamReader currentTeam;
  final SelectionReader activeTeamId;
  final SelectionReader selectedConversationId;
  final SelectionUpdater updateSelection;
  final ConfigurationNotifier notify;

  AppState get state => readState();

  Team addTeam({
    required String name,
    required List<String> memberIds,
    TeamCollaborationMode collaborationMode = TeamCollaborationMode.serial,
  }) {
    final secretary = state.members.firstWhere(
      (member) => member.isSecretary,
      orElse: () => throw StateError('缺少默认秘书成员'),
    );
    final normalizedMemberIds = normalizeTeamMemberIds(
      state,
      secretaryMemberId: secretary.id,
      memberIds: memberIds,
    );
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final team = Team(
      id: 'team-$timestamp',
      name: validateTeamName(name),
      memberIds: normalizedMemberIds,
      secretaryMemberId: secretary.id,
      collaborationMode: collaborationMode,
    );
    commit(
      state.copyWith(
        teams: [...state.teams, team],
        conversations: [
          ...state.conversations,
          createTeamConversation(team),
        ],
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-$timestamp',
            action: 'team_added',
            detail: team.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
    return team;
  }

  void updateTeam({
    required String teamId,
    required String name,
    required List<String> memberIds,
    required TeamCollaborationMode collaborationMode,
  }) {
    final existing = requireTeam(state, teamId);
    final updatedTeam = existing.copyWith(
      name: validateTeamName(name),
      memberIds: normalizeTeamMemberIds(
        state,
        secretaryMemberId: existing.secretaryMemberId,
        memberIds: memberIds,
      ),
      collaborationMode: collaborationMode,
    );
    final updatedMemberIds = updatedTeam.memberIds.toSet();
    final retainedConversations = state.conversations.where((conversation) {
      if (conversation.teamId != teamId || conversation.memberId == null) {
        return true;
      }
      return updatedMemberIds.contains(conversation.memberId);
    }).toList();

    commit(
      state.copyWith(
        teams: state.teams
            .map((team) => team.id == teamId ? updatedTeam : team)
            .toList(),
        conversations: retainedConversations,
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'team_updated',
            detail: updatedTeam.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
    final validConversationIds =
        state.conversations.map((conversation) => conversation.id).toSet();
    final selectedId = selectedConversationId();
    if (selectedId != null && !validConversationIds.contains(selectedId)) {
      updateSelection(
        activeTeamId: teamId,
        selectedConversationId: requireTeamConversation(state, teamId).id,
      );
      notify();
    }
  }

  void deleteTeam(String teamId) {
    final team = requireTeam(state, teamId);
    if (state.teams.length <= 1) {
      throw StateError('至少保留一个团队');
    }
    final removedConversationIds = state.conversations
        .where((conversation) => conversation.teamId == teamId)
        .map((conversation) => conversation.id)
        .toSet();
    final remainingTeams =
        state.teams.where((item) => item.id != teamId).toList();
    final fallbackTeam = remainingTeams.first;

    commit(
      state.copyWith(
        teams: remainingTeams,
        conversations: state.conversations
            .where((conversation) => conversation.teamId != teamId)
            .toList(),
        queuedTasks: state.queuedTasks
            .where(
                (task) => !removedConversationIds.contains(task.conversationId))
            .toList(),
        taskAssignments: state.taskAssignments
            .where((assignment) =>
                !removedConversationIds.contains(assignment.conversationId))
            .toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'team_deleted',
            detail: team.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
    final activeId = activeTeamId();
    final selectedId = selectedConversationId();
    if (activeId == teamId ||
        (selectedId != null && removedConversationIds.contains(selectedId))) {
      updateSelection(
        activeTeamId: fallbackTeam.id,
        selectedConversationId:
            requireTeamConversation(state, fallbackTeam.id).id,
      );
      notify();
    }
  }

  void addModel(ModelProfile model) {
    validateModel(model);
    commit(state.copyWith(models: [...state.models, model]));
  }

  void updateModel(ModelProfile model) {
    validateModel(model);
    requireModel(state, model.id);
    commit(
      state.copyWith(
        models: state.models
            .map((item) => item.id == model.id ? model : item)
            .toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'model_updated',
            detail: model.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  void deleteModel(String modelId) {
    final model = requireModel(state, modelId);
    if (state.members.any((member) => member.modelId == modelId)) {
      throw StateError('模型正在被团队成员使用，不能删除');
    }
    commit(
      state.copyWith(
        models: state.models.where((item) => item.id != modelId).toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'model_deleted',
            detail: model.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  void addRole(RoleTemplate role) {
    validateRole(role);
    commit(state.copyWith(roles: [...state.roles, role]));
  }

  void updateRole(RoleTemplate role) {
    validateRole(role);
    requireRole(state, role.id);
    commit(
      state.copyWith(
        roles: state.roles
            .map((item) => item.id == role.id ? role : item)
            .toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'role_updated',
            detail: role.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  void deleteRole(String roleId) {
    final role = requireRole(state, roleId);
    if (state.members.any((member) => member.roleId == roleId)) {
      throw StateError('角色正在被团队成员使用，不能删除');
    }
    commit(
      state.copyWith(
        roles: state.roles.where((item) => item.id != roleId).toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'role_deleted',
            detail: role.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  void addMember(TeamMember member) {
    validateMember(state, member);
    final team = currentTeam();
    final updatedTeam = team.copyWith(
      memberIds: [...team.memberIds, member.id],
    );
    commit(
      state.copyWith(
        members: [...state.members, member],
        teams: state.teams
            .map((item) => item.id == updatedTeam.id ? updatedTeam : item)
            .toList(),
      ),
    );
  }

  void updateMember(TeamMember member) {
    validateMember(state, member);
    final existing = requireMember(state, member.id);
    commit(
      state.copyWith(
        members: state.members
            .map((item) => item.id == member.id
                ? member.copyWith(isSecretary: existing.isSecretary)
                : item)
            .toList(),
        conversations: state.conversations
            .map((conversation) => conversation.memberId == member.id
                ? Conversation(
                    id: conversation.id,
                    title: member.name,
                    teamId: conversation.teamId,
                    memberId: conversation.memberId,
                    messages: conversation.messages,
                    currentRound: conversation.currentRound,
                    status: conversation.status,
                  )
                : conversation)
            .toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'member_updated',
            detail: member.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  void deleteMember(String memberId) {
    final member = requireMember(state, memberId);
    if (member.isSecretary || currentTeam().secretaryMemberId == memberId) {
      throw StateError('默认秘书不能删除');
    }
    commit(
      state.copyWith(
        members: state.members.where((item) => item.id != memberId).toList(),
        conversations: state.conversations
            .where((conversation) => conversation.memberId != memberId)
            .toList(),
        teams: state.teams
            .map((team) => team.copyWith(
                  memberIds:
                      team.memberIds.where((id) => id != memberId).toList(),
                ))
            .toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'member_deleted',
            detail: member.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }
}

String validateTeamName(String name) {
  final trimmedName = name.trim();
  if (trimmedName.isEmpty) {
    throw ArgumentError('团队名称不能为空');
  }
  return trimmedName;
}

List<String> normalizeTeamMemberIds(
  AppState state, {
  required String secretaryMemberId,
  required List<String> memberIds,
}) {
  final normalizedMemberIds = <String>[
    secretaryMemberId,
    ...memberIds.where((id) => id != secretaryMemberId),
  ];
  for (final memberId in normalizedMemberIds) {
    requireMember(state, memberId);
  }
  return LinkedHashSet<String>.from(normalizedMemberIds).toList();
}

void validateModel(ModelProfile model) {
  if (model.name.trim().isEmpty) {
    throw ArgumentError('模型名称不能为空');
  }
  if (model.modelName.trim().isEmpty) {
    throw ArgumentError('模型标识不能为空');
  }
  if (model.apiKey.trim().isEmpty) {
    throw ArgumentError('API Key 不能为空');
  }
  final uri = Uri.tryParse(model.baseUrl.trim());
  if (uri == null ||
      !uri.hasScheme ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    throw ArgumentError('Base URL 必须是有效的 http 或 https 地址');
  }
  if (model.temperature < 0 || model.temperature > 2) {
    throw ArgumentError('温度必须在 0 到 2 之间');
  }
  if (model.maxTokens <= 0) {
    throw ArgumentError('最大 Token 必须大于 0');
  }
  final reasoningEffort = model.reasoningEffort?.trim();
  if (reasoningEffort != null &&
      reasoningEffort.isNotEmpty &&
      !reasoningEffortValues.contains(reasoningEffort)) {
    throw ArgumentError('深度思考档位无效');
  }
}

void validateRole(RoleTemplate role) {
  if (role.name.trim().isEmpty) {
    throw ArgumentError('角色名称不能为空');
  }
  if (role.identityPrompt.trim().isEmpty) {
    throw ArgumentError('角色身份提示词不能为空');
  }
  if (role.goalPrompt.trim().isEmpty) {
    throw ArgumentError('角色目标提示词不能为空');
  }
  if (role.constraintPrompt.trim().isEmpty) {
    throw ArgumentError('角色约束提示词不能为空');
  }
  if (role.outputFormatPrompt.trim().isEmpty) {
    throw ArgumentError('角色输出格式提示词不能为空');
  }
  if (role.commandPolicy.allowedCommands
      .every((command) => command.trim().isEmpty)) {
    throw ArgumentError('至少需要一个允许命令');
  }
}

void validateMember(AppState state, TeamMember member) {
  if (member.name.trim().isEmpty) {
    throw ArgumentError('成员名称不能为空');
  }
  requireRole(state, member.roleId);
  requireModel(state, member.modelId);
}
