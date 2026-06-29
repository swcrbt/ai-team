import '../core/domain.dart';
import 'app_controller_helpers.dart';

class ConversationSessionStore {
  final Set<String> hiddenConversationIds = <String>{};
  final Set<String> openedConversationIds = <String>{};
  final List<String> conversationOrderIds = <String>[];
  final Set<String> pinnedConversationIds = <String>{};
  final List<String> pinnedConversationOrderIds = <String>[];
  double _conversationListScrollOffset = 0;

  double get conversationListScrollOffset => _conversationListScrollOffset;

  void recordConversationListScrollOffset(double offset) {
    _conversationListScrollOffset = offset;
  }

  bool isPinned(String conversationId) {
    return pinnedConversationIds.contains(conversationId);
  }

  void sync(AppState state) {
    final existingIds =
        state.conversations.map((conversation) => conversation.id).toList();
    final existingIdSet = existingIds.toSet();
    conversationOrderIds.removeWhere((id) => !existingIdSet.contains(id));
    pinnedConversationIds.removeWhere((id) => !existingIdSet.contains(id));
    pinnedConversationOrderIds.removeWhere(
      (id) =>
          !existingIdSet.contains(id) || !pinnedConversationIds.contains(id),
    );
    for (final id in existingIds) {
      if (!conversationOrderIds.contains(id)) {
        conversationOrderIds.add(id);
      }
    }
  }

  List<Conversation> visibleConversations(
    AppState state, {
    required String selectedConversationId,
  }) {
    sync(state);
    final conversationsById = _conversationsById(state);
    final visible = <Conversation>[];
    final visibleObjectKeys = <String>{};
    for (final id in conversationIdsInDisplayOrder(state)) {
      final conversation = conversationsById[id];
      if (conversation == null ||
          !_shouldShowConversation(conversation, selectedConversationId)) {
        continue;
      }
      final key = conversationObjectKey(conversation);
      if (visibleObjectKeys.add(key)) {
        visible.add(conversation);
      }
    }
    return visible;
  }

  List<Conversation> openConversationPanes(
    AppState state, {
    required String selectedConversationId,
  }) {
    sync(state);
    final conversationsById = _conversationsById(state);
    final paneIds = <String>{};
    for (final conversation in visibleConversations(
      state,
      selectedConversationId: selectedConversationId,
    )) {
      paneIds.add(conversation.id);
    }
    paneIds.add(selectedConversationId);
    for (final id in conversationIdsInDisplayOrder(
      state,
      selectedConversationId: selectedConversationId,
      selectedFirst: true,
    )) {
      if (openedConversationIds.contains(id)) {
        paneIds.add(id);
      }
    }
    return paneIds
        .map((id) => conversationsById[id])
        .whereType<Conversation>()
        .where((conversation) => !hiddenConversationIds.contains(
              conversation.id,
            ))
        .toList();
  }

  List<Conversation> conversationHistory(
    AppState state, {
    required String selectedConversationId,
  }) {
    sync(state);
    final conversationsById = _conversationsById(state);
    final current = conversationById(state, selectedConversationId);
    return conversationIdsInDisplayOrder(
      state,
      selectedConversationId: selectedConversationId,
      selectedFirst: true,
    )
        .map((id) => conversationsById[id])
        .whereType<Conversation>()
        .where((conversation) => isSameConversationObject(
              conversation,
              current,
            ))
        .toList();
  }

  Conversation activate(AppState state, String conversationId) {
    final conversation = conversationById(state, conversationId);
    openedConversationIds.add(conversation.id);
    unhideConversationObject(state, conversation);
    moveConversationToFront(state, conversation.id);
    return conversation;
  }

  Conversation activeConversationForObject(
    AppState state,
    Conversation source, {
    String? selectedConversationId,
  }) {
    final conversationsById = _conversationsById(state);
    for (final id in conversationIdsInDisplayOrder(
      state,
      selectedConversationId: selectedConversationId,
      selectedFirst: true,
    )) {
      final conversation = conversationsById[id];
      if (conversation != null &&
          isSameConversationObject(conversation, source)) {
        return conversation;
      }
    }
    return source;
  }

  Conversation? emptyConversationForObject(
    AppState state,
    Conversation source, {
    String? selectedConversationId,
  }) {
    final conversationsById = _conversationsById(state);
    for (final id in conversationIdsInDisplayOrder(
      state,
      selectedConversationId: selectedConversationId,
      selectedFirst: true,
    )) {
      final conversation = conversationsById[id];
      if (conversation != null &&
          isSameConversationObject(conversation, source) &&
          conversation.messages.isEmpty) {
        return conversation;
      }
    }
    return null;
  }

  Conversation? fallbackConversationAfterDeleting(
    AppState state,
    Conversation deleted,
  ) {
    final conversationsById = _conversationsById(state);
    final sameObjectConversations = <Conversation>[];
    for (final id in conversationIdsInDisplayOrder(state)) {
      final conversation = conversationsById[id];
      if (conversation != null &&
          conversation.id != deleted.id &&
          isSameConversationObject(conversation, deleted)) {
        sameObjectConversations.add(conversation);
      }
    }
    for (final conversation in sameObjectConversations) {
      if (conversation.messages.isNotEmpty) {
        return conversation;
      }
    }
    if (sameObjectConversations.isEmpty) {
      return null;
    }
    return sameObjectConversations.first;
  }

