import '../core/domain.dart';

Conversation conversationByIdOrThrow(AppState state, String conversationId) {
  return state.conversations.firstWhere(
    (conversation) => conversation.id == conversationId,
    orElse: () => throw StateError('会话不存在: $conversationId'),
  );
}

Conversation? conversationByIdOrNull(AppState state, String conversationId) {
  for (final conversation in state.conversations) {
    if (conversation.id == conversationId) {
      return conversation;
    }
  }
  return null;
}

QueuedTask? queuedTaskByIdOrNull(AppState state, String taskId) {
  for (final task in state.queuedTasks) {
    if (task.id == taskId) {
      return task;
    }
  }
  return null;
}

ModelProfile requireModel(AppState state, String modelId) {
  return state.models.firstWhere(
    (model) => model.id == modelId,
    orElse: () => throw StateError('模型不存在: $modelId'),
  );
}

Team requireTeam(AppState state, String teamId) {
  return state.teams.firstWhere(
    (team) => team.id == teamId,
    orElse: () => throw StateError('团队不存在: $teamId'),
  );
}

Conversation requireTeamConversation(AppState state, String teamId) {
  return state.conversations.firstWhere(
    (conversation) =>
        conversation.teamId == teamId && conversation.memberId == null,
    orElse: () => throw StateError('团队会话不存在: $teamId'),
  );
}

RoleTemplate requireRole(AppState state, String roleId) {
  return state.roles.firstWhere(
    (role) => role.id == roleId,
    orElse: () => throw StateError('角色不存在: $roleId'),
  );
}

TeamMember requireMember(AppState state, String memberId) {
  return state.members.firstWhere(
    (member) => member.id == memberId,
    orElse: () => throw StateError('成员不存在: $memberId'),
  );
}
