import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/model_gateway.dart';
import 'package:ai_team/core/orchestration/model_message_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs streaming visible model messages outside TeamOrchestrator',
      () async {
    final state = AppState.seed();
    final conversation = state.conversations.firstWhere(
      (item) => item.id == 'conv-member-frontend',
    );
    final model = state.models.firstWhere((item) => item.id == 'model-main');
    final messages = [
      ...conversation.messages,
      ChatMessage(
        id: 'msg-user',
        authorName: '我',
        content: '实现独立 runner',
        createdAt: DateTime(2026, 1, 1),
        isUser: true,
      ),
    ];
    final drafts = <ChatMessage>[];

    final result = await ModelMessageRunner(
      gateway: const _StreamingGateway(
        deltas: [
          ModelStreamDelta(contentDelta: 'hello'),
          ModelStreamDelta(thinkingDelta: 'reasoning'),
          ModelStreamDelta(contentDelta: ' world'),
        ],
        completion: ModelCompletion(
          content: 'hello world',
          thinkingContent: 'reasoning',
          diagnostics: ModelResponseDiagnostics(
            streaming: true,
            contentLength: 11,
            thinkingContentLength: 9,
            contentDeltaCount: 2,
            thinkingDeltaCount: 1,
          ),
        ),
      ),
    ).runVisibleMessage(
      workingState: state,
      conversation: conversation,
      messages: messages,
      authorName: '前端工程师',
      memberId: 'member-frontend',
      model: model,
      systemPrompt: 'system',
      requestMessages: messages,
      onStreamingDraft: ({
        required conversationId,
        required message,
      }) {
        drafts.add(message);
      },
    );

    expect(result.message.content, 'hello world');
    expect(result.message.thinkingContent, 'reasoning');
    expect(
        result.message.generationStatus, ChatMessageGenerationStatus.complete);
    expect(drafts, isNotEmpty);
    expect(drafts.last.generationStatus, ChatMessageGenerationStatus.streaming);
    expect(
      result.workingState.auditLog.map((entry) => entry.action),
      containsAll([
        'model_request_diagnostic',
        'model_response_diagnostic',
      ]),
    );
  });
}

class _StreamingGateway implements MetadataModelGateway {
  const _StreamingGateway({
    required this.deltas,
    required this.completion,
  });

  final List<ModelStreamDelta> deltas;
  final ModelCompletion completion;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    return completion.content;
  }

  @override
  Future<ModelCompletion> completeWithMetadata({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
    ModelStreamDeltaHandler? onDelta,
    List<ModelToolDefinition> tools = const [],
    ModelToolChoice toolChoice = ModelToolChoice.auto,
    List<ModelToolRound> toolRounds = const [],
  }) async {
    for (final delta in deltas) {
      cancellation?.throwIfCancelled();
      onDelta?.call(delta);
    }
    return completion;
  }
}
