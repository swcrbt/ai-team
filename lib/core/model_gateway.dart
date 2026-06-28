import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'domain.dart';

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

Future<ModelCompletion> completeModelWithMetadata(
  ModelGateway gateway, {
  required ModelProfile model,
  required String systemPrompt,
  required List<ChatMessage> messages,
  ModelRequestCancellation? cancellation,
  ModelStreamDeltaHandler? onDelta,
  List<ModelToolDefinition> tools = const [],
  ModelToolChoice toolChoice = ModelToolChoice.auto,
  List<ModelToolRound> toolRounds = const [],
}) async {
  if (gateway is MetadataModelGateway) {
    return gateway.completeWithMetadata(
      model: model,
      systemPrompt: systemPrompt,
      messages: messages,
      cancellation: cancellation,
      onDelta: onDelta,
      tools: tools,
      toolChoice: toolChoice,
      toolRounds: toolRounds,
    );
  }
  if (tools.isNotEmpty || toolRounds.isNotEmpty) {
    throw const ModelGatewayException('当前模型网关不支持原生工具调用');
  }
  final content = await gateway.complete(
    model: model,
    systemPrompt: systemPrompt,
    messages: messages,
    cancellation: cancellation,
  );
  return ModelCompletion(
    content: content,
    diagnostics: ModelResponseDiagnostics(
      streaming: model.streaming,
      contentLength: content.length,
      thinkingContentLength: 0,
      rawResponse: content,
    ),
  );
}

Map<String, Object?> buildOpenAiCompatibleRequestBody({
  required ModelProfile model,
  required String systemPrompt,
  required List<ChatMessage> messages,
  List<ModelToolDefinition> tools = const [],
  ModelToolChoice toolChoice = ModelToolChoice.auto,
  List<ModelToolRound> toolRounds = const [],
}) {
  final reasoningEffort = model.reasoningEffort == null
      ? null
      : _normalizeOptionalText(model.reasoningEffort!);
  final requestBody = <String, Object?>{
    'model': model.modelName,
    'stream': model.streaming,
    'temperature': model.temperature,
    'messages': [
      {'role': 'system', 'content': systemPrompt},
      ...messages.map((message) => {
            'role': message.isUser ? 'user' : 'assistant',
            'content': '${message.authorName}: ${message.content}',
          }),
      ..._toolRoundMessages(toolRounds),
    ],
  };
  if (tools.isNotEmpty) {
    requestBody['tools'] = tools.map((tool) => tool.toJson()).toList();
    requestBody['tool_choice'] = toolChoice.name;
  }
  if (reasoningEffort == null) {
    requestBody['max_tokens'] = model.maxTokens;
  } else {
    requestBody['reasoning_effort'] = reasoningEffort;
    requestBody['max_completion_tokens'] = model.maxTokens;
  }
  return requestBody;
}

List<Map<String, Object?>> _toolRoundMessages(List<ModelToolRound> rounds) {
  return [
    for (final round in rounds) ...[
      {
        'role': 'assistant',
        'content': null,
        'tool_calls': round.calls.map((call) => call.toChatJson()).toList(),
      },
      ...round.results.map((result) => result.toChatJson()),
    ],
  ];
}

Uri openAiCompatibleChatCompletionsEndpoint(ModelProfile model) => Uri.parse(
      '${model.baseUrl.replaceFirst(RegExp(r'/$'), '')}/chat/completions',
    );

