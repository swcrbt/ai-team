import 'dart:convert';
import 'dart:io';

import 'domain.dart';

abstract class ModelGateway {
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
  });
}

class OpenAiCompatibleGateway implements ModelGateway {
  OpenAiCompatibleGateway({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final HttpClient _httpClient;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
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
    final response = await request.close();
    final body = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ModelGatewayException('模型请求失败 ${response.statusCode}: $body');
    }
    final decoded = jsonDecode(body) as Map<String, Object?>;
    final choices = decoded['choices'] as List;
    final first = choices.first as Map<String, Object?>;
    final message = first['message'] as Map<String, Object?>;
    return message['content'] as String;
  }
}

class ModelGatewayException implements Exception {
  const ModelGatewayException(this.message);

  final String message;

  @override
  String toString() => message;
}
