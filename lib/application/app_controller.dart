import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/commands/command_service.dart';
import '../core/domain.dart';
import '../core/file_dialogs.dart';
import '../core/local_store.dart';
import '../core/model_gateway.dart';
import '../core/orchestrator.dart';
import '../core/workspace/workspace_service.dart';
import 'app_controller_helpers.dart';
import 'chat_streaming.dart';
import 'configuration_controller.dart';
import 'conversation_sessions.dart';
import 'state_persistence_queue.dart';
import 'state_lookup.dart';
import 'streaming_draft_registry.dart';
import 'task_queue_controller.dart';
import 'workspace_command_controller.dart';

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
    _streamingDraftRegistry = StreamingDraftRegistry(diagnostics: diagnostics);
    _workspaceCommands = WorkspaceCommandController(
      readState: () => state,
      commit: _commit,
      workspaceService: workspaceService,
      commandService: this.commandService,
    );
    _configuration = ConfigurationController(
      readState: () => state,
      commit: _commit,
      currentTeam: () => currentTeam,
      activeTeamId: () => activeTeamId,
      selectedConversationId: () => selectedConversationId,
      updateSelection: ({
        required activeTeamId,
        required selectedConversationId,
      }) {
        this.activeTeamId = activeTeamId;
        this.selectedConversationId = selectedConversationId;
      },
      notify: notifyListeners,
    );
    _taskQueue = TaskQueueController(
      readState: () => state,
      commit: _commit,
      gateway: orchestrator.gateway,
    );
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
  final ConversationSessionStore _conversationSessions =
      ConversationSessionStore();
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
  late final StreamingDraftRegistry _streamingDraftRegistry;
  late final WorkspaceCommandController _workspaceCommands;
  late final ConfigurationController _configuration;
  late final TaskQueueController _taskQueue;

  Set<String> get hiddenConversationIds =>
      _conversationSessions.hiddenConversationIds;
  Set<String> get openedConversationIds =>
      _conversationSessions.openedConversationIds;
  List<String> get conversationOrderIds =>
      _conversationSessions.conversationOrderIds;
  Set<String> get pinnedConversationIds =>
      _conversationSessions.pinnedConversationIds;
  List<String> get pinnedConversationOrderIds =>
      _conversationSessions.pinnedConversationOrderIds;

  @override
  void dispose() {
    _streamingDraftRegistry.dispose();
    super.dispose();
  }

  ValueListenable<ChatStreamingDraft?> streamingDraftListenable(
    String messageId,
  ) {
    return _streamingDraftRegistry.listenable(messageId);
  }

  void _handleStreamingDraft({
    required String conversationId,
    required ChatMessage message,
  }) {
    _streamingDraftRegistry.update(
      conversationId: conversationId,
      message: message,
    );
  }

  void _clearStreamingDraftsForConversation(String conversationId) {
    _streamingDraftRegistry.clearConversation(conversationId);
  }

  Team get currentTeam {
    final activeId = activeTeamId;
    if (activeId != null) {
      return requireTeam(state, activeId);
    }
    final conversation = state.conversations.firstWhere(
      (item) => item.id == selectedConversationId,
      orElse: () => state.conversations.first,
    );
    return requireTeam(state, conversation.teamId);
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

  List<QueuedTask> get tasksForCurrentConversation =>
      _taskQueue.tasksForConversation(currentConversation.id);

  List<QueuedTask> tasksForConversation(String conversationId) =>
      _taskQueue.tasksForConversation(conversationId);

  List<QueuedTask> get pendingTasksForCurrentConversation {
    return _taskQueue.pendingTasksForConversation(currentConversation.id);
  }

  QueuedTask? get currentRunningTask {
    final id = _runningTaskId;
    if (id == null) {
      return null;
    }
    return _taskQueue.taskByIdOrNull(id);
  }

  Conversation get currentConversation => state.conversations.firstWhere(
        (item) => item.id == selectedConversationId,
        orElse: () => state.conversations.firstWhere(
          (item) => item.teamId == currentTeam.id && item.memberId == null,
        ),
      );

  Conversation conversationById(String conversationId) =>
      conversationByIdOrThrow(state, conversationId);

  List<TeamMember> membersForConversation(String conversationId) {
    final conversation = conversationByIdOrThrow(state, conversationId);
    final team = requireTeam(state, conversation.teamId);
    return state.members
        .where((member) => team.memberIds.contains(member.id))
        .toList();
  }

  Team teamForConversation(String conversationId) {
    return requireTeam(state, conversationByIdOrThrow(state, conversationId).teamId);
  }

  bool isConversationDispatching(String conversationId) {
    return isDispatching && _activeDispatchConversationId == conversationId;
  }

  Conversation get teamConversation => _activeConversationForObject(
        requireTeamConversation(state, currentTeam.id),
      );

  List<Conversation> get visibleConversations {
    return _conversationSessions.visibleConversations(
      state,
      selectedConversationId: selectedConversationId,
    );
  }

  List<Conversation> get openConversationPanes {
    return _conversationSessions.openConversationPanes(
      state,
      selectedConversationId: selectedConversationId,
    );
  }

  List<TeamMember> get currentMembers => state.members
      .where((member) => currentTeam.memberIds.contains(member.id))
      .toList();

  double get conversationListScrollOffset =>
      _conversationSessions.conversationListScrollOffset;

  void recordConversationListScrollOffset(double offset) {
    _conversationSessions.recordConversationListScrollOffset(offset);
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
    final team = requireTeam(state, teamId);
    final conversation = _activeConversationForObject(
      requireTeamConversation(state, team.id),
    );
    _activateConversation(conversation.id);
    notifyListeners();
  }

  void startMemberChat(String memberId) {
    final member = requireMember(state, memberId);
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
    final source = conversationByIdOrThrow(state, selectedConversationId);
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
    final conversation = conversationByIdOrNull(state, conversationId);
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
      _conversationSessions.showConversation(fallbackConversation);
    }

    _clearStreamingDraftsForConversation(conversationId);
    _conversationSessions.removeConversation(conversationId);

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
    return _conversationSessions.isPinned(conversationId);
  }

  List<Conversation> get conversationHistory {
    return _conversationSessions.conversationHistory(
      state,
      selectedConversationId: selectedConversationId,
    );
  }

  void _activateConversation(String conversationId) {
    final conversation = _conversationSessions.activate(state, conversationId);
    selectedConversationId = conversation.id;
    activeTeamId = conversation.teamId;
  }

  Conversation _activeConversationForObject(Conversation source) {
    return _conversationSessions.activeConversationForObject(
      state,
      source,
      selectedConversationId: selectedConversationId,
    );
  }

  Conversation? _emptyConversationForObject(Conversation source) {
    return _conversationSessions.emptyConversationForObject(
      state,
      source,
      selectedConversationId: selectedConversationId,
    );
  }

  Conversation? _fallbackConversationAfterDeleting(Conversation deleted) {
    return _conversationSessions.fallbackConversationAfterDeleting(
      state,
      deleted,
    );
  }

  Conversation _createEmptyConversationForObject(Conversation source) {
    return _conversationSessions.createEmptyConversationForObject(source);
  }

  void togglePinnedConversation(String conversationId) {
    _conversationSessions.togglePinned(state, conversationId);
    notifyListeners();
  }

  void closeConversation(String conversationId) {
    final conversation = conversationByIdOrNull(state, conversationId);
    if (conversation == null) {
      return;
    }
    if (_conversationSessions.closeWouldHideLastVisibleObject(
      state,
      conversation,
      selectedConversationId: selectedConversationId,
    )) {
      return;
    }
    _conversationSessions.closeConversationObject(state, conversation);
    final selectedConversation =
        conversationByIdOrNull(state, selectedConversationId);
    if (selectedConversation == null ||
        _conversationSessions.isHidden(selectedConversationId)) {
      final nextConversation = visibleConversations.first;
      _activateConversation(nextConversation.id);
    }
    notifyListeners();
  }

  Future<void> enqueueCurrentConversationTask(
    String text, {
    int priority = 0,
  }) async {
    await _taskQueue.enqueueConversationTask(
      currentConversation.id,
      text,
      priority: priority,
    );
  }

  void updateTaskPriority(String taskId, int priority) {
    _taskQueue.updateTaskPriority(taskId, priority);
  }

  void appendTaskNote(String taskId, String note) {
    _taskQueue.appendTaskNote(taskId, note);
  }

  void deleteTask(String taskId) {
    _taskQueue.deleteTask(taskId);
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
    _taskQueue.updateTaskStatus(next.id, QueuedTaskStatus.running);
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
        _taskQueue.updateTaskStatus(next.id, QueuedTaskStatus.completed);
      }
    } on ModelGatewayException catch (exception) {
      if (cancellation.isCancelled) {
        _taskQueue.updateTaskStatus(next.id, QueuedTaskStatus.paused);
      } else {
        error = exception.toString();
        _taskQueue.updateTaskStatus(next.id, QueuedTaskStatus.failed);
      }
    } catch (exception) {
      if (cancellation.isCancelled) {
        _taskQueue.updateTaskStatus(next.id, QueuedTaskStatus.paused);
      } else {
        error = exception.toString();
        _taskQueue.updateTaskStatus(next.id, QueuedTaskStatus.failed);
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
    _taskQueue.updateTaskStatus(taskId, QueuedTaskStatus.paused);
  }

  Future<void> resumeTask(String taskId) async {
    _taskQueue.updateTaskStatus(taskId, QueuedTaskStatus.pending);
    await runNextQueuedTask();
  }

  bool _canDispatchConversation(String conversationId) {
    final status = conversationByIdOrThrow(state, conversationId).status;
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
      final conversation = conversationByIdOrThrow(state, conversationId);
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
      final conversation = conversationByIdOrThrow(state, conversationId);
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
    final conversation = conversationByIdOrThrow(state, conversationId);
    final titleMember = _titleMemberForConversation(conversation);
    final role = requireRole(state, titleMember.roleId);
    final model = requireModel(state, titleMember.modelId);
    try {
      final generated = await orchestrator.gateway.complete(
        model: model,
        systemPrompt: role.renderSystemPrompt(
          memberName: titleMember.name,
          teamName: requireTeam(state, conversation.teamId).name,
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
        conversation: conversationByIdOrThrow(state, conversationId),
        firstUserMessage: firstUserMessage,
      );
      if (normalizedTitle == null) {
        return;
      }
      final latestConversation = conversationByIdOrThrow(state, conversationId);
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
      return requireMember(state, conversation.memberId!);
    }
    final team = requireTeam(state, conversation.teamId);
    return requireMember(state, team.secretaryMemberId);
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
    return _configuration.addTeam(
      name: name,
      memberIds: memberIds,
      collaborationMode: collaborationMode,
    );
  }

  void updateTeam({
    required String teamId,
    required String name,
    required List<String> memberIds,
    required TeamCollaborationMode collaborationMode,
  }) {
    _configuration.updateTeam(
      teamId: teamId,
      name: name,
      memberIds: memberIds,
      collaborationMode: collaborationMode,
    );
  }

  void deleteTeam(String teamId) {
    _configuration.deleteTeam(teamId);
  }

  void addModel(ModelProfile model) {
    _configuration.addModel(model);
  }

  void updateModel(ModelProfile model) {
    _configuration.updateModel(model);
  }

  void deleteModel(String modelId) {
    _configuration.deleteModel(modelId);
  }

  void addRole(RoleTemplate role) {
    _configuration.addRole(role);
  }

  void updateRole(RoleTemplate role) {
    _configuration.updateRole(role);
  }

  void deleteRole(String roleId) {
    _configuration.deleteRole(roleId);
  }

  void addMember(TeamMember member) {
    _configuration.addMember(member);
  }

  void updateMember(TeamMember member) {
    _configuration.updateMember(member);
  }

  void deleteMember(String memberId) {
    _configuration.deleteMember(memberId);
  }

  void addWorkspacePath(String path) {
    _workspaceCommands.addWorkspacePath(path);
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
    return _workspaceCommands.readWorkspaceFile(
      workspaceId: workspaceId,
      relativePath: relativePath,
    );
  }

  Future<List<String>> listWorkspaceFiles({
    required String workspaceId,
    int maxFiles = 500,
  }) async {
    return _workspaceCommands.listWorkspaceFiles(
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
    return _workspaceCommands.proposeWorkspacePatch(
      workspaceId: workspaceId,
      relativePath: relativePath,
      proposedContent: proposedContent,
      memberName: memberName,
    );
  }

  CommandRequest requestCommand({
    required String memberId,
    required String command,
    required String workingDirectory,
  }) {
    return _workspaceCommands.requestCommand(
      memberId: memberId,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  void updateCommandRequestStatus(
    String requestId,
    CommandRequestStatus status,
  ) {
    _workspaceCommands.updateCommandRequestStatus(requestId, status);
  }

  Future<CommandRequest> executeCommandRequest(
    String requestId, {
    Future<ProcessResult> Function(String command, String workingDirectory)?
        runner,
  }) async {
    return _workspaceCommands.executeCommandRequest(
      requestId,
      runner: runner,
    );
  }

  List<CommandRequest> commandRequestsForConversation(String conversationId) {
    return _workspaceCommands.commandRequestsForConversation(conversationId);
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
    if (!state.patchProposals.any((item) => item.id == proposal.id)) {
      return;
    }
    final applyError = await _workspaceCommands.applyPatch(proposal);
    if (applyError != null) {
      error = applyError;
    }
    notifyListeners();
  }

  void rejectPatch(PatchProposal proposal) {
    _workspaceCommands.rejectPatch(proposal);
  }

  void _setConversationStatus(
    String conversationId,
    ConversationStatus status,
  ) {
    final updated = conversationByIdOrThrow(state, conversationId).copyWith(status: status);
    _commit(
      state.copyWith(
        conversations: state.conversations
            .map((item) => item.id == updated.id ? updated : item)
            .toList(),
      ),
    );
  }

  Conversation conversationByIdOrThrow(state, String conversationId) {
    return state.conversations.firstWhere(
      (conversation) => conversation.id == conversationId,
      orElse: () => throw StateError('会话不存在: $conversationId'),
    );
  }

  Conversation? conversationByIdOrNull(state, String conversationId) {
    for (final conversation in state.conversations) {
      if (conversation.id == conversationId) {
        return conversation;
      }
    }
    return null;
  }

  QueuedTask? queuedTaskByIdOrNull(state, String taskId) {
    for (final task in state.queuedTasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
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
    final conversation = conversationByIdOrThrow(state, conversationId);
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
      member = requireMember(state, conversation.memberId!);
    } else {
      member = currentMembers.firstWhere(
        (item) => !item.isSecretary,
        orElse: () => currentMembers.first,
      );
    }
    final role = requireRole(state, member.roleId);
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
    _conversationSessions.sync(state);
  }
}