class OpenAiCompatibleGateway implements MetadataModelGateway {
  OpenAiCompatibleGateway({
    HttpClient? httpClient,
    this.requestTimeout = const Duration(seconds: 60),
    this.maxRetries = 2,
    this.retryDelay = const Duration(milliseconds: 300),
  }) : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;
  final Duration requestTimeout;
  final int maxRetries;
  final Duration retryDelay;

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
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      cancellation?.throwIfCancelled();
      try {
        return await _sendOnce(
          model: model,
          systemPrompt: systemPrompt,
          messages: messages,
          cancellation: cancellation,
          onDelta: onDelta,
          tools: tools,
          toolChoice: toolChoice,
          toolRounds: toolRounds,
        );
      } on ModelGatewayException catch (error) {
        lastError = error;
        if (!error.isRetryable || attempt >= maxRetries) {
          rethrow;
        }
      } on SocketException catch (error) {
        lastError = error;
        if (attempt >= maxRetries) {
          throw ModelGatewayException('模型网络请求失败: ${error.message}');
        }
      } on TimeoutException catch (_) {
        lastError = const ModelGatewayException('模型请求超时');
        if (attempt >= maxRetries) {
          throw const ModelGatewayException('模型请求超时');
        }
      }
      if (retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }
    }
    throw ModelGatewayException('模型请求失败: $lastError');
  }

  Future<ModelCompletion> _sendOnce({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
    ModelStreamDeltaHandler? onDelta,
    List<ModelToolDefinition> tools = const [],
    ModelToolChoice toolChoice = ModelToolChoice.auto,
    List<ModelToolRound> toolRounds = const [],
  }) async {
    final endpoint = openAiCompatibleChatCompletionsEndpoint(model);
    final requestUrl = endpoint.toString();
    final request = await _openRequest(endpoint, cancellation);
    request.headers.contentType = ContentType.json;
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${model.apiKey}');
    final requestBody = buildOpenAiCompatibleRequestBody(
      model: model,
      systemPrompt: systemPrompt,
      messages: messages,
      tools: tools,
      toolChoice: toolChoice,
      toolRounds: toolRounds,
    );
    request.write(jsonEncode(requestBody));
    cancellation?.throwIfCancelled();
    final response = await _awaitResponse(request, cancellation);
    cancellation?.throwIfCancelled();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await utf8.decodeStream(response);
      if (response.statusCode == HttpStatus.badRequest &&
          requestBody.containsKey('tools')) {
        throw ModelGatewayException(
          '当前模型/接口不支持原生工具调用: $body',
          isRetryable: false,
        );
      }
      throw ModelGatewayException(
        '模型请求失败 ${response.statusCode}: $body',
        isRetryable: response.statusCode >= 500,
      );
    }
    if (model.streaming) {
      return _parseStreamingContent(
        response,
        requestBody: requestBody,
        requestUrl: requestUrl,
        cancellation: cancellation,
        onDelta: onDelta,
      );
    }
    final body = await utf8.decodeStream(response);
    final decoded = jsonDecode(body) as Map<String, Object?>;
    final choices = decoded['choices'] as List;
    final first = choices.first as Map<String, Object?>;
    final message = first['message'] as Map<String, Object?>;
    final thinkingFieldKeys = <String>{};
    final thinkingContent = _firstStringValue(
      message,
      const ['reasoning_content', 'reasoning', 'thinking'],
      keysSeen: thinkingFieldKeys,
    );
    final content = message['content'] as String? ?? '';
    final toolCalls = _parseToolCalls(message['tool_calls']);
    return ModelCompletion(
      content: content,
      thinkingContent: thinkingContent,
      toolCalls: toolCalls,
      diagnostics: ModelResponseDiagnostics(
        streaming: false,
        contentLength: content.length,
        thinkingContentLength: thinkingContent?.length ?? 0,
        thinkingFieldKeys: thinkingFieldKeys.toList(growable: false),
        toolCallCount: toolCalls.length,
        rawToolCalls: _rawToolCalls(message['tool_calls']),
        rawResponse: body,
        requestBody: requestBody,
        requestUrl: requestUrl,
      ),
    );
  }

  Future<ModelCompletion> _parseStreamingContent(
    HttpClientResponse response, {
    required Map<String, Object?> requestBody,
    required String requestUrl,
    ModelRequestCancellation? cancellation,
    ModelStreamDeltaHandler? onDelta,
  }) async {
    final buffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    final rawBuffer = StringBuffer();
    final thinkingFieldKeys = <String>{};
    final toolCallBuilders = <int, _StreamingToolCallBuilder>{};
    var contentDeltaCount = 0;
    var thinkingDeltaCount = 0;
    final lines = response.transform(utf8.decoder).transform(
          const LineSplitter(),
        );
    final iterator = StreamIterator<String>(lines);
    try {
      while (await _moveNextStreamingLine(iterator, cancellation)) {
        final line = iterator.current;
        cancellation?.throwIfCancelled();
        rawBuffer
          ..write(line)
          ..write('\n');
        final trimmed = line.trim();
        if (trimmed.isEmpty || !trimmed.startsWith('data:')) {
          continue;
        }
        final data = trimmed.substring('data:'.length).trim();
        if (data == '[DONE]') {
          break;
        }
        final decoded = jsonDecode(data) as Map<String, Object?>;
        final choices = decoded['choices'] as List;
        for (final item in choices) {
          final choice = item as Map<String, Object?>;
          final delta = choice['delta'] as Map<String, Object?>?;
          final content = delta?['content'];
          String? contentDelta;
          if (content is String) {
            buffer.write(content);
            contentDelta = content;
            contentDeltaCount++;
          }
          final thinkingDelta = _firstStringValue(
            delta,
            const ['reasoning_content', 'reasoning', 'thinking'],
            keysSeen: thinkingFieldKeys,
          );
          if (thinkingDelta != null) {
            thinkingBuffer.write(thinkingDelta);
            thinkingDeltaCount++;
          }
          _appendStreamingToolCalls(delta?['tool_calls'], toolCallBuilders);
          final streamDelta = ModelStreamDelta(
            contentDelta: contentDelta,
            thinkingDelta: thinkingDelta,
          );
          if (!streamDelta.isEmpty) {
            onDelta?.call(streamDelta);
          }
        }
      }
    } finally {
      await iterator.cancel();
    }
    final thinkingContent = thinkingBuffer.toString();
    final content = buffer.toString();
    final normalizedThinkingContent = _normalizeOptionalText(thinkingContent);
    final toolCalls = _completeStreamingToolCalls(toolCallBuilders);
    return ModelCompletion(
      content: content,
      thinkingContent: normalizedThinkingContent,
      toolCalls: toolCalls,
      diagnostics: ModelResponseDiagnostics(
        streaming: true,
        contentLength: content.length,
        thinkingContentLength: normalizedThinkingContent?.length ?? 0,
        thinkingFieldKeys: thinkingFieldKeys.toList(growable: false),
        contentDeltaCount: contentDeltaCount,
        thinkingDeltaCount: thinkingDeltaCount,
        toolCallCount: toolCalls.length,
        rawToolCalls: toolCalls.map((call) => call.toChatJson()).toList(),
        rawResponse: rawBuffer.toString(),
        requestBody: requestBody,
        requestUrl: requestUrl,
      ),
    );
  }

  Future<HttpClientResponse> _awaitResponse(
    HttpClientRequest request,
    ModelRequestCancellation? cancellation,
  ) {
    final response = request.close().timeout(requestTimeout).catchError((
      Object error,
    ) {
      cancellation?.throwIfCancelled();
      throw error;
    });
    if (cancellation == null) {
      return response;
    }
    return Future.any<HttpClientResponse>([
      response,
      cancellation.cancelled.then<HttpClientResponse>((_) {
        request.abort(const ModelGatewayException('模型请求已取消'));
        throw const ModelGatewayException('模型请求已取消');
      }),
    ]);
  }

  Future<HttpClientRequest> _openRequest(
    Uri endpoint,
    ModelRequestCancellation? cancellation,
  ) {
    final request = _httpClient.postUrl(endpoint);
    if (cancellation == null) {
      return request;
    }
    unawaited(
      request.then<void>(
        (value) {
          if (cancellation.isCancelled) {
            value.abort(const ModelGatewayException('模型请求已取消'));
          }
        },
        onError: (_) {},
      ),
    );
    final guardedRequest = request.catchError((Object error) {
      cancellation.throwIfCancelled();
      throw error;
    });
    return Future.any<HttpClientRequest>([
      guardedRequest,
      cancellation.cancelled.then<HttpClientRequest>(
        (_) => throw const ModelGatewayException('模型请求已取消'),
      ),
    ]);
  }
}

