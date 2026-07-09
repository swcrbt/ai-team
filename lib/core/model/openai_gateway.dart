import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain.dart';
import 'anthropic_request.dart';
import 'anthropic_response.dart';
import 'gateway_contracts.dart';
import 'model_gateway_exception.dart';
import 'openai_request.dart';
import 'openai_stream_parsing.dart';

typedef ImageDataUrlResolver = Future<String> Function(
  MessageAttachment attachment,
);

class OpenAiCompatibleGateway implements MetadataModelGateway {
  OpenAiCompatibleGateway({
    HttpClient? httpClient,
    this.imageDataUrlResolver,
    this.requestTimeout = const Duration(seconds: 60),
    this.maxRetries = 2,
    this.retryDelay = const Duration(milliseconds: 300),
  }) : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;
  final ImageDataUrlResolver? imageDataUrlResolver;
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
    if (model.protocol == ModelProtocol.anthropic) {
      request.headers.set('x-api-key', model.apiKey);
      request.headers.set('anthropic-version', '2023-06-01');
    } else {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${model.apiKey}',
      );
    }

    final imageDataUrls = await _resolveImageDataUrls(messages);

    final requestBody = model.protocol == ModelProtocol.anthropic
        ? buildAnthropicRequestBody(
            model: model,
            systemPrompt: systemPrompt,
            messages: messages,
            imageDataUrls: imageDataUrls,
            tools: tools,
            toolChoice: toolChoice,
            toolRounds: toolRounds,
          )
        : buildOpenAiCompatibleRequestBody(
            model: model,
            systemPrompt: systemPrompt,
            messages: messages,
            imageDataUrls: imageDataUrls,
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
      throw ModelGatewayException(
        '模型请求失败 ${response.statusCode}: $body',
        isRetryable: response.statusCode >= 500,
      );
    }
    if (model.streaming) {
      if (model.protocol == ModelProtocol.anthropic) {
        return parseAnthropicStreamingResponse(
          responseStream: response,
          requestBody: requestBody,
          requestUrl: requestUrl,
          cancellation: cancellation,
          onDelta: onDelta,
        );
      }
      if (model.protocol == ModelProtocol.responses) {
        return _parseResponsesStreamingContent(
          response,
          requestBody: requestBody,
          requestUrl: requestUrl,
          cancellation: cancellation,
          onDelta: onDelta,
        );
      }
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

    if (model.protocol == ModelProtocol.anthropic) {
      return parseAnthropicResponse(
        response: decoded,
        requestBody: requestBody,
        requestUrl: requestUrl,
      );
    }

    if (model.protocol == ModelProtocol.responses) {
      return _parseResponsesContent(
        decoded,
        rawBody: body,
        requestBody: requestBody,
        requestUrl: requestUrl,
      );
    }

    final choices = decoded['choices'] as List;
    final first = choices.first as Map<String, Object?>;
    final message = first['message'] as Map<String, Object?>;
    final thinkingFieldKeys = <String>{};
    final thinkingContent = firstStringValue(
      message,
      const ['reasoning_content', 'reasoning', 'thinking'],
      keysSeen: thinkingFieldKeys,
    );
    final content = message['content'] as String? ?? '';
    final toolCalls = parseToolCalls(message['tool_calls']);
    final usage = parseTokenUsage(decoded['usage']);
    return ModelCompletion(
      content: content,
      thinkingContent: thinkingContent,
      toolCalls: toolCalls,
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      cachedTokens: usage.cachedTokens,
      totalTokens: usage.totalTokens,
      diagnostics: ModelResponseDiagnostics(
        streaming: false,
        contentLength: content.length,
        thinkingContentLength: thinkingContent?.length ?? 0,
        thinkingFieldKeys: thinkingFieldKeys.toList(growable: false),
        toolCallCount: toolCalls.length,
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        cachedTokens: usage.cachedTokens,
        totalTokens: usage.totalTokens,
        rawToolCalls: rawToolCalls(message['tool_calls']),
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
    final toolCallBuilders = <int, StreamingToolCallBuilder>{};
    var contentDeltaCount = 0;
    var thinkingDeltaCount = 0;
    var usage = const ModelTokenUsage();
    final lines = response.transform(utf8.decoder).transform(
          const LineSplitter(),
        );
    final iterator = StreamIterator<String>(lines);
    try {
      while (await moveNextStreamingLine(iterator, cancellation)) {
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
        final parsedUsage = parseTokenUsage(decoded['usage']);
        if (!parsedUsage.isEmpty) {
          usage = parsedUsage;
        }
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
          final thinkingDelta = firstStringValue(
            delta,
            const ['reasoning_content', 'reasoning', 'thinking'],
            keysSeen: thinkingFieldKeys,
          );
          if (thinkingDelta != null) {
            thinkingBuffer.write(thinkingDelta);
            thinkingDeltaCount++;
          }
          appendStreamingToolCalls(delta?['tool_calls'], toolCallBuilders);
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
    final normalizedThinkingContent = normalizeOptionalText(thinkingContent);
    final toolCalls = completeStreamingToolCalls(toolCallBuilders);
    return ModelCompletion(
      content: content,
      thinkingContent: normalizedThinkingContent,
      toolCalls: toolCalls,
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      cachedTokens: usage.cachedTokens,
      totalTokens: usage.totalTokens,
      diagnostics: ModelResponseDiagnostics(
        streaming: true,
        contentLength: content.length,
        thinkingContentLength: normalizedThinkingContent?.length ?? 0,
        thinkingFieldKeys: thinkingFieldKeys.toList(growable: false),
        contentDeltaCount: contentDeltaCount,
        thinkingDeltaCount: thinkingDeltaCount,
        toolCallCount: toolCalls.length,
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        cachedTokens: usage.cachedTokens,
        totalTokens: usage.totalTokens,
        rawToolCalls: toolCalls.map((call) => call.toChatJson()).toList(),
        rawResponse: rawBuffer.toString(),
        requestBody: requestBody,
        requestUrl: requestUrl,
      ),
    );
  }

  ModelCompletion _parseResponsesContent(
    Map<String, Object?> decoded, {
    required String rawBody,
    required Map<String, Object?> requestBody,
    required String requestUrl,
  }) {
    final contentBuffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    final thinkingFieldKeys = <String>{};
    final toolCalls = <ModelToolCall>[];
    final rawToolCallItems = <Map<String, Object?>>[];
    final outputText = decoded['output_text'];
    if (outputText is String) {
      contentBuffer.write(outputText);
    }
    final output = decoded['output'];
    if (output is List) {
      for (final item in output) {
        if (item is! Map) {
          continue;
        }
        final json = Map<String, Object?>.from(item);
        switch (json['type']) {
          case 'message':
            _appendResponsesMessageContent(json['content'], contentBuffer);
          case 'function_call':
            final call = _parseResponsesFunctionCall(json);
            if (call != null) {
              toolCalls.add(call);
              rawToolCallItems.add(json);
            }
          case 'reasoning':
            final thinking = _responsesReasoningText(json);
            if (thinking != null) {
              thinkingFieldKeys.add('reasoning');
              thinkingBuffer.write(thinking);
            }
        }
      }
    }
    final content = contentBuffer.toString();
    final thinkingContent = normalizeOptionalText(thinkingBuffer.toString());
    final usage = parseTokenUsage(decoded['usage']);
    return ModelCompletion(
      content: content,
      thinkingContent: thinkingContent,
      toolCalls: toolCalls,
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      cachedTokens: usage.cachedTokens,
      totalTokens: usage.totalTokens,
      diagnostics: ModelResponseDiagnostics(
        streaming: false,
        contentLength: content.length,
        thinkingContentLength: thinkingContent?.length ?? 0,
        thinkingFieldKeys: thinkingFieldKeys.toList(growable: false),
        toolCallCount: toolCalls.length,
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        cachedTokens: usage.cachedTokens,
        totalTokens: usage.totalTokens,
        rawToolCalls: rawToolCallItems,
        rawResponse: rawBody,
        requestBody: requestBody,
        requestUrl: requestUrl,
      ),
    );
  }

  Future<ModelCompletion> _parseResponsesStreamingContent(
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
    final toolCalls = <ModelToolCall>[];
    final rawToolCallItems = <Map<String, Object?>>[];
    var contentDeltaCount = 0;
    var thinkingDeltaCount = 0;
    var usage = const ModelTokenUsage();
    final lines = response.transform(utf8.decoder).transform(
          const LineSplitter(),
        );
    final iterator = StreamIterator<String>(lines);
    try {
      while (await moveNextStreamingLine(iterator, cancellation)) {
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
        switch (decoded['type']) {
          case 'response.output_text.delta':
            final delta = decoded['delta'];
            if (delta is String && delta.isNotEmpty) {
              buffer.write(delta);
              contentDeltaCount++;
              onDelta?.call(ModelStreamDelta(contentDelta: delta));
            }
          case 'response.reasoning_summary_text.delta':
          case 'response.reasoning_text.delta':
            final delta = decoded['delta'];
            if (delta is String && delta.isNotEmpty) {
              thinkingFieldKeys.add('reasoning');
              thinkingBuffer.write(delta);
              thinkingDeltaCount++;
              onDelta?.call(ModelStreamDelta(thinkingDelta: delta));
            }
          case 'response.output_item.done':
            final item = decoded['item'];
            if (item is Map) {
              final json = Map<String, Object?>.from(item);
              final call = _parseResponsesFunctionCall(json);
              if (call != null) {
                toolCalls.add(call);
                rawToolCallItems.add(json);
              }
            }
          case 'response.completed':
            final responseJson = decoded['response'];
            if (responseJson is Map) {
              final parsedUsage = parseTokenUsage(
                Map<String, Object?>.from(responseJson)['usage'],
              );
              if (!parsedUsage.isEmpty) {
                usage = parsedUsage;
              }
              if (buffer.isEmpty && toolCalls.isEmpty) {
                final completion = _parseResponsesContent(
                  Map<String, Object?>.from(responseJson),
                  rawBody: jsonEncode(responseJson),
                  requestBody: requestBody,
                  requestUrl: requestUrl,
                );
                buffer.write(completion.content);
                final thinking = completion.thinkingContent;
                if (thinking != null) {
                  thinkingFieldKeys.addAll(
                    completion.diagnostics?.thinkingFieldKeys ??
                        const <String>[],
                  );
                  thinkingBuffer.write(thinking);
                }
                toolCalls.addAll(completion.toolCalls);
                rawToolCallItems.addAll(
                  completion.diagnostics?.rawToolCalls ??
                      const <Map<String, Object?>>[],
                );
              }
            }
        }
      }
    } finally {
      await iterator.cancel();
    }
    final content = buffer.toString();
    final thinkingContent = normalizeOptionalText(thinkingBuffer.toString());
    return ModelCompletion(
      content: content,
      thinkingContent: thinkingContent,
      toolCalls: toolCalls,
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      cachedTokens: usage.cachedTokens,
      totalTokens: usage.totalTokens,
      diagnostics: ModelResponseDiagnostics(
        streaming: true,
        contentLength: content.length,
        thinkingContentLength: thinkingContent?.length ?? 0,
        thinkingFieldKeys: thinkingFieldKeys.toList(growable: false),
        contentDeltaCount: contentDeltaCount,
        thinkingDeltaCount: thinkingDeltaCount,
        toolCallCount: toolCalls.length,
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        cachedTokens: usage.cachedTokens,
        totalTokens: usage.totalTokens,
        rawToolCalls: rawToolCallItems,
        rawResponse: rawBuffer.toString(),
        requestBody: requestBody,
        requestUrl: requestUrl,
      ),
    );
  }

  Future<Map<String, String>> _resolveImageDataUrls(
    List<ChatMessage> messages,
  ) async {
    final resolver = imageDataUrlResolver;
    if (resolver == null) {
      return const {};
    }
    final dataUrls = <String, String>{};
    for (final message in messages) {
      for (final attachment in message.attachments) {
        if (attachment.type != MessageAttachmentType.image) {
          continue;
        }
        try {
          dataUrls[attachment.id] = await resolver(attachment);
        } catch (error) {
          throw ModelGatewayException('图片读取失败：$error', isRetryable: false);
        }
      }
    }
    return dataUrls;
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

void _appendResponsesMessageContent(Object? value, StringBuffer buffer) {
  if (value is String) {
    buffer.write(value);
    return;
  }
  if (value is! List) {
    return;
  }
  for (final item in value) {
    if (item is! Map) {
      continue;
    }
    final json = Map<String, Object?>.from(item);
    final text = json['text'];
    if (text is String) {
      buffer.write(text);
      continue;
    }
    final refusal = json['refusal'];
    if (refusal is String) {
      buffer.write(refusal);
    }
  }
}

ModelToolCall? _parseResponsesFunctionCall(Map<String, Object?> json) {
  if (json['type'] != 'function_call') {
    return null;
  }
  final id = json['call_id'] ?? json['id'];
  final name = json['name'];
  final arguments = json['arguments'];
  if (id is! String || name is! String) {
    return null;
  }
  return ModelToolCall(
    id: id,
    name: name,
    arguments: arguments is String ? arguments : jsonEncode(arguments),
  );
}

String? _responsesReasoningText(Map<String, Object?> json) {
  final direct = firstStringValue(
    json,
    const ['text', 'content', 'summary_text'],
  );
  if (direct != null) {
    return direct;
  }
  final summary = json['summary'];
  if (summary is! List) {
    return null;
  }
  final parts = <String>[];
  for (final item in summary) {
    if (item is! Map) {
      continue;
    }
    final text = firstStringValue(
      Map<String, Object?>.from(item),
      const ['text', 'content', 'summary_text'],
    );
    if (text != null) {
      parts.add(text);
    }
  }
  return normalizeOptionalText(parts.join('\n'));
}
