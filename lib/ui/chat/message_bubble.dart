import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../application/chat_streaming.dart';
import '../../core/domain.dart';
import '../../core/workspace/image_service.dart';
import '../app_helpers.dart';
import 'message_image_grid.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.conversationId,
    required this.showAuthorName,
    required this.draftListenable,
    required this.imageService,
    this.diagnostics,
  });

  final ChatMessage message;
  final String conversationId;
  final bool showAuthorName;
  final ValueListenable<ChatStreamingDraft?> draftListenable;
  final ImageService imageService;
  final ChatScrollDiagnostics? diagnostics;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool hovered = false;
  bool thinkingExpanded = false;
  bool copied = false;
  Timer? copyResetTimer;
  Timer? streamingTitleTimer;
  ChatMessage? latestDisplayedMessage;

  @override
  void initState() {
    super.initState();
    _syncThinkingState(null);
  }

  @override
  void dispose() {
    copyResetTimer?.cancel();
    streamingTitleTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      thinkingExpanded = false;
      copied = false;
      copyResetTimer?.cancel();
    }
    _syncThinkingState(oldWidget.message);
  }

  void _syncThinkingState(ChatMessage? oldMessage) {
    final message = widget.message;
    if (message.generationStatus == ChatMessageGenerationStatus.streaming) {
      thinkingExpanded = true;
      streamingTitleTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
      return;
    }
    streamingTitleTimer?.cancel();
    streamingTitleTimer = null;
    if (oldMessage?.generationStatus == ChatMessageGenerationStatus.streaming &&
        message.generationStatus == ChatMessageGenerationStatus.complete) {
      thinkingExpanded = false;
    }
    if (message.generationStatus == ChatMessageGenerationStatus.failed ||
        message.generationStatus == ChatMessageGenerationStatus.stopped) {
      thinkingExpanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatStreamingDraft?>(
      valueListenable: widget.draftListenable,
      builder: (context, draft, _) {
        final message = draft != null &&
                draft.conversationId == widget.conversationId &&
                draft.message.id == widget.message.id
            ? draft.message
            : widget.message;
        return _buildMessage(context, message);
      },
    );
  }

  Widget _buildMessage(BuildContext context, ChatMessage message) {
    latestDisplayedMessage = message;
    final messageBuildCounts = widget.diagnostics?.messageBubbleBuildCounts;
    if (messageBuildCounts != null) {
      messageBuildCounts.update(
        widget.message.id,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final alignRight = message.isUser;
    final showAuthorName = !alignRight && widget.showAuthorName;
    final thinkingContent =
        alignRight ? null : normalizedThinkingContent(message);
    final inlineStatus =
        thinkingContent == null ? messageInlineGenerationStatus(message) : null;
    final showMessageHeader =
        !alignRight && (showAuthorName || inlineStatus != null);
    final showReplyBubble =
        !isStreamingThinkingWithoutReplyContent(message, thinkingContent);
    final thinkingSection = thinkingContent == null
        ? null
        : ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _MessageThinkingDisclosure(
              partitionKey: message.id,
              content: thinkingContent,
              title: thinkingTitle(message),
              expanded: thinkingExpanded,
              streaming: message.generationStatus ==
                  ChatMessageGenerationStatus.streaming,
              diagnostics: widget.diagnostics,
              onToggle: () {
                setState(() {
                  thinkingExpanded = !thinkingExpanded;
                });
              },
            ),
          );
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 760),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: alignRight ? const Color(0xFFE8F1FF) : Colors.white,
        border: Border.all(
          color: alignRight ? const Color(0xFFCFE0FF) : const Color(0xFFE5E7EB),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isAwaitingFirstModelOutput(message))
            Text(
              '正在输入中',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            _MessageBody(
              key: ValueKey('message-body-${message.id}'),
              message: message,
              imageService: widget.imageService,
              diagnostics: widget.diagnostics,
            ),
        ],
      ),
    );
    final actionSlot = SizedBox(
      height: 32,
      child: hovered
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  messageTimeText(message.createdAt),
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '复制',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(28),
                    minimumSize: const Size.square(28),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _copyMessage,
                  icon: Icon(
                    copied ? Icons.check_rounded : Icons.copy_rounded,
                    size: 16,
                  ),
                ),
              ],
            )
          : const SizedBox.shrink(),
    );
    final messageColumn = Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (showMessageHeader) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showAuthorName)
                Text(
                  message.authorName,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (inlineStatus != null) ...[
                if (showAuthorName) const SizedBox(width: 6),
                Text(
                  inlineStatus,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
        ],
        if (thinkingSection != null) ...[
          thinkingSection,
          if (showReplyBubble) const SizedBox(height: 8),
        ],
        if (showReplyBubble) ...[
          bubble,
          const SizedBox(height: 4),
          Align(
            alignment:
                alignRight ? Alignment.centerRight : Alignment.centerLeft,
            child: actionSlot,
          ),
        ],
      ],
    );
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment:
              alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!alignRight) ...[
              CircleAvatar(
                radius: 18,
                backgroundColor: avatarColor(message.authorName),
                child: Text(
                  avatarText(message.authorName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(child: messageColumn),
            if (alignRight) ...[
              const SizedBox(width: 10),
              const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFF2563EB),
                child: Text(
                  '你',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _copyMessage() {
    unawaited(
      Clipboard.setData(
        ClipboardData(
            text: latestDisplayedMessage?.content ?? widget.message.content),
      ),
    );
    copyResetTimer?.cancel();
    setState(() => copied = true);
    copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => copied = false);
      }
    });
  }
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({
    super.key,
    required this.message,
    required this.imageService,
    this.diagnostics,
  });

  final ChatMessage message;
  final ImageService imageService;
  final ChatScrollDiagnostics? diagnostics;

  @override
  Widget build(BuildContext context) {
    if (message.contentBlocks.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final indexed in message.contentBlocks.indexed) ...[
            if (indexed.$1 > 0) const SizedBox(height: 10),
            switch (indexed.$2.type) {
              ChatMessageContentBlockType.text => _MessageTextBlock(
                  message: message,
                  content: indexed.$2.text ?? '',
                  diagnostics: diagnostics,
                ),
              ChatMessageContentBlockType.toolError => SelectableText(
                  indexed.$2.text ?? '',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ChatMessageContentBlockType.commandResult =>
                _CommandResultDisclosure(result: indexed.$2.commandResult!),
            },
          ],
          // 显示图片附件
          if (message.attachments.isNotEmpty)
            MessageImageGrid(
              attachments: message.attachments,
              imageService: imageService,
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MessageTextBlock(
          message: message,
          content: message.content,
          diagnostics: diagnostics,
        ),
        // 显示图片附件
        if (message.attachments.isNotEmpty)
          MessageImageGrid(
            attachments: message.attachments,
            imageService: imageService,
          ),
      ],
    );
  }
}

