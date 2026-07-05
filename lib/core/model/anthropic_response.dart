import 'dart:async';
import 'dart:convert';

import 'gateway_contracts.dart';
import 'model_gateway_exception.dart';

/// 解析 Anthropic 非流式响应
ModelCompletion parseAnthropicResponse({
  required Map<String, Object?> response,
  required Map<String, Object?> requestBody,
  required String requestUrl,
}) {
  // 提取 content 数组
  final contentBlocks = response['content'] as List? ?? [];

  // 分离文本内容和工具调用
  final textParts = <String>[];
  final toolCalls = <ModelToolCall>[];

  for (final block in contentBlocks) {
    if (block is! Map) continue;
    final blockMap = Map<String, Object?>.from(block);
    final type = blockMap['type'] as String?;

    if (type == 'text') {
      final text = blockMap['text'] as String?;
      if (text != null) {
        textParts.add(text);
      }
    } else if (type == 'tool_use') {
      toolCalls.add(_parseToolUse(blockMap));
    }
  }

  final content = textParts.join('');

  // 提取 usage 信息
  final usage = response['usage'] as Map<String, Object?>?;
  final inputTokens = (usage?['input_tokens'] as num?)?.toInt();
  final outputTokens = (usage?['output_tokens'] as num?)?.toInt();

  return ModelCompletion(
    content: content,
    toolCalls: toolCalls,
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    totalTokens:
        (inputTokens ?? 0) + (outputTokens ?? 0) > 0
            ? (inputTokens ?? 0) + (outputTokens ?? 0)
            : null,
    thinkingContent: null, // Anthropic 目前不支持 thinking
    diagnostics: ModelResponseDiagnostics(
      streaming: false,
      contentLength: content.length,
      thinkingContentLength: 0,
      thinkingFieldKeys: const [],
      contentDeltaCount: 0,
      thinkingDeltaCount: 0,
      toolCallCount: toolCalls.length,
      rawResponse: jsonEncode(response),
      requestBody: requestBody,
      requestUrl: requestUrl,
    ),
  );
}

/// 解析工具调用
ModelToolCall _parseToolUse(Map<String, Object?> block) {
  final input = block['input'];
  return ModelToolCall(
    id: block['id'] as String,
    name: block['name'] as String,
    arguments: input is String ? input : jsonEncode(input),
  );
}