  Conversation createEmptyConversationForObject(Conversation source) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return Conversation(
      id: source.memberId == null
          ? 'conv-${source.teamId}-$timestamp'
          : 'conv-${source.teamId}-${source.memberId}-$timestamp',
      title: '',
      teamId: source.teamId,
      memberId: source.memberId,
      messages: const [],
    );
  }

  void removeConversation(String conversationId) {
    openedConversationIds.remove(conversationId);
    hiddenConversationIds.remove(conversationId);
    pinnedConversationIds.remove(conversationId);
    pinnedConversationOrderIds.remove(conversationId);
    conversationOrderIds.remove(conversationId);
  }

  void showConversation(Conversation conversation) {
    openedConversationIds.add(conversation.id);
    hiddenConversationIds.remove(conversation.id);
  }

  void togglePinned(AppState state, String conversationId) {
    if (!state.conversations
        .any((conversation) => conversation.id == conversationId)) {
      return;
    }
    if (pinnedConversationIds.remove(conversationId)) {
      pinnedConversationOrderIds.remove(conversationId);
    } else {
      pinnedConversationIds.add(conversationId);
      pinnedConversationOrderIds.remove(conversationId);
      pinnedConversationOrderIds.insert(0, conversationId);
    }
  }

  bool closeWouldHideLastVisibleObject(
      AppState state, Conversation conversation,
      {required String selectedConversationId}) {
    final visibleObjectKeys = visibleConversations(
      state,
      selectedConversationId: selectedConversationId,
    ).map(conversationObjectKey).toSet();
    final objectKey = conversationObjectKey(conversation);
    return visibleObjectKeys.length <= 1 &&
        visibleObjectKeys.contains(objectKey);
  }

  void closeConversationObject(AppState state, Conversation conversation) {
    for (final item in state.conversations) {
      if (isSameConversationObject(item, conversation)) {
        hiddenConversationIds.add(item.id);
        openedConversationIds.remove(item.id);
      }
    }
  }

  bool isHidden(String conversationId) {
    return hiddenConversationIds.contains(conversationId);
  }

  void unhideConversationObject(AppState state, Conversation source) {
    hiddenConversationIds.removeWhere((id) {
      final conversation = conversationByIdOrNull(state, id);
      return conversation != null &&
          isSameConversationObject(conversation, source);
    });
  }

  String conversationObjectKey(Conversation conversation) {
    final memberId = conversation.memberId;
    if (memberId == null) {
      return 'team:${conversation.teamId}';
    }
    return 'member:${conversation.teamId}:$memberId';
  }

  bool isSameConversationObject(
    Conversation left,
    Conversation right,
  ) {
    return conversationObjectKey(left) == conversationObjectKey(right);
  }

  List<String> conversationIdsInDisplayOrder(
    AppState state, {
    String? selectedConversationId,
    bool selectedFirst = false,
  }) {
    sync(state);
    final existingIdSet =
        state.conversations.map((conversation) => conversation.id).toSet();
    final ids = <String>{};
    if (selectedFirst &&
        selectedConversationId != null &&
        existingIdSet.contains(selectedConversationId)) {
      ids.add(selectedConversationId);
    }
    ids.addAll(
      pinnedConversationOrderIds.where(
        (id) =>
            existingIdSet.contains(id) && pinnedConversationIds.contains(id),
      ),
    );
    ids.addAll(
      conversationOrderIds.where(
        (id) =>
            existingIdSet.contains(id) && !pinnedConversationIds.contains(id),
      ),
    );
    ids.addAll(existingIdSet);
    return ids.toList();
  }

  void moveConversationToFront(AppState state, String conversationId) {
    sync(state);
    if (!conversationOrderIds.contains(conversationId)) {
      return;
    }
    conversationOrderIds.remove(conversationId);
    conversationOrderIds.insert(0, conversationId);
    if (pinnedConversationIds.contains(conversationId)) {
      pinnedConversationOrderIds.remove(conversationId);
      pinnedConversationOrderIds.insert(0, conversationId);
    }
  }

  Conversation conversationById(AppState state, String conversationId) {
    return state.conversations.firstWhere(
      (conversation) => conversation.id == conversationId,
      orElse: () => throw StateError('会话不存在: $conversationId'),
    );
  }

  Conversation? conversationByIdOrNull(AppState state, String conversationId) {
    for (final conversation in state.conversations) {
      if (conversation.id == conversationId) {
        return conversation;
      }
    }
    return null;
  }

  bool _shouldShowConversation(
    Conversation conversation,
    String selectedConversationId,
  ) {
    if (hiddenConversationIds.contains(conversation.id)) {
      return false;
    }
    if (conversation.id == selectedConversationId) {
      return true;
    }
    if (openedConversationIds.contains(conversation.id)) {
      return true;
    }
    return !isGeneratedWelcomeOnlyMemberConversation(conversation);
  }

  Map<String, Conversation> _conversationsById(AppState state) {
    return {
      for (final conversation in state.conversations)
        conversation.id: conversation,
    };
  }
}
