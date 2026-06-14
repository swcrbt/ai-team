import 'domain.dart';
import 'model_gateway.dart';

class TeamOrchestrator {
  TeamOrchestrator(this.gateway);

  final ModelGateway gateway;

  Future<AppState> dispatchQueuedTask(
    AppState state, {
    required String taskId,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
  }) {
    final task = state.queuedTasks.firstWhere((item) => item.id == taskId);
    final conversation = state.conversations.firstWhere(
      (item) => item.id == task.conversationId,
    );
    final userText = [
      task.originalText,
      if (task.notes.isNotEmpty) ...[
        '',
        '备注:',
        ...task.notes.map((note) => '- $note'),
      ],
    ].join('\n');
    if (conversation.memberId == null) {
      return dispatchTeamTask(
        state,
        teamId: conversation.teamId,
        userText: userText,
        cancellation: cancellation,
        onProgress: onProgress,
      );
    }
    return dispatchMemberChat(
      state,
      conversationId: conversation.id,
      userText: userText,
      cancellation: cancellation,
      onProgress: onProgress,
    );
  }

  Future<AppState> dispatchTeamTask(
    AppState state, {
    required String teamId,
    required String userText,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
  }) async {
    final team = state.teams.firstWhere((item) => item.id == teamId);
    final conversation = state.conversations
        .firstWhere((item) => item.teamId == teamId && item.memberId == null);
    final secretary =
        state.members.firstWhere((item) => item.id == team.secretaryMemberId);
    final workerMembers = state.members
        .where((member) =>
            team.memberIds.contains(member.id) && member.id != secretary.id)
        .toList();
    final secretaryRole =
        state.roles.firstWhere((item) => item.id == secretary.roleId);
    final secretaryModel =
        state.models.firstWhere((item) => item.id == secretary.modelId);
    _ensureModelReady(member: secretary, model: secretaryModel);
    final now = DateTime.now();
    final messages = [
      ...conversation.messages,
      ChatMessage(
        id: _id('msg'),
        authorName: '我',
        content: userText,
        createdAt: now,
        isUser: true,
      ),
    ];
    final round = conversation.currentRound + 1;
    var workingState = _replaceConversation(
      state,
      conversation.copyWith(
        messages: messages,
        status: ConversationStatus.running,
      ),
    );
    onProgress?.call(workingState);

    cancellation?.throwIfCancelled();
    var plan = await gateway.complete(
      model: secretaryModel,
      systemPrompt: _secretarySystemPrompt(
        role: secretaryRole,
        secretary: secretary,
        team: team,
        purpose: '秘书分工',
      ),
      messages: [
        ...messages,
        ChatMessage(
          id: _id('msg-plan-request'),
          authorName: '系统',
          content:
              '请按每行“成员名: 具体任务”的格式分配任务。可用成员: ${workerMembers.map((member) => member.name).join('、')}。',
          createdAt: DateTime.now(),
        ),
      ],
      cancellation: cancellation,
    );
    var parsed = _parseAssignmentPlan(plan: plan, members: workerMembers);
    if (parsed.invalidNames.isNotEmpty) {
      plan = await gateway.complete(
        model: secretaryModel,
        systemPrompt: _secretarySystemPrompt(
          role: secretaryRole,
          secretary: secretary,
          team: team,
          purpose: '秘书分工',
        ),
        messages: [
          ...messages,
          ChatMessage(
            id: _id('msg-replan-request'),
            authorName: '系统',
            content:
                '分工包含不存在成员: ${parsed.invalidNames.join('、')}。请只使用: ${workerMembers.map((member) => member.name).join('、')}。',
            createdAt: DateTime.now(),
          ),
        ],
        cancellation: cancellation,
      );
      parsed = _parseAssignmentPlan(plan: plan, members: workerMembers);
      if (parsed.invalidNames.isNotEmpty) {
        throw ModelGatewayException(
          '秘书分工包含不存在成员: ${parsed.invalidNames.join('、')}',
        );
      }
    }

    messages.add(ChatMessage(
      id: _id('msg'),
      authorName: secretary.name,
      memberId: secretary.id,
      content: plan,
      createdAt: DateTime.now(),
    ));

    if (parsed.assignments.isEmpty) {
      final updatedConversation = conversation.copyWith(
        messages: messages,
        currentRound: round,
        status: ConversationStatus.idle,
      );
      return _replaceConversation(workingState, updatedConversation);
    }

    final taskAssignments = [
      for (var index = 0; index < parsed.assignments.length; index++)
        TaskAssignment(
          id: _id('task-$round-$index'),
          conversationId: conversation.id,
          round: round,
          memberId: parsed.assignments[index].member.id,
          memberName: parsed.assignments[index].member.name,
          roleName: state.roles
              .firstWhere(
                (role) => role.id == parsed.assignments[index].member.roleId,
              )
              .name,
          instruction: parsed.assignments[index].instruction,
          status: TaskAssignmentStatus.pending,
          createdAt: DateTime.now(),
        ),
    ];
    workingState = workingState.copyWith(
      taskAssignments: [...workingState.taskAssignments, ...taskAssignments],
    );

    final executedMemberIds = <String>{};
    if (team.collaborationMode == TeamCollaborationMode.serial) {
      for (var index = 0; index < parsed.assignments.length; index++) {
        final outcome = await _runAssignmentWithRecovery(
          state: workingState,
          team: team,
          assignment: parsed.assignments[index],
          messages: messages,
          executedMemberIds: executedMemberIds,
          cancellation: cancellation,
        );
        messages.addAll(outcome.processMessages);
        messages.add(outcome.message);
        workingState = _replaceTaskAssignment(
          workingState,
          taskAssignments[index].copyWith(
            status: outcome.failed
                ? TaskAssignmentStatus.failed
                : TaskAssignmentStatus.completed,
            summary: _summarize(outcome.message.content),
            completedAt: DateTime.now(),
          ),
        );
        final incremental = await _runSecretarySummary(
          state: workingState,
          team: team,
          secretary: secretary,
          secretaryRole: secretaryRole,
          secretaryModel: secretaryModel,
          messages: messages,
          purpose: '秘书增量汇总',
          cancellation: cancellation,
        );
        messages.add(incremental);
        workingState = _replaceConversation(
          workingState,
          conversation.copyWith(
            messages: messages,
            status: ConversationStatus.running,
          ),
        );
        onProgress?.call(workingState);
      }
    } else {
      final planContextMessages = [...messages];
      for (var index = 0; index < parsed.assignments.length; index++) {
        final outcome = await _runAssignmentWithRecovery(
          state: workingState,
          team: team,
          assignment: parsed.assignments[index],
          messages: planContextMessages,
          executedMemberIds: executedMemberIds,
          cancellation: cancellation,
        );
        messages.addAll(outcome.processMessages);
        messages.add(outcome.message);
        workingState = _replaceTaskAssignment(
          workingState,
          taskAssignments[index].copyWith(
            status: outcome.failed
                ? TaskAssignmentStatus.failed
                : TaskAssignmentStatus.completed,
            summary: _summarize(outcome.message.content),
            completedAt: DateTime.now(),
          ),
        );
      }
    }

    final finalSummary = await _runSecretarySummary(
      state: workingState,
      team: team,
      secretary: secretary,
      secretaryRole: secretaryRole,
      secretaryModel: secretaryModel,
      messages: messages,
      purpose: '秘书最终汇总',
      cancellation: cancellation,
    );
    messages.add(finalSummary);

    final nextStatus = round >= team.maxRounds
        ? ConversationStatus.paused
        : ConversationStatus.idle;
    final updatedConversation = conversation.copyWith(
      messages: messages,
      currentRound: round,
      status: nextStatus,
    );
    return _replaceConversation(
      workingState,
      updatedConversation,
    ).copyWith(
      auditLog: [
        ...workingState.auditLog,
        AuditEntry(
          id: _id('audit'),
          action: 'team_task_dispatched',
          detail: 'team=$teamId round=$round text=$userText',
          createdAt: DateTime.now(),
        ),
      ],
    );
  }

