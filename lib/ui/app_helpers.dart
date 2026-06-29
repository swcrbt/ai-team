part of '../app.dart';

String _conversationTitle(AppController controller, Conversation conversation) {
  if (conversation.memberId == null) {
    return '群聊 · ${_conversationDisplayTitle(controller, conversation)}';
  }
  return '私聊 · ${_conversationDisplayTitle(controller, conversation)}';
}

String _messageTimeText(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _auditLogTimeText(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}

String _conversationMeta(AppController controller, Conversation conversation) {
  final status = _statusText(conversation.status);
  final members = controller.membersForConversation(conversation.id);
  if (conversation.memberId == null) {
    return '${members.length} 位成员 · 第 ${conversation.currentRound} 轮 · $status';
  }
  final member = members.firstWhere(
    (item) => item.id == conversation.memberId,
  );
  return '${_roleName(controller.state, member.roleId)} · ${_modelName(controller.state, member.modelId)} · $status';
}

String _inputHint(AppController controller, Conversation conversation) {
  if (conversation.memberId == null) {
    return '发给 ${controller.teamForConversation(conversation.id).name}';
  }
  return '发给 ${_conversationSubjectTitle(controller, conversation)}';
}

String _avatarText(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
}

Color _avatarColor(String name) {
  if (name == '秘书') {
    return const Color(0xFF22C55E);
  }
  if (name.contains('测试')) {
    return const Color(0xFFF59E0B);
  }
  if (name.contains('前端')) {
    return const Color(0xFF3B82F6);
  }
  return const Color(0xFF64748B);
}

String _conversationPreview(Conversation conversation) {
  if (conversation.messages.isEmpty) {
    return '暂无消息';
  }
  final message = conversation.messages.last;
  return '${message.authorName}: ${message.content}'.replaceAll('\n', ' ');
}

String _conversationDisplayTitle(
  AppController controller,
  Conversation conversation,
) {
  final title = _distinctConversationTitle(conversation);
  if (title != null) {
    return title;
  }
  if (conversation.messages.isEmpty) {
    return '新会话';
  }
  return _conversationSubjectTitle(controller, conversation);
}

String _conversationSubjectTitle(
  AppController controller,
  Conversation conversation,
) {
  if (conversation.memberId == null) {
    return controller.teamForConversation(conversation.id).name;
  }
  final member = controller.state.members.firstWhere(
    (item) => item.id == conversation.memberId,
  );
  return member.name;
}

String? _distinctConversationTitle(Conversation conversation) {
  final title = conversation.title.trim();
  if (title.isEmpty || title == '团队会话') {
    return null;
  }
  if (conversation.messages.isNotEmpty &&
      _conversationPreview(conversation).trim() == title) {
    return null;
  }
  String? firstUserMessage;
  for (final message in conversation.messages) {
    if (message.isUser) {
      firstUserMessage = message.content.trim();
      break;
    }
  }
  if (firstUserMessage == title) {
    return null;
  }
  return title;
}

String? _normalizeGeneratedConversationTitle(
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
      title == _conversationPreview(conversation).trim()) {
    return null;
  }
  return title.length > 32 ? title.substring(0, 32) : title;
}

String? _normalizedThinkingContent(ChatMessage message) {
  final thinkingContent = message.thinkingContent;
  if (thinkingContent == null || thinkingContent.trim().isEmpty) {
    return null;
  }
  return thinkingContent;
}

String _thinkingTitle(ChatMessage message) {
  final duration = _messageGenerationDurationText(message);
  return switch (message.generationStatus) {
    ChatMessageGenerationStatus.streaming => '思考中… $duration',
    ChatMessageGenerationStatus.failed => '思考失败 · $duration',
    ChatMessageGenerationStatus.stopped => '思考已停止 · $duration',
    ChatMessageGenerationStatus.complete =>
      message.generationDurationMs == null ? '思考过程' : '已完成思考 · $duration',
  };
}

String? _messageInlineGenerationStatus(ChatMessage message) {
  final duration = _messageGenerationDurationText(message);
  return switch (message.generationStatus) {
    ChatMessageGenerationStatus.failed => '失败 · $duration',
    ChatMessageGenerationStatus.stopped => '已停止 · $duration',
    _ => null,
  };
}

bool _isAwaitingFirstModelOutput(ChatMessage message) {
  return !message.isUser &&
      message.generationStatus == ChatMessageGenerationStatus.streaming &&
      message.content.trim().isEmpty &&
      (message.thinkingContent?.trim().isEmpty ?? true);
}

bool _isStreamingThinkingWithoutReplyContent(
  ChatMessage message,
  String? thinkingContent,
) {
  return !message.isUser &&
      message.generationStatus == ChatMessageGenerationStatus.streaming &&
      message.content.trim().isEmpty &&
      thinkingContent != null;
}

String _messageGenerationDurationText(ChatMessage message) {
  final milliseconds =
      message.generationStatus == ChatMessageGenerationStatus.streaming
          ? DateTime.now().difference(message.createdAt).inMilliseconds
          : message.generationDurationMs ?? 0;
  final seconds = (milliseconds / 1000).ceil().clamp(0, 9999);
  return '${seconds}s';
}

IconData _conversationListIcon(
  AppController controller,
  Conversation conversation,
) {
  if (conversation.memberId == null) {
    return Icons.forum_rounded;
  }
  final member = controller.state.members.firstWhere(
    (item) => item.id == conversation.memberId,
  );
  return member.isSecretary
      ? Icons.assignment_ind_rounded
      : Icons.person_rounded;
}

String _conversationListTitle(
  AppController controller,
  Conversation conversation,
) {
  return _conversationDisplayTitle(controller, conversation);
}

