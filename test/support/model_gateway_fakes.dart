import 'dart:async';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/model_gateway.dart';

class BlockingModelGateway implements ModelGateway {
  final Completer<void> started = Completer<void>();
  ModelRequestCancellation? cancellation;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    this.cancellation = cancellation;
    if (!started.isCompleted) {
      started.complete();
    }
    await cancellation!.cancelled;
    cancellation.throwIfCancelled();
    return 'unreachable';
  }
}

class CompletingBlockingModelGateway implements ModelGateway {
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
    final reply = await _reply.future;
    cancellation?.throwIfCancelled();
    return reply;
  }
}

class BlockingThenRecordingGateway implements ModelGateway {
  final Completer<void> started = Completer<void>();
  ModelRequestCancellation? cancellation;
  var callCount = 0;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    callCount++;
    if (callCount == 1) {
      this.cancellation = cancellation;
      if (!started.isCompleted) {
        started.complete();
      }
      await cancellation!.cancelled;
      cancellation.throwIfCancelled();
    }
    return '已恢复回复';
  }
}

class RecordingModelGateway implements ModelGateway {
  final List<String> modelIds = [];
  final List<String> modelNames = [];

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    modelIds.add(model.id);
    modelNames.add(model.modelName);
    return '使用 ${model.modelName} 回复';
  }
}

class ScriptedReplyGateway implements ModelGateway {
  ScriptedReplyGateway(this.responses);

  final List<String> responses;
  var _index = 0;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    return responses[_index++];
  }
}

class RecordingScriptedGateway implements ModelGateway {
  RecordingScriptedGateway(this.responses);

  final List<String> responses;
  final List<List<ChatMessage>> recordedMessages = [];
  var _index = 0;
  var calls = 0;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    calls++;
    recordedMessages.add([...messages]);
    return responses[_index++];
  }
}

class ScriptedStreamingGateway implements MetadataModelGateway {
  ScriptedStreamingGateway({
    required this.deltas,
    this.pauseAfterDeltaIndex,
    this.deltaDelay = const Duration(milliseconds: 60),
  });

  final List<ModelStreamDelta> deltas;
  final int? pauseAfterDeltaIndex;
  final Duration deltaDelay;
  final Completer<void> completed = Completer<void>();
  final Completer<void> paused = Completer<void>();
  final Completer<void> _resume = Completer<void>();

  void resume() {
    if (!_resume.isCompleted) {
      _resume.complete();
    }
  }

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
    for (var index = 0; index < deltas.length; index++) {
      final delta = deltas[index];
      cancellation?.throwIfCancelled();
      onDelta?.call(delta);
      if (delta.contentDelta != null) {
        content.write(delta.contentDelta);
      }
      if (pauseAfterDeltaIndex == index) {
        if (!paused.isCompleted) {
          paused.complete();
        }
        await _resume.future;
      }
      await Future<void>.delayed(deltaDelay);
    }
    if (!completed.isCompleted) {
      completed.complete();
    }
    return ModelCompletion(content: content.toString());
  }
}

class ScriptedTitleGateway implements ModelGateway {
  ScriptedTitleGateway({required this.title, this.fail = false});

  final String title;
  final bool fail;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    if (fail) {
      throw const ModelGatewayException('标题生成失败');
    }
    return title;
  }
}

class ConversationTitleGateway implements ModelGateway {
  ConversationTitleGateway({
    required this.title,
    required this.reply,
    this.failTitle = false,
  });

  final String title;
  final String reply;
  final bool failTitle;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final prompt = messages.map((message) => message.content).join('\n');
    if (prompt.contains('会话标题')) {
      if (failTitle) {
        throw const ModelGatewayException('标题生成失败');
      }
      return title;
    }
    return reply;
  }
}
