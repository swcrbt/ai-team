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
      ChatMessage(
        id: _id('msg'),
        authorName: secretary.name,
        memberId: secretary.id,
        content:
            '我会把任务拆给 ${workerMembers.map((member) => member.name).join('、')}，并在团队会话中汇总。',
        createdAt: now.add(const Duration(milliseconds: 1)),
      ),
    ];
    final round = conversation.currentRound + 1;
    final assignments = [
      for (var index = 0; index < workerMembers.length; index++)
        TaskAssignment(
          id: _id('task-$round-$index'),
          conversationId: conversation.id,
          round: round,
          memberId: workerMembers[index].id,
          memberName: workerMembers[index].name,
          roleName: state.roles
              .firstWhere((role) => role.id == workerMembers[index].roleId)
              .name,
          instruction: userText,
          status: TaskAssignmentStatus.pending,
          createdAt: now.add(Duration(milliseconds: 2 + index)),
        ),
    ];
    var workingState = _replaceConversation(
      state.copyWith(
        taskAssignments: [...state.taskAssignments, ...assignments],
      ),
      conversation.copyWith(
        messages: messages,
        status: ConversationStatus.running,
      ),
    );
    onProgress?.call(workingState);

    for (var index = 0; index < workerMembers.length; index++) {
      final member = workerMembers[index];
      final assignment = assignments[index];
      cancellation?.throwIfCancelled();
      final role = state.roles.firstWhere((item) => item.id == member.roleId);
      final model =
          state.models.firstWhere((item) => item.id == member.modelId);
      _ensureModelReady(member: member, model: model);
      workingState = _replaceTaskAssignment(
        workingState,
        assignment.copyWith(status: TaskAssignmentStatus.running),
      );
      onProgress?.call(workingState);
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
      workingState = _replaceTaskAssignment(
        workingState,
        assignment.copyWith(
          status: TaskAssignmentStatus.completed,
          summary: _summarize(content),
          completedAt: DateTime.now(),
        ),
      );
      workingState = _replaceConversation(
        workingState,
        conversation.copyWith(
          messages: messages,
          status: ConversationStatus.running,
        ),
      );
      onProgress?.call(workingState);
    }

    cancellation?.throwIfCancelled();
    messages.add(ChatMessage(
      id: _id('msg'),
      authorName: secretary.name,
      memberId: secretary.id,
      content: '汇总：已完成第 $round 轮协作，成员给出了实现与验证建议。需要修改本地项目时会先生成补丁等待确认。',
      createdAt: DateTime.now(),
    ));

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
    if (systemPrompt.contains('测试工程师')) {
      return '测试工程师：为“$latestUser”补充单元测试、Widget 测试和回归验收。';
    }
    return '前端工程师：为“$latestUser”实现 Flutter 桌面界面、状态流和补丁提案。';
  }
}

String _id(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';
