import '../core/domain.dart';
import 'app_controller_helpers.dart';
import 'conversation_sessions.dart';
import 'state_lookup.dart';

typedef ConversationStateReader = AppState Function();
typedef ConversationStateCommitter = void Function(AppState state);
typedef ConversationSelectionReader = String Function();
typedef ActiveTeamReader = String? Function();
typedef ConversationSelectionUpdater = void Function({
  required String selectedConversationId,
  required String? activeTeamId,
});
typedef ConversationNotifier = void Function();
typedef ConversationDraftCleaner = void Function(String conversationId);

class ConversationController {
  const ConversationController({
    required this.readState,
    required this.commit,
    required this.sessions,
    required this.selectedConversationId,
    required this.activeTeamId,
    required this.updateSelection,
    required this.notify,
    required this.clearDraftsForConversation,
  });

  final ConversationStateReader readState;
  final ConversationStateCommitter commit;
  final ConversationSessionStore sessions;
  final ConversationSelectionReader selectedConversationId;
  final ActiveTeamReader activeTeamId;
  final ConversationSelectionUpdater updateSelection;
  final ConversationNotifier notify;
  final ConversationDraftCleaner clearDraftsForConversation;

  AppState get state => readState();

  Conversation currentConversation({required Team currentTeam}) {
    return state.conversations.firstWhere(
      (item) => item.id == selectedConversationId(),
      orElse: () => state.conversations.firstWhere(
        (item) => item.teamId == currentTeam.id && item.memberId == null,
      ),
    );
  }

  Conversation teamConversation({required Team currentTeam}) {
    return activeConversationForObject(
      requireTeamConversation(state, currentTeam.id),
    );
  }

  List<Conversation> get visibleConversations {
    return sessions.visibleConversations(
      state,
      selectedConversationId: selectedConversationId(),
    );
  }

  List<Conversation> get openConversationPanes {
    return sessions.openConversationPanes(
      state,
      selectedConversationId: selectedConversationId(),
    );
  }

  double get conversationListScrollOffset =>
      sessions.conversationListScrollOffset;

  void recordConversationListScrollOffset(double offset) {
    sessions.recordConversationListScrollOffset(offset);
  }

  Conversation conversationForMember(Team currentTeam, String memberId) {
    final source = state.conversations.firstWhere(
      (conversation) =>
          conversation.teamId == currentTeam.id &&
          conversation.memberId == memberId,
      orElse: () => throw StateError('成员会话不存在: $memberId'),
    );
    return activeConversationForObject(source);
  }

  void selectConversation(String conversationId) {
    activateConversation(conversationId);
    notify();
  }

  void startTeamChat(String teamId) {
    final team = requireTeam(state, teamId);
    final conversation = activeConversationForObject(
      requireTeamConversation(state, team.id),
    );
    activateConversation(conversation.id);
    notify();
  }

  void startMemberChat(Team currentTeam, String memberId) {
    final member = requireMember(state, memberId);
    Conversation? conversation;
    for (final item in state.conversations) {
      if (item.teamId == currentTeam.id && item.memberId == memberId) {
        conversation = item;
        break;
      }
    }
    if (conversation == null) {
      final newConversation = createMemberConversation(currentTeam.id, member);
      conversation = newConversation;
      commit(
        state.copyWith(
          conversations: [
            ...state.conversations,
            newConversation,
          ],
        ),
      );
    }
    final activeConversation = activeConversationForObject(conversation);
    activateConversation(activeConversation.id);
    notify();
  }

  Conversation createConversationLikeCurrent() {
    final source = conversationByIdOrThrow(state, selectedConversationId());
    if (source.messages.isEmpty) {
      activateConversation(source.id);
      notify();
      return source;
    }
    final existingEmptySession = emptyConversationForObject(source);
    if (existingEmptySession != null) {
      activateConversation(existingEmptySession.id);
      notify();
      return existingEmptySession;
    }
    final conversation = createEmptyConversationForObject(source);
    commit(
      state.copyWith(
        conversations: [
          ...state.conversations,
          conversation,
        ],
      ),
    );
    activateConversation(conversation.id);
    notify();
    return conversation;
  }

  void deleteConversationSession(String conversationId) {
    final conversation = conversationByIdOrNull(state, conversationId);
    if (conversation == null) {
      return;
    }

    final deletingCurrent = selectedConversationId() == conversationId;
    Conversation? fallbackConversation;
    Conversation? createdFallbackConversation;
    if (deletingCurrent) {
      fallbackConversation = fallbackConversationAfterDeleting(conversation);
      if (fallbackConversation == null) {
        createdFallbackConversation = createEmptyConversationForObject(
          conversation,
        );
        fallbackConversation = createdFallbackConversation;
      }
      updateSelection(
        selectedConversationId: fallbackConversation.id,
        activeTeamId: fallbackConversation.teamId,
      );
      sessions.showConversation(fallbackConversation);
    }

    clearDraftsForConversation(conversationId);
    sessions.removeConversation(conversationId);

    final nextConversations = [
      for (final item in state.conversations)
        if (item.id != conversationId) item,
      if (createdFallbackConversation != null) createdFallbackConversation,
    ];
    commit(
      state.copyWith(
        conversations: nextConversations,
        queuedTasks: state.queuedTasks
            .where((task) => task.conversationId != conversationId)
            .toList(),
        taskAssignments: state.taskAssignments
            .where((assignment) => assignment.conversationId != conversationId)
            .toList(),
      ),
    );

    if (deletingCurrent && fallbackConversation != null) {
      activateConversation(fallbackConversation.id);
      notify();
    }
  }

  bool isConversationPinned(String conversationId) {
    return sessions.isPinned(conversationId);
  }

  List<Conversation> get conversationHistory {
    return sessions.conversationHistory(
      state,
      selectedConversationId: selectedConversationId(),
    );
  }

  Conversation activateConversation(String conversationId) {
    final conversation = sessions.activate(state, conversationId);
    updateSelection(
      selectedConversationId: conversation.id,
      activeTeamId: conversation.teamId,
    );
    return conversation;
  }

  Conversation activeConversationForObject(Conversation source) {
    return sessions.activeConversationForObject(
      state,
      source,
      selectedConversationId: selectedConversationId(),
    );
  }

  Conversation? emptyConversationForObject(Conversation source) {
    return sessions.emptyConversationForObject(
      state,
      source,
      selectedConversationId: selectedConversationId(),
    );
  }

  Conversation? fallbackConversationAfterDeleting(Conversation deleted) {
    return sessions.fallbackConversationAfterDeleting(
      state,
      deleted,
    );
  }

  Conversation createEmptyConversationForObject(Conversation source) {
    return sessions.createEmptyConversationForObject(source);
  }

  void togglePinnedConversation(String conversationId) {
    sessions.togglePinned(state, conversationId);
    notify();
  }

  void closeConversation(String conversationId) {
    final conversation = conversationByIdOrNull(state, conversationId);
    if (conversation == null) {
      return;
    }
    if (sessions.closeWouldHideLastVisibleObject(
      state,
      conversation,
      selectedConversationId: selectedConversationId(),
    )) {
      return;
    }
    sessions.closeConversationObject(state, conversation);
    final selectedConversation =
        conversationByIdOrNull(state, selectedConversationId());
    if (selectedConversation == null ||
        sessions.isHidden(selectedConversationId())) {
      final nextConversation = visibleConversations.first;
      activateConversation(nextConversation.id);
    }
    notify();
  }

  void syncConversationOrder() {
    sessions.sync(state);
  }
}