Future<bool> _moveNextStreamingLine(
  StreamIterator<String> iterator,
  ModelRequestCancellation? cancellation,
) {
  if (cancellation == null) {
    return iterator.moveNext();
  }
  return Future.any<bool>([
    iterator.moveNext(),
    cancellation.cancelled.then<bool>(
      (_) => throw const ModelGatewayException('模型请求已取消'),
    ),
  ]);
}

List<ModelToolCall> _parseToolCalls(Object? value) {
  if (value is! List) {
    return const [];
  }
  final calls = <ModelToolCall>[];
  for (final item in value) {
    if (item is! Map) {
      continue;
    }
    final json = Map<String, Object?>.from(item);
    final function = json['function'];
    if (function is! Map) {
      continue;
    }
    final functionJson = Map<String, Object?>.from(function);
    final id = json['id'];
    final name = functionJson['name'];
    final arguments = functionJson['arguments'];
    if (id is String && name is String) {
      calls.add(
        ModelToolCall(
          id: id,
          name: name,
          arguments: arguments is String ? arguments : '',
        ),
      );
    }
  }
  return calls;
}

List<Map<String, Object?>> _rawToolCalls(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}

void _appendStreamingToolCalls(
  Object? value,
  Map<int, _StreamingToolCallBuilder> builders,
) {
  if (value is! List) {
    return;
  }
  for (final item in value) {
    if (item is! Map) {
      continue;
    }
    final json = Map<String, Object?>.from(item);
    final indexValue = json['index'];
    if (indexValue is! num) {
      continue;
    }
    final index = indexValue.toInt();
    final builder = builders.putIfAbsent(
      index,
      () => _StreamingToolCallBuilder(),
    );
    final id = json['id'];
    if (id is String && id.isNotEmpty) {
      builder.id = id;
    }
    final function = json['function'];
    if (function is Map) {
      final functionJson = Map<String, Object?>.from(function);
      final name = functionJson['name'];
      if (name is String && name.isNotEmpty) {
        builder.name = name;
      }
      final arguments = functionJson['arguments'];
      if (arguments is String) {
        builder.arguments.write(arguments);
      }
    }
  }
}

List<ModelToolCall> _completeStreamingToolCalls(
  Map<int, _StreamingToolCallBuilder> builders,
) {
  final indexes = builders.keys.toList()..sort();
  return [
    for (final index in indexes)
      if (builders[index]!.isComplete) builders[index]!.build(),
  ];
}

class _StreamingToolCallBuilder {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();

  bool get isComplete => id != null && name != null;

  ModelToolCall build() => ModelToolCall(
        id: id!,
        name: name!,
        arguments: arguments.toString(),
      );
}

String? _firstStringValue(
  Map<String, Object?>? json,
  List<String> keys, {
  Set<String>? keysSeen,
}) {
  if (json == null) {
    return null;
  }
  for (final key in keys) {
    if (json.containsKey(key)) {
      keysSeen?.add(key);
    }
    final value = json[key];
    if (value is String) {
      final normalized = _normalizeOptionalText(value);
      if (normalized != null) {
        return normalized;
      }
    }
  }
  return null;
}

String? _normalizeOptionalText(String value) {
  return value.trim().isEmpty ? null : value;
}

class ModelGatewayException implements Exception {
  const ModelGatewayException(this.message, {this.isRetryable = false});

  final String message;
  final bool isRetryable;

  @override
  String toString() => message;
}
