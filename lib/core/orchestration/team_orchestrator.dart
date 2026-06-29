part of '../orchestrator.dart';

typedef StreamingMessageDraftHandler = void Function({
  required String conversationId,
  required ChatMessage message,
});

const _maxModelToolRounds = 3;

class TeamOrchestrator {
  TeamOrchestrator(
    this.gateway, {
    CommandRunner? commandRunner,
  }) : _commandRunner = commandRunner;

  final ModelGateway gateway;
  final CommandRunner? _commandRunner;

  CommandRunner get commandRunner => _commandRunner ?? defaultCommandRunner;

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
    String? continueMessageId,
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
    ChatMessage? visibleToolMessage = continueMessageId == null
        ? null
        : messages
            .where((message) => message.id == continueMessageId)
            .cast<ChatMessage?>()
            .firstWhere((message) => message != null, orElse: () => null);

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
        final baseBlocksForRequest = visibleToolMessage?.contentBlocks ??
            const <ChatMessageContentBlock>[];
        if (model.streaming) {
          current = visibleToolMessage?.copyWith(
                generationStatus: ChatMessageGenerationStatus.streaming,
                generationDurationMs: 0,
              ) ??
              ChatMessage(
                id: _id('msg'),
                authorName: authorName,
                memberId: memberId,
                content: '',
                createdAt: requestStartedAt,
                generationStatus: ChatMessageGenerationStatus.streaming,
                generationDurationMs: 0,
              );
          if (visibleToolMessage == null) {
            messages.add(current);
          } else {
            _replaceMessageInList(messages, current);
          }
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
                  final streamedContent = contentBuffer.toString();
                  final streamedBlocks = baseBlocksForRequest.isEmpty
                      ? null
                      : _appendTextBlock(
                          baseBlocksForRequest,
                          streamedContent,
                        );
                  current = (streamedBlocks == null
                          ? existing.copyWith(content: streamedContent)
                          : _messageWithBlocks(
                              existing,
                              streamedBlocks,
                              generationStatus:
                                  ChatMessageGenerationStatus.streaming,
                            ))
                      .copyWith(
                    thinkingContent:
                        _normalizeOptionalText(thinkingBuffer.toString()),
                    generationStatus: ChatMessageGenerationStatus.streaming,
                    generationDurationMs: elapsedMs,
                  );
                  activeStreamingMessage = current;
                  final publishedMessage = current;
                  if (publishedMessage == null) {
                    return;
                  }
                  if (onStreamingDraft == null) {
                    publish(publishedMessage, force: wasEmpty);
                  } else {
                    publish(publishedMessage, draft: true);
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
          final toolText = completion.content.trim().isNotEmpty
              ? completion.content
              : contentBuffer.toString();
          final existing = current ?? visibleToolMessage;
          final initialBlocks = existing?.contentBlocks.isNotEmpty == true
              ? existing!.contentBlocks
              : _appendTextBlock(
                  visibleToolMessage?.contentBlocks ??
                      const <ChatMessageContentBlock>[],
                  toolText,
                );
          if (existing == null) {
            visibleToolMessage = ChatMessage(
              id: _id('msg'),
              authorName: authorName,
              memberId: memberId,
              content: _contentFromBlocks(initialBlocks),
              contentBlocks: initialBlocks,
              createdAt: DateTime.now(),
              generationStatus: ChatMessageGenerationStatus.streaming,
            );
            messages.add(visibleToolMessage);
          } else {
            visibleToolMessage = _messageWithBlocks(
              existing,
              initialBlocks,
              generationStatus: ChatMessageGenerationStatus.streaming,
            );
            _replaceMessageInList(messages, visibleToolMessage);
          }
          activeStreamingMessage = visibleToolMessage;
          publish(visibleToolMessage, force: true);
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
            visibleToolMessage = _messageWithBlocks(
              visibleToolMessage,
              [
                ...visibleToolMessage.contentBlocks,
                const ChatMessageContentBlock.toolError(
                  '工具调用超过最大轮数 $_maxModelToolRounds',
                ),
              ],
              generationStatus: ChatMessageGenerationStatus.streaming,
            );
            publish(visibleToolMessage, force: true);
            disableTools = true;
            continue;
          }
          final outcome = await _executeModelToolCalls(
            state: nextState,
            conversationId: conversation.id,
            memberId: memberId,
            messageId: visibleToolMessage.id,
            calls: completion.toolCalls,
            commandRunner: commandRunner,
            cancellation: cancellation,
          );
          nextState = outcome.workingState;
          toolRounds.add(outcome.round);
          if (outcome.displayBlocks.isNotEmpty) {
            visibleToolMessage = _messageWithBlocks(
              visibleToolMessage,
              [
                ...visibleToolMessage.contentBlocks,
                ...outcome.displayBlocks,
              ],
              generationStatus: ChatMessageGenerationStatus.streaming,
            );
            activeStreamingMessage = visibleToolMessage;
            publish(visibleToolMessage, force: true);
          }
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
        final finalMessage = visibleToolMessage != null
            ? _messageWithBlocks(
                current ?? visibleToolMessage,
                _appendTextBlock(baseBlocksForRequest, guardedContent),
                generationStatus: ChatMessageGenerationStatus.complete,
              ).copyWith(
                thinkingContent: _normalizeOptionalText(
                      completion.thinkingContent ?? thinkingBuffer.toString(),
                    ) ??
                    current?.thinkingContent,
                generationDurationMs: model.streaming ? elapsedMs : null,
              )
            : (current ??
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
          if (visibleToolMessage == null) {
            messages.add(finalMessage);
          } else {
            _replaceMessageInList(messages, finalMessage);
          }
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

    final resultBlock = ChatMessageContentBlock.commandResult(
      CommandResultAttachment(
        requestId: request.id,
        status: request.status,
        workingDirectory: request.workingDirectory,
        command: request.command,
        output: request.output ?? '',
      ),
    );
    final targetMessage = request.messageId == null
        ? null
        : conversation.messages
            .where((message) => message.id == request.messageId)
            .cast<ChatMessage?>()
            .firstWhere((message) => message != null, orElse: () => null);
    final visibleResultMessage = targetMessage == null
        ? ChatMessage(
            id: _id('msg'),
            authorName: member.name,
            memberId: member.id,
            content: _contentFromBlocks([resultBlock]),
            contentBlocks: [resultBlock],
            createdAt: DateTime.now(),
          )
        : _messageWithBlocks(
            targetMessage,
            [
              ...targetMessage.contentBlocks,
              resultBlock,
            ],
            generationStatus: ChatMessageGenerationStatus.streaming,
          );
    final modelResultMessage = ChatMessage(
      id: visibleResultMessage.id,
      authorName: '系统',
      content: _formatCommandResultMessage(request),
      createdAt: visibleResultMessage.createdAt,
      isUser: true,
    );
    final visibleMessages = targetMessage == null
        ? [
            ...conversation.messages,
            visibleResultMessage,
          ]
        : conversation.messages
            .map((message) =>
                message.id == targetMessage.id ? visibleResultMessage : message)
            .toList();
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
      continueMessageId: visibleResultMessage.id,
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
