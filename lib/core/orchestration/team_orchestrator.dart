import '../commands/command_service.dart';
import '../domain.dart';
import '../model_gateway.dart';
import 'assignment_helpers.dart';
import 'assignment_runner.dart';
import 'member_chat_dispatcher.dart';
import 'model_message_runner.dart';
import 'secretary_private_dispatcher.dart';
import 'secretary_summary_runner.dart';

class TeamOrchestrator {
  TeamOrchestrator(
    this.gateway, {
    CommandRunner? commandRunner,
  })  : _commandRunner = commandRunner,
        _messageRunner = ModelMessageRunner(
          gateway: gateway,
          commandRunner: commandRunner,
        ) {
    _assignmentRunner = AssignmentRunner(messageRunner: _messageRunner);
    _summaryRunner = SecretarySummaryRunner(messageRunner: _messageRunner);
    _memberChatDispatcher = MemberChatDispatcher(
      messageRunner: _messageRunner,
    );
    _secretaryPrivateDispatcher = SecretaryPrivateDispatcher(
      assignmentRunner: _assignmentRunner,
    );
  }

  final ModelGateway gateway;
  final CommandRunner? _commandRunner;
  final ModelMessageRunner _messageRunner;
  late final AssignmentRunner _assignmentRunner;
  late final SecretarySummaryRunner _summaryRunner;
  late final MemberChatDispatcher _memberChatDispatcher;
  late final SecretaryPrivateDispatcher _secretaryPrivateDispatcher;

  CommandRunner get commandRunner => _commandRunner ?? defaultCommandRunner;

  ChatMessage? queuedUserMessageForTask(
    Conversation conversation,
    QueuedTask task,
  ) {
    for (final message in conversation.messages) {
      if (message.isUser && task.messageIds.contains(message.id)) {
        return message;
      }
    }
    return null;
  }

