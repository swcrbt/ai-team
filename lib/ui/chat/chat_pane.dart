import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/app_controller.dart';
import '../../application/chat_streaming.dart';
import '../../core/domain.dart';
import '../app_helpers.dart';
import '../management/management_pages.dart';
import 'chat_controls.dart';
import 'message_bubble.dart';

class ChatPane extends StatefulWidget {
  const ChatPane({
    super.key,
    required this.controller,
    required this.conversationId,
    this.diagnostics,
  });

  final AppController controller;
  final String conversationId;
  final ChatScrollDiagnostics? diagnostics;

  @override
  State<ChatPane> createState() => ChatPaneState();
}

class ChatPaneState extends State<ChatPane> {
  static const _messageBottomThreshold = 24.0;
  static const _messageScrollJumpTolerance = 0.5;
  static const _messageBottomSettleFrameCount = 3;

  final textController = TextEditingController();
  final messageScrollController = ScrollController();
  bool messageIsNearBottom = true;
  int lastMessageListItemCount = -1;
  String? lastMessageId;
  int lastMessageContentLength = -1;
  int lastMessageThinkingLength = -1;
  ChatMessageGenerationStatus? lastMessageGenerationStatus;
  bool messageScrollFrameScheduled = false;
  int? pendingMessageScrollVersion;
  int pendingMessageScrollSettleFrames = 0;
  bool pendingMessageScrollForce = false;
  int messageAutoScrollVersion = 0;
  bool isProgrammaticMessageScroll = false;
  double? lastRecordedMessageScrollOffset;
  String? activeStreamingDraftMessageId;
  ValueListenable<ChatStreamingDraft?>? activeStreamingDraftListenable;
  VoidCallback? activeStreamingDraftListener;

