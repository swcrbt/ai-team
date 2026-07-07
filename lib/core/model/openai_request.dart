import '../domain.dart';
import 'gateway_contracts.dart';

Map<String, Object?> buildOpenAiCompatibleRequestBody({
  required ModelProfile model,
  required String systemPrompt,
  required List<ChatMessage> messages,
  Map<String, String> imageDataUrls = const {},
  List<ModelToolDefinition> tools = const [],
  ModelToolChoice toolChoice = ModelToolChoice.auto,
  List<ModelToolRound> toolRounds = const [],
}) {
  final reasoningEffort = model.reasoningEffort == null
      ? null
      : _normalizeOptionalRequestText(model.reasoningEffort!);
  final requestBody = <String, Object?>{
    'model': model.modelName,
    'stream': model.streaming,
    'temperature': model.temperature,
    'messages': [
      {'role': 'system', 'content': systemPrompt},
      ...messages.map((message) => _messageToOpenAiJson(
            message,
            imageDataUrls: imageDataUrls,
          )),
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

Map<String, Object?> _messageToOpenAiJson(
  ChatMessage message, {
  required Map<String, String> imageDataUrls,
}) {
  final text = '${message.authorName}: ${message.content}';
  final imageParts = [
    for (final attachment in message.attachments)
      if (attachment.type == MessageAttachmentType.image &&
          imageDataUrls.containsKey(attachment.id))
        {
          'type': 'image_url',
          'image_url': {
            'url': imageDataUrls[attachment.id],
            'detail': attachment.detail.name,
          },
        },
  ];
  return {
    'role': message.isUser ? 'user' : 'assistant',
    'content': imageParts.isEmpty
        ? text
        : [
            {'type': 'text', 'text': text},
            ...imageParts,
          ],
  };
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

Uri openAiCompatibleChatCompletionsEndpoint(ModelProfile model) {
  final baseUrl = model.baseUrl.replaceFirst(RegExp(r'/$'), '');
  final endpoint = switch (model.protocol) {
    ModelProtocol.anthropic => '/v1/messages',
    ModelProtocol.responses => '/responses',
    ModelProtocol.chatCompletions => '/chat/completions',
  };
  return Uri.parse('$baseUrl$endpoint');
}

String? _normalizeOptionalRequestText(String value) {
  return value.trim().isEmpty ? null : value;
}
