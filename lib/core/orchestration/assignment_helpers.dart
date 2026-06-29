part of '../orchestrator.dart';

class ParsedAssignment {
  const ParsedAssignment({
    required this.member,
    required this.instruction,
  });

  final TeamMember member;
  final String instruction;
}

class _AssignmentPlan {
  const _AssignmentPlan({
    required this.assignments,
    required this.invalidNames,
  });

  final List<ParsedAssignment> assignments;
  final List<String> invalidNames;
}

class _AssignmentOutcome {
  const _AssignmentOutcome({
    required this.message,
    required this.processMessages,
    required this.workingState,
    this.failed = false,
  });

  final ChatMessage message;
  final List<ChatMessage> processMessages;
  final AppState workingState;
  final bool failed;
}

class _ModelMessageResult {
  const _ModelMessageResult({
    required this.message,
    required this.workingState,
  });

  final ChatMessage message;
  final AppState workingState;
}

class _ToolExecutionOutcome {
  const _ToolExecutionOutcome({
    required this.workingState,
    required this.round,
    this.displayBlocks = const [],
  });

  final AppState workingState;
  final ModelToolRound round;
  final List<ChatMessageContentBlock> displayBlocks;
}

class _SingleToolExecutionOutcome {
  const _SingleToolExecutionOutcome({
    required this.workingState,
    required this.result,
    this.displayBlocks = const [],
  });

  final AppState workingState;
  final ModelToolResult result;
  final List<ChatMessageContentBlock> displayBlocks;
}

_AssignmentPlan _parseAssignmentPlan({
  required String plan,
  required List<TeamMember> members,
}) {
  final assignments = <ParsedAssignment>[];
  final invalidNames = <String>[];
  for (final line in plan.split('\n')) {
    final separator = _assignmentSeparatorIndex(line);
    if (separator <= 0) {
      continue;
    }
    final name = line.substring(0, separator).trim();
    final instruction = line.substring(separator + 1).trim();
    if (name.isEmpty || instruction.isEmpty) {
      continue;
    }
    final member = _memberByNameOrNull(members, name);
    if (member == null) {
      invalidNames.add(name);
      continue;
    }
    assignments.add(ParsedAssignment(member: member, instruction: instruction));
  }
  return _AssignmentPlan(assignments: assignments, invalidNames: invalidNames);
}

int _assignmentSeparatorIndex(String line) {
  final ascii = line.indexOf(':');
  final chinese = line.indexOf('：');
  if (ascii < 0) {
    return chinese;
  }
  if (chinese < 0) {
    return ascii;
  }
  return ascii < chinese ? ascii : chinese;
}

TeamMember? _memberByNameOrNull(List<TeamMember> members, String name) {
  for (final member in members) {
    if (member.name == name) {
      return member;
    }
  }
  return null;
}

String _secretarySystemPrompt({
  required RoleTemplate role,
  required TeamMember secretary,
  required Team team,
  required String purpose,
}) {
  return [
    role.renderSystemPrompt(
      memberName: secretary.name,
      teamName: team.name,
    ),
    purpose,
  ].join('\n');
}

ChatMessage _systemMessage(String content) {
  return ChatMessage(
    id: _id('msg'),
    authorName: '系统',
    content: content,
    createdAt: DateTime.now(),
  );
}

void _ensureModelReady({
  required TeamMember member,
  required ModelProfile model,
}) {
  if (model.apiKey.trim().isEmpty) {
    throw StateError(
        '成员 ${member.name} 的模型 ${model.name} 缺少 API Key，请在模型配置中重新保存。');
  }
}

AppState _replaceConversation(AppState state, Conversation conversation) {
  return state.copyWith(
    conversations: state.conversations
        .map((item) => item.id == conversation.id ? conversation : item)
        .toList(),
  );
}

AppState _ensureMemberConversation(
  AppState state, {
  required String teamId,
  required TeamMember member,
}) {
  final exists = state.conversations.any(
    (conversation) =>
        conversation.teamId == teamId && conversation.memberId == member.id,
  );
  if (exists) {
    return state;
  }
  return state.copyWith(
    conversations: [
      ...state.conversations,
      Conversation(
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
      ),
    ],
  );
}

AppState _replaceTaskAssignment(AppState state, TaskAssignment assignment) {
  return state.copyWith(
    taskAssignments: state.taskAssignments
        .map((item) => item.id == assignment.id ? assignment : item)
        .toList(),
  );
}

void _replaceMessageInList(List<ChatMessage> messages, ChatMessage message) {
  final index = messages.indexWhere((item) => item.id == message.id);
  if (index < 0) {
    messages.add(message);
    return;
  }
  messages[index] = message;
}

String? _normalizeOptionalText(String value) {
  return value.trim().isEmpty ? null : value;
}

String _summarize(String content) {
  final normalized = content.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= 120) {
    return normalized;
  }
  return '${normalized.substring(0, 120)}...';
}

String _formatSecretaryPrivateDispatchSuccess({
  required String memberName,
  required String content,
}) {
  final indented =
      content.trim().split('\n').map((line) => '  $line').join('\n');
  return '- $memberName：\n$indented';
}

class FakeModelGateway implements ModelGateway {
  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final latestUser = messages.lastWhere((message) => message.isUser).content;
    if (systemPrompt.contains('秘书最终汇总') || systemPrompt.contains('秘书增量汇总')) {
      return '汇总：已完成协作，成员给出了实现与验证建议。';
    }
    if (systemPrompt.contains('秘书分工')) {
      return '前端工程师: 为“$latestUser”实现 Flutter 桌面界面、状态流和补丁提案。\n'
          '测试工程师: 为“$latestUser”补充单元测试、Widget 测试和回归验收。';
    }
    if (systemPrompt.contains('测试工程师')) {
      return '测试工程师：为“$latestUser”补充单元测试、Widget 测试和回归验收。';
    }
    return '前端工程师：为“$latestUser”实现 Flutter 桌面界面、状态流和补丁提案。';
  }
}

String _id(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';
