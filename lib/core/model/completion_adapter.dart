part of '../model_gateway.dart';

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