String _conversationListSubtitle(
  AppController controller,
  Conversation conversation,
) {
  if (conversation.messages.isEmpty) {
    final prefix = conversation.memberId == null ? '群聊' : '私聊';
    return '$prefix · ${_conversationSubjectTitle(controller, conversation)}';
  }
  if (conversation.memberId == null) {
    return _conversationPreview(conversation);
  }
  final member = controller.state.members.firstWhere(
    (item) => item.id == conversation.memberId,
  );
  return _privateConversationPreview(controller, conversation, member);
}

String? _conversationListBadge(
  AppController controller,
  Conversation conversation,
) {
  if (conversation.memberId == null) {
    return controller.state.teams
        .firstWhere((team) => team.id == conversation.teamId)
        .memberIds
        .length
        .toString();
  }
  final member = controller.state.members.firstWhere(
    (item) => item.id == conversation.memberId,
  );
  return member.isSecretary ? 'BOT' : null;
}

String _privateConversationPreview(
  AppController controller,
  Conversation conversation,
  TeamMember member,
) {
  if (conversation.messages.length > 1) {
    return _conversationPreview(conversation);
  }
  return _roleName(controller.state, member.roleId);
}

String _conversationMenuTitle(
  AppController controller,
  Conversation conversation,
) {
  final title = _conversationDisplayTitle(controller, conversation);
  final subject = _conversationSubjectTitle(controller, conversation);
  if (title == subject) {
    return title;
  }
  return '$title · $subject';
}

List<TeamMember> _typingMembers(
  AppController controller,
  Conversation conversation,
) {
  if (conversation.status != ConversationStatus.running) {
    return const [];
  }
  final streamingMemberIds = conversation.messages
      .where(
        (message) =>
            message.generationStatus == ChatMessageGenerationStatus.streaming &&
            message.memberId != null,
      )
      .map((message) => message.memberId!)
      .toSet();
  final memberId = conversation.memberId;
  if (memberId != null) {
    if (streamingMemberIds.contains(memberId)) {
      return const [];
    }
    return [
      controller.state.members.firstWhere((member) => member.id == memberId),
    ];
  }
  final runningAssignments = controller
      .taskAssignmentsForConversation(conversation.id)
      .where((assignment) => assignment.status == TaskAssignmentStatus.running)
      .toList();
  if (runningAssignments.isEmpty) {
    final members = controller.membersForConversation(conversation.id);
    final fallback = members.firstWhere(
      (member) => !member.isSecretary,
      orElse: () => members.first,
    );
    return streamingMemberIds.contains(fallback.id) ? const [] : [fallback];
  }
  return runningAssignments
      .map(
        (assignment) => controller.state.members.firstWhere(
          (member) => member.id == assignment.memberId,
        ),
      )
      .where((member) => !streamingMemberIds.contains(member.id))
      .toList();
}

int _queuedTaskSort(QueuedTask a, QueuedTask b) {
  final priority = b.priority.compareTo(a.priority);
  if (priority != 0) {
    return priority;
  }
  return a.createdAt.compareTo(b.createdAt);
}

QueuedTask? _firstQueuedTaskOrNull(List<QueuedTask> tasks) {
  if (tasks.isEmpty) {
    return null;
  }
  return tasks.first;
}

QueuedTask? _firstTaskWithStatus(
  List<QueuedTask> tasks,
  QueuedTaskStatus status,
) {
  for (final task in tasks) {
    if (task.status == status) {
      return task;
    }
  }
  return null;
}

String _initialConversationId(AppState state) {
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

String _queuedTaskStatusText(QueuedTaskStatus status) {
  return switch (status) {
    QueuedTaskStatus.pending => '待执行',
    QueuedTaskStatus.running => '执行中',
    QueuedTaskStatus.paused => '已暂停',
    QueuedTaskStatus.completed => '已完成',
    QueuedTaskStatus.failed => '失败',
  };
}

Conversation _createTeamConversation(Team team) {
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

Conversation _createMemberConversation(String teamId, TeamMember member) {
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

bool _isGeneratedWelcomeOnlyMemberConversation(Conversation conversation) {
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

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final trimmed = normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final index = trimmed.lastIndexOf('/');
  return index >= 0 ? trimmed.substring(index + 1) : trimmed;
}

String _statusText(ConversationStatus status) {
  return switch (status) {
    ConversationStatus.idle => '待命',
    ConversationStatus.running => '运行中',
    ConversationStatus.paused => '已暂停',
    ConversationStatus.stopped => '已停止',
    ConversationStatus.failed => '失败',
  };
}

String _collaborationModeLabel(TeamCollaborationMode mode) {
  return switch (mode) {
    TeamCollaborationMode.serial => '串行',
    TeamCollaborationMode.parallel => '并行',
  };
}

String _taskStatusText(TaskAssignmentStatus status) {
  return switch (status) {
    TaskAssignmentStatus.pending => '待执行',
    TaskAssignmentStatus.running => '执行中',
    TaskAssignmentStatus.completed => '已完成',
    TaskAssignmentStatus.failed => '失败',
    TaskAssignmentStatus.cancelled => '已取消',
  };
}

Color _taskStatusColor(TaskAssignmentStatus status) {
  return switch (status) {
    TaskAssignmentStatus.pending => const Color(0xFF6B7280),
    TaskAssignmentStatus.running => const Color(0xFF2563EB),
    TaskAssignmentStatus.completed => const Color(0xFF047857),
    TaskAssignmentStatus.failed => const Color(0xFFBE123C),
    TaskAssignmentStatus.cancelled => const Color(0xFF92400E),
  };
}
