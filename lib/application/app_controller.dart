import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/commands/command_service.dart';
import '../core/domain.dart';
import '../core/file_dialogs.dart';
import '../core/local_store.dart';
import '../core/model_gateway.dart';
import '../core/orchestrator.dart';
import '../core/patching.dart';
import '../core/workspace/workspace_service.dart';
import 'app_controller_helpers.dart';
import 'chat_streaming.dart';
import 'state_persistence_queue.dart';

class AppController extends ChangeNotifier {
  AppController(
    AppState initialState,
    this.orchestrator, {
    this.onStateChanged,
    this.fileDialogs = const SystemFileDialogService(),
    JsonLocalStore? exportStore,
    this.workspaceService = const WorkspaceService(),
    CommandService? commandService,
    this.diagnostics,
  })  : state = initialState,
        exportStore = exportStore ?? JsonLocalStore.defaultStore(),
        commandService = commandService ?? const CommandService(),
        selectedConversationId = initialConversationId(initialState) {
    final conversation = state.conversations.firstWhere(
      (item) => item.id == selectedConversationId,
    );
    if (conversation.memberId == null) {
      activeTeamId = conversation.teamId;
    }
    _syncConversationOrder();
  }

  AppState state;
  String selectedConversationId;
  String? activeTeamId;
  final Set<String> hiddenConversationIds = <String>{};
  final Set<String> openedConversationIds = <String>{};
  final List<String> conversationOrderIds = <String>[];
  final Set<String> pinnedConversationIds = <String>{};
  final List<String> pinnedConversationOrderIds = <String>[];
  double _conversationListScrollOffset = 0;
  final TeamOrchestrator orchestrator;
  final StateChanged? onStateChanged;
  final FileDialogService fileDialogs;
  final JsonLocalStore exportStore;
  final WorkspaceService workspaceService;
  final CommandService commandService;
  final ChatScrollDiagnostics? diagnostics;
  bool isDispatching = false;
  String? error;
  String? _runningTaskId;
  ModelRequestCancellation? _activeCancellation;
  String? _activeDispatchConversationId;
  ConversationStatus? _requestedCancellationStatus;
  final StatePersistenceQueue _persistenceQueue = StatePersistenceQueue();
  final Map<String, ValueNotifier<ChatStreamingDraft?>>
      _streamingDraftNotifiers = {};
  final Map<String, Set<String>> _streamingDraftMessageIdsByConversation = {};

  @override
  void dispose() {
    for (final notifier in _streamingDraftNotifiers.values) {
      notifier.dispose();
    }
    _streamingDraftNotifiers.clear();
    _streamingDraftMessageIdsByConversation.clear();
    super.dispose();
  }

  ValueListenable<ChatStreamingDraft?> streamingDraftListenable(
    String messageId,
  ) {
    return _streamingDraftNotifiers.putIfAbsent(
      messageId,
      () => ValueNotifier<ChatStreamingDraft?>(null),
    );
  }

  void _handleStreamingDraft({
    required String conversationId,
    required ChatMessage message,
  }) {
    diagnostics?.streamingDraftUpdateCount++;
    _streamingDraftMessageIdsByConversation
        .putIfAbsent(conversationId, () => <String>{})
        .add(message.id);
    final notifier = _streamingDraftNotifiers.putIfAbsent(
      message.id,
      () => ValueNotifier<ChatStreamingDraft?>(null),
    );
    notifier.value = ChatStreamingDraft(
      conversationId: conversationId,
      message: message,
    );
  }

  void _clearStreamingDraftsForConversation(String conversationId) {
    final messageIds =
        _streamingDraftMessageIdsByConversation.remove(conversationId);
    if (messageIds == null) {
      return;
    }
    for (final messageId in messageIds) {
      final notifier = _streamingDraftNotifiers[messageId];
      if (notifier?.value != null) {
        notifier!.value = null;
      }
    }
  }

  Team get currentTeam {
    final activeId = activeTeamId;
    if (activeId != null) {
      return _requireTeam(activeId);
    }
    final conversation = state.conversations.firstWhere(
      (item) => item.id == selectedConversationId,
      orElse: () => state.conversations.first,
    );
    return _requireTeam(conversation.teamId);
  }

  List<PatchProposal> get patchProposals => state.patchProposals;

  List<TaskAssignment> get currentTaskAssignments => state.taskAssignments
      .where(
        (assignment) => assignment.conversationId == currentConversation.id,
      )
      .toList()
    ..sort((a, b) {
      final roundComparison = b.round.compareTo(a.round);
      if (roundComparison != 0) {
        return roundComparison;
      }
      return a.createdAt.compareTo(b.createdAt);
    });

  List<TaskAssignment> taskAssignmentsForConversation(String conversationId) {
    return state.taskAssignments
        .where((assignment) => assignment.conversationId == conversationId)
        .toList()
      ..sort((a, b) {
        final roundComparison = b.round.compareTo(a.round);
        if (roundComparison != 0) {
          return roundComparison;
        }
        return a.createdAt.compareTo(b.createdAt);
      });
  }

  List<QueuedTask> get tasksForCurrentConversation => state.queuedTasks
      .where((task) => task.conversationId == currentConversation.id)
      .toList();

  List<QueuedTask> tasksForConversation(String conversationId) =>
      state.queuedTasks
          .where((task) => task.conversationId == conversationId)
          .toList();

  List<QueuedTask> get pendingTasksForCurrentConversation {
    final tasks = tasksForCurrentConversation
        .where((task) => task.status == QueuedTaskStatus.pending)
        .toList();
    tasks.sort(queuedTaskSort);
    return tasks;
  }

  QueuedTask? get currentRunningTask {
    final id = _runningTaskId;
    if (id == null) {
      return null;
    }
    return _taskByIdOrNull(id);
  }

  Conversation get currentConversation => state.conversations.firstWhere(
        (item) => item.id == selectedConversationId,
        orElse: () => state.conversations.firstWhere(
          (item) => item.teamId == currentTeam.id && item.memberId == null,
        ),
      );

  Conversation conversationById(String conversationId) =>
      _conversationById(conversationId);

  List<TeamMember> membersForConversation(String conversationId) {
    final conversation = _conversationById(conversationId);
    final team = _requireTeam(conversation.teamId);
    return state.members
        .where((member) => team.memberIds.contains(member.id))
        .toList();
  }

  Team teamForConversation(String conversationId) {
    return _requireTeam(_conversationById(conversationId).teamId);
  }

  bool isConversationDispatching(String conversationId) {
    return isDispatching && _activeDispatchConversationId == conversationId;
  }

  Conversation get teamConversation => _activeConversationForObject(
        _teamConversationFor(currentTeam.id),
      );

