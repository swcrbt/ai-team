import 'package:flutter/foundation.dart';

import '../core/domain.dart';
import 'chat_streaming.dart';

class StreamingDraftRegistry {
  StreamingDraftRegistry({this.diagnostics});

  final ChatScrollDiagnostics? diagnostics;
  final Map<String, ValueNotifier<ChatStreamingDraft?>> _notifiers = {};
  final Map<String, Set<String>> _messageIdsByConversation = {};

  ValueListenable<ChatStreamingDraft?> listenable(String messageId) {
    return _notifiers.putIfAbsent(
      messageId,
      () => ValueNotifier<ChatStreamingDraft?>(null),
    );
  }

  void update({
    required String conversationId,
    required ChatMessage message,
  }) {
    diagnostics?.streamingDraftUpdateCount++;
    _messageIdsByConversation
        .putIfAbsent(conversationId, () => <String>{})
        .add(message.id);
    final notifier = _notifiers.putIfAbsent(
      message.id,
      () => ValueNotifier<ChatStreamingDraft?>(null),
    );
    notifier.value = ChatStreamingDraft(
      conversationId: conversationId,
      message: message,
    );
  }

  void clearConversation(String conversationId) {
    final messageIds = _messageIdsByConversation.remove(conversationId);
    if (messageIds == null) {
      return;
    }
    for (final messageId in messageIds) {
      final notifier = _notifiers[messageId];
      if (notifier?.value != null) {
        notifier!.value = null;
      }
    }
  }

  void dispose() {
    for (final notifier in _notifiers.values) {
      notifier.dispose();
    }
    _notifiers.clear();
    _messageIdsByConversation.clear();
  }
}