  @override
  void dispose() {
    _clearActiveStreamingDraftSubscription();
    textController.dispose();
    messageScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.diagnostics?.chatPaneBuildCount++;
    final conversation = widget.controller.conversationById(
      widget.conversationId,
    );
    final typingMemberList = typingMembers(widget.controller, conversation);
    final pendingPatches =
        widget.controller.selectedConversationId == conversation.id
            ? widget.controller.patchProposals
                .where((patch) => patch.status == PatchStatus.pending)
                .toList()
            : const <PatchProposal>[];
    final commandRequests = widget.controller.commandRequestsForConversation(
      conversation.id,
    );
    final compactHeader = MediaQuery.sizeOf(context).width < 900;
    final messageListItemCount = conversation.messages.length +
        typingMemberList.length +
        commandRequests.length +
        pendingPatches.length;
    final currentLastMessage =
        conversation.messages.isEmpty ? null : conversation.messages.last;
    final currentLastMessageId = currentLastMessage?.id;
    final currentLastMessageContentLength =
        currentLastMessage?.content.length ?? 0;
    final currentLastMessageThinkingLength =
        currentLastMessage?.thinkingContent?.length ?? 0;
    final currentLastMessageGenerationStatus =
        currentLastMessage?.generationStatus;
    final messageStructureChanged =
        messageListItemCount != lastMessageListItemCount ||
            currentLastMessageId != lastMessageId;
    final lastMessageBodyChanged =
        currentLastMessageContentLength != lastMessageContentLength ||
            currentLastMessageThinkingLength != lastMessageThinkingLength ||
            currentLastMessageGenerationStatus != lastMessageGenerationStatus;
    final lastMessageStatusChanged =
        currentLastMessageGenerationStatus != lastMessageGenerationStatus;
    lastMessageListItemCount = messageListItemCount;
    lastMessageId = currentLastMessageId;
    lastMessageContentLength = currentLastMessageContentLength;
    lastMessageThinkingLength = currentLastMessageThinkingLength;
    lastMessageGenerationStatus = currentLastMessageGenerationStatus;
    _syncActiveStreamingDraftSubscription(conversation.id, currentLastMessage);
    if (lastMessageBodyChanged) {
      widget.diagnostics?.contentUpdateCount++;
    }
    if ((messageStructureChanged || lastMessageBodyChanged) &&
        messageIsNearBottom) {
      final needsSettle = currentLastMessageGenerationStatus !=
              ChatMessageGenerationStatus.streaming &&
          (messageStructureChanged || lastMessageStatusChanged);
      _scheduleMessageScrollToBottom(
        settleFrames: needsSettle ? _messageBottomSettleFrameCount : 0,
      );
    }
    final showBackToBottomButton = !messageIsNearBottom;
    final tokenUsage = _tokenUsageFor(conversation);
    return Column(
      children: [
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: conversation.memberId == null
                    ? const Color(0xFF22C55E)
                    : const Color(0xFF3B82F6),
                child: Icon(
                  conversation.memberId == null
                      ? Icons.forum_rounded
                      : Icons.person_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversationTitle(widget.controller, conversation),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      conversationMeta(widget.controller, conversation),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              if (!compactHeader) ...[
                const SizedBox(width: 12),
                _HeaderMembersPill(
                  count: widget.controller
                      .membersForConversation(conversation.id)
                      .length,
                ),
              ],
              const SizedBox(width: 8),
              _SafetyStatusButton(
                compact: compactHeader,
                pendingCount: commandRequests
                        .where(
                          (request) =>
                              request.status == CommandRequestStatus.pending,
                        )
                        .length +
                    pendingPatches.length,
                onPressed: () => _showSafetyDrawer(
                  context,
                  conversation,
                  commandRequests,
                  pendingPatches,
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: '会话操作',
                icon: const Icon(Icons.expand_more_rounded),
                onSelected: _handleConversationMenuAction,
                itemBuilder: (menuContext) => [
                  const PopupMenuItem(
                    value: 'new',
                    child: Row(
                      children: [
                        Icon(Icons.add_comment_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('新增会话'),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(enabled: false, child: Text('历史会话')),
                  for (final item in widget.controller.conversationHistory)
                    PopupMenuItem(
                      value: 'select:${item.id}',
                      child: Row(
                        children: [
                          Icon(
                            item.memberId == null
                                ? Icons.forum_rounded
                                : Icons.person_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              conversationMenuTitle(widget.controller, item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: '删除会话',
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => unawaited(
                              _confirmDeleteConversationSession(
                                menuContext,
                                item,
                              ),
                            ),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              ColoredBox(
                color: const Color(0xFFFCFCFD),
                child: Listener(
                  onPointerSignal: (event) =>
                      _handleMessagePointerSignal(event),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) =>
                        _handleMessageScrollNotification(notification),
                    child: NotificationListener<ScrollMetricsNotification>(
                      onNotification: (notification) =>
                          _handleMessageScrollMetricsNotification(notification),
                      child: KeyedSubtree(
                        key: ValueKey('chat-message-list-${conversation.id}'),
                        child: ListView.builder(
                          key: const ValueKey('chat-message-list'),
                          controller: messageScrollController,
                          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                          itemCount: messageListItemCount,
                          itemBuilder: (context, index) {
                            if (index < conversation.messages.length) {
                              return MessageBubble(
                                message: conversation.messages[index],
                                conversationId: conversation.id,
                                showAuthorName: conversation.memberId == null,
                                draftListenable:
                                    widget.controller.streamingDraftListenable(
                                  conversation.messages[index].id,
                                ),
                                diagnostics: widget.diagnostics,
                              );
                            }
                            final typingIndex =
                                index - conversation.messages.length;
                            if (typingIndex < typingMemberList.length) {
                              return TypingIndicator(
                                member: typingMemberList[typingIndex],
                              );
                            }
                            final commandIndex =
                                typingIndex - typingMemberList.length;
                            if (commandIndex < commandRequests.length) {
                              final request = commandRequests[commandIndex];
                              return ChatCommandRequestCard(
                                request: request,
                                onApproveExecute: () => unawaited(
                                  widget.controller
                                      .approveExecuteCommandRequestAndContinue(
                                    request.id,
                                  ),
                                ),
                                onReject: () => widget.controller
                                    .updateCommandRequestStatus(
                                  request.id,
                                  CommandRequestStatus.denied,
                                ),
                              );
                            }
                            final patch = pendingPatches[
                                commandIndex - commandRequests.length];
                            return ChatPatchConfirmationCard(
                              patch: patch,
                              onApply: () =>
                                  widget.controller.applyPatch(patch),
                              onReject: () =>
                                  widget.controller.rejectPatch(patch),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (showBackToBottomButton)
                Positioned(
                  right: 24,
                  bottom: 18,
                  child: IconButton.filledTonal(
                    tooltip: '回到底部',
                    onPressed: _scrollCurrentConversationToBottom,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ),
            ],
          ),
        ),
        if (widget.controller.error != null)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF1F2),
            padding: const EdgeInsets.all(10),
            child: Text(
              widget.controller.error!,
              style: const TextStyle(color: Color(0xFFBE123C)),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleInputKeyEvent,
                    child: TextField(
                      key: ValueKey('chat-input-${conversation.id}'),
                      controller: textController,
                      minLines: 3,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: inputHint(widget.controller, conversation),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      TokenUsageMeter(data: tokenUsage),
                      const SizedBox(width: 8),
                      SplitSendButton(
                        isDispatching: widget.controller.isDispatching,
                        isConversationDispatching: widget.controller
                            .isConversationDispatching(conversation.id),
                        onSend: _submit,
                        onStop: () => widget.controller.stopConversationById(
                          conversation.id,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  TokenUsageData _tokenUsageFor(Conversation conversation) {
    final model = _modelForConversation(conversation);
    final messageUsage = _latestMessageUsage(conversation);
    final auditUsage = _latestAuditUsage();
    return TokenUsageData(
      contextWindowTokens: model.contextWindowTokens,
      inputTokens: messageUsage.inputTokens ?? auditUsage.inputTokens,
      outputTokens: messageUsage.outputTokens ?? auditUsage.outputTokens,
      cachedTokens: messageUsage.cachedTokens ?? auditUsage.cachedTokens,
      totalTokens: messageUsage.totalTokens ?? auditUsage.totalTokens,
    );
  }

  ModelProfile _modelForConversation(Conversation conversation) {
    final memberId = conversation.memberId;
    if (memberId != null) {
      final member = widget.controller.state.members.firstWhere(
        (item) => item.id == memberId,
        orElse: () => widget.controller.state.members.first,
      );
      return widget.controller.state.models.firstWhere(
        (model) => model.id == member.modelId,
        orElse: () => widget.controller.state.models.first,
      );
    }
    final team = widget.controller.teamForConversation(conversation.id);
    final secretary = widget.controller.state.members.firstWhere(
      (member) => member.id == team.secretaryMemberId,
      orElse: () => widget.controller.state.members.first,
    );
    return widget.controller.state.models.firstWhere(
      (model) => model.id == secretary.modelId,
      orElse: () => widget.controller.state.models.first,
    );
  }

  _TokenFields _latestMessageUsage(Conversation conversation) {
    for (final message in conversation.messages.reversed) {
      if (message.inputTokens != null ||
          message.outputTokens != null ||
          message.cachedTokens != null ||
          message.totalTokens != null) {
        return _TokenFields(
          inputTokens: message.inputTokens,
          outputTokens: message.outputTokens,
          cachedTokens: message.cachedTokens,
          totalTokens: message.totalTokens,
        );
      }
    }
    return const _TokenFields();
  }

  _TokenFields _latestAuditUsage() {
    for (final entry in widget.controller.state.auditLog.reversed) {
      final metadata = entry.metadata;
      if (metadata == null) {
        continue;
      }
      final fields = _TokenFields(
        inputTokens: _metadataInt(metadata['inputTokens']),
        outputTokens: _metadataInt(metadata['outputTokens']),
        cachedTokens: _metadataInt(metadata['cachedTokens']),
        totalTokens: _metadataInt(metadata['totalTokens']),
      );
      if (!fields.isEmpty) {
        return fields;
      }
    }
    return const _TokenFields();
  }

  Future<void> _submit() async {
    final text = textController.text;
    textController.clear();
    await widget.controller.dispatchConversation(widget.conversationId, text);
  }

  void _handleConversationMenuAction(String value) {
    if (value == 'new') {
      widget.controller.createConversationLikeCurrent();
      return;
    }
    const prefix = 'select:';
    if (value.startsWith(prefix)) {
      widget.controller.selectConversation(value.substring(prefix.length));
    }
  }

  void _showSafetyDrawer(
    BuildContext context,
    Conversation conversation,
    List<CommandRequest> commandRequests,
    List<PatchProposal> pendingPatches,
  ) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭安全状态',
      barrierColor: Colors.black.withValues(alpha: 0.08),
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 76, right: 22),
              child: _SafetyStatusDrawer(
                controller: widget.controller,
                conversation: conversation,
                commandRequests: commandRequests,
                pendingPatches: pendingPatches,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }

  Future<void> _confirmDeleteConversationSession(
    BuildContext menuContext,
    Conversation conversation,
  ) async {
    Navigator.of(menuContext).pop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除该会话？'),
        content: Text(
          '删除后将永久移除“${conversationMenuTitle(widget.controller, conversation)}”及其消息。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      widget.controller.deleteConversationSession(conversation.id);
    }
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (widget.controller.isConversationDispatching(widget.conversationId)) {
        widget.controller.stopConversationById(widget.conversationId);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      _insertLineBreak();
    } else if (!widget.controller.isDispatching) {
      unawaited(_submit());
    }
    return KeyEventResult.handled;
  }

  void _insertLineBreak() {
    final value = textController.value;
    final selection = value.selection;
    final text = value.text;
    if (!selection.isValid) {
      textController.text = '$text\n';
      textController.selection = TextSelection.collapsed(
        offset: textController.text.length,
      );
      return;
    }
    final nextText = text.replaceRange(selection.start, selection.end, '\n');
    textController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: selection.start + 1),
      composing: TextRange.empty,
    );
  }

  bool _isNearMessageBottom() {
    if (!messageScrollController.hasClients) {
      return true;
    }
    return _isNearMessageBottomMetrics(messageScrollController.position);
  }

  bool _isNearMessageBottomMetrics(ScrollMetrics metrics) {
    return metrics.maxScrollExtent - metrics.pixels <= _messageBottomThreshold;
  }

  bool _handleMessageScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical ||
        isProgrammaticMessageScroll) {
      return false;
    }
    _recordMessageScrollPosition(notification.metrics.pixels);
    _syncMessageNearBottom(notification.metrics);
    return false;
  }

  bool _handleMessageScrollMetricsNotification(
    ScrollMetricsNotification notification,
  ) {
    if (notification.metrics.axis != Axis.vertical ||
        isProgrammaticMessageScroll) {
      return false;
    }
    _recordMessageScrollPosition(notification.metrics.pixels);
    _syncMessageNearBottom(notification.metrics, canCancelPendingScroll: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !messageScrollController.hasClients) {
        return;
      }
      final position = messageScrollController.position;
      _recordMessageScrollPosition(position.pixels);
      _syncMessageNearBottom(position, canCancelPendingScroll: false);
    });
    return false;
  }

  void _handleMessagePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !messageScrollController.hasClients) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !messageScrollController.hasClients) {
        return;
      }
      _syncMessageNearBottom(messageScrollController.position);
    });
  }

  void _recordMessageScrollPosition(double offset) {
    lastRecordedMessageScrollOffset = offset;
  }

  void _syncMessageNearBottom(
    ScrollMetrics metrics, {
    bool canCancelPendingScroll = true,
  }) {
    _setMessageIsNearBottom(
      _isNearMessageBottomMetrics(metrics),
      canCancelPendingScroll: canCancelPendingScroll,
    );
  }

  void _setMessageIsNearBottom(
    bool value, {
    bool canCancelPendingScroll = true,
  }) {
    final previous = messageIsNearBottom;
    if (previous &&
        !value &&
        !canCancelPendingScroll &&
        (messageScrollFrameScheduled || pendingMessageScrollVersion != null)) {
      return;
    }
    messageIsNearBottom = value;
    if (previous && !value && canCancelPendingScroll) {
      _cancelPendingMessageScrollToBottom();
    }
    if (previous != value && mounted) {
      widget.diagnostics?.nearBottomFlipCount++;
      setState(() {});
    }
  }

  void _scrollCurrentConversationToBottom() {
    _scheduleMessageScrollToBottom(
      settleFrames: _messageBottomSettleFrameCount,
      force: true,
    );
  }

  void _syncActiveStreamingDraftSubscription(
    String conversationId,
    ChatMessage? message,
  ) {
    final nextMessageId =
        message?.generationStatus == ChatMessageGenerationStatus.streaming
            ? message!.id
            : null;
    if (nextMessageId == activeStreamingDraftMessageId) {
      return;
    }
    _clearActiveStreamingDraftSubscription();
    if (nextMessageId == null) {
      return;
    }
    final listenable = widget.controller.streamingDraftListenable(
      nextMessageId,
    );
    late final VoidCallback listener;
    listener = () {
      final draft = listenable.value;
      if (!mounted ||
          draft == null ||
          draft.conversationId != conversationId ||
          draft.message.id != nextMessageId) {
        return;
      }
      widget.diagnostics?.contentUpdateCount++;
      if (messageIsNearBottom) {
        _scheduleMessageScrollToBottom();
      }
    };
    listenable.addListener(listener);
    activeStreamingDraftMessageId = nextMessageId;
    activeStreamingDraftListenable = listenable;
    activeStreamingDraftListener = listener;
  }

  void _clearActiveStreamingDraftSubscription() {
    final listenable = activeStreamingDraftListenable;
    final listener = activeStreamingDraftListener;
    if (listenable != null && listener != null) {
      listenable.removeListener(listener);
    }
    activeStreamingDraftMessageId = null;
    activeStreamingDraftListenable = null;
    activeStreamingDraftListener = null;
  }

  void _scheduleMessageScrollToBottom({
    int settleFrames = 0,
    bool force = false,
  }) {
    widget.diagnostics?.scrollScheduleCount++;
    pendingMessageScrollVersion = messageAutoScrollVersion;
    if (settleFrames > pendingMessageScrollSettleFrames) {
      pendingMessageScrollSettleFrames = settleFrames;
    }
    pendingMessageScrollForce = pendingMessageScrollForce || force;
    if (messageScrollFrameScheduled) {
      return;
    }
    messageScrollFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      messageScrollFrameScheduled = false;
      final scheduledVersion = pendingMessageScrollVersion;
      final settleFrames = pendingMessageScrollSettleFrames;
      final force = pendingMessageScrollForce;
      pendingMessageScrollVersion = null;
      pendingMessageScrollSettleFrames = 0;
      pendingMessageScrollForce = false;
      if (!mounted ||
          !messageScrollController.hasClients ||
          scheduledVersion != messageAutoScrollVersion) {
        return;
      }
      if (!force && !messageIsNearBottom && settleFrames > 0) {
        return;
      }
      final target = messageScrollController.position.maxScrollExtent;
      _jumpMessageScrollTo(target);
      if (settleFrames > 0 && (force || messageIsNearBottom)) {
        _scheduleMessageScrollToBottom(settleFrames: settleFrames - 1);
      }
    });
  }

  void _cancelPendingMessageScrollToBottom() {
    pendingMessageScrollVersion = null;
    pendingMessageScrollSettleFrames = 0;
    pendingMessageScrollForce = false;
    messageAutoScrollVersion++;
  }

  void _jumpMessageScrollTo(double target) {
    final position = messageScrollController.position;
    final beforePixels = position.pixels;
    final beforeMaxScrollExtent = position.maxScrollExtent;
    final correctionDistance = target - beforePixels;
    if (correctionDistance.abs() <= _messageScrollJumpTolerance) {
      _recordMessageScrollPosition(position.pixels);
      _setMessageIsNearBottom(_isNearMessageBottom());
      return;
    }
    isProgrammaticMessageScroll = true;
    messageScrollController.jumpTo(target);
    isProgrammaticMessageScroll = false;
    final afterPosition = messageScrollController.position;
    final diagnostics = widget.diagnostics;
    if (diagnostics != null) {
      diagnostics.actualJumpCount++;
      diagnostics.jumpSamples.add(
        ChatScrollJumpSample(
          beforePixels: beforePixels,
          beforeMaxScrollExtent: beforeMaxScrollExtent,
          target: target,
          afterPixels: afterPosition.pixels,
          afterMaxScrollExtent: afterPosition.maxScrollExtent,
        ),
      );
    }
    _recordMessageScrollPosition(messageScrollController.position.pixels);
    _setMessageIsNearBottom(_isNearMessageBottom());
  }
}

class _HeaderMembersPill extends StatelessWidget {
  const _HeaderMembersPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF3),
        border: Border.all(color: const Color(0xFFA7F3D0)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count 名成员',
        style: const TextStyle(
          color: Color(0xFF047857),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SafetyStatusButton extends StatelessWidget {
  const _SafetyStatusButton({
    required this.compact,
    required this.pendingCount,
    required this.onPressed,
  });

  final bool compact;
  final int pendingCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Tooltip(
        message: '安全状态',
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            fixedSize: const Size(34, 30),
            minimumSize: const Size(34, 30),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const Icon(Icons.receipt_long_rounded, size: 16),
              if (pendingCount > 0)
                Positioned(
                  top: -8,
                  right: -9,
                  child: _SmallCountBadge(count: pendingCount),
                ),
            ],
          ),
        ),
      );
    }
    return Tooltip(
      message: '安全状态',
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.receipt_long_rounded, size: 16),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('安全状态'),
            if (pendingCount > 0) ...[
              const SizedBox(width: 6),
              _SmallCountBadge(count: pendingCount),
            ],
          ],
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}

class _SmallCountBadge extends StatelessWidget {
  const _SmallCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count.toString(),
        style: const TextStyle(
          color: Color(0xFFB45309),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SafetyStatusDrawer extends StatelessWidget {
  const _SafetyStatusDrawer({
    required this.controller,
    required this.conversation,
    required this.commandRequests,
    required this.pendingPatches,
  });

  final AppController controller;
  final Conversation conversation;
  final List<CommandRequest> commandRequests;
  final List<PatchProposal> pendingPatches;

  @override
  Widget build(BuildContext context) {
    final members = controller.membersForConversation(conversation.id);
    final pendingCommands = commandRequests
        .where((request) => request.status == CommandRequestStatus.pending)
        .length;
    final approvedCommands = commandRequests
        .where((request) => request.status == CommandRequestStatus.approved)
        .length;
    final latestAudit = controller.state.auditLog.isEmpty
        ? null
        : controller.state.auditLog.last;
    return Material(
      elevation: 14,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 292,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFCBD5E1)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '会话安全状态',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭安全状态',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  _SafetyLine(
                    label: '成员状态',
                    value: members.map((member) => member.name).join('、'),
                    badge: '${members.length}',
                    color: const Color(0xFF047857),
                  ),
                  _SafetyLine(
                    label: '命令审批',
                    value: pendingCommands > 0
                        ? '$pendingCommands 条等待确认'
                        : approvedCommands > 0
                            ? '$approvedCommands 条允许中'
                            : '无待处理命令',
                    badge: pendingCommands > 0
                        ? '待审批'
                        : approvedCommands > 0
                            ? '允许中'
                            : '空',
                    color: pendingCommands > 0
                        ? const Color(0xFFB45309)
                        : const Color(0xFF2563EB),
                  ),
                  _SafetyLine(
                    label: '补丁确认',
                    value: pendingPatches.isEmpty
                        ? '无待确认补丁'
                        : '${pendingPatches.length} 个补丁等待确认',
                    badge: pendingPatches.isEmpty ? '空' : '待确认',
                    color: pendingPatches.isEmpty
                        ? const Color(0xFF64748B)
                        : const Color(0xFFB45309),
                  ),
                  _SafetyLine(
                    label: '审计摘要',
                    value: latestAudit == null
                        ? '暂无审计记录'
                        : '${latestAudit.action} · ${messageTimeText(latestAudit.createdAt)}',
                    badge: 'newest',
                    color: const Color(0xFF475569),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyLine extends StatelessWidget {
  const _SafetyLine({
    required this.label,
    required this.value,
    required this.badge,
    required this.color,
  });

  final String label;
  final String value;
  final String badge;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFD),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  border: Border.all(color: color.withValues(alpha: 0.24)),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TokenFields {
  const _TokenFields({
    this.inputTokens,
    this.outputTokens,
    this.cachedTokens,
    this.totalTokens,
  });

  final int? inputTokens;
  final int? outputTokens;
  final int? cachedTokens;
  final int? totalTokens;

  bool get isEmpty =>
      inputTokens == null &&
      outputTokens == null &&
      cachedTokens == null &&
      totalTokens == null;
}

int? _metadataInt(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  return null;
}