class _MessageTextBlock extends StatelessWidget {
  const _MessageTextBlock({
    required this.message,
    required this.content,
    this.diagnostics,
  });

  final ChatMessage message;
  final String content;
  final ChatScrollDiagnostics? diagnostics;

  @override
  Widget build(BuildContext context) {
    if (message.isUser || message.authorName == '系统') {
      return SelectableText(content);
    }
    if (message.generationStatus == ChatMessageGenerationStatus.streaming) {
      return _StreamingPartitionedText(
        key: ValueKey('streaming-message-body-${message.id}'),
        partitionKey: message.id,
        content: content,
        diagnostics: diagnostics,
      );
    }
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(
      color: const Color(0xFF1A1B21),
      height: 1.45,
    );
    diagnostics?.markdownBodyBuildCount++;
    return MarkdownBody(
      data: content,
      selectable: true,
      imageBuilder: (uri, title, alt) => Text(
        alt?.trim().isNotEmpty == true ? alt! : uri.toString(),
        style: bodyStyle?.copyWith(
          color: Colors.grey.shade600,
          fontStyle: FontStyle.italic,
        ),
      ),
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: bodyStyle,
        a: bodyStyle?.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
        code: bodyStyle?.copyWith(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor: const Color(0xFFF3F4F6),
        ),
        h1: bodyStyle?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        h2: bodyStyle?.copyWith(
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
        h3: bodyStyle?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        h4: bodyStyle?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        h5: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
        h6: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
        blockSpacing: 10,
        listIndent: 22,
        tableHead: bodyStyle?.copyWith(fontWeight: FontWeight.w700),
        tableBody: bodyStyle,
        tableBorder: TableBorder.all(color: const Color(0xFFD1D5DB)),
        tableCellsPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        tableHeadCellsDecoration: const BoxDecoration(color: Color(0xFFF3F4F6)),
        blockquote: bodyStyle?.copyWith(color: Colors.grey.shade700),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
        blockquoteDecoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          border: Border(
            left: BorderSide(color: Color(0xFFCBD5E1), width: 3),
          ),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(4),
        ),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB)),
          ),
        ),
      ),
    );
  }
}

