import 'dart:async';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/model_gateway.dart';

class ModelCall {
  const ModelCall({
    required this.systemPrompt,
    required this.messages,
  });

  final String systemPrompt;
  final List<ChatMessage> messages;
}

class ScriptedRecordingGateway implements ModelGateway {
  ScriptedRecordingGateway(this.responses);

  final List<String> responses;
  final List<ModelCall> calls = [];
  var _index = 0;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    calls.add(ModelCall(
      systemPrompt: systemPrompt,
      messages: [...messages],
    ));
    cancellation?.throwIfCancelled();
    return responses[_index++];
  }
}

class ScriptedToolGateway implements MetadataModelGateway {
  ScriptedToolGateway({
    required this.toolCall,
    required this.finalReply,
    this.firstReplyBeforeTool = '',
  });

  final ModelToolCall? toolCall;
  final String finalReply;
  final String firstReplyBeforeTool;
  final List<ModelToolDefinition> firstTools = [];
  final List<ModelToolRound> toolRounds = [];
  String? firstSystemPrompt;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    final completion = await completeWithMetadata(
      model: model,
      systemPrompt: systemPrompt,
      messages: messages,
      cancellation: cancellation,
    );
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
    cancellation?.throwIfCancelled();
    if (toolRounds.isEmpty) {
      firstTools.addAll(tools);
      firstSystemPrompt = systemPrompt;
      final toolCall = this.toolCall;
      if (toolCall == null) {
        return ModelCompletion(
          content: finalReply,
          diagnostics: ModelResponseDiagnostics(
            streaming: false,
            contentLength: finalReply.length,
            thinkingContentLength: 0,
            toolCallCount: 0,
          ),
        );
      }
      return ModelCompletion(
        content: firstReplyBeforeTool,
        toolCalls: [toolCall],
        diagnostics: ModelResponseDiagnostics(
          streaming: false,
          contentLength: firstReplyBeforeTool.length,
          thinkingContentLength: 0,
          toolCallCount: 1,
        ),
      );
    }
    this.toolRounds.addAll(toolRounds);
    return ModelCompletion(
      content: finalReply,
      diagnostics: ModelResponseDiagnostics(
        streaming: false,
        contentLength: finalReply.length,
        thinkingContentLength: 0,
      ),
    );
  }
}

class BlockingRecordingGateway implements ModelGateway {
  final Completer<void> started = Completer<void>();
  final Completer<String> _reply = Completer<String>();

  void finish(String value) {
    if (!_reply.isCompleted) {
      _reply.complete(value);
    }
  }

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    if (!started.isCompleted) {
      started.complete();
    }
    final value = await _reply.future;
    cancellation?.throwIfCancelled();
    return value;
  }
}

class ScriptedOutcomeGateway implements ModelGateway {
  ScriptedOutcomeGateway(this.outcomes);

  final List<Object> outcomes;
  var _index = 0;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final outcome = outcomes[_index++];
    if (outcome is ModelGatewayException) {
      throw outcome;
    }
    return outcome as String;
  }
}

class FailsThenSucceedsRecordingGateway implements ModelGateway {
  final List<String> memberNames = [];

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final memberName =
        RegExp(r'成员名称: ([^\n]+)').firstMatch(systemPrompt)?.group(1);
    if (memberName != null) {
      memberNames.add(memberName);
    }
    if (systemPrompt.contains('秘书')) {
      return '前端工程师: 实现界面';
    }
    if (memberName == '前端工程师') {
      throw const ModelGatewayException('前端失败');
    }
    return '$memberName 完成';
  }
}

class AlwaysFailingGateway implements ModelGateway {
  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    throw const ModelGatewayException('forced failure');
  }
}

class ScriptedMetadataGateway implements MetadataModelGateway {
  ScriptedMetadataGateway(this.completion);

  final ModelCompletion completion;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
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
    cancellation?.throwIfCancelled();
    return completion;
  }
}

class ScriptedStreamingMetadataGateway implements MetadataModelGateway {
  ScriptedStreamingMetadataGateway({required this.deltas});

  final List<ModelStreamDelta> deltas;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    final completion = await completeWithMetadata(
      model: model,
      systemPrompt: systemPrompt,
      messages: messages,
      cancellation: cancellation,
    );
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
    final content = StringBuffer();
    final thinking = StringBuffer();
    for (final delta in deltas) {
      cancellation?.throwIfCancelled();
      onDelta?.call(delta);
      if (delta.contentDelta != null) {
        content.write(delta.contentDelta);
      }
      if (delta.thinkingDelta != null) {
        thinking.write(delta.thinkingDelta);
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    return ModelCompletion(
      content: content.toString(),
      thinkingContent: thinking.toString(),
    );
  }
}