  Future<AppState> dispatchQueuedTask(
    AppState state, {
    required String taskId,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
    StreamingMessageDraftHandler? onStreamingDraft,
  }) async {
    final task = state.queuedTasks.firstWhere((item) => item.id == taskId);
    final conversation = state.conversations.firstWhere(
      (item) => item.id == task.conversationId,
    );
    
    try {
      final queuedUserMessage = queuedUserMessageForTask(conversation, task);
      
      // 如果有排队的用户消息，直接复用而不是创建新的
      if (queuedUserMessage != null) {
        final requestMessages = [
          ...conversation.messages,
          if (task.notes.isNotEmpty)
            ChatMessage(
              id: orchestrationId('task-notes-${task.id}'),
              authorName: '系统',
              content: ['备注:', ...task.notes.map((note) => '- $note')].join('\n'),
              createdAt: DateTime.now(),
            ),
        ];
        
        if (conversation.memberId == null) {
          // 团队会话：直接调用底层逻辑，跳过 dispatchTeamTask 的用户消息创建
          final team = state.teams.firstWhere((item) => item.id == conversation.teamId);
          final secretary = state.members.firstWhere((item) => item.id == team.secretaryMemberId);
          final workerMembers = state.members
              .where((member) => team.memberIds.contains(member.id) && member.id != secretary.id)
              .toList();
          final secretaryRole = state.roles.firstWhere((item) => item.id == secretary.roleId);
          final secretaryModel = state.models.firstWhere((item) => item.id == secretary.modelId);
          ensureModelReady(member: secretary, model: secretaryModel);
          
          final round = conversation.currentRound + 1;
          var workingState = replaceConversation(
            state,
            conversation.copyWith(status: ConversationStatus.running),
          );
          onProgress?.call(workingState);
          
          cancellation?.throwIfCancelled();
          var planResult = await _messageRunner.runVisibleMessage(
            workingState: workingState,
            conversation: conversation,
            messages: conversation.messages,
            authorName: secretary.name,
            memberId: secretary.id,
            model: secretaryModel,
            systemPrompt: secretarySystemPrompt(
              role: secretaryRole,
              secretary: secretary,
              team: team,
              purpose: '秘书分工',
            ),
            requestMessages: [
              ...requestMessages,
              ChatMessage(
                id: orchestrationId('msg-plan-request'),
                authorName: '系统',
                content: '请按每行"成员名: 具体任务"的格式分配任务。可用成员: ${workerMembers.map((member) => member.name).join('、')}。',
                createdAt: DateTime.now(),
              ),
            ],
            cancellation: cancellation,
            onProgress: onProgress,
            onStreamingDraft: onStreamingDraft,
          );
          workingState = planResult.workingState;
          var plan = planResult.message.content;
          var parsed = parseAssignmentPlan(plan: plan, members: workerMembers);
          
          if (parsed.invalidNames.isNotEmpty) {
            planResult = await _messageRunner.runVisibleMessage(
              workingState: workingState,
              conversation: conversation,
              messages: conversation.messages,
              authorName: secretary.name,
              memberId: secretary.id,
              model: secretaryModel,
              systemPrompt: secretarySystemPrompt(
                role: secretaryRole,
                secretary: secretary,
                team: team,
                purpose: '秘书分工',
              ),
              requestMessages: [
                ...requestMessages,
                ChatMessage(
                  id: orchestrationId('msg-replan-request'),
                  authorName: '系统',
                  content: '分工包含不存在成员: ${parsed.invalidNames.join('、')}。请只使用: ${workerMembers.map((member) => member.name).join('、')}。',
                  createdAt: DateTime.now(),
                ),
              ],
              cancellation: cancellation,
              onProgress: onProgress,
              onStreamingDraft: onStreamingDraft,
            );
            workingState = planResult.workingState;
            plan = planResult.message.content;
            parsed = parseAssignmentPlan(plan: plan, members: workerMembers);
            if (parsed.invalidNames.isNotEmpty) {
              throw ModelGatewayException(
                '秘书分工包含不存在成员: ${parsed.invalidNames.join('、')}',
              );
            }
          }
          
          if (parsed.assignments.isEmpty) {
            final updatedConversation = conversation.copyWith(
              currentRound: round,
              status: ConversationStatus.idle,
            );
            return replaceConversation(workingState, updatedConversation);
          }
          
          final taskAssignments = [
            for (var index = 0; index < parsed.assignments.length; index++)
              TaskAssignment(
                id: orchestrationId('task-$round-$index'),
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
          
          final messages = [...conversation.messages];
          final executedMemberIds = <String>{};
          if (team.collaborationMode == TeamCollaborationMode.serial) {
            for (var index = 0; index < parsed.assignments.length; index++) {
              final outcome = await _assignmentRunner.runWithRecovery(
                state: workingState,
                workingState: workingState,
                conversation: conversation,
                team: team,
                assignment: parsed.assignments[index],
                messages: requestMessages,
                visibleMessages: messages,
                executedMemberIds: executedMemberIds,
                cancellation: cancellation,
                onProgress: onProgress,
                onStreamingDraft: onStreamingDraft,
              );
              messages.addAll(outcome.processMessages);
              workingState = outcome.workingState;
              workingState = replaceTaskAssignment(
                workingState,
                taskAssignments[index].copyWith(
                  status: outcome.failed
                      ? TaskAssignmentStatus.failed
                      : TaskAssignmentStatus.completed,
                  summary: summarizeMessage(outcome.message.content),
                  completedAt: DateTime.now(),
                ),
              );
              final incremental = await _summaryRunner.run(
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
              workingState = replaceConversation(
                workingState,
                conversation.copyWith(
                  messages: messages,
                  status: ConversationStatus.running,
                ),
              );
              onProgress?.call(workingState);
            }
          } else {
            final planContextMessages = [...requestMessages];
            for (var index = 0; index < parsed.assignments.length; index++) {
              final outcome = await _assignmentRunner.runWithRecovery(
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
              workingState = replaceTaskAssignment(
                workingState,
                taskAssignments[index].copyWith(
                  status: outcome.failed
                      ? TaskAssignmentStatus.failed
                      : TaskAssignmentStatus.completed,
                  summary: summarizeMessage(outcome.message.content),
                  completedAt: DateTime.now(),
                ),
              );
            }
          }
          
          final finalSummary = await _summaryRunner.run(
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
          return replaceConversation(
            workingState,
            updatedConversation,
          ).copyWith(
            auditLog: [
              ...workingState.auditLog,
              AuditEntry(
                id: orchestrationId('audit'),
                action: 'team_task_dispatched',
                detail: 'team=${conversation.teamId} round=$round text=${task.originalText}',
                createdAt: DateTime.now(),
              ),
            ],
          );
        } else {
          // 成员会话：使用 dispatchMemberChat，传入已存在的用户消息 ID
          return await dispatchMemberChat(
            state,
            conversationId: conversation.id,
            userText: task.originalText,
            userMessageId: queuedUserMessage.id,
            attachments: queuedUserMessage.attachments,
            cancellation: cancellation,
            onProgress: onProgress,
            onStreamingDraft: onStreamingDraft,
          );
        }
      }
      
      // 向后兼容：没有排队用户消息的旧任务
      final userText = [
        task.originalText,
        if (task.notes.isNotEmpty) ...[
          '',
          '备注:',
          ...task.notes.map((note) => '- $note'),
        ],
      ].join('\n');
      if (conversation.memberId == null) {
        return await dispatchTeamTask(
          state,
          teamId: conversation.teamId,
          conversationId: conversation.id,
          userText: userText,
          cancellation: cancellation,
          onProgress: onProgress,
          onStreamingDraft: onStreamingDraft,
        );
      }
      return await dispatchMemberChat(
        state,
        conversationId: conversation.id,
        userText: userText,
        cancellation: cancellation,
        onProgress: onProgress,
        onStreamingDraft: onStreamingDraft,
      );
    } on ModelGatewayException catch (exception) {
      // 创建错误消息并添加到对话中
      final errorMessage = ChatMessage(
        id: orchestrationId('error-${task.id}'),
        authorName: '系统',
        content: exception.message,
        createdAt: DateTime.now(),
        memberId: conversation.memberId,
        contentBlocks: [
          ChatMessageContentBlock.toolError(exception.message),
        ],
        generationStatus: ChatMessageGenerationStatus.complete,
      );
      
      final updatedConversation = conversation.copyWith(
        messages: [...conversation.messages, errorMessage],
        status: ConversationStatus.idle,
      );
      
      final updatedState = replaceConversation(state, updatedConversation);
      
      // 通知进度更新，让 UI 立即显示错误消息
      onProgress?.call(updatedState);
      
      // 重新抛出异常，让 dispatch_controller 标记任务为 failed
      rethrow;
    } catch (exception) {
      // 处理其他未预期的异常
      final errorMessage = ChatMessage(
        id: orchestrationId('error-${task.id}'),
        authorName: '系统',
        content: exception.toString(),
        createdAt: DateTime.now(),
        memberId: conversation.memberId,
        contentBlocks: [
          ChatMessageContentBlock.toolError(exception.toString()),
        ],
        generationStatus: ChatMessageGenerationStatus.complete,
      );
      
      final updatedConversation = conversation.copyWith(
        messages: [...conversation.messages, errorMessage],
        status: ConversationStatus.idle,
      );
      
      final updatedState = replaceConversation(state, updatedConversation);
      onProgress?.call(updatedState);
      
      rethrow;
    }
  }

  Future<AppState> dispatchTeamTask(
    AppState state, {
    required String teamId,
    String? conversationId,
    required String userText,
    String? userMessageId,
    List<MessageAttachment>? attachments,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
    StreamingMessageDraftHandler? onStreamingDraft,
    void Function()? onUserMessageCommitted,
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
    ensureModelReady(member: secretary, model: secretaryModel);
    final now = DateTime.now();
    final messages = [
      ...conversation.messages,
      ChatMessage(
        id: userMessageId ?? orchestrationId('msg'),
        authorName: '我',
        content: userText,
        createdAt: now,
        isUser: true,
        attachments: attachments ?? const [],
      ),
    ];
    final round = conversation.currentRound + 1;
    var workingState = replaceConversation(
      state,
      conversation.copyWith(
        messages: messages,
        status: ConversationStatus.running,
      ),
    );
    onProgress?.call(workingState);
    onUserMessageCommitted?.call();

    cancellation?.throwIfCancelled();
    var planResult = await _messageRunner.runVisibleMessage(
      workingState: workingState,
      conversation: conversation,
      messages: messages,
      authorName: secretary.name,
      memberId: secretary.id,
      model: secretaryModel,
      systemPrompt: secretarySystemPrompt(
        role: secretaryRole,
        secretary: secretary,
        team: team,
        purpose: '秘书分工',
      ),
      requestMessages: [
        ...messages,
        ChatMessage(
          id: orchestrationId('msg-plan-request'),
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
    var parsed = parseAssignmentPlan(plan: plan, members: workerMembers);
    if (parsed.invalidNames.isNotEmpty) {
      planResult = await _messageRunner.runVisibleMessage(
        workingState: workingState,
        conversation: conversation,
        messages: messages,
        authorName: secretary.name,
        memberId: secretary.id,
        model: secretaryModel,
        systemPrompt: secretarySystemPrompt(
          role: secretaryRole,
          secretary: secretary,
          team: team,
          purpose: '秘书分工',
        ),
        requestMessages: [
          ...messages,
          ChatMessage(
            id: orchestrationId('msg-replan-request'),
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
      parsed = parseAssignmentPlan(plan: plan, members: workerMembers);
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
      return replaceConversation(workingState, updatedConversation);
    }

    final taskAssignments = [
      for (var index = 0; index < parsed.assignments.length; index++)
        TaskAssignment(
          id: orchestrationId('task-$round-$index'),
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
        final outcome = await _assignmentRunner.runWithRecovery(
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
        workingState = replaceTaskAssignment(
          workingState,
          taskAssignments[index].copyWith(
            status: outcome.failed
                ? TaskAssignmentStatus.failed
                : TaskAssignmentStatus.completed,
            summary: summarizeMessage(outcome.message.content),
            completedAt: DateTime.now(),
          ),
        );
        final incremental = await _summaryRunner.run(
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
        workingState = replaceConversation(
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
        final outcome = await _assignmentRunner.runWithRecovery(
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
        workingState = replaceTaskAssignment(
          workingState,
          taskAssignments[index].copyWith(
            status: outcome.failed
                ? TaskAssignmentStatus.failed
                : TaskAssignmentStatus.completed,
            summary: summarizeMessage(outcome.message.content),
            completedAt: DateTime.now(),
          ),
        );
      }
    }

    final finalSummary = await _summaryRunner.run(
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
    return replaceConversation(
      workingState,
      updatedConversation,
    ).copyWith(
      auditLog: [
        ...workingState.auditLog,
        AuditEntry(
          id: orchestrationId('audit'),
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
    String? userMessageId,
    List<MessageAttachment>? attachments,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
    StreamingMessageDraftHandler? onStreamingDraft,
    void Function()? onUserMessageCommitted,
  }) {
    return _memberChatDispatcher.dispatchMemberChat(
      state,
      conversationId: conversationId,
      userText: userText,
      userMessageId: userMessageId,
      attachments: attachments,
      cancellation: cancellation,
      onProgress: onProgress,
      onStreamingDraft: onStreamingDraft,
      onUserMessageCommitted: onUserMessageCommitted,
    );
  }

  Future<AppState> continueMemberChatAfterCommandResult(
    AppState state, {
    required String conversationId,
    required CommandRequest request,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
    StreamingMessageDraftHandler? onStreamingDraft,
  }) {
    return _memberChatDispatcher.continueMemberChatAfterCommandResult(
      state,
      conversationId: conversationId,
      request: request,
      cancellation: cancellation,
      onProgress: onProgress,
      onStreamingDraft: onStreamingDraft,
    );
  }

  List<TeamMember> secretaryPrivateDispatchTargets(
    AppState state, {
    required String conversationId,
    required String userText,
  }) {
    return _secretaryPrivateDispatcher.dispatchTargets(
      state,
      conversationId: conversationId,
      userText: userText,
    );
  }

  Future<AppState> dispatchSecretaryPrivateMemberTask(
    AppState state, {
    required String conversationId,
    required String userText,
    String? userMessageId,
    List<MessageAttachment>? attachments,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
    StreamingMessageDraftHandler? onStreamingDraft,
    void Function()? onUserMessageCommitted,
  }) {
    return _secretaryPrivateDispatcher.dispatch(
      state,
      conversationId: conversationId,
      userText: userText,
      userMessageId: userMessageId,
      attachments: attachments,
      cancellation: cancellation,
      onProgress: onProgress,
      onStreamingDraft: onStreamingDraft,
      onUserMessageCommitted: onUserMessageCommitted,
    );
  }
}
