import '../domain.dart';
import '../model_gateway.dart';
import 'assignment_helpers.dart';
import 'model_message_runner.dart';
import 'model_message_tools.dart';

class MemberChatDispatcher {
  const MemberChatDispatcher({
    required ModelMessageRunner messageRunner,
  }) : _messageRunner = messageRunner;

  final ModelMessageRunner _messageRunner;

  Future<AppState> dispatchMemberChat(
    AppState state, {
    required String conversationId,
    required String userText,
    String? userMessageId,
    List<MessageAttachment>? preparedAttachments,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
    StreamingMessageDraftHandler? onStreamingDraft,
    void Function()? onUserMessageCommitted,
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
    ensureModelReady(member: member, model: model);
    final now = DateTime.now();
    final messages = [
      ...conversation.messages,
      ChatMessage(
        id: userMessageId ?? orchestrationId('msg'),
        authorName: '我',
        content: userText,
        createdAt: now,
        isUser: true,
        attachments: preparedAttachments ?? const [],
      ),
    ];
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
    final result = await _messageRunner.runVisibleMessage(
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
    return replaceConversation(workingState, updatedConversation).copyWith(
      auditLog: [
        ...workingState.auditLog,
        AuditEntry(
          id: orchestrationId('audit'),
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
    ensureModelReady(member: member, model: model);

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
            id: orchestrationId('msg'),
            authorName: member.name,
            memberId: member.id,
            content: contentFromBlocks([resultBlock]),
            contentBlocks: [resultBlock],
            createdAt: DateTime.now(),
          )
        : messageWithBlocks(
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
      content: formatCommandResultMessage(request),
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
    var workingState = replaceConversation(
      state,
      conversation.copyWith(
        messages: visibleMessages,
        status: ConversationStatus.running,
      ),
    );
    onProgress?.call(workingState);

    final result = await _messageRunner.runVisibleMessage(
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
    return replaceConversation(workingState, updatedConversation).copyWith(
      auditLog: [
        ...workingState.auditLog,
        AuditEntry(
          id: orchestrationId('audit'),
          action: 'command_result_continued',
          detail: 'conversation=$conversationId command=${request.id}',
          createdAt: DateTime.now(),
        ),
      ],
    );
  }
}
