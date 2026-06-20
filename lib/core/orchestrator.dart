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
    var planResult = await _runVisibleModelMessage(
      workingState: workingState,
      conversation: conversation,
      messages: messages,
      authorName: secretary.name,
      memberId: secretary.id,
      model: secretaryModel,
      systemPrompt: _secretarySystemPrompt(
        role: secretaryRole,
        secretary: secretary,
        team: team,
        purpose: '秘书分工',
      ),
      requestMessages: [
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
      onProgress: onProgress,
    );
    workingState = planResult.workingState;
    var plan = planResult.message.content;
    var parsed = _parseAssignmentPlan(plan: plan, members: workerMembers);
    if (parsed.invalidNames.isNotEmpty) {
      planResult = await _runVisibleModelMessage(
        workingState: workingState,
        conversation: conversation,
        messages: messages,
        authorName: secretary.name,
        memberId: secretary.id,
        model: secretaryModel,
        systemPrompt: _secretarySystemPrompt(
          role: secretaryRole,
          secretary: secretary,
          team: team,
          purpose: '秘书分工',
        ),
        requestMessages: [
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
        onProgress: onProgress,
      );
      workingState = planResult.workingState;
      plan = planResult.message.content;
      parsed = _parseAssignmentPlan(plan: plan, members: workerMembers);
      if (parsed.invalidNames.isNotEmpty) {
        throw ModelGatewayException(
          '秘书分工包含不存在成员: ${parsed.invalidNames.join('、')}',
        );
      }
    }

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
          workingState: workingState,
          conversation: conversation,
          team: team,
          assignment: parsed.assignments[index],
          messages: messages,
          visibleMessages: messages,
          executedMemberIds: executedMemberIds,
          cancellation: cancellation,
          onProgress: onProgress,
        );
        messages.addAll(outcome.processMessages);
        workingState = outcome.workingState;
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
          workingState: workingState,
          conversation: conversation,
          team: team,
          secretary: secretary,
          secretaryRole: secretaryRole,
          secretaryModel: secretaryModel,
          messages: messages,
          purpose: '秘书增量汇总',
          cancellation: cancellation,
          onProgress: onProgress,
        );
        workingState = incremental.workingState;
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
          workingState: workingState,
          conversation: conversation,
          team: team,
          assignment: parsed.assignments[index],
          messages: planContextMessages,
          visibleMessages: messages,
          executedMemberIds: executedMemberIds,
          cancellation: cancellation,
          onProgress: onProgress,
        );
        messages.addAll(outcome.processMessages);
        workingState = outcome.workingState;
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
      workingState: workingState,
      conversation: conversation,
      team: team,
      secretary: secretary,
      secretaryRole: secretaryRole,
      secretaryModel: secretaryModel,
      messages: messages,
      purpose: '秘书最终汇总',
      cancellation: cancellation,
      onProgress: onProgress,
    );
    workingState = finalSummary.workingState;

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

  Future<_ModelMessageResult> _runSecretarySummary({
    required AppState state,
    required AppState workingState,
    required Conversation conversation,
    required Team team,
    required TeamMember secretary,
    required RoleTemplate secretaryRole,
    required ModelProfile secretaryModel,
    required List<ChatMessage> messages,
    required String purpose,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
  }) async {
    cancellation?.throwIfCancelled();
    return _runVisibleModelMessage(
      workingState: workingState,
      conversation: conversation,
      messages: messages,
      authorName: secretary.name,
      memberId: secretary.id,
      model: secretaryModel,
      systemPrompt: _secretarySystemPrompt(
        role: secretaryRole,
        secretary: secretary,
        team: team,
        purpose: purpose,
      ),
      requestMessages: messages,
      cancellation: cancellation,
      onProgress: onProgress,
    );
  }

  Future<_AssignmentOutcome> _runAssignmentWithRecovery({
    required AppState state,
    required AppState workingState,
    required Conversation conversation,
    required Team team,
    required ParsedAssignment assignment,
    required List<ChatMessage> messages,
    required List<ChatMessage> visibleMessages,
    required Set<String> executedMemberIds,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
  }) async {
    final processMessages = <ChatMessage>[];
    try {
      final result = await _runAssignment(
        state: state,
        workingState: workingState,
        conversation: conversation,
        team: team,
        assignment: assignment,
        messages: messages,
        visibleMessages: visibleMessages,
        cancellation: cancellation,
        onProgress: onProgress,
      );
      executedMemberIds.add(assignment.member.id);
      return _AssignmentOutcome(
        message: result.message,
        processMessages: processMessages,
        workingState: result.workingState,
      );
    } catch (firstError) {
      cancellation?.throwIfCancelled();
      processMessages.add(_systemMessage('执行失败，正在重试：$firstError'));
      try {
        final result = await _runAssignment(
          state: state,
          workingState: workingState,
          conversation: conversation,
          team: team,
          assignment: assignment,
          messages: messages,
          visibleMessages: visibleMessages,
          cancellation: cancellation,
          onProgress: onProgress,
        );
        executedMemberIds.add(assignment.member.id);
        return _AssignmentOutcome(
          message: result.message,
          processMessages: processMessages,
          workingState: result.workingState,
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
            workingState: workingState,
            failed: true,
          );
        }
        processMessages.add(
          _systemMessage(
            '${assignment.member.name} 重试失败，已转派给 ${replacement.name}',
          ),
        );
        final result = await _runAssignment(
          state: state,
          workingState: workingState,
          conversation: conversation,
          team: team,
          assignment: ParsedAssignment(
            member: replacement,
            instruction: assignment.instruction,
          ),
          messages: messages,
          visibleMessages: visibleMessages,
          cancellation: cancellation,
          onProgress: onProgress,
        );
        executedMemberIds.add(replacement.id);
        return _AssignmentOutcome(
          message: result.message,
          processMessages: processMessages,
          workingState: result.workingState,
        );
      }
    }
  }

  Future<_ModelMessageResult> _runAssignment({
    required AppState state,
    required AppState workingState,
    required Conversation conversation,
    required Team team,
    required ParsedAssignment assignment,
    required List<ChatMessage> messages,
    required List<ChatMessage> visibleMessages,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
  }) async {
    final member = assignment.member;
    final role = state.roles.firstWhere((item) => item.id == member.roleId);
    final model = state.models.firstWhere((item) => item.id == member.modelId);
    _ensureModelReady(member: member, model: model);
    cancellation?.throwIfCancelled();
    return _runVisibleModelMessage(
      workingState: workingState,
      conversation: conversation,
      messages: visibleMessages,
      authorName: member.name,
      memberId: member.id,
      model: model,
      systemPrompt: role.renderSystemPrompt(
        memberName: member.name,
        teamName: team.name,
      ),
      requestMessages: [
        ...messages,
        ChatMessage(
          id: _id('msg-assignment'),
          authorName: '秘书',
          content: '任务分配：${assignment.instruction}',
          createdAt: DateTime.now(),
          isUser: true,
        ),
      ],
      cancellation: cancellation,
      onProgress: onProgress,
    );
  }

  Future<_ModelMessageResult> _runVisibleModelMessage({
    required AppState workingState,
    required Conversation conversation,
    required List<ChatMessage> messages,
    required String authorName,
    required String? memberId,
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> requestMessages,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
  }) async {
    final startedAt = DateTime.now();
    final contentBuffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    var nextState = workingState;
    var lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
    ChatMessage? current;
    final outboundMessages = [...requestMessages];

    void publish(ChatMessage message, {bool force = false}) {
      _replaceMessageInList(messages, message);
      nextState = _replaceConversation(
        nextState,
        conversation.copyWith(
          messages: [...messages],
          status: ConversationStatus.running,
        ),
      );
      final now = DateTime.now();
      if (force ||
          now.difference(lastProgressAt) >= const Duration(milliseconds: 50)) {
        lastProgressAt = now;
        onProgress?.call(nextState);
      }
    }

    if (model.streaming) {
      current = ChatMessage(
        id: _id('msg'),
        authorName: authorName,
        memberId: memberId,
        content: '',
        createdAt: startedAt,
        generationStatus: ChatMessageGenerationStatus.streaming,
        generationDurationMs: 0,
      );
      messages.add(current);
      publish(current, force: true);
    }

    try {
      final requestBody = buildOpenAiCompatibleRequestBody(
        model: model,
        systemPrompt: systemPrompt,
        messages: outboundMessages,
      );
      nextState = _appendModelRequestDiagnostic(
        nextState,
        conversationId: conversation.id,
        memberId: memberId,
        model: model,
        requestBody: requestBody,
      );
      onProgress?.call(nextState);
      final completion = await completeModelWithMetadata(
        gateway,
        model: model,
        systemPrompt: systemPrompt,
        messages: outboundMessages,
        cancellation: cancellation,
        onDelta: model.streaming
            ? (delta) {
                final contentDelta = delta.contentDelta;
                if (contentDelta != null) {
                  contentBuffer.write(contentDelta);
                }
                final thinkingDelta = delta.thinkingDelta;
                if (thinkingDelta != null) {
                  thinkingBuffer.write(thinkingDelta);
                }
                final existing = current;
                if (existing == null) {
                  return;
                }
                final wasEmpty = existing.content.trim().isEmpty &&
                    (existing.thinkingContent?.trim().isEmpty ?? true);
                final elapsedMs =
                    DateTime.now().difference(startedAt).inMilliseconds;
                current = existing.copyWith(
                  content: contentBuffer.toString(),
                  thinkingContent:
                      _normalizeOptionalText(thinkingBuffer.toString()),
                  generationStatus: ChatMessageGenerationStatus.streaming,
                  generationDurationMs: elapsedMs,
                );
                publish(current!, force: wasEmpty);
              }
            : null,
      );
      cancellation?.throwIfCancelled();
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      final finalMessage = (current ??
              ChatMessage(
                id: _id('msg'),
                authorName: authorName,
                memberId: memberId,
                content: completion.content,
                thinkingContent: completion.thinkingContent,
                createdAt: DateTime.now(),
              ))
          .copyWith(
        content: completion.content,
        thinkingContent: _normalizeOptionalText(
              completion.thinkingContent ?? thinkingBuffer.toString(),
            ) ??
            current?.thinkingContent,
        generationStatus: ChatMessageGenerationStatus.complete,
        generationDurationMs: model.streaming ? elapsedMs : null,
      );
      if (current == null) {
        messages.add(finalMessage);
      } else {
        _replaceMessageInList(messages, finalMessage);
      }
      nextState = _replaceConversation(
        nextState,
        conversation.copyWith(
          messages: [...messages],
          status: ConversationStatus.running,
        ),
      );
      nextState = _appendModelResponseDiagnostic(
        nextState,
        conversationId: conversation.id,
        messageId: finalMessage.id,
        memberId: memberId,
        model: model,
        diagnostics: completion.diagnostics ??
            ModelResponseDiagnostics(
              streaming: model.streaming,
              contentLength: finalMessage.content.length,
              thinkingContentLength: finalMessage.thinkingContent?.length ?? 0,
            ),
      );
      if (model.streaming) {
        onProgress?.call(nextState);
      }
      return _ModelMessageResult(
        message: finalMessage,
        workingState: nextState,
      );
    } catch (_) {
      final existing = current;
      if (existing != null) {
        final hasPartialContent = existing.content.trim().isNotEmpty ||
            (existing.thinkingContent?.trim().isNotEmpty ?? false);
        if (hasPartialContent) {
          final status = cancellation?.isCancelled == true
              ? ChatMessageGenerationStatus.stopped
              : ChatMessageGenerationStatus.failed;
          final partial = existing.copyWith(
            generationStatus: status,
            generationDurationMs:
                DateTime.now().difference(startedAt).inMilliseconds,
          );
          _replaceMessageInList(messages, partial);
        } else {
          messages.removeWhere((message) => message.id == existing.id);
        }
        nextState = _replaceConversation(
          nextState,
          conversation.copyWith(
            messages: [...messages],
            status: ConversationStatus.running,
          ),
        );
        onProgress?.call(nextState);
      }
      rethrow;
    }
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
    final result = await _runVisibleModelMessage(
      workingState: workingState,
      conversation: conversation,
      messages: messages,
      authorName: member.name,
      memberId: member.id,
      model: model,
      systemPrompt: role.renderSystemPrompt(
        memberName: member.name,
        teamName: team.name,
      ),
      requestMessages: messages,
      cancellation: cancellation,
      onProgress: onProgress,
    );
    workingState = result.workingState;
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

  List<TeamMember> secretaryPrivateDispatchTargets(
    AppState state, {
    required String conversationId,
    required String userText,
  }) {
    final conversation = state.conversations.firstWhere(
      (item) => item.id == conversationId,
      orElse: () => const Conversation(
        id: '',
        title: '',
        teamId: '',
        messages: [],
      ),
    );
    if (conversation.id.isEmpty || conversation.memberId == null) {
      return const [];
    }
    final team = state.teams.firstWhere(
      (item) => item.id == conversation.teamId,
      orElse: () => const Team(
        id: '',
        name: '',
        memberIds: [],
        secretaryMemberId: '',
      ),
    );
    if (team.id.isEmpty || conversation.memberId != team.secretaryMemberId) {
      return const [];
    }
    return _mentionedDispatchMembers(
      state: state,
      team: team,
      userText: userText,
    );
  }

  Future<AppState> dispatchSecretaryPrivateMemberTask(
    AppState state, {
    required String conversationId,
    required String userText,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
  }) async {
    final sourceConversation =
        state.conversations.firstWhere((item) => item.id == conversationId);
    final team = state.teams.firstWhere(
      (item) => item.id == sourceConversation.teamId,
    );
    if (sourceConversation.memberId != team.secretaryMemberId) {
      throw StateError('只有秘书私聊可以调度成员: $conversationId');
    }
    final secretary = state.members.firstWhere(
      (item) => item.id == team.secretaryMemberId,
    );
    final targets = _mentionedDispatchMembers(
      state: state,
      team: team,
      userText: userText,
    );
    if (targets.isEmpty) {
      throw StateError('秘书私聊调度缺少目标成员');
    }

    final now = DateTime.now();
    final sourceMessages = [
      ...sourceConversation.messages,
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
        content: '已发送给${targets.map((member) => member.name).join('、')}，等待回复。',
        createdAt: DateTime.now(),
      ),
    ];
    var workingState = _replaceConversation(
      state,
      sourceConversation.copyWith(
        messages: sourceMessages,
        status: ConversationStatus.running,
      ),
    );
    onProgress?.call(workingState);

    final summaries = <String>[];
    for (final target in targets) {
      cancellation?.throwIfCancelled();
      workingState = _ensureMemberConversation(
        workingState,
        teamId: team.id,
        member: target,
      );
      final targetConversation = workingState.conversations.firstWhere(
        (item) => item.teamId == team.id && item.memberId == target.id,
      );
      final targetMessages = [
        ...targetConversation.messages,
        ChatMessage(
          id: _id('msg-assignment'),
          authorName: secretary.name,
          memberId: secretary.id,
          content: '任务分配：$userText',
          createdAt: DateTime.now(),
        ),
      ];
      workingState = _replaceConversation(
        workingState,
        targetConversation.copyWith(
          messages: targetMessages,
          status: ConversationStatus.running,
        ),
      );
      onProgress?.call(workingState);
      final targetModel = workingState.models.firstWhere(
        (model) => model.id == target.modelId,
      );

      try {
        final result = await _runAssignment(
          state: workingState,
          workingState: workingState,
          conversation: targetConversation,
          team: team,
          assignment: ParsedAssignment(member: target, instruction: userText),
          messages: targetConversation.messages,
          visibleMessages: targetMessages,
          cancellation: cancellation,
          onProgress: onProgress,
        );
        workingState = result.workingState;
        if (result.message.content.trim().isEmpty &&
            (result.message.thinkingContent?.trim().isEmpty ?? true)) {
          throw const ModelGatewayException('成员未返回内容');
        }
        summaries.add(_formatSecretaryPrivateDispatchSuccess(
          memberName: target.name,
          content: result.message.content,
        ));
        workingState = _replaceConversation(
          workingState,
          targetConversation.copyWith(
            messages: targetMessages,
            status: ConversationStatus.idle,
          ),
        );
        workingState = _appendSecretaryPrivateDispatchAudit(
          workingState,
          secretary: secretary,
          target: target,
          sourceConversation: sourceConversation,
          targetConversation: targetConversation,
          userText: userText,
          status: 'completed',
          targetModel: targetModel,
          responseChars: result.message.content.length,
        );
      } catch (error) {
        cancellation?.throwIfCancelled();
        summaries.add('- ${target.name}：调度失败：$error');
        workingState = _replaceConversation(
          workingState,
          targetConversation.copyWith(
            messages: [
              ...targetMessages,
              _systemMessage('任务失败：$error'),
            ],
            status: ConversationStatus.failed,
          ),
        );
        workingState = _appendSecretaryPrivateDispatchAudit(
          workingState,
          secretary: secretary,
          target: target,
          sourceConversation: sourceConversation,
          targetConversation: targetConversation,
          userText: userText,
          status: 'failed',
          targetModel: targetModel,
          responseChars: 0,
          error: error.toString(),
        );
      }
      onProgress?.call(workingState);
    }

    final summaryMessage = ChatMessage(
      id: _id('msg'),
      authorName: secretary.name,
      memberId: secretary.id,
      content: [
        '已私聊调度成员并汇总结果：',
        ...summaries,
      ].join('\n'),
      createdAt: DateTime.now(),
    );
    sourceMessages.add(summaryMessage);
    workingState = _replaceConversation(
      workingState,
      sourceConversation.copyWith(
        messages: sourceMessages,
        status: ConversationStatus.idle,
      ),
    );
    onProgress?.call(workingState);
    return workingState;
  }
}

