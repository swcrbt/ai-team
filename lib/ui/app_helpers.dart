import 'package:flutter/material.dart';

import '../application/app_controller.dart';
import '../core/domain.dart';

String conversationTitle(AppController controller, Conversation conversation) {
  if (conversation.memberId == null) {
    return '群聊 · ${conversationDisplayTitle(controller, conversation)}';
  }
  return '私聊 · ${conversationDisplayTitle(controller, conversation)}';
}

String messageTimeText(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String auditLogTimeText(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}

String conversationMeta(AppController controller, Conversation conversation) {
  final status = statusText(conversation.status);
  final members = controller.membersForConversation(conversation.id);
  if (conversation.memberId == null) {
    return '${members.length} 名成员 · 第 ${conversation.currentRound} 轮 · $status';
  }
  final member = members.firstWhere((item) => item.id == conversation.memberId);
  return '${roleName(controller.state, member.roleId)} · ${modelName(controller.state, member.modelId)} · $status';
}

String roleName(AppState state, String roleId) =>
    state.roles.firstWhere((role) => role.id == roleId).name;

String modelName(AppState state, String modelId) =>
    state.models.firstWhere((model) => model.id == modelId).name;

String inputHint(AppController controller, Conversation conversation) {
  if (conversation.memberId == null) {
    return '发给 ${controller.teamForConversation(conversation.id).name}';
  }
  return '发给 ${conversationSubjectTitle(controller, conversation)}';
}

String avatarText(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
}

Color avatarColor(String name) {
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

String conversationPreview(Conversation conversation) {
  if (conversation.messages.isEmpty) {
    return '暂无消息';
  }
  final message = conversation.messages.last;
  return '${message.authorName}: ${message.content}'.replaceAll('\n', ' ');
}

String conversationDisplayTitle(
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
  return conversationSubjectTitle(controller, conversation);
}

String conversationSubjectTitle(
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
      conversationPreview(conversation).trim() == title) {
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

String? normalizedThinkingContent(ChatMessage message) {
  final thinkingContent = message.thinkingContent;
  if (thinkingContent == null || thinkingContent.trim().isEmpty) {
    return null;
  }
  return thinkingContent;
}

String thinkingTitle(ChatMessage message) {
  final duration = messageGenerationDurationText(message);
  return switch (message.generationStatus) {
    ChatMessageGenerationStatus.streaming => '思考中… $duration',
    ChatMessageGenerationStatus.failed => '思考失败 · $duration',
    ChatMessageGenerationStatus.stopped => '思考已停止 · $duration',
    ChatMessageGenerationStatus.complete =>
      message.generationDurationMs == null ? '思考过程' : '已完成思考 · $duration',
  };
}

String? messageInlineGenerationStatus(ChatMessage message) {
  final duration = messageGenerationDurationText(message);
  return switch (message.generationStatus) {
    ChatMessageGenerationStatus.failed => '失败 · $duration',
    ChatMessageGenerationStatus.stopped => '已停止 · $duration',
    _ => null,
  };
}

bool isAwaitingFirstModelOutput(ChatMessage message) {
  return !message.isUser &&
      message.generationStatus == ChatMessageGenerationStatus.streaming &&
      message.content.trim().isEmpty &&
      (message.thinkingContent?.trim().isEmpty ?? true);
}

bool isStreamingThinkingWithoutReplyContent(
  ChatMessage message,
  String? thinkingContent,
) {
  return !message.isUser &&
      message.generationStatus == ChatMessageGenerationStatus.streaming &&
      message.content.trim().isEmpty &&
      thinkingContent != null;
}

String messageGenerationDurationText(ChatMessage message) {
  final milliseconds =
      message.generationStatus == ChatMessageGenerationStatus.streaming
          ? DateTime.now().difference(message.createdAt).inMilliseconds
          : message.generationDurationMs ?? 0;
  final seconds = (milliseconds / 1000).ceil().clamp(0, 9999);
  return '${seconds}s';
}

IconData conversationListIcon(
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

String conversationListTitle(
  AppController controller,
  Conversation conversation,
) {
  return conversationDisplayTitle(controller, conversation);
}

String conversationListSubtitle(
  AppController controller,
  Conversation conversation,
) {
  if (conversation.messages.isEmpty) {
    final prefix = conversation.memberId == null ? '群聊' : '私聊';
    return '$prefix · ${conversationSubjectTitle(controller, conversation)}';
  }
  if (conversation.memberId == null) {
    return conversationPreview(conversation);
  }
  final member = controller.state.members.firstWhere(
    (item) => item.id == conversation.memberId,
  );
  return _privateConversationPreview(controller, conversation, member);
}

String? conversationListBadge(
  AppController controller,
  Conversation conversation,
) {
  if (conversation.memberId == null) {
    final memberCount = controller.state.teams
        .firstWhere((team) => team.id == conversation.teamId)
        .memberIds
        .length;
    return '$memberCount 名';
  }
  return null;
}

String? conversationStatusPill(
  AppController controller,
  Conversation conversation,
) {
  if (controller
      .commandRequestsForConversation(conversation.id)
      .any((request) => request.status == CommandRequestStatus.pending)) {
    return '待审批';
  }
  if (controller
      .commandRequestsForConversation(conversation.id)
      .any((request) => request.status == CommandRequestStatus.approved)) {
    return '允许中';
  }
  if (controller.state.patchProposals.any(
    (proposal) => proposal.status == PatchStatus.pending,
  )) {
    return '有补丁';
  }
  if (conversation.status == ConversationStatus.running) {
    return '执行中';
  }
  return null;
}

String _privateConversationPreview(
  AppController controller,
  Conversation conversation,
  TeamMember member,
) {
  if (conversation.messages.length > 1) {
    return conversationPreview(conversation);
  }
  return roleName(controller.state, member.roleId);
}

String conversationMenuTitle(
  AppController controller,
  Conversation conversation,
) {
  final title = conversationDisplayTitle(controller, conversation);
  final subject = conversationSubjectTitle(controller, conversation);
  if (title == subject) {
    return title;
  }
  return '$title · $subject';
}

List<TeamMember> typingMembers(
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

String statusText(ConversationStatus status) {
  return switch (status) {
    ConversationStatus.idle => '待命',
    ConversationStatus.running => '运行中',
    ConversationStatus.paused => '已暂停',
    ConversationStatus.stopped => '已停止',
    ConversationStatus.failed => '失败',
  };
}

String collaborationModeLabel(TeamCollaborationMode mode) {
  return switch (mode) {
    TeamCollaborationMode.serial => '串行',
    TeamCollaborationMode.parallel => '并行',
  };
}
