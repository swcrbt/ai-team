part of '../../app.dart';

class _ChatPane extends StatefulWidget {
  const _ChatPane({
    super.key,
    required this.controller,
    required this.conversationId,
    this.diagnostics,
  });

  final AppController controller;
  final String conversationId;
  final ChatScrollDiagnostics? diagnostics;

  @override
  State<_ChatPane> createState() => _ChatPaneState();
}

class _ChatPaneState extends State<_ChatPane> {
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
    final conversation =
        widget.controller.conversationById(widget.conversationId);
    final typingMembers = _typingMembers(widget.controller, conversation);
    final pendingPatches =
        widget.controller.selectedConversationId == conversation.id
            ? widget.controller.patchProposals
                .where((patch) => patch.status == PatchStatus.pending)
                .toList()
            : const <PatchProposal>[];
    final commandRequests =
        widget.controller.commandRequestsForConversation(conversation.id);
    final messageListItemCount = conversation.messages.length +
        typingMembers.length +
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
    _syncActiveStreamingDraftSubscription(
      conversation.id,
      currentLastMessage,
    );
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
    return Column(
      children: [
        Container(
          height: 74,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.centerLeft,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
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
                      _conversationTitle(widget.controller, conversation),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _conversationMeta(widget.controller, conversation),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
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
                  const PopupMenuItem(
                    enabled: false,
                    child: Text('历史会话'),
                  ),
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
                              _conversationMenuTitle(
                                widget.controller,
                                item,
                              ),
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
                  onPointerSignal: (event) => _handleMessagePointerSignal(
                    event,
                  ),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) =>
                        _handleMessageScrollNotification(notification),
                    child: NotificationListener<ScrollMetricsNotification>(
                      onNotification: (notification) =>
                          _handleMessageScrollMetricsNotification(
                        notification,
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(
                          'chat-message-list-${conversation.id}',
                        ),
                        child: ListView.builder(
                          key: const ValueKey('chat-message-list'),
                          controller: messageScrollController,
                          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                          itemCount: messageListItemCount,
                          itemBuilder: (context, index) {
                            if (index < conversation.messages.length) {
                              return _MessageBubble(
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
                            if (typingIndex < typingMembers.length) {
                              return _TypingIndicator(
                                member: typingMembers[typingIndex],
                              );
                            }
                            final commandIndex =
                                typingIndex - typingMembers.length;
                            if (commandIndex < commandRequests.length) {
                              final request = commandRequests[commandIndex];
                              return _ChatCommandRequestCard(
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
                            return _ChatPatchConfirmationCard(
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
        _TaskQueueBar(
          controller: widget.controller,
          conversationId: conversation.id,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(4),
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
                        hintText: _inputHint(widget.controller, conversation),
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
                  child: _SplitSendButton(
                    isDispatching: widget.controller.isDispatching,
                    isConversationDispatching: widget.controller
                        .isConversationDispatching(conversation.id),
                    onSend: _submit,
                    onStop: () =>
                        widget.controller.stopConversationById(conversation.id),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
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
          '删除后将永久移除“${_conversationMenuTitle(widget.controller, conversation)}”及其消息。',
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

  bool _handleMessageScrollNotification(
    ScrollNotification notification,
  ) {
    if (notification.metrics.axis != Axis.vertical ||
        isProgrammaticMessageScroll) {
      return false;
    }
    _recordMessageScrollPosition(
      notification.metrics.pixels,
    );
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
    _syncMessageNearBottom(
      notification.metrics,
      canCancelPendingScroll: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !messageScrollController.hasClients) {
        return;
      }
      final position = messageScrollController.position;
      _recordMessageScrollPosition(position.pixels);
      _syncMessageNearBottom(
        position,
        canCancelPendingScroll: false,
      );
    });
    return false;
  }

  void _handleMessagePointerSignal(
    PointerSignalEvent event,
  ) {
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
        _scheduleMessageScrollToBottom(
          settleFrames: settleFrames - 1,
        );
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
    _recordMessageScrollPosition(
      messageScrollController.position.pixels,
    );
    _setMessageIsNearBottom(_isNearMessageBottom());
  }
}

enum _SendButtonMenuAction { send, stop }

class _SplitSendButton extends StatelessWidget {
  const _SplitSendButton({
    required this.isDispatching,
    required this.isConversationDispatching,
    required this.onSend,
    required this.onStop,
  });

  final bool isDispatching;
  final bool isConversationDispatching;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final primaryAction = isConversationDispatching
        ? onStop
        : isDispatching
            ? null
            : onSend;
    final menuAction = isConversationDispatching
        ? _SendButtonMenuAction.stop
        : isDispatching
            ? null
            : _SendButtonMenuAction.send;
    final enabled = primaryAction != null;
    final backgroundColor =
        enabled ? const Color(0xFF0EA5E9) : const Color(0xFFB8DDF0);
    final foregroundColor =
        enabled ? Colors.white : Colors.white.withValues(alpha: 0.72);

    return ClipRRect(
      key: const ValueKey('chat-send-button'),
      borderRadius: BorderRadius.circular(4),
      child: Material(
        color: backgroundColor,
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: isConversationDispatching ? '停止生成' : '发送',
                child: InkWell(
                  onTap: primaryAction,
                  child: SizedBox(
                    width: 66,
                    height: 32,
                    child: Center(
                      child: isConversationDispatching
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.stop_rounded,
                                  size: 14,
                                  color: foregroundColor,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '停止',
                                  style: TextStyle(
                                    color: foregroundColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              '发送(S)',
                              style: TextStyle(
                                color: foregroundColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 18, color: Colors.white24),
              MenuAnchor(
                alignmentOffset: const Offset(-70, 4),
                menuChildren: [
                  if (menuAction != null)
                    MenuItemButton(
                      onPressed: () {
                        switch (menuAction) {
                          case _SendButtonMenuAction.send:
                            onSend();
                          case _SendButtonMenuAction.stop:
                            onStop();
                        }
                      },
                      child: Text(
                        menuAction == _SendButtonMenuAction.stop
                            ? '停止生成'
                            : '发送',
                      ),
                    ),
                ],
                builder: (context, controller, child) {
                  return Tooltip(
                    message: '发送选项',
                    child: InkWell(
                      onTap: menuAction == null
                          ? null
                          : () {
                              if (controller.isOpen) {
                                controller.close();
                              } else {
                                controller.open();
                              }
                            },
                      child: SizedBox(
                        width: 26,
                        height: 32,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: foregroundColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({required this.member});

  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: _avatarColor(member.name),
          child: Text(
            _avatarText(member.name),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${member.name} 正在输入中',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.conversationId,
    required this.showAuthorName,
    required this.draftListenable,
    this.diagnostics,
  });

  final ChatMessage message;
  final String conversationId;
  final bool showAuthorName;
  final ValueListenable<ChatStreamingDraft?> draftListenable;
  final ChatScrollDiagnostics? diagnostics;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
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
  void didUpdateWidget(covariant _MessageBubble oldWidget) {
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
        alignRight ? null : _normalizedThinkingContent(message);
    final inlineStatus = thinkingContent == null
        ? _messageInlineGenerationStatus(message)
        : null;
    final showMessageHeader =
        !alignRight && (showAuthorName || inlineStatus != null);
    final showReplyBubble =
        !_isStreamingThinkingWithoutReplyContent(message, thinkingContent);
    final thinkingSection = thinkingContent == null
        ? null
        : ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: _MessageThinkingDisclosure(
              partitionKey: message.id,
              content: thinkingContent,
              title: _thinkingTitle(message),
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
      constraints: const BoxConstraints(maxWidth: 680),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: alignRight ? const Color(0xFFE8F1FF) : Colors.white,
        border: Border.all(
          color: alignRight ? const Color(0xFFCFE0FF) : const Color(0xFFE5E7EB),
        ),
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isAwaitingFirstModelOutput(message))
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
                  _messageTimeText(message.createdAt),
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
                backgroundColor: _avatarColor(message.authorName),
                child: Text(
                  _avatarText(message.authorName),
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
                  '我',
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
    this.diagnostics,
  });

  final ChatMessage message;
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
        ],
      );
    }
    return _MessageTextBlock(
      message: message,
      content: message.content,
      diagnostics: diagnostics,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_right_rounded,
                  size: 20,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 4),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(
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
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        height: 1.45,
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }
}
