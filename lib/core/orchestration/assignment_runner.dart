import '../domain.dart';
import '../model_gateway.dart';
import 'assignment_helpers.dart';
import 'model_message_runner.dart';

class AssignmentRunner {
  const AssignmentRunner({
    required ModelMessageRunner messageRunner,
  }) : _messageRunner = messageRunner;

  final ModelMessageRunner _messageRunner;

  Future<AssignmentOutcome> runWithRecovery({
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
      final result = await run(
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
      return AssignmentOutcome(
        message: result.message,
        processMessages: processMessages,
        workingState: result.workingState,
      );
    } catch (firstError) {
      cancellation?.throwIfCancelled();
      processMessages.add(systemMessage('执行失败，正在重试：$firstError'));
      try {
        final result = await run(
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
        return AssignmentOutcome(
          message: result.message,
          processMessages: processMessages,
          workingState: result.workingState,
        );
      } catch (secondError) {
        cancellation?.throwIfCancelled();
        final replacement = findReplacementMember(
          state: state,
          team: team,
          failedMember: assignment.member,
          executedMemberIds: executedMemberIds,
        );
        if (replacement == null) {
          processMessages.add(systemMessage('任务失败：$secondError'));
          return AssignmentOutcome(
            message: systemMessage('${assignment.member.name} 执行失败，无法转派。'),
            processMessages: processMessages,
            workingState: workingState,
            failed: true,
          );
        }
        processMessages.add(
          systemMessage(
            '${assignment.member.name} 重试失败，已转派给 ${replacement.name}',
          ),
        );
        final result = await run(
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
        return AssignmentOutcome(
          message: result.message,
          processMessages: processMessages,
          workingState: result.workingState,
        );
      }
    }
  }

  Future<ModelMessageResult> run({
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
    ensureModelReady(member: member, model: model);
    cancellation?.throwIfCancelled();
    return _messageRunner.runVisibleMessage(
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
          id: orchestrationId('msg-assignment'),
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
}

TeamMember? findReplacementMember({
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
