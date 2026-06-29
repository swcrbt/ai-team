part of '../model_gateway.dart';

abstract class ModelGateway {
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  });
}

abstract class MetadataModelGateway implements ModelGateway {
  Future<ModelCompletion> completeWithMetadata({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
    ModelStreamDeltaHandler? onDelta,
    List<ModelToolDefinition> tools = const [],
    ModelToolChoice toolChoice = ModelToolChoice.auto,
    List<ModelToolRound> toolRounds = const [],
  });
}

typedef ModelStreamDeltaHandler = void Function(ModelStreamDelta delta);

class ModelStreamDelta {
  const ModelStreamDelta({
    this.contentDelta,
    this.thinkingDelta,
  });

  final String? contentDelta;
  final String? thinkingDelta;

  bool get isEmpty =>
      (contentDelta == null || contentDelta!.isEmpty) &&
      (thinkingDelta == null || thinkingDelta!.isEmpty);
}

enum ModelToolChoice { auto, none, required }

class ModelToolDefinition {
  const ModelToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;
  final Map<String, Object?> parameters;

  Map<String, Object?> toJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}

class ModelToolCall {
  const ModelToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final String arguments;

  Map<String, Object?> toChatJson() => {
        'id': id,
        'type': 'function',
        'function': {
          'name': name,
          'arguments': arguments,
        },
      };
}

class ModelToolResult {
  const ModelToolResult({
    required this.toolCallId,
    required this.name,
    required this.content,
  });

  final String toolCallId;
  final String name;
  final String content;

  Map<String, Object?> toChatJson() => {
        'role': 'tool',
        'tool_call_id': toolCallId,
        'name': name,
        'content': content,
      };
}

class ModelToolRound {
  const ModelToolRound({
    required this.calls,
    required this.results,
  });

  final List<ModelToolCall> calls;
  final List<ModelToolResult> results;
}

class ModelCompletion {
  const ModelCompletion({
    required this.content,
    this.thinkingContent,
    this.toolCalls = const [],
    this.diagnostics,
  });

  final String content;
  final String? thinkingContent;
  final List<ModelToolCall> toolCalls;
  final ModelResponseDiagnostics? diagnostics;
}

class ModelResponseDiagnostics {
  const ModelResponseDiagnostics({
    required this.streaming,
    required this.contentLength,
    required this.thinkingContentLength,
    this.thinkingFieldKeys = const [],
    this.contentDeltaCount = 0,
    this.thinkingDeltaCount = 0,
    this.toolCallCount = 0,
    this.rawToolCalls = const [],
    this.rawResponse,
    this.requestBody,
    this.requestUrl,
  });

  final bool streaming;
  final int contentLength;
  final int thinkingContentLength;
  final List<String> thinkingFieldKeys;
  final int contentDeltaCount;
  final int thinkingDeltaCount;
  final int toolCallCount;
  final List<Map<String, Object?>> rawToolCalls;
  final String? rawResponse;
  final Map<String, Object?>? requestBody;
  final String? requestUrl;

  bool get sawThinkingField => thinkingFieldKeys.isNotEmpty;

  Map<String, Object?> toJson() => {
        'streaming': streaming,
        'contentLength': contentLength,
        'thinkingContentLength': thinkingContentLength,
        'thinkingFieldKeys': thinkingFieldKeys,
        'contentDeltaCount': contentDeltaCount,
        'thinkingDeltaCount': thinkingDeltaCount,
        'toolCallCount': toolCallCount,
        'rawToolCalls': rawToolCalls,
        'rawResponse': rawResponse,
        'requestBody': requestBody,
        'requestUrl': requestUrl,
      };
}

class ModelRequestCancellation {
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  Future<void> get cancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }

  void throwIfCancelled() {
    if (isCancelled) {
      throw const ModelGatewayException('模型请求已取消');
    }
  }
}