class _CommandResultDisclosure extends StatelessWidget {
  const _CommandResultDisclosure({required this.result});

  final CommandResultAttachment result;

  @override
  Widget build(BuildContext context) {
    final output = result.output.trim();
    return Material(
      color: const Color(0xFFF8FAFC),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        initiallyExpanded: false,
        title: const Text(
          '命令执行结果',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${result.status.name} · ${result.command}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              [
                result.workingDirectory,
                '\$ ${result.command}',
                if (output.isNotEmpty) output else '<empty>',
              ].join('\n'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamingPartitionedText extends StatefulWidget {
  const _StreamingPartitionedText({
    super.key,
    required this.partitionKey,
    required this.content,
    this.diagnostics,
    this.isThinking = false,
  });

  final String partitionKey;
  final String content;
  final ChatScrollDiagnostics? diagnostics;
  final bool isThinking;

  @override
  State<_StreamingPartitionedText> createState() =>
      _StreamingPartitionedTextState();
}

class _StreamingPartitionedTextState extends State<_StreamingPartitionedText> {
  final partition = StreamingTextPartition();
  final stableSegments = <Widget>[];

  @override
  void initState() {
    super.initState();
    _applyContent(widget.content, reset: true);
  }

  @override
  void didUpdateWidget(covariant _StreamingPartitionedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.partitionKey != widget.partitionKey) {
      _applyContent(widget.content, reset: true);
      return;
    }
    if (oldWidget.content != widget.content) {
      _applyContent(widget.content);
    }
  }

  void _applyContent(String content, {bool reset = false}) {
    final update = partition.apply(content, reset: reset);
    if (update.reset) {
      stableSegments.clear();
    }
    for (final stableText in update.newStableSegments) {
      stableSegments.add(
        _StableStreamingTextSegment(
          key: ValueKey(
            'streaming-stable-${widget.partitionKey}-${stableSegments.length}',
          ),
          text: stableText,
          isThinking: widget.isThinking,
        ),
      );
      widget.diagnostics?.streamingStableSegmentCommitCount++;
    }
    if (update.tailChanged) {
      widget.diagnostics?.streamingTailUpdateCount++;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isThinking) {
      widget.diagnostics?.streamingThinkingBuildCount++;
    } else {
      widget.diagnostics?.streamingBodyBuildCount++;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...stableSegments,
        if (partition.liveTail.isNotEmpty)
          _StreamingLiveTailText(
            text: partition.liveTail,
            isThinking: widget.isThinking,
          ),
      ],
    );
  }
}

class _StableStreamingTextSegment extends StatelessWidget {
  const _StableStreamingTextSegment({
    super.key,
    required this.text,
    required this.isThinking,
  });

  final String text;
  final bool isThinking;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: _streamingTextStyle(context, isThinking));
  }
}

class _StreamingLiveTailText extends StatelessWidget {
  const _StreamingLiveTailText({
    required this.text,
    required this.isThinking,
  });

  final String text;
  final bool isThinking;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: _streamingTextStyle(context, isThinking));
  }
}

TextStyle? _streamingTextStyle(BuildContext context, bool isThinking) {
  if (isThinking) {
    return TextStyle(
      color: Colors.grey.shade700,
      height: 1.45,
    );
  }
  return Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: const Color(0xFF1A1B21),
        height: 1.45,
      );
}

class _MessageThinkingDisclosure extends StatelessWidget {
  const _MessageThinkingDisclosure({
    required this.partitionKey,
    required this.content,
    required this.title,
    required this.expanded,
    required this.streaming,
    this.diagnostics,
    required this.onToggle,
  });

  final String partitionKey;
  final String content;
  final String title;
  final bool expanded;
  final bool streaming;
  final ChatScrollDiagnostics? diagnostics;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFEFF6FF), Color(0xFFFAFCFF)],
          ),
          border: Border.all(color: const Color(0xFFBFDBFE)),
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onToggle,
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  border: expanded
                      ? const Border(
                          bottom: BorderSide(color: Color(0xFFDBEAFE)),
                        )
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1D4ED8),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Text(
                      'provider returned',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 20,
                      color: const Color(0xFF1D4ED8),
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  child: streaming
                      ? _StreamingPartitionedText(
                          key: ValueKey('streaming-thinking-$partitionKey'),
                          partitionKey: partitionKey,
                          content: content,
                          diagnostics: diagnostics,
                          isThinking: true,
                        )
                      : SelectableText(
                          content,
                          style: const TextStyle(
                            color: Color(0xFF334155),
                            height: 1.45,
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