AppState _appendModelRequestDiagnostic(
  AppState state, {
  required String conversationId,
  required String? memberId,
  required ModelProfile model,
  required Map<String, Object?> requestBody,
}) {
  final detail = [
    'conversation=$conversationId',
    if (memberId != null) 'member=$memberId',
    'model=${model.id}',
    'modelName=${model.name}',
    'streaming=${model.streaming}',
  ].join(' ');
  final metadata = <String, Object?>{
    'conversation': conversationId,
    if (memberId != null) 'member': memberId,
    'model': model.id,
    'modelName': model.name,
    'streaming': model.streaming,
    'requestBody': requestBody,
  };
  return state.copyWith(
    auditLog: [
      ...state.auditLog,
      AuditEntry(
        id: _id('audit'),
        action: 'model_request_diagnostic',
        detail: detail,
        metadata: metadata,
        createdAt: DateTime.now(),
      ),
    ],
  );
}

AppState _appendModelResponseDiagnostic(
  AppState state, {
  required String conversationId,
  required String messageId,
  required String? memberId,
  required ModelProfile model,
  required ModelResponseDiagnostics diagnostics,
}) {
  final thinkingFieldKeys = diagnostics.thinkingFieldKeys.isEmpty
      ? 'none'
      : diagnostics.thinkingFieldKeys.join(',');
  final detail = [
    'conversation=$conversationId',
    'message=$messageId',
    if (memberId != null) 'member=$memberId',
    'model=${model.id}',
    'modelName=${model.name}',
    'streaming=${diagnostics.streaming}',
    'contentChars=${diagnostics.contentLength}',
    'thinkingChars=${diagnostics.thinkingContentLength}',
    'thinkingFieldKeys=$thinkingFieldKeys',
    'contentDeltas=${diagnostics.contentDeltaCount}',
    'thinkingDeltas=${diagnostics.thinkingDeltaCount}',
  ].join(' ');
  final metadata = <String, Object?>{
    'conversation': conversationId,
    'message': messageId,
    if (memberId != null) 'member': memberId,
    'model': model.id,
    'modelName': model.name,
    'streaming': diagnostics.streaming,
    'contentChars': diagnostics.contentLength,
    'thinkingChars': diagnostics.thinkingContentLength,
    'thinkingFieldKeys': diagnostics.thinkingFieldKeys,
    'contentDeltas': diagnostics.contentDeltaCount,
    'thinkingDeltas': diagnostics.thinkingDeltaCount,
    if (diagnostics.requestBody != null) 'requestBody': diagnostics.requestBody,
    if (diagnostics.rawResponse != null) 'rawResponse': diagnostics.rawResponse,
  };
  return state.copyWith(
    auditLog: [
      ...state.auditLog,
      AuditEntry(
        id: _id('audit'),
        action: 'model_response_diagnostic',
        detail: detail,
        metadata: metadata,
        createdAt: DateTime.now(),
      ),
    ],
  );
}