/// 解析 Anthropic 流式响应
Future<ModelCompletion> parseAnthropicStreamingResponse({
  required Stream<List<int>> responseStream,
  required Map<String, Object?> requestBody,
  required String requestUrl,
  ModelRequestCancellation? cancellation,
  ModelStreamDeltaHandler? onDelta,
}) async {
  final contentBuffer = StringBuffer();
  final toolCallBuilders = <String, _AnthropicToolCallBuilder>{};

  var inputTokens = 0;
  var outputTokens = 0;
  var contentDeltaCount = 0;

  // 记录每个 content block 的类型
  final blockTypes = <int, String>{};

  final lines = responseStream
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final iterator = StreamIterator<String>(lines);

  try {
    while (await _moveNextWithCancellation(iterator, cancellation)) {
      final line = iterator.current;

      // 跳过事件类型行（event: xxx）
      if (line.startsWith('event: ')) {
        continue;
      }

      // 解析 data 行
      if (!line.startsWith('data: ')) {
        continue;
      }

      final dataLine = line.substring(6).trim();
      if (dataLine.isEmpty) {
        continue;
      }

      try {
        final event = jsonDecode(dataLine) as Map<String, Object?>;
        final eventType = event['type'] as String?;

        switch (eventType) {
          case 'message_start':
            // 提取初始 usage 信息
            final message = event['message'] as Map<String, Object?>?;
            final usage = message?['usage'] as Map<String, Object?>?;
            if (usage != null) {
              inputTokens = (usage['input_tokens'] as num?)?.toInt() ?? 0;
            }
            break;

          case 'content_block_start':
            // 记录新 content block 的类型
            final index = (event['index'] as num?)?.toInt() ?? 0;
            final contentBlock = event['content_block'] as Map<String, Object?>?;
            final blockType = contentBlock?['type'] as String?;
            if (blockType != null) {
              blockTypes[index] = blockType;
            }

            // 如果是 tool_use，初始化 builder
            if (blockType == 'tool_use') {
              final id = contentBlock?['id'] as String?;
              final name = contentBlock?['name'] as String?;
              if (id != null && name != null) {
                toolCallBuilders[id] = _AnthropicToolCallBuilder(
                  id: id,
                  name: name,
                  index: index,
                );
              }
            }
            break;

          case 'content_block_delta':
            final index = (event['index'] as num?)?.toInt() ?? 0;
            final delta = event['delta'] as Map<String, Object?>?;
            final deltaType = delta?['type'] as String?;

            if (deltaType == 'text_delta') {
              // 文本内容
              final text = delta?['text'] as String? ?? '';
              contentBuffer.write(text);
              contentDeltaCount++;

              if (onDelta != null) {
                onDelta(ModelStreamDelta(
                  contentDelta: text,
                  thinkingDelta: null,
                ));
              }
            } else if (deltaType == 'input_json_delta') {
              // 工具调用的参数增量
              final partial = delta?['partial_json'] as String? ?? '';
              // 查找对应的 tool_use block
              for (final builder in toolCallBuilders.values) {
                if (builder.index == index) {
                  builder.appendInput(partial);
                  break;
                }
              }
            }
            break;

          case 'content_block_stop':
            final index = (event['index'] as num?)?.toInt() ?? 0;
            // Content block 结束，如果是工具调用，完成解析
            final blockType = blockTypes[index];
            if (blockType == 'tool_use') {
              for (final builder in toolCallBuilders.values) {
                if (builder.index == index) {
                  builder.finalize();
                  break;
                }
              }
            }
            break;

          case 'message_delta':
            // 获取最终的 output_tokens
            final usage = event['usage'] as Map<String, Object?>?;
            if (usage != null) {
              outputTokens = (usage['output_tokens'] as num?)?.toInt() ?? 0;
            }
            break;

          case 'message_stop':
            // 消息结束
            break;

          case 'error':
            // 错误处理
            final error = event['error'] as Map<String, Object?>?;
            final errorMessage = error?['message'] as String? ?? '未知错误';
            throw ModelGatewayException('Anthropic API 错误: $errorMessage');
        }
      } catch (e) {
        if (e is ModelGatewayException) {
          rethrow;
        }
        // 忽略单个事件的解析错误，继续处理
        continue;
      }
    }
  } finally {
    await iterator.cancel();
  }

  final content = contentBuffer.toString();
  final toolCalls = toolCallBuilders.values
      .map((builder) => builder.build())
      .where((call) => call != null)
      .cast<ModelToolCall>()
      .toList();

  return ModelCompletion(
    content: content,
    toolCalls: toolCalls,
    inputTokens: inputTokens > 0 ? inputTokens : null,
    outputTokens: outputTokens > 0 ? outputTokens : null,
    totalTokens: inputTokens + outputTokens > 0
        ? inputTokens + outputTokens
        : null,
    thinkingContent: null,
    diagnostics: ModelResponseDiagnostics(
      streaming: true,
      contentLength: content.length,
      thinkingContentLength: 0,
      thinkingFieldKeys: const [],
      contentDeltaCount: contentDeltaCount,
      thinkingDeltaCount: 0,
      toolCallCount: toolCalls.length,
      rawResponse: null,
      requestBody: requestBody,
      requestUrl: requestUrl,
    ),
  );
}

/// 带取消支持的迭代器移动
Future<bool> _moveNextWithCancellation(
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

/// 工具调用构建器（用于流式响应）
class _AnthropicToolCallBuilder {
  _AnthropicToolCallBuilder({
    required this.id,
    required this.name,
    this.index,
  });

  final String id;
  final String name;
  final int? index;
  final _inputBuffer = StringBuffer();
  Object? _parsedInput;

  void appendInput(String partial) {
    _inputBuffer.write(partial);
  }

  void finalize() {
    try {
      final inputJson = _inputBuffer.toString();
      if (inputJson.isNotEmpty) {
        _parsedInput = jsonDecode(inputJson);
      }
    } catch (e) {
      // 解析失败，保持为 null
    }
  }

  ModelToolCall? build() {
    if (_parsedInput == null) {
      return null;
    }
    return ModelToolCall(
      id: id,
      name: name,
      arguments: _parsedInput is String 
          ? _parsedInput as String 
          : jsonEncode(_parsedInput),
    );
  }
}
