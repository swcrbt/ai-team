part of '../model_gateway.dart';

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