AppState _appendSecretaryPrivateDispatchAudit(
  AppState state, {
  required TeamMember secretary,
  required TeamMember target,
  required Conversation sourceConversation,
  required Conversation targetConversation,
  required String userText,
  required String status,
  required ModelProfile targetModel,
  required int responseChars,
  String? error,
}) {
  return state.copyWith(
    auditLog: [
      ...state.auditLog,
      AuditEntry(
        id: _id('audit'),
        action: 'secretary_private_member_dispatch',
        detail: 'secretary=${secretary.id} target=${target.id} status=$status',
        metadata: {
          'secretary': secretary.id,
          'targetMember': target.id,
          'sourceConversation': sourceConversation.id,
          'targetConversation': targetConversation.id,
          'text': userText,
          'status': status,
          'targetModel': targetModel.id,
          'responseChars': responseChars,
          if (error != null) 'error': error,
        },
        createdAt: DateTime.now(),
      ),
    ],
  );
}

List<TeamMember> _mentionedDispatchMembers({
  required AppState state,
  required Team team,
  required String userText,
}) {
  final matches = <({TeamMember member, int index})>[];
  for (final member in state.members) {
    if (!team.memberIds.contains(member.id) ||
        member.id == team.secretaryMemberId) {
      continue;
    }
    final index = userText.indexOf(member.name);
    if (index >= 0) {
      matches.add((member: member, index: index));
    }
  }
  matches.sort((a, b) {
    final byIndex = a.index.compareTo(b.index);
    if (byIndex != 0) {
      return byIndex;
    }
    return team.memberIds
        .indexOf(a.member.id)
        .compareTo(team.memberIds.indexOf(b.member.id));
  });
  return matches.map((match) => match.member).toList();
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
  final indented = content
      .trim()
      .split('\n')
      .map((line) => '  $line')
      .join('\n');
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
