import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/commands/command_service.dart';
import '../core/domain.dart';
import '../core/file_dialogs.dart';
import '../core/local_store.dart';
import '../core/orchestrator.dart';
import '../core/storage_directories.dart';
import '../core/workspace/workspace_service.dart';
import '../core/workspace/image_service.dart';
import 'app_controller_helpers.dart';
import 'chat_streaming.dart';
import 'configuration_controller.dart';
import 'conversation_controller.dart';
import 'conversation_sessions.dart';
import 'conversation_title_generator.dart';
import 'dispatch_controller.dart';
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
    StorageDirectories? storageDirectories,
    this.storageDirectoryConfigStore,
  })  : state = initialState,
        exportStore = exportStore ?? JsonLocalStore.defaultStore(),
        storageDirectories = storageDirectories ??
            StorageDirectories(
              stateDirectory: (exportStore ?? JsonLocalStore.defaultStore())
                  .file
                  .parent
                  .path,
              auditDirectory:
                  '${(exportStore ?? JsonLocalStore.defaultStore()).file.parent.path}/audit',
              conversationDirectory:
                  '${(exportStore ?? JsonLocalStore.defaultStore()).file.parent.path}/conversations',
              cacheDirectory:
                  '${(exportStore ?? JsonLocalStore.defaultStore()).file.parent.path}/cache',
            ),
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
    _conversations = ConversationController(
      readState: () => state,
      commit: _commit,
      sessions: _conversationSessions,
      selectedConversationId: () => selectedConversationId,
      activeTeamId: () => activeTeamId,
      updateSelection: ({
        required selectedConversationId,
        required activeTeamId,
      }) {
        this.selectedConversationId = selectedConversationId;
        this.activeTeamId = activeTeamId;
      },
      notify: notifyListeners,
      clearDraftsForConversation: _clearStreamingDraftsForConversation,
    );
    _conversationTitleGenerator = ConversationTitleGenerator(
      readState: () => state,
      commit: _commit,
      gateway: orchestrator.gateway,
    );
    
    // 初始化图片服务
    imageService = ImageService(
      Directory(this.storageDirectories.stateDirectory),
    );
    
    _dispatch = DispatchController(
      readState: () => state,
      commit: _commit,
      taskQueue: _taskQueue,
      workspaceCommands: _workspaceCommands,
      titleGenerator: _conversationTitleGenerator,
      orchestrator: orchestrator,
      commandService: this.commandService,
      imageService: imageService,
      selectedConversationId: () => selectedConversationId,
      notify: _notifyListeners,
      onStreamingDraft: _handleStreamingDraft,
      clearStreamingDraftsForConversation: _clearStreamingDraftsForConversation,
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
  StorageDirectories storageDirectories;
  final StorageDirectoryConfigStore? storageDirectoryConfigStore;
  final StatePersistenceQueue _persistenceQueue = StatePersistenceQueue();
  late final StreamingDraftRegistry _streamingDraftRegistry;
  late final WorkspaceCommandController _workspaceCommands;
  late final ConfigurationController _configuration;
  late final TaskQueueController _taskQueue;
  late final ConversationController _conversations;
  late final ConversationTitleGenerator _conversationTitleGenerator;
  late final DispatchController _dispatch;
  late final ImageService imageService;

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
  bool get isDispatching => _dispatch.isDispatching;
  String? get error => _dispatch.error;
  set error(String? value) {
    _dispatch.error = value;
  }

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
    return _dispatch.currentRunningTask;
  }

  Conversation get currentConversation => _conversations.currentConversation(
        currentTeam: currentTeam,
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
    final conversation = conversationByIdOrThrow(state, conversationId);
    return requireTeam(state, conversation.teamId);
  }

  bool modelSupportsImagesForConversation(String conversationId) {
    final conversation = conversationByIdOrThrow(state, conversationId);
    if (conversation.memberId != null) {
      final member = state.members.firstWhere((item) => item.id == conversation.memberId);
      final model = state.models.firstWhere((item) => item.id == member.modelId);
      return model.supportsImages;
    }
    final team = state.teams.firstWhere((item) => item.id == conversation.teamId);
    final secretary = state.members.firstWhere((item) => item.id == team.secretaryMemberId);
    final model = state.models.firstWhere((item) => item.id == secretary.modelId);
    return model.supportsImages;
  }

  bool isConversationDispatching(String conversationId) {
    return _dispatch.isConversationDispatching(conversationId);
  }

  Conversation get teamConversation => _conversations.teamConversation(
        currentTeam: currentTeam,
      );

  List<Conversation> get visibleConversations {
    return _conversations.visibleConversations;
  }

  List<Conversation> get openConversationPanes {
    return _conversations.openConversationPanes;
  }

  double get conversationListScrollOffset =>
      _conversations.conversationListScrollOffset;

  List<TeamMember> get currentMembers => state.members
      .where((member) => currentTeam.memberIds.contains(member.id))
      .toList();

  void recordConversationListScrollOffset(double offset) {
    _conversations.recordConversationListScrollOffset(offset);
  }

  Conversation conversationForMember(String memberId) {
    return _conversations.conversationForMember(currentTeam, memberId);
  }

  void selectConversation(String conversationId) {
    _conversations.selectConversation(conversationId);
  }

  void startTeamChat(String teamId) {
    _conversations.startTeamChat(teamId);
  }

  void startMemberChat(String memberId) {
    _conversations.startMemberChat(currentTeam, memberId);
  }

  Conversation createConversationLikeCurrent() {
    return _conversations.createConversationLikeCurrent();
  }

  void deleteConversationSession(String conversationId) {
    _conversations.deleteConversationSession(conversationId);
  }

  bool isConversationPinned(String conversationId) {
    return _conversations.isConversationPinned(conversationId);
  }

  List<Conversation> get conversationHistory {
    return _conversations.conversationHistory;
  }

  void togglePinnedConversation(String conversationId) {
    _conversations.togglePinnedConversation(conversationId);
  }

  void closeConversation(String conversationId) {
    _conversations.closeConversation(conversationId);
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
    await _dispatch.runNextQueuedTask();
  }

  void pauseTask(String taskId) {
    _dispatch.pauseTask(taskId);
  }

  Future<void> resumeTask(String taskId) async {
    await _dispatch.resumeTask(taskId);
  }

  Future<void> dispatch(String text) async {
    await _dispatch.dispatch(text);
  }

  Future<void> dispatchConversation(
    String conversationId,
    String text, {
    List<File>? images,
  }) async {
    await _dispatch.dispatchConversation(
      conversationId,
      text,
      images: images,
    );
  }

  void pauseConversation() {
    _dispatch.pauseConversation();
  }

  void pauseConversationById(String conversationId) {
    _dispatch.pauseConversationById(conversationId);
  }

  void resumeConversation() {
    _dispatch.resumeConversation();
  }

  void stopConversation() {
    _dispatch.stopConversation();
  }

  void stopConversationById(String conversationId) {
    _dispatch.stopConversationById(conversationId);
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
    await _dispatch.approveExecuteCommandRequestAndContinue(
      requestId,
      runner: runner,
    );
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

  Future<void> updateStorageDirectories(
    StorageDirectories directories, {
    required bool migrate,
  }) async {
    final previous = storageDirectories;
    if (migrate) {
      await storageDirectoryConfigStore?.copyExistingData(
        from: previous,
        to: directories,
      );
    }
    await storageDirectoryConfigStore?.save(directories);
    storageDirectories = directories;
    _notifyListeners();
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
    _conversations.syncConversationOrder();
  }
}
