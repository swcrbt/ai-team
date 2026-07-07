import 'dart:convert';

import '../domain.dart';
import 'gateway_contracts.dart';

/// 构建 Anthropic Messages API 请求体
Map<String, Object?> buildAnthropicRequestBody({
  required ModelProfile model,
  required String systemPrompt,
  required List<ChatMessage> messages,
  Map<String, String> imageDataUrls = const {},
  List<ModelToolDefinition> tools = const [],
  ModelToolChoice toolChoice = ModelToolChoice.auto,
  List<ModelToolRound> toolRounds = const [],
}) {
  final requestBody = <String, Object?>{
    'model': model.modelName,
    'max_tokens': model.maxTokens,
    'temperature': model.temperature,
    'stream': model.streaming,
  };

  // System prompt 作为顶层字段
  final normalizedSystemPrompt = systemPrompt.trim();
  if (normalizedSystemPrompt.isNotEmpty) {
    requestBody['system'] = normalizedSystemPrompt;
  }

  // 构建 messages 数组（不包含 system 消息）
  requestBody['messages'] = [
    ...messages.map((message) => _messageToAnthropicJson(
          message,
          imageDataUrls: imageDataUrls,
        )),
    ..._buildToolRoundMessages(toolRounds),
  ];

  // 添加工具定义（如果有）
  if (tools.isNotEmpty) {
    requestBody['tools'] = tools.map(_convertToolToAnthropic).toList();

    // Anthropic 的 tool_choice 格式
    if (toolChoice == ModelToolChoice.required) {
      requestBody['tool_choice'] = {'type': 'any'};
    } else if (toolChoice == ModelToolChoice.none) {
      requestBody['tool_choice'] = {'type': 'auto'};
    }
    // auto 是默认行为，不需要显式设置
  }

  return requestBody;
}

Map<String, Object?> _messageToAnthropicJson(
  ChatMessage message, {
  required Map<String, String> imageDataUrls,
}) {
  final imageBlocks = [
    for (final attachment in message.attachments)
      if (attachment.type == MessageAttachmentType.image &&
          imageDataUrls.containsKey(attachment.id))
        _imageBlockFromDataUrl(
          imageDataUrls[attachment.id]!,
          fallbackMimeType: attachment.mimeType ?? 'image/png',
        ),
  ];
  return {
    'role': message.isUser ? 'user' : 'assistant',
    'content': imageBlocks.isEmpty
        ? message.content
        : [
            {'type': 'text', 'text': message.content},
            ...imageBlocks,
          ],
  };
}

Map<String, Object?> _imageBlockFromDataUrl(
  String dataUrl, {
  required String fallbackMimeType,
}) {
  final match = RegExp(r'^data:([^;]+);base64,(.*)$').firstMatch(dataUrl);
  return {
    'type': 'image',
    'source': {
      'type': 'base64',
      'media_type': match?.group(1) ?? fallbackMimeType,
      'data': match?.group(2) ?? dataUrl,
    },
  };
}

/// 将通用工具定义转换为 Anthropic 格式
Map<String, Object?> _convertToolToAnthropic(ModelToolDefinition tool) {
  final json = Map<String, Object?>.from(tool.toJson());

  // 移除 OpenAI 特有的 'type' 字段
  json.remove('type');

  // 将 'function' 下的内容提升到顶层
  final function = json['function'] as Map<String, Object?>?;
  if (function != null) {
    json.remove('function');
    json['name'] = function['name'];
    json['description'] = function['description'];

    // 将 'parameters' 重命名为 'input_schema'
    if (function.containsKey('parameters')) {
      json['input_schema'] = function['parameters'];
    }
  }

  return json;
}

/// 构建工具调用相关的消息
List<Map<String, Object?>> _buildToolRoundMessages(
  List<ModelToolRound> rounds,
) {
  final messages = <Map<String, Object?>>[];

  for (final round in rounds) {
    // Assistant 消息包含工具调用
    if (round.calls.isNotEmpty) {
      messages.add({
        'role': 'assistant',
        'content': round.calls.map(_convertToolCallToAnthropic).toList(),
      });
    }

    // User 消息包含工具结果
    if (round.results.isNotEmpty) {
      messages.add({
        'role': 'user',
        'content': round.results.map(_convertToolResultToAnthropic).toList(),
      });
    }
  }

  return messages;
}

/// 将工具调用转换为 Anthropic 格式
Map<String, Object?> _convertToolCallToAnthropic(ModelToolCall call) {
  // 解析 arguments（如果是 JSON 字符串）
  Object? input = call.arguments;
  if (input is String) {
    try {
      input = jsonDecode(input);
    } catch (_) {
      // 如果解析失败，保持原样
    }
  }

  return {
    'type': 'tool_use',
    'id': call.id,
    'name': call.name,
    'input': input,
  };
}

/// 将工具结果转换为 Anthropic 格式
Map<String, Object?> _convertToolResultToAnthropic(ModelToolResult result) {
  return {
    'type': 'tool_result',
    'tool_use_id': result.toolCallId,
    'content': result.content,
  };
}
