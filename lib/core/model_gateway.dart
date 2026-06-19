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

class ModelCompletion {
  const ModelCompletion({
    required this.content,
    this.thinkingContent,
    this.diagnostics,
  });

  final String content;
  final String? thinkingContent;
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
    this.rawResponse,
    this.requestBody,
  });

  final bool streaming;
  final int contentLength;
  final int thinkingContentLength;
  final List<String> thinkingFieldKeys;
  final int contentDeltaCount;
  final int thinkingDeltaCount;
  final String? rawResponse;
  final Map<String, Object?>? requestBody;

  bool get sawThinkingField => thinkingFieldKeys.isNotEmpty;

  Map<String, Object?> toJson() => {
        'streaming': streaming,
        'contentLength': contentLength,
        'thinkingContentLength': thinkingContentLength,
        'thinkingFieldKeys': thinkingFieldKeys,
        'contentDeltaCount': contentDeltaCount,
        'thinkingDeltaCount': thinkingDeltaCount,
        'rawResponse': rawResponse,
        'requestBody': requestBody,
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
}) async {
  if (gateway is MetadataModelGateway) {
    return gateway.completeWithMetadata(
      model: model,
      systemPrompt: systemPrompt,
      messages: messages,
      cancellation: cancellation,
      onDelta: onDelta,
    );
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
  }) async {
    final endpoint = Uri.parse(
      '${model.baseUrl.replaceFirst(RegExp(r'/$'), '')}/chat/completions',
    );
    final request = await _httpClient.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${model.apiKey}');
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
      ],
    };
    if (reasoningEffort == null) {
      requestBody['max_tokens'] = model.maxTokens;
    } else {
      requestBody['reasoning_effort'] = reasoningEffort;
      requestBody['max_completion_tokens'] = model.maxTokens;
    }
    request.write(jsonEncode(requestBody));
    cancellation?.throwIfCancelled();
    final response = await _awaitResponse(request, cancellation);
    cancellation?.throwIfCancelled();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await utf8.decodeStream(response);
      throw ModelGatewayException(
        '模型请求失败 ${response.statusCode}: $body',
        isRetryable: response.statusCode >= 500,
      );
    }
    if (model.streaming) {
      return _parseStreamingContent(
        response,
        requestBody: requestBody,
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
    return ModelCompletion(
      content: content,
      thinkingContent: thinkingContent,
      diagnostics: ModelResponseDiagnostics(
        streaming: false,
        contentLength: content.length,
        thinkingContentLength: thinkingContent?.length ?? 0,
        thinkingFieldKeys: thinkingFieldKeys.toList(growable: false),
        rawResponse: body,
        requestBody: requestBody,
      ),
    );
  }

  Future<ModelCompletion> _parseStreamingContent(
    HttpClientResponse response, {
    required Map<String, Object?> requestBody,
    ModelRequestCancellation? cancellation,
    ModelStreamDeltaHandler? onDelta,
  }) async {
    final buffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    final rawBuffer = StringBuffer();
    final thinkingFieldKeys = <String>{};
    var contentDeltaCount = 0;
    var thinkingDeltaCount = 0;
    final lines = response.transform(utf8.decoder).transform(
          const LineSplitter(),
        );
    await for (final line in lines) {
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
        final streamDelta = ModelStreamDelta(
          contentDelta: contentDelta,
          thinkingDelta: thinkingDelta,
        );
        if (!streamDelta.isEmpty) {
          onDelta?.call(streamDelta);
        }
      }
    }
    final thinkingContent = thinkingBuffer.toString();
    final content = buffer.toString();
    final normalizedThinkingContent = _normalizeOptionalText(thinkingContent);
    return ModelCompletion(
      content: content,
      thinkingContent: normalizedThinkingContent,
      diagnostics: ModelResponseDiagnostics(
        streaming: true,
        contentLength: content.length,
        thinkingContentLength: normalizedThinkingContent?.length ?? 0,
        thinkingFieldKeys: thinkingFieldKeys.toList(growable: false),
        contentDeltaCount: contentDeltaCount,
        thinkingDeltaCount: thinkingDeltaCount,
        rawResponse: rawBuffer.toString(),
        requestBody: requestBody,
      ),
    );
  }

  Future<HttpClientResponse> _awaitResponse(
    HttpClientRequest request,
    ModelRequestCancellation? cancellation,
  ) {
    final response = request.close().timeout(requestTimeout);
    if (cancellation == null) {
      return response;
    }
    return Future.any<HttpClientResponse>([
      response,
      cancellation.cancelled.then<HttpClientResponse>(
        (_) => throw const ModelGatewayException('模型请求已取消'),
      ),
    ]);
  }
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
