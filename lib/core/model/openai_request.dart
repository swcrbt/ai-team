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
  if (model.protocol == ModelProtocol.responses) {
    return _buildOpenAiResponsesRequestBody(
      model: model,
      systemPrompt: systemPrompt,
      messages: messages,
      imageDataUrls: imageDataUrls,
      tools: tools,
      toolChoice: toolChoice,
      toolRounds: toolRounds,
    );
  }
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

Map<String, Object?> _buildOpenAiResponsesRequestBody({
  required ModelProfile model,
  required String systemPrompt,
  required List<ChatMessage> messages,
  required Map<String, String> imageDataUrls,
  required List<ModelToolDefinition> tools,
  required ModelToolChoice toolChoice,
  required List<ModelToolRound> toolRounds,
}) {
  final reasoningEffort = model.reasoningEffort == null
      ? null
      : _normalizeOptionalRequestText(model.reasoningEffort!);
  final requestBody = <String, Object?>{
    'model': model.modelName,
    'stream': model.streaming,
    'temperature': model.temperature,
    'input': [
      _responsesInputMessage(
        role: 'system',
        text: systemPrompt,
      ),
      ...messages.map((message) => _messageToResponsesInputJson(
            message,
            imageDataUrls: imageDataUrls,
          )),
      ..._responsesToolRoundItems(toolRounds),
    ],
    'max_output_tokens': model.maxTokens,
  };
  if (tools.isNotEmpty) {
    requestBody['tools'] = tools.map(_toolToResponsesJson).toList();
    requestBody['tool_choice'] = toolChoice.name;
  }
  if (reasoningEffort != null) {
    requestBody['reasoning'] = {'effort': reasoningEffort};
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

Map<String, Object?> _messageToResponsesInputJson(
  ChatMessage message, {
  required Map<String, String> imageDataUrls,
}) {
  final text = '${message.authorName}: ${message.content}';
  final content = <Map<String, Object?>>[
    {
      'type': message.isUser ? 'input_text' : 'output_text',
      'text': text,
    },
    for (final attachment in message.attachments)
      if (attachment.type == MessageAttachmentType.image &&
          imageDataUrls.containsKey(attachment.id))
        {
          'type': 'input_image',
          'image_url': imageDataUrls[attachment.id],
          'detail': attachment.detail.name,
        },
  ];
  return {
    if (!message.isUser) 'type': 'message',
    'role': message.isUser ? 'user' : 'assistant',
    'content': content,
  };
}

Map<String, Object?> _responsesInputMessage({
  required String role,
  required String text,
}) =>
    {
      'role': role,
      'content': [
        {'type': 'input_text', 'text': text},
      ],
    };

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

List<Map<String, Object?>> _responsesToolRoundItems(
  List<ModelToolRound> rounds,
) {
  return [
    for (final round in rounds) ...[
      ...round.calls.map((call) => {
            'type': 'function_call',
            'call_id': call.id,
            'name': call.name,
            'arguments': call.arguments,
          }),
      ...round.results.map((result) => {
            'type': 'function_call_output',
            'call_id': result.toolCallId,
            'output': result.content,
          }),
    ],
  ];
}

Map<String, Object?> _toolToResponsesJson(ModelToolDefinition tool) => {
      'type': 'function',
      'name': tool.name,
      'description': tool.description,
      'parameters': tool.parameters,
    };

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
