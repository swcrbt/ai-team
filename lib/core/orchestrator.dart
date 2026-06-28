import 'dart:convert';
import 'dart:io';

import 'domain.dart';
import 'model_gateway.dart';

typedef StreamingMessageDraftHandler = void Function({
  required String conversationId,
  required ChatMessage message,
});

typedef CommandRunner = Future<ProcessResult> Function(
  String command,
  String workingDirectory,
);

const _maxModelToolRounds = 3;

class TeamOrchestrator {
  TeamOrchestrator(
    this.gateway, {
    CommandRunner? commandRunner,
  }) : commandRunner = commandRunner ?? _defaultCommandRunner;

  final ModelGateway gateway;
  final CommandRunner commandRunner;

  Future<AppState> dispatchQueuedTask(
    AppState state, {
    required String taskId,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
    StreamingMessageDraftHandler? onStreamingDraft,
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
        conversationId: conversation.id,
        userText: userText,
        cancellation: cancellation,
        onProgress: onProgress,
        onStreamingDraft: onStreamingDraft,
      );
    }
    return dispatchMemberChat(
      state,
      conversationId: conversation.id,
      userText: userText,
      cancellation: cancellation,
      onProgress: onProgress,
      onStreamingDraft: onStreamingDraft,
    );
  }

  Future<AppState> dispatchTeamTask(
    AppState state, {
    required String teamId,
    String? conversationId,
    required String userText,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
    StreamingMessageDraftHandler? onStreamingDraft,
  }) async {
    final team = state.teams.firstWhere((item) => item.id == teamId);
    final conversation = state.conversations.firstWhere(
      (item) => conversationId == null
          ? item.teamId == teamId && item.memberId == null
          : item.id == conversationId,
    );
    if (conversation.memberId != null) {
      throw StateError('团队会话不能指向成员私聊: ${conversation.id}');
    }
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
      onStreamingDraft: onStreamingDraft,
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
        onStreamingDraft: onStreamingDraft,
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
          onStreamingDraft: onStreamingDraft,
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
          onStreamingDraft: onStreamingDraft,
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
          onStreamingDraft: onStreamingDraft,
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
      onStreamingDraft: onStreamingDraft,
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
    StreamingMessageDraftHandler? onStreamingDraft,
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
      onStreamingDraft: onStreamingDraft,
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
    StreamingMessageDraftHandler? onStreamingDraft,
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
        onStreamingDraft: onStreamingDraft,
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
          onStreamingDraft: onStreamingDraft,
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
          onStreamingDraft: onStreamingDraft,
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
    StreamingMessageDraftHandler? onStreamingDraft,
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
      onStreamingDraft: onStreamingDraft,
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
    StreamingMessageDraftHandler? onStreamingDraft,
    bool enableTools = true,
  }) async {
    final startedAt = DateTime.now();
    var nextState = workingState;
    var lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
    final outboundMessages = [...requestMessages];
    final activeRole = _roleForMember(nextState, memberId);
    final toolDefinitions = enableTools && gateway is MetadataModelGateway
        ? _modelToolDefinitions(role: activeRole)
        : const <ModelToolDefinition>[];
    final toolSystemPrompt = toolDefinitions.isEmpty
        ? systemPrompt
        : _appendToolSystemPrompt(
            systemPrompt,
            role: activeRole,
          );
    final toolRounds = <ModelToolRound>[];
    var disableTools = false;
    ChatMessage? activeStreamingMessage;

    void publish(
      ChatMessage message, {
      bool force = false,
      bool draft = false,
    }) {
      _replaceMessageInList(messages, message);
      nextState = _replaceConversation(
        nextState,
        conversation.copyWith(
          messages: [...messages],
          status: ConversationStatus.running,
        ),
      );
      if (draft && onStreamingDraft != null) {
        onStreamingDraft(
          conversationId: conversation.id,
          message: message,
        );
        return;
      }
      final now = DateTime.now();
      if (force ||
          now.difference(lastProgressAt) >= const Duration(milliseconds: 50)) {
        lastProgressAt = now;
        onProgress?.call(nextState);
      }
    }

    try {
      for (var roundIndex = 0;; roundIndex++) {
        final requestStartedAt = DateTime.now();
        final contentBuffer = StringBuffer();
        final thinkingBuffer = StringBuffer();
        ChatMessage? current;
        if (model.streaming) {
          current = ChatMessage(
            id: _id('msg'),
            authorName: authorName,
            memberId: memberId,
            content: '',
            createdAt: requestStartedAt,
            generationStatus: ChatMessageGenerationStatus.streaming,
            generationDurationMs: 0,
          );
          messages.add(current);
          activeStreamingMessage = current;
          publish(current, force: true);
        }

        final activeTools =
            disableTools ? const <ModelToolDefinition>[] : toolDefinitions;
        final requestBody = buildOpenAiCompatibleRequestBody(
          model: model,
          systemPrompt: toolSystemPrompt,
          messages: outboundMessages,
          tools: activeTools,
          toolChoice:
              disableTools ? ModelToolChoice.none : ModelToolChoice.auto,
          toolRounds: toolRounds,
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
          systemPrompt: toolSystemPrompt,
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
                  final elapsedMs = DateTime.now()
                      .difference(requestStartedAt)
                      .inMilliseconds;
                  current = existing.copyWith(
                    content: contentBuffer.toString(),
                    thinkingContent:
                        _normalizeOptionalText(thinkingBuffer.toString()),
                    generationStatus: ChatMessageGenerationStatus.streaming,
                    generationDurationMs: elapsedMs,
                  );
                  activeStreamingMessage = current;
                  if (onStreamingDraft == null) {
                    publish(current!, force: wasEmpty);
                  } else {
                    publish(current!, draft: true);
                  }
                }
              : null,
          tools: activeTools,
          toolChoice:
              disableTools ? ModelToolChoice.none : ModelToolChoice.auto,
          toolRounds: toolRounds,
        );
        cancellation?.throwIfCancelled();
        if (completion.toolCalls.isNotEmpty) {
          final existing = current;
          if (existing != null) {
            messages.removeWhere((message) => message.id == existing.id);
            activeStreamingMessage = null;
            nextState = _replaceConversation(
              nextState,
              conversation.copyWith(
                messages: [...messages],
                status: ConversationStatus.running,
              ),
            );
            onProgress?.call(nextState);
          }
          if (roundIndex >= _maxModelToolRounds - 1) {
            toolRounds.add(
              ModelToolRound(
                calls: completion.toolCalls,
                results: completion.toolCalls
                    .map(
                      (call) => ModelToolResult(
                        toolCallId: call.id,
                        name: call.name,
                        content: _toolResultJson(
                          ok: false,
                          error: '工具调用超过最大轮数 $_maxModelToolRounds',
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
            disableTools = true;
            continue;
          }
          final outcome = await _executeModelToolCalls(
            state: nextState,
            conversationId: conversation.id,
            memberId: memberId,
            calls: completion.toolCalls,
            commandRunner: commandRunner,
            cancellation: cancellation,
          );
          nextState = outcome.workingState;
          toolRounds.add(outcome.round);
          onProgress?.call(nextState);
          continue;
        }

        final guardedContent = _guardCommandExecutionClaim(
          content: completion.content,
          requestMessages: outboundMessages,
          toolDefinitions: toolDefinitions,
          toolRounds: toolRounds,
        );
        final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
        final finalMessage = (current ??
                ChatMessage(
                  id: _id('msg'),
                  authorName: authorName,
                  memberId: memberId,
                  content: guardedContent,
                  thinkingContent: completion.thinkingContent,
                  createdAt: DateTime.now(),
                ))
            .copyWith(
          content: guardedContent,
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
        activeStreamingMessage = null;
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
                thinkingContentLength:
                    finalMessage.thinkingContent?.length ?? 0,
              ),
        );
        if (model.streaming) {
          onProgress?.call(nextState);
        }
        return _ModelMessageResult(
          message: finalMessage,
          workingState: nextState,
        );
      }
    } catch (_) {
      final existing = activeStreamingMessage;
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
    StreamingMessageDraftHandler? onStreamingDraft,
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
      onStreamingDraft: onStreamingDraft,
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

  Future<AppState> continueMemberChatAfterCommandResult(
    AppState state, {
    required String conversationId,
    required CommandRequest request,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
    StreamingMessageDraftHandler? onStreamingDraft,
  }) async {
    final conversation =
        state.conversations.firstWhere((item) => item.id == conversationId);
    final memberId = conversation.memberId;
    if (memberId == null) {
      throw StateError('命令结果只能回灌到成员私聊: ${conversation.id}');
    }
    if (request.memberId != null && request.memberId != memberId) {
      throw StateError('命令请求成员与会话成员不匹配: ${request.id}');
    }
    final member = state.members.firstWhere((item) => item.id == memberId);
    final team =
        state.teams.firstWhere((item) => item.id == conversation.teamId);
    final role = state.roles.firstWhere((item) => item.id == member.roleId);
    final model = state.models.firstWhere((item) => item.id == member.modelId);
    _ensureModelReady(member: member, model: model);

    final visibleResultMessage = ChatMessage(
      id: _id('msg'),
      authorName: '系统',
      content: _formatCommandResultMessage(request),
      createdAt: DateTime.now(),
    );
    final modelResultMessage = ChatMessage(
      id: visibleResultMessage.id,
      authorName: '系统',
      content: visibleResultMessage.content,
      createdAt: visibleResultMessage.createdAt,
      isUser: true,
    );
    final visibleMessages = [
      ...conversation.messages,
      visibleResultMessage,
    ];
    var workingState = _replaceConversation(
      state,
      conversation.copyWith(
        messages: visibleMessages,
        status: ConversationStatus.running,
      ),
    );
    onProgress?.call(workingState);

    final result = await _runVisibleModelMessage(
      workingState: workingState,
      conversation: conversation,
      messages: visibleMessages,
      authorName: member.name,
      memberId: member.id,
      model: model,
      systemPrompt: [
        role.renderSystemPrompt(
          memberName: member.name,
          teamName: team.name,
        ),
        '你刚收到一条已执行命令的结果。只能基于该结果回答用户问题，不要再调用工具或请求命令。',
      ].join('\n'),
      requestMessages: [
        ...conversation.messages,
        modelResultMessage,
      ],
      cancellation: cancellation,
      onProgress: onProgress,
      onStreamingDraft: onStreamingDraft,
      enableTools: false,
    );
    workingState = result.workingState;
    final updatedConversation = conversation.copyWith(
      messages: visibleMessages,
      status: ConversationStatus.idle,
    );
    return _replaceConversation(workingState, updatedConversation).copyWith(
      auditLog: [
        ...workingState.auditLog,
        AuditEntry(
          id: _id('audit'),
          action: 'command_result_continued',
          detail: 'conversation=$conversationId command=${request.id}',
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
    StreamingMessageDraftHandler? onStreamingDraft,
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
    final waitingMessage = ChatMessage(
      id: _id('msg'),
      authorName: secretary.name,
      memberId: secretary.id,
      content: '已分配给${targets.map((member) => member.name).join('、')}，等待回复中',
      createdAt: DateTime.now(),
      generationStatus: ChatMessageGenerationStatus.streaming,
    );
    final sourceMessages = [
      ...sourceConversation.messages,
      ChatMessage(
        id: _id('msg'),
        authorName: '我',
        content: userText,
        createdAt: now,
        isUser: true,
      ),
      waitingMessage,
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
          onStreamingDraft: onStreamingDraft,
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

    final summaryMessage = waitingMessage.copyWith(
      content: [
        '已私聊调度成员并汇总结果：',
        ...summaries,
      ].join('\n'),
      generationStatus: ChatMessageGenerationStatus.complete,
    );
    _replaceMessageInList(sourceMessages, summaryMessage);
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

List<ModelToolDefinition> _modelToolDefinitions({
  required RoleTemplate? role,
}) {
  return [
    const ModelToolDefinition(
      name: 'list_workspace_files',
      description: 'List non-hidden files in a configured local workspace.',
      parameters: {
        'type': 'object',
        'properties': {
          'workspaceId': {'type': 'string'},
          'maxFiles': {'type': 'integer', 'minimum': 1, 'maximum': 500},
        },
        'required': ['workspaceId'],
        'additionalProperties': false,
      },
    ),
    const ModelToolDefinition(
      name: 'read_workspace_file',
      description: 'Read a UTF-8 text file from a configured local workspace.',
      parameters: {
        'type': 'object',
        'properties': {
          'workspaceId': {'type': 'string'},
          'relativePath': {'type': 'string'},
        },
        'required': ['workspaceId', 'relativePath'],
        'additionalProperties': false,
      },
    ),
    if (role?.canProposePatch ?? true)
      const ModelToolDefinition(
        name: 'propose_workspace_patch',
        description:
            'Create a pending unified diff proposal. This does not write files.',
        parameters: {
          'type': 'object',
          'properties': {
            'workspaceId': {'type': 'string'},
            'relativePath': {'type': 'string'},
            'proposedContent': {'type': 'string'},
          },
          'required': ['workspaceId', 'relativePath', 'proposedContent'],
          'additionalProperties': false,
        },
      ),
    const ModelToolDefinition(
      name: 'request_command',
      description:
          'Request a command for the current member. The app evaluates the member role policy: commands that require confirmation become pending requests, and allowed commands may execute immediately. 默认使用当前成员；除非系统明确要求，不要填写 memberId 或成员显示名。',
      parameters: {
        'type': 'object',
        'properties': {
          'memberId': {'type': 'string'},
          'command': {'type': 'string'},
          'workingDirectory': {'type': 'string'},
        },
        'required': ['command', 'workingDirectory'],
        'additionalProperties': false,
      },
    ),
  ];
}

RoleTemplate? _roleForMember(AppState state, String? memberId) {
  if (memberId == null) {
    return null;
  }
  final member = state.members.firstWhere(
    (item) => item.id == memberId,
    orElse: () => const TeamMember(
      id: '',
      name: '',
      roleId: '',
      modelId: '',
    ),
  );
  if (member.id.isEmpty) {
    return null;
  }
  return state.roles.firstWhere(
    (item) => item.id == member.roleId,
    orElse: () => const RoleTemplate(
      id: '',
      name: '',
      description: '',
      identityPrompt: '',
      goalPrompt: '',
      constraintPrompt: '',
      outputFormatPrompt: '',
      commandPolicy: CommandPolicy(
        allowedCommands: [],
        blockedCommands: [],
        allowedDirectories: [],
        requiresConfirmation: true,
      ),
    ),
  );
}

String _appendToolSystemPrompt(
  String systemPrompt, {
  required RoleTemplate? role,
}) {
  final commandPolicy = role?.commandPolicy;
  final commandPolicyText = commandPolicy == null
      ? null
      : [
          '当前角色命令策略:',
          'allowedCommands=${jsonEncode(commandPolicy.allowedCommands)}',
          'blockedCommands=${jsonEncode(commandPolicy.blockedCommands)}',
          'allowedDirectories=${jsonEncode(commandPolicy.allowedDirectories)}',
          'requiresConfirmation=${commandPolicy.requiresConfirmation}',
          'allowedCommands 中的 "*" 表示允许所有通过安全语法检查、禁止命令检查和目录检查的命令；它本身不会关闭确认开关。',
          'requiresConfirmation=false 表示允许命令可自动执行；仍不会绕过危险语法检查、禁止命令或目录限制。',
        ].join(' ');
  return [
    systemPrompt,
    if (commandPolicyText != null) commandPolicyText,
    '需要读取本地项目、提出补丁或请求命令时，优先调用可用工具；不要伪造工具结果。补丁只会创建待确认提案；命令会按当前角色策略处理，需要确认时创建待批准请求，无需确认时可以自动执行并返回结果。',
    '涉及执行命令、磁盘占用、df、du 或系统查询时必须调用 request_command；未调用工具前不能声称已执行、已尝试执行或已运行命令。',
  ].join('\n');
}

String _guardCommandExecutionClaim({
  required String content,
  required List<ChatMessage> requestMessages,
  required List<ModelToolDefinition> toolDefinitions,
  required List<ModelToolRound> toolRounds,
}) {
  final canRequestCommand =
      toolDefinitions.any((tool) => tool.name == 'request_command');
  if (!canRequestCommand ||
      _toolRoundsContainTool(toolRounds, 'request_command') ||
      !_hasCommandIntent(requestMessages) ||
      !_claimsCommandExecution(content)) {
    return content;
  }
  return '未创建命令请求，不能声称已执行命令。请调用 request_command 创建命令请求，并等待用户审批或执行结果。';
}

bool _toolRoundsContainTool(List<ModelToolRound> rounds, String name) {
  return rounds.any(
    (round) => round.calls.any((call) => call.name == name),
  );
}

bool _hasCommandIntent(List<ChatMessage> messages) {
  final text = messages.map((message) => message.content).join('\n');
  return RegExp(
    r'(执行|运行|命令|磁盘|系统查询|\bdf\b|\bdu\b)',
    caseSensitive: false,
  ).hasMatch(text);
}

bool _claimsCommandExecution(String content) {
  return RegExp(
    r'(已|已经|尝试|试图|正在)?\s*(执行|运行|调用|尝试执行|尝试运行)',
    caseSensitive: false,
  ).hasMatch(content);
}

String _formatCommandResultMessage(CommandRequest request) {
  final output = request.output?.trim();
  return [
    '命令执行结果',
    '工作目录: ${request.workingDirectory}',
    '命令: ${request.command}',
    '状态: ${request.status.name}',
    if (output != null && output.isNotEmpty) '输出:\n$output' else '输出: <empty>',
  ].join('\n');
}

Future<ProcessResult> _defaultCommandRunner(
  String command,
  String workingDirectory,
) {
  if (Platform.isWindows) {
    return Process.run(
      'cmd',
      ['/c', command],
      workingDirectory: workingDirectory,
      runInShell: false,
    );
  }
  return Process.run(
    '/bin/sh',
    ['-lc', command],
    workingDirectory: workingDirectory,
    runInShell: false,
  );
}

Future<_ToolExecutionOutcome> _executeModelToolCalls({
  required AppState state,
  required String conversationId,
  required String? memberId,
  required List<ModelToolCall> calls,
  required CommandRunner commandRunner,
  ModelRequestCancellation? cancellation,
}) async {
  var workingState = state;
  final results = <ModelToolResult>[];
  for (final call in calls) {
    final result = await _executeModelToolCall(
      state: workingState,
      conversationId: conversationId,
      activeMemberId: memberId,
      call: call,
      commandRunner: commandRunner,
      cancellation: cancellation,
    );
    workingState = result.workingState;
    results.add(result.result);
  }
  return _ToolExecutionOutcome(
    workingState: workingState,
    round: ModelToolRound(calls: calls, results: results),
  );
}

Future<_SingleToolExecutionOutcome> _executeModelToolCall({
  required AppState state,
  required String conversationId,
  required String? activeMemberId,
  required ModelToolCall call,
  required CommandRunner commandRunner,
  ModelRequestCancellation? cancellation,
}) async {
  if (cancellation?.isCancelled == true) {
    return _toolFailure(state, call, '工具调用已取消');
  }
  try {
    final arguments = _decodeToolArguments(call.arguments);
    switch (call.name) {
      case 'list_workspace_files':
        final files = await _listWorkspaceFiles(
          state,
          workspaceId: _requiredString(arguments, 'workspaceId'),
          maxFiles: _optionalPositiveInt(arguments, 'maxFiles') ?? 500,
        );
        return _toolSuccess(
          state,
          call,
          {
            'files': files,
          },
        );
      case 'read_workspace_file':
        final content = await _readWorkspaceFile(
          state,
          workspaceId: _requiredString(arguments, 'workspaceId'),
          relativePath: _requiredString(arguments, 'relativePath'),
        );
        return _toolSuccess(
          state,
          call,
          {
            'content': content,
          },
        );
      case 'propose_workspace_patch':
        return _proposeWorkspacePatchTool(
          state,
          call,
          activeMemberId: activeMemberId,
          arguments: arguments,
        );
      case 'request_command':
        return _requestCommandTool(
          state,
          call,
          conversationId: conversationId,
          activeMemberId: activeMemberId,
          commandRunner: commandRunner,
          arguments: arguments,
        );
      default:
        return _toolFailure(state, call, '未知工具: ${call.name}');
    }
  } catch (error) {
    return _toolFailure(state, call, error.toString());
  }
}

_SingleToolExecutionOutcome _proposeWorkspacePatchTool(
  AppState state,
  ModelToolCall call, {
  required String? activeMemberId,
  required Map<String, Object?> arguments,
}) {
  final member = _memberForTool(state, activeMemberId);
  final role = state.roles.firstWhere((item) => item.id == member.roleId);
  if (!role.canProposePatch) {
    return _toolFailure(state, call, '${member.name} 不允许生成补丁');
  }
  final file = _workspaceFile(
    state,
    workspaceId: _requiredString(arguments, 'workspaceId'),
    relativePath: _requiredString(arguments, 'relativePath'),
  );
  final originalContent = file.existsSync() ? file.readAsStringSync() : '';
  final proposal = PatchProposal.fromFileChange(
    id: _id('patch'),
    filePath: file.path,
    originalContent: originalContent,
    proposedContent: _requiredString(arguments, 'proposedContent'),
    memberName: member.name,
  );
  final nextState = state.copyWith(
    patchProposals: [...state.patchProposals, proposal],
    auditLog: [
      ...state.auditLog,
      AuditEntry(
        id: _id('audit'),
        action: 'patch_proposed',
        detail: '${proposal.memberName}: ${proposal.filePath}',
        createdAt: DateTime.now(),
      ),
    ],
  );
  return _toolSuccess(
    nextState,
    call,
    {
      'patchId': proposal.id,
      'status': proposal.status.name,
      'filePath': proposal.filePath,
      'diff': proposal.diff,
    },
  );
}

Future<_SingleToolExecutionOutcome> _requestCommandTool(
  AppState state,
  ModelToolCall call, {
  required String conversationId,
  required String? activeMemberId,
  required CommandRunner commandRunner,
  required Map<String, Object?> arguments,
}) async {
  final member = _resolveCommandToolMember(
    state,
    activeMemberId: activeMemberId,
    requestedMember: _optionalString(arguments, 'memberId'),
  );
  if (member == null) {
    final requestedMember = _optionalString(arguments, 'memberId');
    return _toolFailure(
      state,
      call,
      requestedMember == null
          ? '成员工具调用缺少当前成员'
          : activeMemberId != null && activeMemberId.trim().isNotEmpty
              ? '不允许跨成员请求命令: $requestedMember'
              : '未知或不允许的成员: $requestedMember',
    );
  }
  final role = state.roles
      .where((item) => item.id == member.roleId)
      .cast<RoleTemplate?>()
      .firstWhere((item) => item != null, orElse: () => null);
  if (role == null) {
    return _toolFailure(state, call, '成员缺少角色配置: ${member.name}');
  }
  final command = _requiredString(arguments, 'command');
  final workingDirectory = _requiredString(arguments, 'workingDirectory');
  final decision = role.commandPolicy.evaluate(
    command,
    workingDirectory: workingDirectory,
  );
  final request = CommandRequest.pending(
    id: _id('command'),
    memberName: member.name,
    command: command,
    workingDirectory: workingDirectory,
    decision: decision,
    conversationId: conversationId,
    memberId: member.id,
    toolCallId: call.id,
  );
  var nextState = state.copyWith(
    commandRequests: [...state.commandRequests, request],
    auditLog: [
      ...state.auditLog,
      AuditEntry(
        id: _id('audit'),
        action: decision == CommandDecision.denied
            ? 'command_denied'
            : 'command_requested',
        detail: '${member.name}: $command',
        createdAt: DateTime.now(),
      ),
    ],
  );
  if (decision == CommandDecision.allowed) {
    final runResult = await _runCommandForTool(
      commandRunner: commandRunner,
      request: request,
    );
    final updatedRequest = request.copyWith(
      status: runResult.status,
      output: runResult.output,
    );
    nextState = nextState.copyWith(
      commandRequests: nextState.commandRequests
          .map((item) => item.id == request.id ? updatedRequest : item)
          .toList(),
      auditLog: [
        ...nextState.auditLog,
        AuditEntry(
          id: _id('audit'),
          action: runResult.status == CommandRequestStatus.executed
              ? 'command_executed'
              : 'command_failed',
          detail: '${request.command} exit=${runResult.exitCode}',
          createdAt: DateTime.now(),
        ),
      ],
    );
    return _toolSuccess(
      nextState,
      call,
      {
        'requestId': updatedRequest.id,
        'decision': updatedRequest.decision.name,
        'status': updatedRequest.status.name,
        'conversationId': updatedRequest.conversationId,
        'memberId': updatedRequest.memberId,
        'output': updatedRequest.output ?? '',
        'exitCode': runResult.exitCode,
        'requiresUserAction': false,
      },
    );
  }
  return _toolSuccess(
    nextState,
    call,
    {
      'requestId': request.id,
      'decision': request.decision.name,
      'status': request.status.name,
      'conversationId': request.conversationId,
      'memberId': request.memberId,
      'requiresUserAction': request.status == CommandRequestStatus.pending &&
          request.decision == CommandDecision.requiresConfirmation,
    },
  );
}

Future<_CommandRunResult> _runCommandForTool({
  required CommandRunner commandRunner,
  required CommandRequest request,
}) async {
  try {
    final result = await commandRunner(
      request.command,
      request.workingDirectory,
    );
    final output = _commandOutputFromProcessResult(result);
    return _CommandRunResult(
      status: result.exitCode == 0
          ? CommandRequestStatus.executed
          : CommandRequestStatus.failed,
      output: output,
      exitCode: result.exitCode,
    );
  } catch (error) {
    return _CommandRunResult(
      status: CommandRequestStatus.failed,
      output: error.toString(),
      exitCode: null,
    );
  }
}

String _commandOutputFromProcessResult(ProcessResult result) {
  return [
    if (result.stdout.toString().trim().isNotEmpty)
      result.stdout.toString().trim(),
    if (result.stderr.toString().trim().isNotEmpty)
      result.stderr.toString().trim(),
  ].join('\n');
}

TeamMember? _resolveCommandToolMember(
  AppState state, {
  required String? activeMemberId,
  required String? requestedMember,
}) {
  TeamMember? activeMember;
  if (activeMemberId != null && activeMemberId.trim().isNotEmpty) {
    activeMember = state.members
        .where((member) => member.id == activeMemberId)
        .cast<TeamMember?>()
        .firstWhere((member) => member != null, orElse: () => null);
  }
  final requested = requestedMember?.trim();
  if (requested == null || requested.isEmpty) {
    return activeMember;
  }
  if (activeMember != null &&
      (requested == activeMember.id || requested == activeMember.name)) {
    return activeMember;
  }
  if (activeMember != null) {
    return null;
  }
  return state.members
      .where((member) => member.id == requested)
      .cast<TeamMember?>()
      .firstWhere((member) => member != null, orElse: () => null);
}

Map<String, Object?> _decodeToolArguments(String arguments) {
  final decoded = jsonDecode(arguments);
  if (decoded is! Map) {
    throw const FormatException('工具参数必须是 JSON object');
  }
  return Map<String, Object?>.from(decoded);
}

String _requiredString(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError('$key 不能为空');
  }
  return value;
}

String? _optionalString(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value;
}

int? _optionalPositiveInt(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value == null) {
    return null;
  }
  if (value is! num || value <= 0) {
    throw ArgumentError('$key 必须是正整数');
  }
  return value.toInt();
}

TeamMember _memberForTool(AppState state, String? memberId) {
  if (memberId == null || memberId.trim().isEmpty) {
    throw ArgumentError('成员工具调用缺少 memberId');
  }
  return state.members.firstWhere((item) => item.id == memberId);
}

Future<List<String>> _listWorkspaceFiles(
  AppState state, {
  required String workspaceId,
  required int maxFiles,
}) async {
  final root = _workspaceRoot(state, workspaceId);
  if (!await root.exists()) {
    throw StateError('工作区不存在: ${root.path}');
  }
  final rootPath = root.absolute.path;
  final files = <String>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (files.length >= maxFiles) {
      break;
    }
    final path = entity.absolute.path;
    final relative = _relativeWorkspacePath(rootPath, path);
    if (_isHiddenWorkspacePath(relative)) {
      continue;
    }
    if (entity is File) {
      files.add(relative);
    }
  }
  files.sort();
  return files;
}

Future<String> _readWorkspaceFile(
  AppState state, {
  required String workspaceId,
  required String relativePath,
}) async {
  final file = _workspaceFile(
    state,
    workspaceId: workspaceId,
    relativePath: relativePath,
  );
  if (!await file.exists()) {
    throw StateError('文件不存在: $relativePath');
  }
  return file.readAsString();
}

Directory _workspaceRoot(AppState state, String workspaceId) {
  final workspace =
      state.workspaces.firstWhere((item) => item.id == workspaceId);
  return Directory(workspace.path).absolute;
}

File _workspaceFile(
  AppState state, {
  required String workspaceId,
  required String relativePath,
}) {
  if (relativePath.trim().isEmpty ||
      relativePath.startsWith('/') ||
      relativePath.split('/').contains('..')) {
    throw ArgumentError('非法相对路径: $relativePath');
  }
  final root = _workspaceRoot(state, workspaceId).absolute.path;
  final file = File('$root/$relativePath').absolute;
  if (!file.path.startsWith('$root/')) {
    throw ArgumentError('文件路径越过工作区边界: $relativePath');
  }
  return file;
}

String _relativeWorkspacePath(String rootPath, String entityPath) {
  final normalizedRoot = rootPath.replaceAll('\\', '/');
  final normalizedEntity = entityPath.replaceAll('\\', '/');
  if (normalizedEntity == normalizedRoot) {
    return '';
  }
  return normalizedEntity.substring(normalizedRoot.length + 1);
}

bool _isHiddenWorkspacePath(String relativePath) {
  return relativePath
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .any((segment) => segment.startsWith('.'));
}

_SingleToolExecutionOutcome _toolSuccess(
  AppState state,
  ModelToolCall call,
  Map<String, Object?> payload,
) {
  return _SingleToolExecutionOutcome(
    workingState: state,
    result: ModelToolResult(
      toolCallId: call.id,
      name: call.name,
      content: _toolResultJson(ok: true, payload: payload),
    ),
  );
}

_SingleToolExecutionOutcome _toolFailure(
  AppState state,
  ModelToolCall call,
  String error,
) {
  return _SingleToolExecutionOutcome(
    workingState: state,
    result: ModelToolResult(
      toolCallId: call.id,
      name: call.name,
      content: _toolResultJson(ok: false, error: error),
    ),
  );
}

String _toolResultJson({
  required bool ok,
  Map<String, Object?> payload = const {},
  String? error,
}) {
  return jsonEncode({
    'ok': ok,
    ...payload,
    if (error != null) 'error': error,
  });
}

AppState _appendModelRequestDiagnostic(
  AppState state, {
  required String conversationId,
  required String? memberId,
  required ModelProfile model,
  required Map<String, Object?> requestBody,
}) {
  final requestUrl = openAiCompatibleChatCompletionsEndpoint(model).toString();
  final detail = [
    'conversation=$conversationId',
    if (memberId != null) 'member=$memberId',
    'model=${model.modelName}',
    'url=$requestUrl',
    'modelProfileName=${model.name}',
    'streaming=${model.streaming}',
  ].join(' ');
  final metadata = <String, Object?>{
    'conversation': conversationId,
    if (memberId != null) 'member': memberId,
    'model': model.modelName,
    'requestUrl': requestUrl,
    'modelProfileName': model.name,
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
  final requestUrl = diagnostics.requestUrl ??
      openAiCompatibleChatCompletionsEndpoint(model).toString();
  final detail = [
    'conversation=$conversationId',
    'message=$messageId',
    if (memberId != null) 'member=$memberId',
    'model=${model.modelName}',
    'url=$requestUrl',
    'modelProfileName=${model.name}',
    'streaming=${diagnostics.streaming}',
    'contentChars=${diagnostics.contentLength}',
    'thinkingChars=${diagnostics.thinkingContentLength}',
    'thinkingFieldKeys=$thinkingFieldKeys',
    'contentDeltas=${diagnostics.contentDeltaCount}',
    'thinkingDeltas=${diagnostics.thinkingDeltaCount}',
    'toolCalls=${diagnostics.toolCallCount}',
  ].join(' ');
  final metadata = <String, Object?>{
    'conversation': conversationId,
    'message': messageId,
    if (memberId != null) 'member': memberId,
    'model': model.modelName,
    'requestUrl': requestUrl,
    'modelProfileName': model.name,
    'streaming': diagnostics.streaming,
    'contentChars': diagnostics.contentLength,
    'thinkingChars': diagnostics.thinkingContentLength,
    'thinkingFieldKeys': diagnostics.thinkingFieldKeys,
    'contentDeltas': diagnostics.contentDeltaCount,
    'thinkingDeltas': diagnostics.thinkingDeltaCount,
    'toolCalls': diagnostics.toolCallCount,
    if (diagnostics.rawToolCalls.isNotEmpty)
      'rawToolCalls': diagnostics.rawToolCalls,
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
          'targetModel': targetModel.modelName,
          'targetModelProfileName': targetModel.name,
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

class _ToolExecutionOutcome {
  const _ToolExecutionOutcome({
    required this.workingState,
    required this.round,
  });

  final AppState workingState;
  final ModelToolRound round;
}

class _SingleToolExecutionOutcome {
  const _SingleToolExecutionOutcome({
    required this.workingState,
    required this.result,
  });

  final AppState workingState;
  final ModelToolResult result;
}

class _CommandRunResult {
  const _CommandRunResult({
    required this.status,
    required this.output,
    required this.exitCode,
  });

  final CommandRequestStatus status;
  final String output;
  final int? exitCode;
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