  Future<ChatMessage> _runSecretarySummary({
    required AppState state,
    required Team team,
    required TeamMember secretary,
    required RoleTemplate secretaryRole,
    required ModelProfile secretaryModel,
    required List<ChatMessage> messages,
    required String purpose,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final content = await gateway.complete(
      model: secretaryModel,
      systemPrompt: _secretarySystemPrompt(
        role: secretaryRole,
        secretary: secretary,
        team: team,
        purpose: purpose,
      ),
      messages: messages,
      cancellation: cancellation,
    );
    cancellation?.throwIfCancelled();
    return ChatMessage(
      id: _id('msg'),
      authorName: secretary.name,
      memberId: secretary.id,
      content: content,
      createdAt: DateTime.now(),
    );
  }

  Future<_AssignmentOutcome> _runAssignmentWithRecovery({
    required AppState state,
    required Team team,
    required ParsedAssignment assignment,
    required List<ChatMessage> messages,
    required Set<String> executedMemberIds,
    ModelRequestCancellation? cancellation,
  }) async {
    final processMessages = <ChatMessage>[];
    try {
      final message = await _runAssignment(
        state: state,
        team: team,
        assignment: assignment,
        messages: messages,
        cancellation: cancellation,
      );
      executedMemberIds.add(assignment.member.id);
      return _AssignmentOutcome(
        message: message,
        processMessages: processMessages,
      );
    } catch (firstError) {
      cancellation?.throwIfCancelled();
      processMessages.add(_systemMessage('执行失败，正在重试：$firstError'));
      try {
        final message = await _runAssignment(
          state: state,
          team: team,
          assignment: assignment,
          messages: messages,
          cancellation: cancellation,
        );
        executedMemberIds.add(assignment.member.id);
        return _AssignmentOutcome(
          message: message,
          processMessages: processMessages,
        );
      } catch (secondError) {
        cancellation?.throwIfCancelled();
        final replacement = _findReplacementMember(
          state: state,
          team: team,
          failedMember: assignment.member,
          executedMemberIds: executedMemberIds,
        );
        if (replacement == null) {
          processMessages.add(_systemMessage('任务失败：$secondError'));
          return _AssignmentOutcome(
            message: _systemMessage('${assignment.member.name} 执行失败，无法转派。'),
            processMessages: processMessages,
            failed: true,
          );
        }
        processMessages.add(
          _systemMessage(
            '${assignment.member.name} 重试失败，已转派给 ${replacement.name}',
          ),
        );
        final message = await _runAssignment(
          state: state,
          team: team,
          assignment: ParsedAssignment(
            member: replacement,
            instruction: assignment.instruction,
          ),
          messages: messages,
          cancellation: cancellation,
        );
        executedMemberIds.add(replacement.id);
        return _AssignmentOutcome(
          message: message,
          processMessages: processMessages,
        );
      }
    }
  }

  Future<ChatMessage> _runAssignment({
    required AppState state,
    required Team team,
    required ParsedAssignment assignment,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    final member = assignment.member;
    final role = state.roles.firstWhere((item) => item.id == member.roleId);
    final model = state.models.firstWhere((item) => item.id == member.modelId);
    _ensureModelReady(member: member, model: model);
    cancellation?.throwIfCancelled();
    final content = await gateway.complete(
      model: model,
      systemPrompt: role.renderSystemPrompt(
        memberName: member.name,
        teamName: team.name,
      ),
      messages: [
        ...messages,
        ChatMessage(
          id: _id('msg-assignment'),
          authorName: '秘书',
          content: '任务分配：${assignment.instruction}',
          createdAt: DateTime.now(),
        ),
      ],
      cancellation: cancellation,
    );
    cancellation?.throwIfCancelled();
    return ChatMessage(
      id: _id('msg'),
      authorName: member.name,
      memberId: member.id,
      content: content,
      createdAt: DateTime.now(),
    );
  }

  TeamMember? _findReplacementMember({
    required AppState state,
    required Team team,
    required TeamMember failedMember,
    required Set<String> executedMemberIds,
  }) {
    final candidates = state.members
        .where(
          (member) =>
              team.memberIds.contains(member.id) &&
              member.id != failedMember.id &&
              !member.isSecretary &&
              member.roleId == failedMember.roleId,
        )
        .toList();
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) {
      final priority = b.executionPriority.compareTo(a.executionPriority);
      if (priority != 0) {
        return priority;
      }
      final aExecuted = executedMemberIds.contains(a.id);
      final bExecuted = executedMemberIds.contains(b.id);
      if (aExecuted != bExecuted) {
        return aExecuted ? 1 : -1;
      }
      return team.memberIds
          .indexOf(a.id)
          .compareTo(team.memberIds.indexOf(b.id));
    });
    return candidates.first;
  }

