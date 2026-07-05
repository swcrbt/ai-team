import '../core/domain.dart';

int queuedTaskSort(QueuedTask a, QueuedTask b) {
  final priority = b.priority.compareTo(a.priority);
  if (priority != 0) {
    return priority;
  }
  return a.createdAt.compareTo(b.createdAt);
}

QueuedTask? firstQueuedTaskOrNull(List<QueuedTask> tasks) {
  if (tasks.isEmpty) {
    return null;
  }
  return tasks.first;
}

String initialConversationId(AppState state) {
  if (state.queuedTasks.isNotEmpty) {
    return state.queuedTasks.first.conversationId;
  }
  return state.conversations
      .firstWhere(
        (conversation) => conversation.memberId != null,
        orElse: () => state.conversations.first,
      )
      .id;
}

String? normalizeGeneratedConversationTitle(
  String value, {
  required Conversation conversation,
  required String firstUserMessage,
}) {
  final title = value
      .trim()
      .split(RegExp(r'[\r\n]+'))
      .first
      .trim()
      .replaceAll(RegExp(r"""^["“”'‘’]+|["“”'‘’]+$"""), '')
      .trim();
  if (title.isEmpty ||
      title == firstUserMessage.trim() ||
      title == conversationPreview(conversation).trim()) {
    return null;
  }
  return title.length > 32 ? title.substring(0, 32) : title;
}

String conversationPreview(Conversation conversation) {
  if (conversation.messages.isEmpty) {
    return '暂无消息';
  }
  final message = conversation.messages.last;
  return '${message.authorName}: ${message.content}'.replaceAll('\n', ' ');
}

Conversation createTeamConversation(Team team) {
  return Conversation(
    id: 'conv-${team.id}',
    title: '团队会话',
    teamId: team.id,
    memberId: null,
    messages: [
      ChatMessage(
        id: 'msg-welcome-${team.id}',
        authorName: '秘书',
        memberId: team.secretaryMemberId,
        content: '把开发任务发到这里，我会分配给团队成员并汇总结果。',
        createdAt: DateTime.now(),
      ),
    ],
  );
}

Conversation createMemberConversation(String teamId, TeamMember member) {
  return Conversation(
    id: 'conv-$teamId-${member.id}',
    title: member.name,
    teamId: teamId,
    memberId: member.id,
    messages: [
      ChatMessage(
        id: 'msg-welcome-$teamId-${member.id}',
        authorName: member.name,
        memberId: member.id,
        content: '这里是和${member.name}的独立会话。',
        createdAt: DateTime.now(),
      ),
    ],
  );
}

bool isGeneratedWelcomeOnlyMemberConversation(Conversation conversation) {
  final memberId = conversation.memberId;
  if (memberId == null || conversation.teamId == 'team-default') {
    return false;
  }
  if (conversation.id != 'conv-${conversation.teamId}-$memberId' ||
      conversation.messages.length != 1) {
    return false;
  }
  final message = conversation.messages.single;
  return message.id == 'msg-welcome-${conversation.teamId}-$memberId' &&
      message.memberId == memberId;
}

String pathBasename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final trimmed = normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final index = trimmed.lastIndexOf('/');
  return index >= 0 ? trimmed.substring(index + 1) : trimmed;
}
