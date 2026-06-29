import '../commands/command_service.dart';
import '../domain.dart';
import '../model_gateway.dart';
import 'assignment_helpers.dart';
import 'audit_and_private_dispatch.dart';
import 'model_message_tools.dart';
import 'tool_executor.dart';

typedef StreamingMessageDraftHandler = void Function({
  required String conversationId,
  required ChatMessage message,
});

const maxModelToolRounds = 3;

class ModelMessageRunner {
  ModelMessageRunner({
    required this.gateway,
    CommandRunner? commandRunner,
  }) : commandRunner = commandRunner ?? defaultCommandRunner;

  final ModelGateway gateway;
  final CommandRunner commandRunner;

  Future<ModelMessageResult> runVisibleMessage({
    required AppState workingState,
    required Conversation conversation,
    required List<ChatMessage> messages,
    required String authorName,
    required String? memberId,
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> requestMessages,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
    StreamingMessageDraftHandler? onStreamingDraft,
    bool enableTools = true,
    String? continueMessageId,
  }) async {
    final startedAt = DateTime.now();
    var nextState = workingState;
    var lastProgressAt = DateTime.fromMillisecondsSinceEpoch(0);
    final outboundMessages = [...requestMessages];
    final activeRole = roleForMember(nextState, memberId);
    final toolDefinitions = enableTools && gateway is MetadataModelGateway
        ? modelToolDefinitions(role: activeRole)
        : const <ModelToolDefinition>[];
    final toolSystemPrompt = toolDefinitions.isEmpty
        ? systemPrompt
        : appendToolSystemPrompt(
            systemPrompt,
            role: activeRole,
          );
    final toolRounds = <ModelToolRound>[];
    var disableTools = false;
    ChatMessage? activeStreamingMessage;
    ChatMessage? visibleToolMessage = continueMessageId == null
        ? null
        : messages
            .where((message) => message.id == continueMessageId)
            .cast<ChatMessage?>()
            .firstWhere((message) => message != null, orElse: () => null);

    void publish(
      ChatMessage message, {
      bool force = false,
      bool draft = false,
    }) {
      replaceMessageInList(messages, message);
      nextState = replaceConversation(
        nextState,
        conversation.copyWith(
          messages: [...messages],
          status: ConversationStatus.running,
        ),
      );
      if (draft && onStreamingDraft != null) {
        onStreamingDraft(
          conversationId: conversation.id,
          message: message,
        );
        return;
      }
      final now = DateTime.now();
      if (force ||
          now.difference(lastProgressAt) >= const Duration(milliseconds: 50)) {
        lastProgressAt = now;
        onProgress?.call(nextState);
      }
    }

    try {
      for (var roundIndex = 0;; roundIndex++) {
        final requestStartedAt = DateTime.now();
        final contentBuffer = StringBuffer();
        final thinkingBuffer = StringBuffer();
        ChatMessage? current;
        final baseBlocksForRequest = visibleToolMessage?.contentBlocks ??
            const <ChatMessageContentBlock>[];
        if (model.streaming) {
          current = visibleToolMessage?.copyWith(
                generationStatus: ChatMessageGenerationStatus.streaming,
                generationDurationMs: 0,
              ) ??
              ChatMessage(
                id: orchestrationId('msg'),
                authorName: authorName,
                memberId: memberId,
                content: '',
                createdAt: requestStartedAt,
                generationStatus: ChatMessageGenerationStatus.streaming,
                generationDurationMs: 0,
              );
          if (visibleToolMessage == null) {
            messages.add(current);
          } else {
            replaceMessageInList(messages, current);
          }
          activeStreamingMessage = current;
          publish(current, force: true);
        }

        final activeTools =
            disableTools ? const <ModelToolDefinition>[] : toolDefinitions;
        final requestBody = buildOpenAiCompatibleRequestBody(
          model: model,
          systemPrompt: toolSystemPrompt,
          messages: outboundMessages,
          tools: activeTools,
          toolChoice:
              disableTools ? ModelToolChoice.none : ModelToolChoice.auto,
          toolRounds: toolRounds,
        );
        nextState = appendModelRequestDiagnostic(
          nextState,
          conversationId: conversation.id,
          memberId: memberId,
          model: model,
          requestBody: requestBody,
        );
        onProgress?.call(nextState);
        final completion = await completeModelWithMetadata(
          gateway,
          model: model,
          systemPrompt: toolSystemPrompt,
          messages: outboundMessages,
          cancellation: cancellation,
          onDelta: model.streaming
              ? (delta) {
                  final contentDelta = delta.contentDelta;
                  if (contentDelta != null) {
                    contentBuffer.write(contentDelta);
                  }
                  final thinkingDelta = delta.thinkingDelta;
                  if (thinkingDelta != null) {
                    thinkingBuffer.write(thinkingDelta);
                  }
                  final existing = current;
                  if (existing == null) {
                    return;
                  }
                  final wasEmpty = existing.content.trim().isEmpty &&
                      (existing.thinkingContent?.trim().isEmpty ?? true);
                  final elapsedMs = DateTime.now()
                      .difference(requestStartedAt)
                      .inMilliseconds;
                  final streamedContent = contentBuffer.toString();
                  final streamedBlocks = baseBlocksForRequest.isEmpty
                      ? null
                      : appendTextBlock(
                          baseBlocksForRequest,
                          streamedContent,
                        );
                  current = (streamedBlocks == null
                          ? existing.copyWith(content: streamedContent)
                          : messageWithBlocks(
                              existing,
                              streamedBlocks,
                              generationStatus:
                                  ChatMessageGenerationStatus.streaming,
                            ))
                      .copyWith(
                    thinkingContent: normalizeOptionalOrchestrationText(
                      thinkingBuffer.toString(),
                    ),
                    generationStatus: ChatMessageGenerationStatus.streaming,
                    generationDurationMs: elapsedMs,
                  );
                  activeStreamingMessage = current;
                  final publishedMessage = current;
                  if (publishedMessage == null) {
                    return;
                  }
                  if (onStreamingDraft == null) {
                    publish(publishedMessage, force: wasEmpty);
                  } else {
                    publish(publishedMessage, draft: true);
                  }
                }
              : null,
          tools: activeTools,
          toolChoice:
              disableTools ? ModelToolChoice.none : ModelToolChoice.auto,
          toolRounds: toolRounds,
        );
        cancellation?.throwIfCancelled();
        if (completion.toolCalls.isNotEmpty) {
          final toolText = completion.content.trim().isNotEmpty
              ? completion.content
              : contentBuffer.toString();
          final existing = current ?? visibleToolMessage;
          final initialBlocks = existing?.contentBlocks.isNotEmpty == true
              ? existing!.contentBlocks
              : appendTextBlock(
                  visibleToolMessage?.contentBlocks ??
                      const <ChatMessageContentBlock>[],
                  toolText,
                );
          if (existing == null) {
            visibleToolMessage = ChatMessage(
              id: orchestrationId('msg'),
              authorName: authorName,
              memberId: memberId,
              content: contentFromBlocks(initialBlocks),
              contentBlocks: initialBlocks,
              createdAt: DateTime.now(),
              generationStatus: ChatMessageGenerationStatus.streaming,
            );
            messages.add(visibleToolMessage);
          } else {
            visibleToolMessage = messageWithBlocks(
              existing,
              initialBlocks,
              generationStatus: ChatMessageGenerationStatus.streaming,
            );
            replaceMessageInList(messages, visibleToolMessage);
          }
          activeStreamingMessage = visibleToolMessage;
          publish(visibleToolMessage, force: true);
          if (roundIndex >= maxModelToolRounds - 1) {
            toolRounds.add(
              ModelToolRound(
                calls: completion.toolCalls,
                results: completion.toolCalls
                    .map(
                      (call) => ModelToolResult(
                        toolCallId: call.id,
                        name: call.name,
                        content: toolResultJson(
                          ok: false,
                          error: '工具调用超过最大轮数 $maxModelToolRounds',
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
            visibleToolMessage = messageWithBlocks(
              visibleToolMessage,
              [
                ...visibleToolMessage.contentBlocks,
                const ChatMessageContentBlock.toolError(
                  '工具调用超过最大轮数 $maxModelToolRounds',
                ),
              ],
              generationStatus: ChatMessageGenerationStatus.streaming,
            );
            publish(visibleToolMessage, force: true);
            disableTools = true;
            continue;
          }
          final outcome = await executeModelToolCalls(
            state: nextState,
            conversationId: conversation.id,
            memberId: memberId,
            messageId: visibleToolMessage.id,
            calls: completion.toolCalls,
            commandRunner: commandRunner,
            cancellation: cancellation,
          );
          nextState = outcome.workingState;
          toolRounds.add(outcome.round);
          if (outcome.displayBlocks.isNotEmpty) {
            visibleToolMessage = messageWithBlocks(
              visibleToolMessage,
              [
                ...visibleToolMessage.contentBlocks,
                ...outcome.displayBlocks,
              ],
              generationStatus: ChatMessageGenerationStatus.streaming,
            );
            activeStreamingMessage = visibleToolMessage;
            publish(visibleToolMessage, force: true);
          }
          onProgress?.call(nextState);
          continue;
        }

        final guardedContent = guardCommandExecutionClaim(
          content: completion.content,
          requestMessages: outboundMessages,
          toolDefinitions: toolDefinitions,
          toolRounds: toolRounds,
        );
        final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
        final finalMessage = visibleToolMessage != null
            ? messageWithBlocks(
                current ?? visibleToolMessage,
                appendTextBlock(baseBlocksForRequest, guardedContent),
                generationStatus: ChatMessageGenerationStatus.complete,
              ).copyWith(
                thinkingContent: normalizeOptionalOrchestrationText(
                      completion.thinkingContent ?? thinkingBuffer.toString(),
                    ) ??
                    current?.thinkingContent,
                generationDurationMs: model.streaming ? elapsedMs : null,
              )
            : (current ??
                    ChatMessage(
                      id: orchestrationId('msg'),
                      authorName: authorName,
                      memberId: memberId,
                      content: guardedContent,
                      thinkingContent: completion.thinkingContent,
                      createdAt: DateTime.now(),
                    ))
                .copyWith(
                content: guardedContent,
                thinkingContent: normalizeOptionalOrchestrationText(
                      completion.thinkingContent ?? thinkingBuffer.toString(),
                    ) ??
                    current?.thinkingContent,
                generationStatus: ChatMessageGenerationStatus.complete,
                generationDurationMs: model.streaming ? elapsedMs : null,
              );
        if (current == null) {
          if (visibleToolMessage == null) {
            messages.add(finalMessage);
          } else {
            replaceMessageInList(messages, finalMessage);
          }
        } else {
          replaceMessageInList(messages, finalMessage);
        }
        activeStreamingMessage = null;
        nextState = replaceConversation(
          nextState,
          conversation.copyWith(
            messages: [...messages],
            status: ConversationStatus.running,
          ),
        );
        nextState = appendModelResponseDiagnostic(
          nextState,
          conversationId: conversation.id,
          messageId: finalMessage.id,
          memberId: memberId,
          model: model,
          diagnostics: completion.diagnostics ??
              ModelResponseDiagnostics(
                streaming: model.streaming,
                contentLength: finalMessage.content.length,
                thinkingContentLength:
                    finalMessage.thinkingContent?.length ?? 0,
              ),
        );
        if (model.streaming) {
          onProgress?.call(nextState);
        }
        return ModelMessageResult(
          message: finalMessage,
          workingState: nextState,
        );
      }
    } catch (_) {
      final existing = activeStreamingMessage;
      if (existing != null) {
        final hasPartialContent = existing.content.trim().isNotEmpty ||
            (existing.thinkingContent?.trim().isNotEmpty ?? false);
        if (hasPartialContent) {
          final status = cancellation?.isCancelled == true
              ? ChatMessageGenerationStatus.stopped
              : ChatMessageGenerationStatus.failed;
          final partial = existing.copyWith(
            generationStatus: status,
            generationDurationMs:
                DateTime.now().difference(startedAt).inMilliseconds,
          );
          replaceMessageInList(messages, partial);
        } else {
          messages.removeWhere((message) => message.id == existing.id);
        }
        nextState = replaceConversation(
          nextState,
          conversation.copyWith(
            messages: [...messages],
            status: ConversationStatus.running,
          ),
        );
        onProgress?.call(nextState);
      }
      rethrow;
    }
  }
}
