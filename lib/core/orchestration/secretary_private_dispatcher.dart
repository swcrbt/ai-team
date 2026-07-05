import '../domain.dart';
import '../model_gateway.dart';
import 'assignment_helpers.dart';
import 'assignment_runner.dart';
import 'audit_and_private_dispatch.dart';
import 'model_message_runner.dart';

class SecretaryPrivateDispatcher {
  const SecretaryPrivateDispatcher({
    required AssignmentRunner assignmentRunner,
  }) : _assignmentRunner = assignmentRunner;

  final AssignmentRunner _assignmentRunner;

  List<TeamMember> dispatchTargets(
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
    return mentionedDispatchMembers(
      state: state,
      team: team,
      userText: userText,
    );
  }

  Future<AppState> dispatch(
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
    final targets = mentionedDispatchMembers(
      state: state,
      team: team,
      userText: userText,
    );
    if (targets.isEmpty) {
      throw StateError('秘书私聊调度缺少目标成员');
    }

    final now = DateTime.now();
    final waitingMessage = ChatMessage(
      id: orchestrationId('msg'),
      authorName: secretary.name,
      memberId: secretary.id,
      content: '已分配给${targets.map((member) => member.name).join('、')}，等待回复中',
      createdAt: DateTime.now(),
      generationStatus: ChatMessageGenerationStatus.streaming,
    );
    final sourceMessages = [
      ...sourceConversation.messages,
      ChatMessage(
        id: orchestrationId('msg'),
        authorName: '我',
        content: userText,
        createdAt: now,
        isUser: true,
      ),
      waitingMessage,
    ];
    var workingState = replaceConversation(
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
      workingState = ensureMemberConversation(
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
          id: orchestrationId('msg-assignment'),
          authorName: secretary.name,
          memberId: secretary.id,
          content: '任务分配：$userText',
          createdAt: DateTime.now(),
        ),
      ];
      workingState = replaceConversation(
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
        final result = await _assignmentRunner.run(
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
        summaries.add(formatSecretaryPrivateDispatchSuccess(
          memberName: target.name,
          content: result.message.content,
        ));
        workingState = replaceConversation(
          workingState,
          targetConversation.copyWith(
            messages: targetMessages,
            status: ConversationStatus.idle,
          ),
        );
        workingState = appendSecretaryPrivateDispatchAudit(
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
        workingState = replaceConversation(
          workingState,
          targetConversation.copyWith(
            messages: [
              ...targetMessages,
              systemMessage('任务失败：$error'),
            ],
            status: ConversationStatus.failed,
          ),
        );
        workingState = appendSecretaryPrivateDispatchAudit(
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
    replaceMessageInList(sourceMessages, summaryMessage);
    workingState = replaceConversation(
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