  Future<AppState> dispatchMemberChat(
    AppState state, {
    required String conversationId,
    required String userText,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
  }) async {
    final conversation =
        state.conversations.firstWhere((item) => item.id == conversationId);
    final memberId = conversation.memberId;
    if (memberId == null) {
      throw StateError('成员私聊会话缺少成员: ${conversation.id}');
    }
    final member = state.members.firstWhere((item) => item.id == memberId);
    final team =
        state.teams.firstWhere((item) => item.id == conversation.teamId);
    final role = state.roles.firstWhere((item) => item.id == member.roleId);
    final model = state.models.firstWhere((item) => item.id == member.modelId);
    _ensureModelReady(member: member, model: model);
    final now = DateTime.now();
    final messages = [
      ...conversation.messages,
      ChatMessage(
        id: _id('msg'),
        authorName: '我',
        content: userText,
        createdAt: now,
        isUser: true,
      ),
    ];
    var workingState = _replaceConversation(
      state,
      conversation.copyWith(
        messages: messages,
        status: ConversationStatus.running,
      ),
    );
    onProgress?.call(workingState);

    cancellation?.throwIfCancelled();
    final content = await gateway.complete(
      model: model,
      systemPrompt: role.renderSystemPrompt(
        memberName: member.name,
        teamName: team.name,
      ),
      messages: messages,
      cancellation: cancellation,
    );
    cancellation?.throwIfCancelled();
    messages.add(ChatMessage(
      id: _id('msg'),
      authorName: member.name,
      memberId: member.id,
      content: content,
      createdAt: DateTime.now(),
    ));
    final updatedConversation = conversation.copyWith(
      messages: messages,
      status: ConversationStatus.idle,
    );
    return _replaceConversation(workingState, updatedConversation).copyWith(
      auditLog: [
        ...workingState.auditLog,
        AuditEntry(
          id: _id('audit'),
          action: 'member_chat_dispatched',
          detail: 'member=${member.id} text=$userText',
          createdAt: DateTime.now(),
        ),
      ],
    );
  }
}

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
    this.failed = false,
  });

  final ChatMessage message;
  final List<ChatMessage> processMessages;
  final bool failed;
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

AppState _replaceTaskAssignment(AppState state, TaskAssignment assignment) {
  return state.copyWith(
    taskAssignments: state.taskAssignments
        .map((item) => item.id == assignment.id ? assignment : item)
        .toList(),
  );
}

String _summarize(String content) {
  final normalized = content.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.length <= 120) {
    return normalized;
  }
  return '${normalized.substring(0, 120)}...';
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
