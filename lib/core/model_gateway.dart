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

class OpenAiCompatibleGateway implements ModelGateway {
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
    Object? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      cancellation?.throwIfCancelled();
      try {
        return await _sendOnce(
          model: model,
          systemPrompt: systemPrompt,
          messages: messages,
          cancellation: cancellation,
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

  Future<String> _sendOnce({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    final endpoint = Uri.parse(
      '${model.baseUrl.replaceFirst(RegExp(r'/$'), '')}/chat/completions',
    );
    final request = await _httpClient.postUrl(endpoint);
    request.headers.contentType = ContentType.json;
    request.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer ${model.apiKey}');
    request.write(jsonEncode({
      'model': model.modelName,
      'stream': false,
      'temperature': model.temperature,
      'max_tokens': model.maxTokens,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        ...messages.map((message) => {
              'role': message.isUser ? 'user' : 'assistant',
              'content': '${message.authorName}: ${message.content}',
            }),
      ],
    }));
    cancellation?.throwIfCancelled();
    final response = await _awaitResponse(request, cancellation);
    final body = await utf8.decodeStream(response);
    cancellation?.throwIfCancelled();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ModelGatewayException(
        '模型请求失败 ${response.statusCode}: $body',
        isRetryable: response.statusCode >= 500,
      );
    }
    final decoded = jsonDecode(body) as Map<String, Object?>;
    final choices = decoded['choices'] as List;
    final first = choices.first as Map<String, Object?>;
    final message = first['message'] as Map<String, Object?>;
    return message['content'] as String;
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

class ModelGatewayException implements Exception {
  const ModelGatewayException(this.message, {this.isRetryable = false});

  final String message;
  final bool isRetryable;

  @override
  String toString() => message;
}
