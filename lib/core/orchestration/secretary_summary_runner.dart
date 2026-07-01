import '../domain.dart';
import '../model_gateway.dart';
import 'assignment_helpers.dart';
import 'model_message_runner.dart';

class SecretarySummaryRunner {
  const SecretarySummaryRunner({
    required ModelMessageRunner messageRunner,
  }) : _messageRunner = messageRunner;

  final ModelMessageRunner _messageRunner;

  Future<ModelMessageResult> run({
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
    return _messageRunner.runVisibleMessage(
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
        purpose: purpose,
      ),
      requestMessages: messages,
      cancellation: cancellation,
      onProgress: onProgress,
      onStreamingDraft: onStreamingDraft,
    );
  }
}