  List<Conversation> get visibleConversations {
    _syncConversationOrder();
    final conversationsById = {
      for (final conversation in state.conversations)
        conversation.id: conversation,
    };
    final visible = <Conversation>[];
    final visibleObjectKeys = <String>{};
    for (final id in _conversationIdsInDisplayOrder()) {
      final conversation = conversationsById[id];
      if (conversation == null || !_shouldShowConversation(conversation)) {
        continue;
      }
      final objectKey = _conversationObjectKey(conversation);
      if (visibleObjectKeys.add(objectKey)) {
        visible.add(conversation);
      }
    }
    return visible;
  }

  List<Conversation> get openConversationPanes {
    _syncConversationOrder();
    final conversationsById = {
      for (final conversation in state.conversations)
        conversation.id: conversation,
    };
    final paneIds = <String>{};
    for (final conversation in visibleConversations) {
      paneIds.add(conversation.id);
    }
    paneIds.add(selectedConversationId);
    for (final id in _conversationIdsInDisplayOrder(selectedFirst: true)) {
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

  bool _shouldShowConversation(Conversation conversation) {
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

  List<TeamMember> get currentMembers => state.members
      .where((member) => currentTeam.memberIds.contains(member.id))
      .toList();

  double get conversationListScrollOffset => _conversationListScrollOffset;

  void recordConversationListScrollOffset(double offset) {
    _conversationListScrollOffset = offset;
  }

  Conversation conversationForMember(String memberId) {
    final source = state.conversations.firstWhere(
      (item) => item.teamId == currentTeam.id && item.memberId == memberId,
      orElse: () => throw StateError('成员会话不存在: $memberId'),
    );
    return _activeConversationForObject(source);
  }

  void selectConversation(String conversationId) {
    _activateConversation(conversationId);
    notifyListeners();
  }

  void startTeamChat(String teamId) {
    final team = _requireTeam(teamId);
    final conversation = _activeConversationForObject(
      _teamConversationFor(team.id),
    );
    _activateConversation(conversation.id);
    notifyListeners();
  }

  void startMemberChat(String memberId) {
    final member = _requireMember(memberId);
    Conversation? conversation;
    for (final item in state.conversations) {
      if (item.teamId == currentTeam.id && item.memberId == memberId) {
        conversation = item;
        break;
      }
    }
    if (conversation == null) {
      conversation = createMemberConversation(currentTeam.id, member);
      _commit(
        state.copyWith(
          conversations: [
            ...state.conversations,
            conversation,
          ],
        ),
      );
    }
    conversation = _activeConversationForObject(conversation);
    _activateConversation(conversation.id);
    notifyListeners();
  }

  Conversation createConversationLikeCurrent() {
    final source = _conversationById(selectedConversationId);
    if (source.messages.isEmpty) {
      _activateConversation(source.id);
      notifyListeners();
      return source;
    }
    final existingEmptySession = _emptyConversationForObject(source);
    if (existingEmptySession != null) {
      _activateConversation(existingEmptySession.id);
      notifyListeners();
      return existingEmptySession;
    }
    final conversation = _createEmptyConversationForObject(source);
    _commit(
      state.copyWith(
        conversations: [
          ...state.conversations,
          conversation,
        ],
      ),
    );
    _activateConversation(conversation.id);
    notifyListeners();
    return conversation;
  }

  void deleteConversationSession(String conversationId) {
    final conversation = _conversationByIdOrNull(conversationId);
    if (conversation == null) {
      return;
    }

    final deletingCurrent = selectedConversationId == conversationId;
    Conversation? fallbackConversation;
    Conversation? createdFallbackConversation;
    if (deletingCurrent) {
      fallbackConversation = _fallbackConversationAfterDeleting(conversation);
      if (fallbackConversation == null) {
        createdFallbackConversation = _createEmptyConversationForObject(
          conversation,
        );
        fallbackConversation = createdFallbackConversation;
      }
      selectedConversationId = fallbackConversation.id;
      activeTeamId = fallbackConversation.teamId;
      openedConversationIds.add(fallbackConversation.id);
      hiddenConversationIds.remove(fallbackConversation.id);
    }

    _clearStreamingDraftsForConversation(conversationId);
    openedConversationIds.remove(conversationId);
    hiddenConversationIds.remove(conversationId);
    pinnedConversationIds.remove(conversationId);
    pinnedConversationOrderIds.remove(conversationId);
    conversationOrderIds.remove(conversationId);

    final nextConversations = [
      for (final item in state.conversations)
        if (item.id != conversationId) item,
      if (createdFallbackConversation != null) createdFallbackConversation,
    ];
    _commit(
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
      _activateConversation(fallbackConversation.id);
      notifyListeners();
    }
  }

  bool isConversationPinned(String conversationId) {
    return pinnedConversationIds.contains(conversationId);
  }

  List<Conversation> get conversationHistory {
    _syncConversationOrder();
    final conversationsById = {
      for (final conversation in state.conversations)
        conversation.id: conversation,
    };
    final current = _conversationById(selectedConversationId);
    return _conversationIdsInDisplayOrder(selectedFirst: true)
        .map((id) => conversationsById[id])
        .whereType<Conversation>()
        .where((conversation) => _isSameConversationObject(
              conversation,
              current,
            ))
        .toList();
  }

  void _activateConversation(String conversationId) {
    final conversation = _conversationById(conversationId);
    selectedConversationId = conversation.id;
    openedConversationIds.add(conversation.id);
    _unhideConversationObject(conversation);
    activeTeamId = conversation.teamId;
    _moveConversationToFront(conversation.id);
  }

  Conversation _activeConversationForObject(Conversation source) {
    final conversationsById = {
      for (final conversation in state.conversations)
        conversation.id: conversation,
    };
    for (final id in _conversationIdsInDisplayOrder(selectedFirst: true)) {
      final conversation = conversationsById[id];
      if (conversation != null &&
          _isSameConversationObject(conversation, source)) {
        return conversation;
      }
    }
    return source;
  }

  Conversation? _emptyConversationForObject(Conversation source) {
    final conversationsById = {
      for (final conversation in state.conversations)
        conversation.id: conversation,
    };
    for (final id in _conversationIdsInDisplayOrder(selectedFirst: true)) {
      final conversation = conversationsById[id];
      if (conversation != null &&
          _isSameConversationObject(conversation, source) &&
          conversation.messages.isEmpty) {
        return conversation;
      }
    }
    return null;
  }

  Conversation? _fallbackConversationAfterDeleting(Conversation deleted) {
    final conversationsById = {
      for (final conversation in state.conversations)
        conversation.id: conversation,
    };
    final sameObjectConversations = <Conversation>[];
    for (final id in _conversationIdsInDisplayOrder()) {
      final conversation = conversationsById[id];
      if (conversation != null &&
          conversation.id != deleted.id &&
          _isSameConversationObject(conversation, deleted)) {
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

  Conversation _createEmptyConversationForObject(Conversation source) {
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

  String _conversationObjectKey(Conversation conversation) {
    final memberId = conversation.memberId;
    if (memberId == null) {
      return 'team:${conversation.teamId}';
    }
    return 'member:${conversation.teamId}:$memberId';
  }

  bool _isSameConversationObject(
    Conversation left,
    Conversation right,
  ) {
    return _conversationObjectKey(left) == _conversationObjectKey(right);
  }

  void _unhideConversationObject(Conversation source) {
    hiddenConversationIds.removeWhere((id) {
      final conversation = _conversationByIdOrNull(id);
      return conversation != null &&
          _isSameConversationObject(
            conversation,
            source,
          );
    });
  }

  void togglePinnedConversation(String conversationId) {
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
    notifyListeners();
  }

  void closeConversation(String conversationId) {
    final conversation = _conversationByIdOrNull(conversationId);
    if (conversation == null) {
      return;
    }
    final visibleObjectKeys = visibleConversations
        .map((conversation) => _conversationObjectKey(conversation))
        .toSet();
    final objectKey = _conversationObjectKey(conversation);
    if (visibleObjectKeys.length <= 1 &&
        visibleObjectKeys.contains(objectKey)) {
      return;
    }
    for (final item in state.conversations) {
      if (_isSameConversationObject(item, conversation)) {
        hiddenConversationIds.add(item.id);
        openedConversationIds.remove(item.id);
      }
    }
    final selectedConversation =
        _conversationByIdOrNull(selectedConversationId);
    if (selectedConversation == null ||
        hiddenConversationIds.contains(selectedConversationId)) {
      final nextConversation = visibleConversations.first;
      _activateConversation(nextConversation.id);
    }
    notifyListeners();
  }

  Future<void> enqueueCurrentConversationTask(
    String text, {
    int priority = 0,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final conversation = currentConversation;
    final team = _requireTeam(conversation.teamId);
    final secretary = state.members.firstWhere(
      (member) => member.id == team.secretaryMemberId,
    );
    final secretaryRole = _requireRole(secretary.roleId);
    final secretaryModel = _requireModel(secretary.modelId);
    final now = DateTime.now();
    final generating = ChatMessage(
      id: 'msg-${now.microsecondsSinceEpoch}',
      authorName: secretary.name,
      memberId: secretary.id,
      content: '正在生成任务',
      createdAt: now,
    );
    _appendMessage(conversation.id, generating);
    try {
      final title = await orchestrator.gateway.complete(
        model: secretaryModel,
        systemPrompt: secretaryRole.renderSystemPrompt(
          memberName: secretary.name,
          teamName: team.name,
        ),
        messages: [
          ChatMessage(
            id: 'msg-title-source-${now.microsecondsSinceEpoch}',
            authorName: '我',
            content: '请为这条任务生成一句简短标题：$trimmed',
            createdAt: now,
            isUser: true,
          ),
        ],
      );
      final createdAt = DateTime.now();
      final taskId = 'task-${createdAt.microsecondsSinceEpoch}';
      final userMessage = ChatMessage(
        id: 'msg-${createdAt.microsecondsSinceEpoch}',
        authorName: '我',
        content: trimmed,
        createdAt: createdAt,
        isUser: true,
        taskIds: [taskId],
      );
      final latestConversation = _conversationById(conversation.id);
      _commit(
        state.copyWith(
          queuedTasks: [
            ...state.queuedTasks,
            QueuedTask(
              id: taskId,
              conversationId: conversation.id,
              title: title.trim(),
              originalText: trimmed,
              priority: priority,
              status: QueuedTaskStatus.pending,
              createdAt: createdAt,
              updatedAt: createdAt,
              messageIds: [userMessage.id],
            ),
          ],
          conversations: state.conversations
              .map(
                (item) => item.id == conversation.id
                    ? latestConversation.copyWith(
                        messages: [
                          ...latestConversation.messages
                              .where((message) => message.id != generating.id),
                          userMessage,
                        ],
                      )
                    : item,
              )
              .toList(),
        ),
      );
    } catch (exception) {
      _replaceMessageContent(
        generating.id,
        '任务标题生成失败：$exception',
      );
    }
  }

  void updateTaskPriority(String taskId, int priority) {
    _commit(
      state.copyWith(
        queuedTasks: state.queuedTasks
            .map(
              (task) => task.id == taskId
                  ? task.copyWith(
                      priority: priority,
                      updatedAt: DateTime.now(),
                    )
                  : task,
            )
            .toList(),
      ),
    );
  }

  void appendTaskNote(String taskId, String note) {
    final trimmed = note.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final task = state.queuedTasks.firstWhere((item) => item.id == taskId);
    final message = ChatMessage(
      id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
      authorName: '系统',
      content: '已为任务追加备注',
      createdAt: DateTime.now(),
      taskIds: [taskId],
    );
    _commit(
      state.copyWith(
        queuedTasks: state.queuedTasks
            .map(
              (item) => item.id == taskId
                  ? item.copyWith(
                      notes: [...item.notes, trimmed],
                      messageIds: [...item.messageIds, message.id],
                      updatedAt: DateTime.now(),
                    )
                  : item,
            )
            .toList(),
        conversations: state.conversations
            .map(
              (conversation) => conversation.id == task.conversationId
                  ? conversation.copyWith(
                      messages: [...conversation.messages, message],
                    )
                  : conversation,
            )
            .toList(),
      ),
    );
  }

  void deleteTask(String taskId) {
    final task = state.queuedTasks.firstWhere((item) => item.id == taskId);
    _commit(
      state.copyWith(
        queuedTasks:
            state.queuedTasks.where((item) => item.id != taskId).toList(),
        conversations: state.conversations
            .map(
              (conversation) => conversation.id == task.conversationId
                  ? conversation.copyWith(
                      messages: conversation.messages
                          .where(
                            (message) =>
                                !message.taskIds.contains(taskId) &&
                                !task.messageIds.contains(message.id),
                          )
                          .toList(),
                    )
                  : conversation,
            )
            .toList(),
      ),
    );
  }

  Future<void> runNextQueuedTask() async {
    if (_runningTaskId != null) {
      return;
    }
    final next = firstQueuedTaskOrNull(pendingTasksForCurrentConversation);
    if (next == null) {
      return;
    }
    _runningTaskId = next.id;
    isDispatching = true;
    error = null;
    final cancellation = ModelRequestCancellation();
    _activeCancellation = cancellation;
    _updateTaskStatus(next.id, QueuedTaskStatus.running);
    try {
      final updated = await orchestrator.dispatchQueuedTask(
        state,
        taskId: next.id,
        cancellation: cancellation,
        onProgress: _commit,
        onStreamingDraft: _handleStreamingDraft,
      );
      if (!cancellation.isCancelled) {
        _commit(updated);
        _updateTaskStatus(next.id, QueuedTaskStatus.completed);
      }
    } on ModelGatewayException catch (exception) {
      if (cancellation.isCancelled) {
        _updateTaskStatus(next.id, QueuedTaskStatus.paused);
      } else {
        error = exception.toString();
        _updateTaskStatus(next.id, QueuedTaskStatus.failed);
      }
    } catch (exception) {
      if (cancellation.isCancelled) {
        _updateTaskStatus(next.id, QueuedTaskStatus.paused);
      } else {
        error = exception.toString();
        _updateTaskStatus(next.id, QueuedTaskStatus.failed);
      }
    } finally {
      if (_runningTaskId == next.id) {
        _runningTaskId = null;
      }
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
      isDispatching = false;
      _clearStreamingDraftsForConversation(next.conversationId);
      notifyListeners();
    }
  }

  void pauseTask(String taskId) {
    if (_runningTaskId == taskId) {
      _activeCancellation?.cancel();
    }
    _updateTaskStatus(taskId, QueuedTaskStatus.paused);
  }

  Future<void> resumeTask(String taskId) async {
    _updateTaskStatus(taskId, QueuedTaskStatus.pending);
    await runNextQueuedTask();
  }

  bool _canDispatchConversation(String conversationId) {
    final status = _conversationById(conversationId).status;
    if (status == ConversationStatus.paused) {
      error = '当前会话已暂停，请先点击继续。';
      return false;
    }
    return true;
  }

  Future<void> dispatch(String text) async {
    await dispatchConversation(selectedConversationId, text);
  }

  Future<void> dispatchConversation(
    String conversationId,
    String text,
  ) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isDispatching) {
      return;
    }
    if (!_canDispatchConversation(conversationId)) {
      notifyListeners();
      return;
    }
    isDispatching = true;
    error = null;
    final cancellation = ModelRequestCancellation();
    _activeCancellation = cancellation;
    _activeDispatchConversationId = conversationId;
    _requestedCancellationStatus = null;
    _notifyListeners();
    try {
      final conversation = _conversationById(conversationId);
      final shouldGenerateTitle =
          _shouldGenerateConversationTitleAfterFirstUserMessage(conversation);
      if (conversation.memberId == null) {
        _commit(
          await orchestrator.dispatchTeamTask(
            state,
            teamId: conversation.teamId,
            conversationId: conversation.id,
            userText: trimmed,
            cancellation: cancellation,
            onProgress: _commit,
            onStreamingDraft: _handleStreamingDraft,
          ),
        );
      } else if (orchestrator
          .secretaryPrivateDispatchTargets(
            state,
            conversationId: conversation.id,
            userText: trimmed,
          )
          .isNotEmpty) {
        _commit(
          await orchestrator.dispatchSecretaryPrivateMemberTask(
            state,
            conversationId: conversation.id,
            userText: trimmed,
            cancellation: cancellation,
            onProgress: _commit,
            onStreamingDraft: _handleStreamingDraft,
          ),
        );
      } else {
        _commit(
          await orchestrator.dispatchMemberChat(
            state,
            conversationId: conversation.id,
            userText: trimmed,
            cancellation: cancellation,
            onProgress: _commit,
            onStreamingDraft: _handleStreamingDraft,
          ),
        );
      }
      if (shouldGenerateTitle) {
        await _generateConversationTitle(
          conversationId: conversationId,
          firstUserMessage: trimmed,
        );
      }
    } catch (exception) {
      if (cancellation.isCancelled) {
        _commitCancelledDispatch(
          conversationId,
          _requestedCancellationStatus ?? ConversationStatus.stopped,
        );
        return;
      }
      error = exception.toString();
      final conversation = _conversationById(conversationId);
      final failed = conversation.copyWith(
        status: ConversationStatus.failed,
        messages: [
          ...conversation.messages,
          ChatMessage(
            id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
            authorName: '系统',
            content: '模型调用失败：$error',
            createdAt: DateTime.now(),
          ),
        ],
      );
      _commit(
        state.copyWith(
          conversations: state.conversations
              .map((item) => item.id == failed.id ? failed : item)
              .toList(),
        ),
      );
    } finally {
      isDispatching = false;
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
      if (_activeDispatchConversationId == conversationId) {
        _activeDispatchConversationId = null;
      }
      _requestedCancellationStatus = null;
      _clearStreamingDraftsForConversation(conversationId);
      _notifyListeners();
    }
  }

  bool _shouldGenerateConversationTitleAfterFirstUserMessage(
    Conversation conversation,
  ) {
    return conversation.title.trim().isEmpty &&
        !conversation.messages.any((message) => message.isUser);
  }

  Future<void> _generateConversationTitle({
    required String conversationId,
    required String firstUserMessage,
  }) async {
    final conversation = _conversationById(conversationId);
    final titleMember = _titleMemberForConversation(conversation);
    final role = _requireRole(titleMember.roleId);
    final model = _requireModel(titleMember.modelId);
    try {
      final generated = await orchestrator.gateway.complete(
        model: model,
        systemPrompt: role.renderSystemPrompt(
          memberName: titleMember.name,
          teamName: _requireTeam(conversation.teamId).name,
        ),
        messages: [
          ChatMessage(
            id: 'msg-title-source-${DateTime.now().microsecondsSinceEpoch}',
            authorName: '我',
            content: '请为这段聊天生成一个 3-8 个字的会话标题，只返回标题：$firstUserMessage',
            createdAt: DateTime.now(),
            isUser: true,
          ),
        ],
      );
      final normalizedTitle = normalizeGeneratedConversationTitle(
        generated,
        conversation: _conversationById(conversationId),
        firstUserMessage: firstUserMessage,
      );
      if (normalizedTitle == null) {
        return;
      }
      final latestConversation = _conversationById(conversationId);
      _commit(
        state.copyWith(
          conversations: state.conversations
              .map(
                (item) => item.id == conversationId
                    ? latestConversation.copyWith(title: normalizedTitle)
                    : item,
              )
              .toList(),
        ),
      );
    } catch (_) {
      return;
    }
  }

  TeamMember _titleMemberForConversation(Conversation conversation) {
    if (conversation.memberId != null) {
      return _requireMember(conversation.memberId!);
    }
    final team = _requireTeam(conversation.teamId);
    return _requireMember(team.secretaryMemberId);
  }

  void pauseConversation() {
    pauseConversationById(selectedConversationId);
  }

  void pauseConversationById(String conversationId) {
    if (isConversationDispatching(conversationId)) {
      _cancelActiveDispatch(conversationId, ConversationStatus.paused);
      return;
    }
    _setConversationStatus(conversationId, ConversationStatus.paused);
  }

  void resumeConversation() {
    _setConversationStatus(selectedConversationId, ConversationStatus.idle);
  }

  void stopConversation() {
    stopConversationById(selectedConversationId);
  }

  void stopConversationById(String conversationId) {
    if (isConversationDispatching(conversationId)) {
      _cancelActiveDispatch(conversationId, ConversationStatus.stopped);
      return;
    }
    _setConversationStatus(conversationId, ConversationStatus.stopped);
  }

  Team addTeam({
    required String name,
    required List<String> memberIds,
    TeamCollaborationMode collaborationMode = TeamCollaborationMode.serial,
  }) {
    final secretary = state.members.firstWhere(
      (member) => member.isSecretary,
      orElse: () => throw StateError('缺少默认秘书成员'),
    );
    final normalizedMemberIds = _normalizeTeamMemberIds(
      secretaryMemberId: secretary.id,
      memberIds: memberIds,
    );
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final team = Team(
      id: 'team-$timestamp',
      name: _validateTeamName(name),
      memberIds: normalizedMemberIds,
      secretaryMemberId: secretary.id,
      collaborationMode: collaborationMode,
    );
    _commit(
      state.copyWith(
        teams: [...state.teams, team],
        conversations: [
          ...state.conversations,
          createTeamConversation(team),
        ],
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-$timestamp',
            action: 'team_added',
            detail: team.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
    return team;
  }

  void updateTeam({
    required String teamId,
    required String name,
    required List<String> memberIds,
    required TeamCollaborationMode collaborationMode,
  }) {
    final existing = _requireTeam(teamId);
    final updatedTeam = existing.copyWith(
      name: _validateTeamName(name),
      memberIds: _normalizeTeamMemberIds(
        secretaryMemberId: existing.secretaryMemberId,
        memberIds: memberIds,
      ),
      collaborationMode: collaborationMode,
    );
    final updatedMemberIds = updatedTeam.memberIds.toSet();
    final retainedConversations = state.conversations.where((conversation) {
      if (conversation.teamId != teamId || conversation.memberId == null) {
        return true;
      }
      return updatedMemberIds.contains(conversation.memberId);
    }).toList();

    _commit(
      state.copyWith(
        teams: state.teams
            .map((team) => team.id == teamId ? updatedTeam : team)
            .toList(),
        conversations: retainedConversations,
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'team_updated',
            detail: updatedTeam.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
    final validConversationIds =
        state.conversations.map((conversation) => conversation.id).toSet();
    if (!validConversationIds.contains(selectedConversationId)) {
      selectedConversationId = _teamConversationFor(teamId).id;
      activeTeamId = teamId;
      notifyListeners();
    }
  }

  void deleteTeam(String teamId) {
    final team = _requireTeam(teamId);
    if (state.teams.length <= 1) {
      throw StateError('至少保留一个团队');
    }
    final removedConversationIds = state.conversations
        .where((conversation) => conversation.teamId == teamId)
        .map((conversation) => conversation.id)
        .toSet();
    final remainingTeams =
        state.teams.where((item) => item.id != teamId).toList();
    final fallbackTeam = remainingTeams.first;

    _commit(
      state.copyWith(
        teams: remainingTeams,
        conversations: state.conversations
            .where((conversation) => conversation.teamId != teamId)
            .toList(),
        queuedTasks: state.queuedTasks
            .where(
                (task) => !removedConversationIds.contains(task.conversationId))
            .toList(),
        taskAssignments: state.taskAssignments
            .where((assignment) =>
                !removedConversationIds.contains(assignment.conversationId))
            .toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'team_deleted',
            detail: team.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
    if (activeTeamId == teamId ||
        removedConversationIds.contains(selectedConversationId)) {
      activeTeamId = fallbackTeam.id;
      selectedConversationId = _teamConversationFor(fallbackTeam.id).id;
      notifyListeners();
    }
  }

  void addModel(ModelProfile model) {
    _validateModel(model);
    _commit(state.copyWith(models: [...state.models, model]));
  }

  void updateModel(ModelProfile model) {
    _validateModel(model);
    _requireModel(model.id);
    _commit(
      state.copyWith(
        models: state.models
            .map((item) => item.id == model.id ? model : item)
            .toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'model_updated',
            detail: model.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  void deleteModel(String modelId) {
    final model = _requireModel(modelId);
    if (state.members.any((member) => member.modelId == modelId)) {
      throw StateError('模型正在被团队成员使用，不能删除');
    }
    _commit(
      state.copyWith(
        models: state.models.where((item) => item.id != modelId).toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'model_deleted',
            detail: model.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  void addRole(RoleTemplate role) {
    _validateRole(role);
    _commit(state.copyWith(roles: [...state.roles, role]));
  }

  void updateRole(RoleTemplate role) {
    _validateRole(role);
    _requireRole(role.id);
    _commit(
      state.copyWith(
        roles: state.roles
            .map((item) => item.id == role.id ? role : item)
            .toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'role_updated',
            detail: role.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  void deleteRole(String roleId) {
    final role = _requireRole(roleId);
    if (state.members.any((member) => member.roleId == roleId)) {
      throw StateError('角色正在被团队成员使用，不能删除');
    }
    _commit(
      state.copyWith(
        roles: state.roles.where((item) => item.id != roleId).toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'role_deleted',
            detail: role.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  void addMember(TeamMember member) {
    _validateMember(member);
    final updatedTeam = currentTeam.copyWith(
      memberIds: [...currentTeam.memberIds, member.id],
    );
    _commit(
      state.copyWith(
        members: [...state.members, member],
        teams: state.teams
            .map((team) => team.id == updatedTeam.id ? updatedTeam : team)
            .toList(),
      ),
    );
  }

  void updateMember(TeamMember member) {
    _validateMember(member);
    final existing = _requireMember(member.id);
    _commit(
      state.copyWith(
        members: state.members
            .map((item) => item.id == member.id
                ? member.copyWith(isSecretary: existing.isSecretary)
                : item)
            .toList(),
        conversations: state.conversations
            .map((conversation) => conversation.memberId == member.id
                ? Conversation(
                    id: conversation.id,
                    title: member.name,
                    teamId: conversation.teamId,
                    memberId: conversation.memberId,
                    messages: conversation.messages,
                    currentRound: conversation.currentRound,
                    status: conversation.status,
                  )
                : conversation)
            .toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'member_updated',
            detail: member.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  void deleteMember(String memberId) {
    final member = _requireMember(memberId);
    if (member.isSecretary || currentTeam.secretaryMemberId == memberId) {
      throw StateError('默认秘书不能删除');
    }
    _commit(
      state.copyWith(
        members: state.members.where((item) => item.id != memberId).toList(),
        conversations: state.conversations
            .where((conversation) => conversation.memberId != memberId)
            .toList(),
        teams: state.teams
            .map((team) => team.copyWith(
                  memberIds:
                      team.memberIds.where((id) => id != memberId).toList(),
                ))
            .toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'member_deleted',
            detail: member.name,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  void addWorkspacePath(String path) {
    final normalized = Directory(path).absolute.path;
    final workspace = ProjectWorkspace(
      id: 'workspace-${DateTime.now().microsecondsSinceEpoch}',
      name: pathBasename(normalized),
      path: normalized,
    );
    _commit(
      state.copyWith(
        workspaces: [...state.workspaces, workspace],
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'workspace_added',
            detail: normalized,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  Future<bool> pickAndAddWorkspace() async {
    final path = await fileDialogs.pickDirectory();
    if (path == null || path.trim().isEmpty) {
      return false;
    }
    addWorkspacePath(path);
    return true;
  }

  Future<bool> exportConfiguration({required bool includeSecrets}) async {
    final path = await fileDialogs.pickSaveFile(
      fileName: includeSecrets
          ? 'ai-team-config-with-secrets.json'
          : 'ai-team-config.json',
      allowedExtensions: ['json'],
    );
    if (path == null || path.trim().isEmpty) {
      return false;
    }
    await exportStore.exportTo(
      File(path),
      state,
      includeSecrets: includeSecrets,
    );
    return true;
  }

  Future<bool> importConfiguration() async {
    final path = await fileDialogs.pickOpenFile(allowedExtensions: ['json']);
    if (path == null || path.trim().isEmpty) {
      return false;
    }
    try {
      final decoded =
          jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
      _commit(ConfigExporter.importState(decoded));
      error = null;
      return true;
    } catch (exception) {
      error = '导入配置失败：$exception';
      notifyListeners();
      return false;
    }
  }

  Future<String> readWorkspaceFile({
    required String workspaceId,
    required String relativePath,
  }) async {
    return workspaceService.readFile(
      state,
      workspaceId: workspaceId,
      relativePath: relativePath,
    );
  }

  Future<List<String>> listWorkspaceFiles({
    required String workspaceId,
    int maxFiles = 500,
  }) async {
    return workspaceService.listFiles(
      state,
      workspaceId: workspaceId,
      maxFiles: maxFiles,
    );
  }

  Future<PatchProposal> proposeWorkspacePatch({
    required String workspaceId,
    required String relativePath,
    required String proposedContent,
    required String memberName,
  }) async {
    final proposal = await workspaceService.proposePatch(
      state,
      workspaceId: workspaceId,
      relativePath: relativePath,
      proposedContent: proposedContent,
      memberName: memberName,
      id: 'patch-${DateTime.now().microsecondsSinceEpoch}',
    );
    _commit(
      state.copyWith(
        patchProposals: [...state.patchProposals, proposal],
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'patch_proposed',
            detail: '${proposal.memberName}: ${proposal.filePath}',
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
    return proposal;
  }

  CommandRequest requestCommand({
    required String memberId,
    required String command,
    required String workingDirectory,
  }) {
    final member = state.members.firstWhere((item) => item.id == memberId);
    final role = state.roles.firstWhere((item) => item.id == member.roleId);
    final decision = role.commandPolicy.evaluate(
      command,
      workingDirectory: workingDirectory,
    );
    final request = CommandRequest.pending(
      id: 'command-${DateTime.now().microsecondsSinceEpoch}',
      memberName: member.name,
      command: command,
      workingDirectory: workingDirectory,
      decision: decision,
    );
    _commit(
      state.copyWith(
        commandRequests: [...state.commandRequests, request],
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: decision == CommandDecision.denied
                ? 'command_denied'
                : 'command_requested',
            detail: '${member.name}: $command',
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
    return request;
  }

  void updateCommandRequestStatus(
    String requestId,
    CommandRequestStatus status,
  ) {
    final existing =
        state.commandRequests.firstWhere((item) => item.id == requestId);
    if (existing.decision == CommandDecision.denied &&
        status != CommandRequestStatus.denied) {
      throw StateError('策略拒绝的命令不能被批准或执行');
    }
    if ((existing.status == CommandRequestStatus.executed ||
            existing.status == CommandRequestStatus.failed) &&
        status != existing.status) {
      throw StateError('已结束的命令请求不能修改状态');
    }
    _commit(
      state.copyWith(
        commandRequests: state.commandRequests
            .map((request) => request.id == requestId
                ? request.copyWith(status: status)
                : request)
            .toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: 'command_${status.name}',
            detail: requestId,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  Future<CommandRequest> executeCommandRequest(
    String requestId, {
    Future<ProcessResult> Function(String command, String workingDirectory)?
        runner,
  }) async {
    final request =
        state.commandRequests.firstWhere((item) => item.id == requestId);
    if (request.status != CommandRequestStatus.approved) {
      throw StateError('只有已批准的命令请求才能执行');
    }
    final runResult =
        await (runner == null ? commandService : CommandService(runner: runner))
            .run(request);
    final updated = request.copyWith(
      status: runResult.status,
      output: runResult.output,
    );
    _commit(
      state.copyWith(
        commandRequests: state.commandRequests
            .map((item) => item.id == requestId ? updated : item)
            .toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: runResult.status == CommandRequestStatus.executed
                ? 'command_executed'
                : 'command_failed',
            detail: '${request.command} exit=${runResult.exitCode}',
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
    return updated;
  }

  List<CommandRequest> commandRequestsForConversation(String conversationId) {
    return state.commandRequests
        .where((request) => request.conversationId == conversationId)
        .where((request) =>
            request.status == CommandRequestStatus.pending ||
            request.status == CommandRequestStatus.approved)
        .toList();
  }

  Future<void> approveExecuteCommandRequestAndContinue(
    String requestId, {
    Future<ProcessResult> Function(String command, String workingDirectory)?
        runner,
  }) async {
    if (isDispatching) {
      return;
    }
    isDispatching = true;
    error = null;
    final cancellation = ModelRequestCancellation();
    _activeCancellation = cancellation;
    _requestedCancellationStatus = null;
    _notifyListeners();
    try {
      var request =
          state.commandRequests.firstWhere((item) => item.id == requestId);
      if (request.status == CommandRequestStatus.pending) {
        updateCommandRequestStatus(requestId, CommandRequestStatus.approved);
        request =
            state.commandRequests.firstWhere((item) => item.id == requestId);
      }
      final commandRunner = runner ?? commandService.runner;
      final executed =
          await executeCommandRequest(request.id, runner: commandRunner);
      final conversationId = executed.conversationId;
      if (conversationId != null && conversationId.trim().isNotEmpty) {
        _activeDispatchConversationId = conversationId;
        _commit(
          await orchestrator.continueMemberChatAfterCommandResult(
            state,
            conversationId: conversationId,
            request: executed,
            cancellation: cancellation,
            onProgress: _commit,
            onStreamingDraft: _handleStreamingDraft,
          ),
        );
      }
    } catch (exception) {
      if (cancellation.isCancelled) {
        final conversationId = _activeDispatchConversationId;
        if (conversationId != null) {
          _commitCancelledDispatch(
            conversationId,
            _requestedCancellationStatus ?? ConversationStatus.stopped,
          );
        }
        return;
      }
      error = exception.toString();
      _notifyListeners();
    } finally {
      isDispatching = false;
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
      _activeDispatchConversationId = null;
      _requestedCancellationStatus = null;
      _notifyListeners();
    }
  }

  Future<void> applyPatch(PatchProposal proposal) async {
    final index =
        state.patchProposals.indexWhere((item) => item.id == proposal.id);
    if (index < 0) {
      return;
    }
    try {
      final applied = await PatchApplier().apply(proposal);
      final proposals = [...state.patchProposals];
      proposals[index] = applied;
      _commit(
        state.copyWith(
          patchProposals: proposals,
          auditLog: [
            ...state.auditLog,
            AuditEntry(
              id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
              action: 'patch_applied',
              detail: applied.filePath,
              createdAt: DateTime.now(),
            ),
          ],
        ),
      );
    } catch (exception) {
      error = exception.toString();
    }
    notifyListeners();
  }

  void rejectPatch(PatchProposal proposal) {
    final index =
        state.patchProposals.indexWhere((item) => item.id == proposal.id);
    if (index >= 0) {
      final proposals = [...state.patchProposals];
      proposals[index] = proposal.copyWith(status: PatchStatus.rejected);
      _commit(
        state.copyWith(
          patchProposals: proposals,
          auditLog: [
            ...state.auditLog,
            AuditEntry(
              id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
              action: 'patch_rejected',
              detail: proposal.filePath,
              createdAt: DateTime.now(),
            ),
          ],
        ),
      );
    }
  }

  void _setConversationStatus(
    String conversationId,
    ConversationStatus status,
  ) {
    final updated = _conversationById(conversationId).copyWith(status: status);
    _commit(
      state.copyWith(
        conversations: state.conversations
            .map((item) => item.id == updated.id ? updated : item)
            .toList(),
      ),
    );
  }

  Conversation _conversationById(String conversationId) {
    return state.conversations.firstWhere(
      (conversation) => conversation.id == conversationId,
      orElse: () => throw StateError('会话不存在: $conversationId'),
    );
  }

  Conversation? _conversationByIdOrNull(String conversationId) {
    for (final conversation in state.conversations) {
      if (conversation.id == conversationId) {
        return conversation;
      }
    }
    return null;
  }

  QueuedTask? _taskByIdOrNull(String taskId) {
    for (final task in state.queuedTasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  void _updateTaskStatus(String taskId, QueuedTaskStatus status) {
    _commit(
      state.copyWith(
        queuedTasks: state.queuedTasks
            .map(
              (task) => task.id == taskId
                  ? task.copyWith(
                      status: status,
                      updatedAt: DateTime.now(),
                    )
                  : task,
            )
            .toList(),
      ),
    );
  }

  void _appendMessage(String conversationId, ChatMessage message) {
    _commit(
      state.copyWith(
        conversations: state.conversations
            .map(
              (conversation) => conversation.id == conversationId
                  ? conversation.copyWith(
                      messages: [...conversation.messages, message],
                    )
                  : conversation,
            )
            .toList(),
      ),
    );
  }

  void _replaceMessageContent(String messageId, String content) {
    _commit(
      state.copyWith(
        conversations: state.conversations
            .map(
              (conversation) => conversation.copyWith(
                messages: conversation.messages
                    .map(
                      (message) => message.id == messageId
                          ? ChatMessage(
                              id: message.id,
                              authorName: message.authorName,
                              content: content,
                              thinkingContent: message.thinkingContent,
                              generationStatus: message.generationStatus,
                              generationDurationMs:
                                  message.generationDurationMs,
                              createdAt: message.createdAt,
                              memberId: message.memberId,
                              isUser: message.isUser,
                              taskIds: message.taskIds,
                            )
                          : message,
                    )
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
  }

  void _cancelActiveDispatch(
    String conversationId,
    ConversationStatus status,
  ) {
    _requestedCancellationStatus = status;
    _activeCancellation?.cancel();
    _setConversationStatus(conversationId, status);
  }

  void _commitCancelledDispatch(
    String conversationId,
    ConversationStatus status,
  ) {
    final action = status == ConversationStatus.paused
        ? 'team_task_paused'
        : 'team_task_stopped';
    final content = status == ConversationStatus.paused
        ? '任务已暂停，继续后可以重新发起下一轮协作。'
        : '任务已停止，本轮未完成的模型请求已取消。';
    final conversation = _conversationById(conversationId);
    final now = DateTime.now();
    final updated = conversation.copyWith(
      status: status,
      messages: [
        ..._stopStreamingMessages(conversation.messages, now),
        ChatMessage(
          id: 'msg-${now.microsecondsSinceEpoch}',
          authorName: '系统',
          content: content,
          createdAt: now,
        ),
      ],
    );
    final cancelledAssignments = _cancelOpenAssignments(
      state.taskAssignments,
      updated.id,
    );
    _commit(
      state.copyWith(
        conversations: state.conversations
            .map((item) => item.id == updated.id ? updated : item)
            .toList(),
        taskAssignments: _ensureCancelledAssignment(
          cancelledAssignments,
          updated,
        ),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: action,
            detail: teamForConversation(conversationId).id,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  List<ChatMessage> _stopStreamingMessages(
    List<ChatMessage> messages,
    DateTime stoppedAt,
  ) {
    return messages
        .map(
          (message) => message.generationStatus ==
                  ChatMessageGenerationStatus.streaming
              ? message.copyWith(
                  generationStatus: ChatMessageGenerationStatus.stopped,
                  generationDurationMs: message.generationDurationMs ??
                      stoppedAt.difference(message.createdAt).inMilliseconds,
                )
              : message,
        )
        .toList();
  }

  List<TaskAssignment> _cancelOpenAssignments(
    List<TaskAssignment> assignments,
    String conversationId,
  ) {
    return assignments
        .map(
          (assignment) => assignment.conversationId == conversationId &&
                  (assignment.status == TaskAssignmentStatus.pending ||
                      assignment.status == TaskAssignmentStatus.running)
              ? assignment.copyWith(
                  status: TaskAssignmentStatus.cancelled,
                  completedAt: DateTime.now(),
                )
              : assignment,
        )
        .toList();
  }

  List<TaskAssignment> _ensureCancelledAssignment(
    List<TaskAssignment> assignments,
    Conversation conversation,
  ) {
    final hasCancelled = assignments.any(
      (assignment) =>
          assignment.conversationId == conversation.id &&
          assignment.status == TaskAssignmentStatus.cancelled,
    );
    if (hasCancelled) {
      return assignments;
    }
    TeamMember member;
    if (conversation.memberId != null) {
      member = _requireMember(conversation.memberId!);
    } else {
      member = currentMembers.firstWhere(
        (item) => !item.isSecretary,
        orElse: () => currentMembers.first,
      );
    }
    final role = _requireRole(member.roleId);
    return [
      ...assignments,
      TaskAssignment(
        id: 'task-cancelled-${DateTime.now().microsecondsSinceEpoch}',
        conversationId: conversation.id,
        round: conversation.currentRound + 1,
        memberId: member.id,
        memberName: member.name,
        roleName: role.name,
        instruction: '请求已取消',
        status: TaskAssignmentStatus.cancelled,
        createdAt: DateTime.now(),
        completedAt: DateTime.now(),
      ),
    ];
  }

  void _commit(AppState nextState) {
    diagnostics?.globalCommitCount++;
    state = nextState;
    _syncConversationOrder();
    if (!state.conversations.any((item) => item.id == selectedConversationId)) {
      selectedConversationId = initialConversationId(state);
    }
    _persistState(state);
    _notifyListeners();
  }

  void _notifyListeners() {
    diagnostics?.globalNotifyCount++;
    notifyListeners();
  }

  Future<void> flushPersistence() => _persistenceQueue.idle;

  void _persistState(AppState snapshot) {
    final handler = onStateChanged;
    if (handler == null) {
      return;
    }
    diagnostics?.persistenceWriteCount++;
    _persistenceQueue.enqueue(
      snapshot: snapshot,
      handler: handler,
      onError: (message) => error = message,
    );
  }

  void _syncConversationOrder() {
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

  List<String> _conversationIdsInDisplayOrder({bool selectedFirst = false}) {
    _syncConversationOrder();
    final existingIdSet =
        state.conversations.map((conversation) => conversation.id).toSet();
    final ids = <String>{};
    if (selectedFirst && existingIdSet.contains(selectedConversationId)) {
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

  void _moveConversationToFront(String conversationId) {
    _syncConversationOrder();
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

  ModelProfile _requireModel(String modelId) {
    return state.models.firstWhere(
      (model) => model.id == modelId,
      orElse: () => throw StateError('模型不存在: $modelId'),
    );
  }

  Team _requireTeam(String teamId) {
    return state.teams.firstWhere(
      (team) => team.id == teamId,
      orElse: () => throw StateError('团队不存在: $teamId'),
    );
  }

  Conversation _teamConversationFor(String teamId) {
    return state.conversations.firstWhere(
      (conversation) =>
          conversation.teamId == teamId && conversation.memberId == null,
      orElse: () => throw StateError('团队会话不存在: $teamId'),
    );
  }

  RoleTemplate _requireRole(String roleId) {
    return state.roles.firstWhere(
      (role) => role.id == roleId,
      orElse: () => throw StateError('角色不存在: $roleId'),
    );
  }

  TeamMember _requireMember(String memberId) {
    return state.members.firstWhere(
      (member) => member.id == memberId,
      orElse: () => throw StateError('成员不存在: $memberId'),
    );
  }

  String _validateTeamName(String name) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('团队名称不能为空');
    }
    return trimmedName;
  }

  List<String> _normalizeTeamMemberIds({
    required String secretaryMemberId,
    required List<String> memberIds,
  }) {
    final normalizedMemberIds = <String>[
      secretaryMemberId,
      ...memberIds.where((id) => id != secretaryMemberId),
    ];
    for (final memberId in normalizedMemberIds) {
      _requireMember(memberId);
    }
    return LinkedHashSet<String>.from(normalizedMemberIds).toList();
  }

  void _validateModel(ModelProfile model) {
    if (model.name.trim().isEmpty) {
      throw ArgumentError('模型名称不能为空');
    }
    if (model.modelName.trim().isEmpty) {
      throw ArgumentError('模型标识不能为空');
    }
    if (model.apiKey.trim().isEmpty) {
      throw ArgumentError('API Key 不能为空');
    }
    final uri = Uri.tryParse(model.baseUrl.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw ArgumentError('Base URL 必须是有效的 http 或 https 地址');
    }
    if (model.temperature < 0 || model.temperature > 2) {
      throw ArgumentError('温度必须在 0 到 2 之间');
    }
    if (model.maxTokens <= 0) {
      throw ArgumentError('最大 Token 必须大于 0');
    }
    final reasoningEffort = model.reasoningEffort?.trim();
    if (reasoningEffort != null &&
        reasoningEffort.isNotEmpty &&
        !reasoningEffortValues.contains(reasoningEffort)) {
      throw ArgumentError('深度思考档位无效');
    }
  }

  void _validateRole(RoleTemplate role) {
    if (role.name.trim().isEmpty) {
      throw ArgumentError('角色名称不能为空');
    }
    if (role.identityPrompt.trim().isEmpty) {
      throw ArgumentError('角色身份提示词不能为空');
    }
    if (role.goalPrompt.trim().isEmpty) {
      throw ArgumentError('角色目标提示词不能为空');
    }
    if (role.constraintPrompt.trim().isEmpty) {
      throw ArgumentError('角色约束提示词不能为空');
    }
    if (role.outputFormatPrompt.trim().isEmpty) {
      throw ArgumentError('角色输出格式提示词不能为空');
    }
    if (role.commandPolicy.allowedCommands
        .every((command) => command.trim().isEmpty)) {
      throw ArgumentError('至少需要一个允许命令');
    }
  }

  void _validateMember(TeamMember member) {
    if (member.name.trim().isEmpty) {
      throw ArgumentError('成员名称不能为空');
    }
    _requireRole(member.roleId);
    _requireModel(member.modelId);
  }
}
