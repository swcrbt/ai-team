import 'dart:convert';
import 'dart:collection';
import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/domain.dart';
import 'core/file_dialogs.dart';
import 'core/local_store.dart';
import 'core/model_gateway.dart';
import 'core/orchestrator.dart';
import 'core/patching.dart';

typedef StateChanged = FutureOr<void> Function(AppState state);

const _reasoningEffortOffValue = '';
const _reasoningEffortValues = [
  'none',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh'
];
const _reasoningEffortLabels = <String, String>{
  _reasoningEffortOffValue: '关闭',
  'none': 'none',
  'minimal': 'minimal',
  'low': 'low',
  'medium': 'medium',
  'high': 'high',
  'xhigh': 'xhigh',
};

class AiTeamApp extends StatelessWidget {
  const AiTeamApp({
    super.key,
    required this.initialState,
    required this.modelGateway,
    this.onStateChanged,
    this.fileDialogs = const SystemFileDialogService(),
  });

  final AppState initialState;
  final ModelGateway modelGateway;
  final StateChanged? onStateChanged;
  final FileDialogService fileDialogs;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Team',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
      ),
      home: AiTeamHome(
        initialState: initialState,
        modelGateway: modelGateway,
        onStateChanged: onStateChanged,
        fileDialogs: fileDialogs,
      ),
    );
  }
}

class AiTeamHome extends StatefulWidget {
  const AiTeamHome({
    super.key,
    required this.initialState,
    required this.modelGateway,
    this.onStateChanged,
    this.fileDialogs = const SystemFileDialogService(),
  });

  final AppState initialState;
  final ModelGateway modelGateway;
  final StateChanged? onStateChanged;
  final FileDialogService fileDialogs;

  @override
  State<AiTeamHome> createState() => _AiTeamHomeState();
}

class _AiTeamHomeState extends State<AiTeamHome> {
  late AppController controller;
  _MainView mainView = _MainView.chat;

  @override
  void initState() {
    super.initState();
    controller = AppController(
      widget.initialState,
      TeamOrchestrator(widget.modelGateway),
      onStateChanged: widget.onStateChanged,
      fileDialogs: widget.fileDialogs,
    );
  }

  @override
  void dispose() {
    unawaited(controller.flushPersistence());
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final conversationListWidth =
                    (constraints.maxWidth * 0.28).clamp(300.0, 360.0);
                return Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: _AppSidebar(
                        selectedView: mainView,
                        onChat: () => setState(() => mainView = _MainView.chat),
                        onTeam: () {
                          setState(() => mainView = _MainView.teams);
                        },
                        onModels: () =>
                            setState(() => mainView = _MainView.models),
                        onRoles: () =>
                            setState(() => mainView = _MainView.roles),
                        onMembers: () =>
                            setState(() => mainView = _MainView.members),
                        onHistory: () =>
                            setState(() => mainView = _MainView.history),
                        onAudit: () =>
                            setState(() => mainView = _MainView.audit),
                        onProject: () =>
                            setState(() => mainView = _MainView.project),
                        onSettings: () =>
                            setState(() => mainView = _MainView.settings),
                      ),
                    ),
                    if (mainView == _MainView.teams)
                      Expanded(
                        child: _TeamManagementPage(
                          controller: controller,
                          onStartChat: () =>
                              setState(() => mainView = _MainView.chat),
                        ),
                      )
                    else if (mainView == _MainView.models)
                      Expanded(
                        child: _ModelManagementPage(controller: controller),
                      )
                    else if (mainView == _MainView.roles)
                      Expanded(
                        child: _RoleManagementPage(controller: controller),
                      )
                    else if (mainView == _MainView.members)
                      Expanded(
                        child: _MemberManagementPage(
                          controller: controller,
                          onStartChat: () =>
                              setState(() => mainView = _MainView.chat),
                        ),
                      )
                    else if (mainView == _MainView.history)
                      Expanded(
                        child: _HistoryPage(controller: controller),
                      )
                    else if (mainView == _MainView.audit)
                      Expanded(
                        child: _AuditLogPage(controller: controller),
                      )
                    else if (mainView == _MainView.project)
                      Expanded(
                        child: _ProjectPage(
                          controller: controller,
                        ),
                      )
                    else if (mainView == _MainView.settings)
                      Expanded(
                        child: _SettingsPage(
                          controller: controller,
                        ),
                      )
                    else ...[
                      SizedBox(
                        width: conversationListWidth,
                        child: _ConversationList(
                          controller: controller,
                          selectedView: mainView,
                          onSelectConversation: (conversationId) {
                            controller.selectConversation(conversationId);
                            setState(() => mainView = _MainView.chat);
                          },
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: _ChatPane(controller: controller)),
                    ],
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

enum _MainView {
  chat,
  teams,
  models,
  roles,
  members,
  history,
  audit,
  project,
  settings,
}

class AppController extends ChangeNotifier {
  AppController(
    AppState initialState,
    this.orchestrator, {
    this.onStateChanged,
    this.fileDialogs = const SystemFileDialogService(),
    JsonLocalStore? exportStore,
  })  : state = initialState,
        exportStore = exportStore ?? JsonLocalStore.defaultStore(),
        selectedConversationId = _initialConversationId(initialState) {
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
  final TeamOrchestrator orchestrator;
  final StateChanged? onStateChanged;
  final FileDialogService fileDialogs;
  final JsonLocalStore exportStore;
  bool isDispatching = false;
  String? error;
  String? _runningTaskId;
  ModelRequestCancellation? _activeCancellation;
  ConversationStatus? _requestedCancellationStatus;
  Future<void> _persistenceQueue = Future<void>.value();

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

  List<QueuedTask> get tasksForCurrentConversation => state.queuedTasks
      .where((task) => task.conversationId == currentConversation.id)
      .toList();

  List<QueuedTask> get pendingTasksForCurrentConversation {
    final tasks = tasksForCurrentConversation
        .where((task) => task.status == QueuedTaskStatus.pending)
        .toList();
    tasks.sort(_queuedTaskSort);
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

  Conversation get teamConversation => state.conversations.firstWhere(
        (item) => item.teamId == currentTeam.id && item.memberId == null,
      );

  List<Conversation> get visibleConversations {
    _syncConversationOrder();
    final conversationsById = {
      for (final conversation in state.conversations)
        conversation.id: conversation,
    };
    final visibleIds = [
      ...pinnedConversationOrderIds.where(
        (id) {
          final conversation = conversationsById[id];
          return pinnedConversationIds.contains(id) &&
              conversation != null &&
              _shouldShowConversation(conversation);
        },
      ),
      ...conversationOrderIds.where(
        (id) {
          final conversation = conversationsById[id];
          return !pinnedConversationIds.contains(id) &&
              conversation != null &&
              _shouldShowConversation(conversation);
        },
      ),
    ];
    return visibleIds.map((id) => conversationsById[id]!).toList();
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
    return !_isGeneratedWelcomeOnlyMemberConversation(conversation);
  }

  List<TeamMember> get currentMembers => state.members
      .where((member) => currentTeam.memberIds.contains(member.id))
      .toList();

  Conversation conversationForMember(String memberId) {
    return state.conversations.firstWhere(
      (item) => item.teamId == currentTeam.id && item.memberId == memberId,
      orElse: () => throw StateError('成员会话不存在: $memberId'),
    );
  }

  void selectConversation(String conversationId) {
    selectedConversationId = conversationId;
    hiddenConversationIds.remove(conversationId);
    final conversation = state.conversations.firstWhere(
      (item) => item.id == conversationId,
    );
    activeTeamId = conversation.teamId;
    notifyListeners();
  }

  void startTeamChat(String teamId) {
    final team = _requireTeam(teamId);
    activeTeamId = team.id;
    selectedConversationId = _teamConversationFor(team.id).id;
    hiddenConversationIds.remove(selectedConversationId);
    _moveConversationToFront(selectedConversationId);
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
      conversation = _createMemberConversation(currentTeam.id, member);
      _commit(
        state.copyWith(
          conversations: [
            ...state.conversations,
            conversation,
          ],
        ),
      );
    }
    selectedConversationId = conversation.id;
    openedConversationIds.add(conversation.id);
    hiddenConversationIds.remove(conversation.id);
    activeTeamId = conversation.teamId;
    _moveConversationToFront(conversation.id);
    notifyListeners();
  }

  bool isConversationPinned(String conversationId) {
    return pinnedConversationIds.contains(conversationId);
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
    if (!state.conversations
        .any((conversation) => conversation.id == conversationId)) {
      return;
    }
    final visibleConversationIds = state.conversations
        .where(
            (conversation) => !hiddenConversationIds.contains(conversation.id))
        .map((conversation) => conversation.id)
        .toList();
    if (visibleConversationIds.length <= 1 &&
        visibleConversationIds.contains(conversationId)) {
      return;
    }
    hiddenConversationIds.add(conversationId);
    if (selectedConversationId == conversationId ||
        hiddenConversationIds.contains(selectedConversationId)) {
      final nextConversation = state.conversations.firstWhere(
        (conversation) => !hiddenConversationIds.contains(conversation.id),
        orElse: () => state.conversations.first,
      );
      selectedConversationId = nextConversation.id;
      activeTeamId = nextConversation.teamId;
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
    final next = _firstQueuedTaskOrNull(pendingTasksForCurrentConversation);
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

  bool _canDispatchCurrentConversation() {
    final status = currentConversation.status;
    if (status == ConversationStatus.paused) {
      error = '当前会话已暂停，请先点击继续。';
      return false;
    }
    return true;
  }

  Future<void> dispatch(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isDispatching) {
      return;
    }
    if (!_canDispatchCurrentConversation()) {
      notifyListeners();
      return;
    }
    isDispatching = true;
    error = null;
    final cancellation = ModelRequestCancellation();
    _activeCancellation = cancellation;
    _requestedCancellationStatus = null;
    notifyListeners();
    try {
      final conversation = currentConversation;
      if (conversation.memberId == null) {
        _commit(
          await orchestrator.dispatchTeamTask(
            state,
            teamId: conversation.teamId,
            userText: trimmed,
            cancellation: cancellation,
            onProgress: _commit,
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
          ),
        );
      }
    } catch (exception) {
      if (cancellation.isCancelled) {
        _commitCancelledDispatch(
          _requestedCancellationStatus ?? ConversationStatus.stopped,
        );
        return;
      }
      error = exception.toString();
      final failed = currentConversation.copyWith(
        status: ConversationStatus.failed,
        messages: [
          ...currentConversation.messages,
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
      _requestedCancellationStatus = null;
      notifyListeners();
    }
  }

  void pauseConversation() {
    if (isDispatching) {
      _cancelActiveDispatch(ConversationStatus.paused);
      return;
    }
    _setConversationStatus(ConversationStatus.paused);
  }

  void resumeConversation() {
    _setConversationStatus(ConversationStatus.idle);
  }

  void stopConversation() {
    if (isDispatching) {
      _cancelActiveDispatch(ConversationStatus.stopped);
      return;
    }
    _setConversationStatus(ConversationStatus.stopped);
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
          _createTeamConversation(team),
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
      name: _basename(normalized),
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
    final file = _workspaceFile(workspaceId, relativePath);
    if (!await file.exists()) {
      throw StateError('文件不存在: $relativePath');
    }
    return file.readAsString();
  }

  Future<List<String>> listWorkspaceFiles({
    required String workspaceId,
    int maxFiles = 500,
  }) async {
    final root = _workspaceRoot(workspaceId);
    if (!await root.exists()) {
      throw StateError('工作区不存在: ${root.path}');
    }
    final rootPath = root.absolute.path;
    final files = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (files.length >= maxFiles) {
        break;
      }
      final path = entity.absolute.path;
      final relative = _relativeWorkspacePath(rootPath, path);
      if (_isHiddenWorkspacePath(relative)) {
        continue;
      }
      if (entity is File) {
        files.add(relative);
      }
    }
    files.sort();
    return files;
  }

  Future<PatchProposal> proposeWorkspacePatch({
    required String workspaceId,
    required String relativePath,
    required String proposedContent,
    required String memberName,
  }) async {
    final file = _workspaceFile(workspaceId, relativePath);
    final originalContent =
        await file.exists() ? await file.readAsString() : '';
    final proposal = PatchProposal.fromFileChange(
      id: 'patch-${DateTime.now().microsecondsSinceEpoch}',
      filePath: file.path,
      originalContent: originalContent,
      proposedContent: proposedContent,
      memberName: memberName,
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
    final run = runner ?? _runShellCommand;
    final result = await run(request.command, request.workingDirectory);
    final output = [
      if (result.stdout.toString().trim().isNotEmpty)
        result.stdout.toString().trim(),
      if (result.stderr.toString().trim().isNotEmpty)
        result.stderr.toString().trim(),
    ].join('\n');
    final status = result.exitCode == 0
        ? CommandRequestStatus.executed
        : CommandRequestStatus.failed;
    final updated = request.copyWith(status: status, output: output);
    _commit(
      state.copyWith(
        commandRequests: state.commandRequests
            .map((item) => item.id == requestId ? updated : item)
            .toList(),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: status == CommandRequestStatus.executed
                ? 'command_executed'
                : 'command_failed',
            detail: '${request.command} exit=${result.exitCode}',
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
    return updated;
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

  void _setConversationStatus(ConversationStatus status) {
    final updated = currentConversation.copyWith(status: status);
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

  void _cancelActiveDispatch(ConversationStatus status) {
    _requestedCancellationStatus = status;
    _activeCancellation?.cancel();
    _setConversationStatus(status);
  }

  void _commitCancelledDispatch(ConversationStatus status) {
    final action = status == ConversationStatus.paused
        ? 'team_task_paused'
        : 'team_task_stopped';
    final content = status == ConversationStatus.paused
        ? '任务已暂停，继续后可以重新发起下一轮协作。'
        : '任务已停止，本轮未完成的模型请求已取消。';
    final updated = currentConversation.copyWith(
      status: status,
      messages: [
        ...currentConversation.messages,
        ChatMessage(
          id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
          authorName: '系统',
          content: content,
          createdAt: DateTime.now(),
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
            detail: currentTeam.id,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
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
    state = nextState;
    _syncConversationOrder();
    if (!state.conversations.any((item) => item.id == selectedConversationId)) {
      selectedConversationId = _initialConversationId(state);
    }
    _persistState(state);
    notifyListeners();
  }

  Future<void> flushPersistence() => _persistenceQueue;

  void _persistState(AppState snapshot) {
    final handler = onStateChanged;
    if (handler == null) {
      return;
    }
    final save = _persistenceQueue.then(
      (_) => Future<void>.sync(() => handler(snapshot)),
    );
    _persistenceQueue = save.catchError((Object error, StackTrace stackTrace) {
      this.error = '状态保存失败：$error';
    });
    unawaited(_persistenceQueue);
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
        !_reasoningEffortValues.contains(reasoningEffort)) {
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

  File _workspaceFile(String workspaceId, String relativePath) {
    if (relativePath.trim().isEmpty ||
        relativePath.startsWith('/') ||
        relativePath.split('/').contains('..')) {
      throw ArgumentError('非法相对路径: $relativePath');
    }
    final root = _workspaceRoot(workspaceId).absolute.path;
    final file = File('$root/$relativePath').absolute;
    if (!file.path.startsWith('$root/')) {
      throw ArgumentError('文件路径越过工作区边界: $relativePath');
    }
    return file;
  }

  Directory _workspaceRoot(String workspaceId) {
    final workspace =
        state.workspaces.firstWhere((item) => item.id == workspaceId);
    return Directory(workspace.path).absolute;
  }

  Future<ProcessResult> _runShellCommand(
    String command,
    String workingDirectory,
  ) {
    if (Platform.isWindows) {
      return Process.run(
        'cmd',
        ['/c', command],
        workingDirectory: workingDirectory,
        runInShell: false,
      );
    }
    return Process.run(
      '/bin/sh',
      ['-lc', command],
      workingDirectory: workingDirectory,
      runInShell: false,
    );
  }
}

class _AppSidebar extends StatelessWidget {
  const _AppSidebar({
    required this.selectedView,
    required this.onChat,
    required this.onTeam,
    required this.onModels,
    required this.onRoles,
    required this.onMembers,
    required this.onHistory,
    required this.onAudit,
    required this.onProject,
    required this.onSettings,
  });

  final _MainView selectedView;
  final VoidCallback onChat;
  final VoidCallback onTeam;
  final VoidCallback onModels;
  final VoidCallback onRoles;
  final VoidCallback onMembers;
  final VoidCallback onHistory;
  final VoidCallback onAudit;
  final VoidCallback onProject;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF050505),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF4F7CFF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white70, width: 2),
            ),
            child: const Text(
              'AI',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _SidebarButton(
                    icon: Icons.chat_bubble_rounded,
                    label: '消息',
                    selected: selectedView == _MainView.chat,
                    onPressed: onChat,
                  ),
                  _SidebarButton(
                    icon: Icons.groups_rounded,
                    label: '团队',
                    selected: selectedView == _MainView.teams,
                    onPressed: onTeam,
                  ),
                  _SidebarButton(
                    icon: Icons.memory_rounded,
                    label: '模型',
                    selected: selectedView == _MainView.models,
                    onPressed: onModels,
                  ),
                  _SidebarButton(
                    icon: Icons.badge_rounded,
                    label: '角色',
                    selected: selectedView == _MainView.roles,
                    onPressed: onRoles,
                  ),
                  _SidebarButton(
                    icon: Icons.manage_accounts_rounded,
                    label: '成员',
                    selected: selectedView == _MainView.members,
                    onPressed: onMembers,
                  ),
                  _SidebarButton(
                    icon: Icons.history_rounded,
                    label: '历史',
                    selected: selectedView == _MainView.history,
                    onPressed: onHistory,
                  ),
                  _SidebarButton(
                    icon: Icons.receipt_long_rounded,
                    label: '审计',
                    selected: selectedView == _MainView.audit,
                    onPressed: onAudit,
                  ),
                  _SidebarButton(
                    icon: Icons.folder_copy_rounded,
                    label: '项目',
                    selected: selectedView == _MainView.project,
                    onPressed: onProject,
                  ),
                ],
              ),
            ),
          ),
          _SidebarButton(
            icon: Icons.settings_rounded,
            label: '设置',
            selected: selectedView == _MainView.settings,
            onPressed: onSettings,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: IconButton(
          onPressed: onPressed,
          style: IconButton.styleFrom(
            backgroundColor:
                selected ? const Color(0xFF3B82F6) : Colors.transparent,
            foregroundColor: selected ? Colors.white : const Color(0xFFB8C2D8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.controller,
    required this.selectedView,
    required this.onSelectConversation,
  });

  final AppController controller;
  final _MainView selectedView;
  final ValueChanged<String> onSelectConversation;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF7F8FB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        hintText: '搜索',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: '新增',
                  onPressed: () => _showMemberDialog(context, controller),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              key: const ValueKey('conversation-list'),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: controller.visibleConversations.length,
              separatorBuilder: (context, index) => const Divider(
                height: 1,
                indent: 72,
                color: Color(0xFFE5E7EB),
              ),
              itemBuilder: (context, index) {
                final conversation = controller.visibleConversations[index];
                return _RailTile(
                  key: ValueKey('conversation-row-${conversation.id}'),
                  icon: _conversationListIcon(controller, conversation),
                  title: _conversationListTitle(controller, conversation),
                  subtitle: _conversationListSubtitle(controller, conversation),
                  badge: _conversationListBadge(controller, conversation),
                  selected: selectedView == _MainView.chat &&
                      controller.selectedConversationId == conversation.id,
                  pinned: controller.isConversationPinned(conversation.id),
                  onTap: () => onSelectConversation(conversation.id),
                  onContextMenu: (position) => _showConversationContextMenu(
                    context,
                    position,
                    controller,
                    conversation.id,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showConversationContextMenu(
  BuildContext context,
  Offset position,
  AppController controller,
  String conversationId,
) async {
  final isPinned = controller.isConversationPinned(conversationId);
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: [
      PopupMenuItem(
        value: 'pin',
        child: Text(isPinned ? '取消置顶' : '置顶'),
      ),
      const PopupMenuItem(
        value: 'delete',
        child: Text('删除'),
      ),
    ],
  );
  if (action == 'pin') {
    controller.togglePinnedConversation(conversationId);
  } else if (action == 'delete') {
    controller.closeConversation(conversationId);
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.selected = false,
    this.pinned = false,
    this.onTap,
    this.onContextMenu,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final bool selected;
  final bool pinned;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final titleColor = selected ? Colors.white : const Color(0xFF111827);
    final subtitleColor = selected
        ? Colors.white.withValues(alpha: 0.82)
        : const Color(0xFF4B5563);
    final iconColor = selected ? Colors.white : const Color(0xFF2563EB);
    final avatarColor = selected
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFEFF6FF);
    final backgroundColor = selected
        ? const Color(0xFF2F80ED)
        : pinned
            ? const Color(0xFFE9EDF3)
            : Colors.transparent;
    return Padding(
      padding: EdgeInsets.zero,
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          onContextMenu?.call(details.globalPosition);
        },
        child: Material(
          color: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            dense: true,
            minLeadingWidth: 38,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            onTap: onTap,
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: avatarColor,
              child: Icon(icon, size: 18, color: iconColor),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Color(0xFFD97706),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: subtitleColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatPane extends StatefulWidget {
  const _ChatPane({required this.controller});

  final AppController controller;

  @override
  State<_ChatPane> createState() => _ChatPaneState();
}

enum _MessageUserScrollDirection { idle, history, bottom }

class _ChatPaneState extends State<_ChatPane> {
  static const _autoScrollBottomThreshold = 96.0;
  static const _messageBottomReachedTolerance = 1.0;

  final textController = TextEditingController();
  final messageScrollController = ScrollController();
  final messageScrollOffsetsByConversation = <String, double>{};
  final messageAutoFollowByConversation = <String, bool>{};
  final messageUserScrollDirectionsByConversation =
      <String, _MessageUserScrollDirection>{};
  String? lastConversationId;
  int lastMessageListItemCount = -1;
  String? lastMessageId;
  int lastMessageContentLength = -1;
  int lastMessageThinkingLength = -1;
  ChatMessageGenerationStatus? lastMessageGenerationStatus;
  bool messageScrollFrameScheduled = false;
  String? pendingMessageScrollConversationId;
  int? pendingMessageScrollVersion;
  int messageAutoScrollVersion = 0;
  bool isProgrammaticMessageScroll = false;

  @override
  void dispose() {
    textController.dispose();
    messageScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.controller.currentConversation;
    final typingMembers = _typingMembers(widget.controller, conversation);
    final pendingPatches = widget.controller.patchProposals
        .where((patch) => patch.status == PatchStatus.pending)
        .toList();
    final messageListItemCount = conversation.messages.length +
        typingMembers.length +
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
    final conversationChanged = conversation.id != lastConversationId;
    final messageStructureChanged = conversationChanged ||
        messageListItemCount != lastMessageListItemCount ||
        currentLastMessageId != lastMessageId;
    final lastMessageBodyChanged =
        currentLastMessageContentLength != lastMessageContentLength ||
            currentLastMessageThinkingLength != lastMessageThinkingLength ||
            currentLastMessageGenerationStatus != lastMessageGenerationStatus;
    if (conversationChanged) {
      _restoreMessageScrollOffset(conversation.id);
    }
    lastConversationId = conversation.id;
    lastMessageListItemCount = messageListItemCount;
    lastMessageId = currentLastMessageId;
    lastMessageContentLength = currentLastMessageContentLength;
    lastMessageThinkingLength = currentLastMessageThinkingLength;
    lastMessageGenerationStatus = currentLastMessageGenerationStatus;
    if (!conversationChanged &&
        (messageStructureChanged || lastMessageBodyChanged) &&
        _autoFollowMessages(conversation.id)) {
      _scheduleMessageScrollToBottom(conversation.id);
    }
    final showBackToBottomButton = !_autoFollowMessages(conversation.id);
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
                    conversation.id,
                  ),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) =>
                        _handleMessageScrollNotification(
                      notification,
                      conversation.id,
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
                            showAuthorName: conversation.memberId == null,
                          );
                        }
                        final typingIndex =
                            index - conversation.messages.length;
                        if (typingIndex < typingMembers.length) {
                          return _TypingIndicator(
                            member: typingMembers[typingIndex],
                          );
                        }
                        final patch =
                            pendingPatches[typingIndex - typingMembers.length];
                        return _ChatPatchConfirmationCard(
                          patch: patch,
                          onApply: () => widget.controller.applyPatch(patch),
                          onReject: () => widget.controller.rejectPatch(patch),
                        );
                      },
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
        _TaskQueueBar(controller: widget.controller),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Focus(
                    onKeyEvent: _handleInputKeyEvent,
                    child: TextField(
                      controller: textController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: _inputHint(widget.controller, conversation),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ),
                const IconButton(
                  tooltip: '表情',
                  onPressed: null,
                  icon: Icon(Icons.mood_rounded),
                ),
                const IconButton(
                  tooltip: '提及',
                  onPressed: null,
                  icon: Icon(Icons.alternate_email_rounded),
                ),
                IconButton.filled(
                  tooltip: widget.controller.isDispatching ? '停止生成' : '发送',
                  onPressed: widget.controller.isDispatching
                      ? widget.controller.stopConversation
                      : _submit,
                  icon: Icon(
                    widget.controller.isDispatching
                        ? Icons.stop_rounded
                        : Icons.send_rounded,
                  ),
                ),
                const SizedBox(width: 6),
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
    await widget.controller.dispatch(text);
  }

  KeyEventResult _handleInputKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (widget.controller.isDispatching) {
        widget.controller.stopConversation();
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

  bool _autoFollowMessages(String conversationId) {
    return messageAutoFollowByConversation[conversationId] ?? true;
  }

  bool _isNearMessageBottom() {
    if (!messageScrollController.hasClients) {
      return true;
    }
    return _isNearMessageBottomMetrics(messageScrollController.position);
  }

  bool _isNearMessageBottomMetrics(ScrollMetrics metrics) {
    return metrics.maxScrollExtent - metrics.pixels <=
        _autoScrollBottomThreshold;
  }

  bool _isAtMessageBottomMetrics(ScrollMetrics metrics) {
    return metrics.maxScrollExtent - metrics.pixels <=
        _messageBottomReachedTolerance;
  }

  bool _handleMessageScrollNotification(
    ScrollNotification notification,
    String conversationId,
  ) {
    if (notification.metrics.axis != Axis.vertical ||
        isProgrammaticMessageScroll) {
      return false;
    }
    final previousOffset = messageScrollOffsetsByConversation[conversationId];
    _recordMessageScrollPosition(
      conversationId,
      notification.metrics.pixels,
    );
    if (notification is ScrollUpdateNotification &&
        notification.scrollDelta != null) {
      final scrollDelta = _messageScrollDelta(notification, previousOffset);
      if (scrollDelta < 0) {
        _recordMessageScrollDirection(
          conversationId,
          _MessageUserScrollDirection.history,
        );
        _disableMessageAutoFollow(conversationId);
      } else if (scrollDelta > 0) {
        _recordMessageScrollDirection(
          conversationId,
          _MessageUserScrollDirection.bottom,
        );
        if (_isNearMessageBottomMetrics(notification.metrics)) {
          _setMessageAutoFollow(conversationId, true);
        }
      }
    } else if (notification is ScrollEndNotification) {
      _restoreMessageAutoFollowAfterUserScrollEnd(
        conversationId,
        notification.metrics,
      );
    }
    return false;
  }

  double _messageScrollDelta(
    ScrollUpdateNotification notification,
    double? previousOffset,
  ) {
    if (previousOffset != null) {
      final delta = notification.metrics.pixels - previousOffset;
      if (delta != 0) {
        return delta;
      }
    }
    return notification.scrollDelta ?? 0;
  }

  void _handleMessagePointerSignal(
    PointerSignalEvent event,
    String conversationId,
  ) {
    if (event is! PointerScrollEvent ||
        !messageScrollController.hasClients ||
        widget.controller.currentConversation.id != conversationId) {
      return;
    }
    final position = messageScrollController.position;
    final scrollDelta = event.scrollDelta.dy;
    if (scrollDelta < 0 && position.pixels > position.minScrollExtent) {
      _recordMessageScrollDirection(
        conversationId,
        _MessageUserScrollDirection.history,
      );
      _disableMessageAutoFollow(conversationId);
    } else if (scrollDelta > 0) {
      _recordMessageScrollDirection(
        conversationId,
        _MessageUserScrollDirection.bottom,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !messageScrollController.hasClients ||
            widget.controller.currentConversation.id != conversationId) {
          return;
        }
        _restoreMessageAutoFollowAfterUserScrollEnd(
          conversationId,
          messageScrollController.position,
        );
      });
    }
  }

  void _recordMessageScrollPosition(String conversationId, double offset) {
    messageScrollOffsetsByConversation[conversationId] = offset;
  }

  void _recordMessageScrollDirection(
    String conversationId,
    _MessageUserScrollDirection direction,
  ) {
    messageUserScrollDirectionsByConversation[conversationId] = direction;
  }

  _MessageUserScrollDirection _lastMessageScrollDirection(
    String conversationId,
  ) {
    return messageUserScrollDirectionsByConversation[conversationId] ??
        _MessageUserScrollDirection.idle;
  }

  void _restoreMessageAutoFollowAfterUserScrollEnd(
    String conversationId,
    ScrollMetrics metrics,
  ) {
    if (_isAtMessageBottomMetrics(metrics) ||
        (_lastMessageScrollDirection(conversationId) ==
                _MessageUserScrollDirection.bottom &&
            _isNearMessageBottomMetrics(metrics))) {
      _recordMessageScrollDirection(
        conversationId,
        _MessageUserScrollDirection.idle,
      );
      _setMessageAutoFollow(conversationId, true);
    }
  }

  void _setMessageAutoFollow(String conversationId, bool value) {
    final previous = _autoFollowMessages(conversationId);
    messageAutoFollowByConversation[conversationId] = value;
    if (previous != value &&
        mounted &&
        widget.controller.currentConversation.id == conversationId) {
      setState(() {});
    }
  }

  void _disableMessageAutoFollow(String conversationId) {
    _cancelPendingMessageAutoScroll();
    _setMessageAutoFollow(conversationId, false);
  }

  void _restoreMessageScrollOffset(String conversationId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !messageScrollController.hasClients ||
          widget.controller.currentConversation.id != conversationId) {
        return;
      }
      final savedOffset = messageScrollOffsetsByConversation[conversationId];
      final position = messageScrollController.position;
      final target = (savedOffset ?? position.minScrollExtent)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _jumpMessageScrollTo(target, conversationId);
      _recordMessageScrollPosition(
        conversationId,
        messageScrollController.position.pixels,
      );
      _setMessageAutoFollow(conversationId, _isNearMessageBottom());
    });
  }

  void _scrollCurrentConversationToBottom() {
    final conversationId = widget.controller.currentConversation.id;
    _setMessageAutoFollow(conversationId, true);
    _scheduleMessageScrollToBottom(conversationId);
  }

  void _scheduleMessageScrollToBottom(String conversationId) {
    pendingMessageScrollConversationId = conversationId;
    pendingMessageScrollVersion = messageAutoScrollVersion;
    if (messageScrollFrameScheduled) {
      return;
    }
    messageScrollFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      messageScrollFrameScheduled = false;
      final scheduledConversationId = pendingMessageScrollConversationId;
      final scheduledVersion = pendingMessageScrollVersion;
      pendingMessageScrollConversationId = null;
      pendingMessageScrollVersion = null;
      if (!mounted ||
          !messageScrollController.hasClients ||
          scheduledConversationId == null ||
          scheduledVersion != messageAutoScrollVersion ||
          widget.controller.currentConversation.id != scheduledConversationId ||
          !_autoFollowMessages(scheduledConversationId)) {
        return;
      }
      final target = messageScrollController.position.maxScrollExtent;
      _jumpMessageScrollTo(target, scheduledConversationId);
    });
  }

  void _cancelPendingMessageAutoScroll() {
    pendingMessageScrollConversationId = null;
    pendingMessageScrollVersion = null;
    messageAutoScrollVersion++;
  }

  void _jumpMessageScrollTo(double target, String conversationId) {
    isProgrammaticMessageScroll = true;
    messageScrollController.jumpTo(target);
    isProgrammaticMessageScroll = false;
    _recordMessageScrollPosition(
      conversationId,
      messageScrollController.position.pixels,
    );
    _setMessageAutoFollow(conversationId, _isNearMessageBottom());
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
    required this.showAuthorName,
  });

  final ChatMessage message;
  final bool showAuthorName;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool hovered = false;
  bool thinkingExpanded = false;
  bool copied = false;
  Timer? copyResetTimer;
  Timer? streamingTitleTimer;

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
    final message = widget.message;
    final alignRight = message.isUser;
    final showAuthorName = !alignRight && widget.showAuthorName;
    final thinkingContent =
        alignRight ? null : _normalizedThinkingContent(message);
    final inlineStatus = thinkingContent == null
        ? _messageInlineGenerationStatus(message)
        : null;
    final showMessageHeader =
        !alignRight && (showAuthorName || inlineStatus != null);
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
          if (thinkingContent != null) ...[
            _MessageThinkingDisclosure(
              content: thinkingContent,
              title: _thinkingTitle(message),
              expanded: thinkingExpanded,
              onToggle: () {
                setState(() {
                  thinkingExpanded = !thinkingExpanded;
                });
              },
            ),
            const SizedBox(height: 10),
          ],
          if (_isAwaitingFirstModelOutput(message))
            Text(
              '正在输入中',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            )
          else
            SelectableText(message.content),
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
        bubble,
        const SizedBox(height: 4),
        Align(
          alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
          child: actionSlot,
        ),
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
    unawaited(Clipboard.setData(ClipboardData(text: widget.message.content)));
    copyResetTimer?.cancel();
    setState(() => copied = true);
    copyResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => copied = false);
      }
    });
  }
}

class _MessageThinkingDisclosure extends StatelessWidget {
  const _MessageThinkingDisclosure({
    required this.content,
    required this.title,
    required this.expanded,
    required this.onToggle,
  });

  final String content;
  final String title;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: SelectableText(
                  content,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    height: 1.45,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ManagementPage extends StatelessWidget {
  const _ManagementPage({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(subtitle),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _TeamManagementPage extends StatelessWidget {
  const _TeamManagementPage({
    required this.controller,
    required this.onStartChat,
  });

  final AppController controller;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    return _ManagementPage(
      title: '团队管理',
      subtitle: '创建团队、配置成员，并从团队发起群聊',
      child: _Panel(
        title: '团队列表',
        icon: Icons.groups_rounded,
        action: IconButton(
          tooltip: '新增团队',
          onPressed: () => _showTeamDialog(context, controller),
          icon: const Icon(Icons.add_rounded),
        ),
        child: Column(
          children: controller.state.teams
              .map(
                (team) => _TeamCard(
                  controller: controller,
                  team: team,
                  onStartChat: () {
                    controller.startTeamChat(team.id);
                    onStartChat();
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.controller,
    required this.team,
    required this.onStartChat,
  });

  final AppController controller;
  final Team team;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    final members = controller.state.members
        .where((member) => team.memberIds.contains(member.id))
        .toList();
    return _KeyValueRow(
      label: team.name,
      value:
          '${_collaborationModeLabel(team.collaborationMode)}协同 · ${members.map((member) => member.name).join('、')}',
      actions: [
        FilledButton(
          onPressed: onStartChat,
          child: const Text('发起聊天'),
        ),
        IconButton(
          tooltip: '编辑团队',
          onPressed: () => _showTeamDialog(
            context,
            controller,
            team: team,
          ),
          icon: const Icon(Icons.edit_rounded),
        ),
        IconButton(
          tooltip: '删除团队',
          onPressed: controller.state.teams.length <= 1
              ? null
              : () => _runConfigAction(
                    context,
                    () => controller.deleteTeam(team.id),
                  ),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
    );
  }
}

class _ModelManagementPage extends StatelessWidget {
  const _ModelManagementPage({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _ManagementPage(
      title: '模型管理',
      subtitle: 'OpenAI 兼容模型、请求参数和密钥引用在这里维护',
      child: _ModelConfigPanel(controller: controller),
    );
  }
}

class _RoleManagementPage extends StatelessWidget {
  const _RoleManagementPage({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _ManagementPage(
      title: '角色管理',
      subtitle: '角色提示词、命令策略和项目读取权限在这里维护',
      child: _RoleConfigPanel(controller: controller),
    );
  }
}

class _MemberManagementPage extends StatelessWidget {
  const _MemberManagementPage({
    required this.controller,
    required this.onStartChat,
  });

  final AppController controller;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    return _ManagementPage(
      title: '成员管理',
      subtitle: '团队成员、角色绑定和模型绑定在这里维护',
      child: _MemberConfigPanel(
        controller: controller,
        onStartChat: onStartChat,
      ),
    );
  }
}

class _ProjectPage extends StatelessWidget {
  const _ProjectPage({
    required this.controller,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '项目管理',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('本地工作区、文件浏览和补丁预览集中在这里管理'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _WorkspacePanel(controller: controller),
          ),
        ),
      ],
    );
  }
}

class _HistoryPage extends StatefulWidget {
  const _HistoryPage({required this.controller});

  final AppController controller;

  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage> {
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim();
    final tasks = widget.controller.state.queuedTasks
        .where(
          (task) => query.isEmpty || task.title.contains(query),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(
      children: [
        Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '历史',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('跨会话查看任务历史和关联信息'),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: TextField(
            controller: searchController,
            decoration: const InputDecoration(
              labelText: '搜索标题',
              prefixIcon: Icon(Icons.search_rounded),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                child: ExpansionTile(
                  title: Text(task.title),
                  subtitle: Text(
                    '${_queuedTaskStatusText(task.status)} · 优先级 ${task.priority}',
                  ),
                  trailing: IconButton(
                    tooltip: '删除历史任务',
                    onPressed: () {
                      widget.controller.deleteTask(task.id);
                      setState(() {});
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(task.originalText),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AuditLogPage extends StatelessWidget {
  const _AuditLogPage({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.state.auditLog.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _ManagementPage(
      title: '审计日志',
      subtitle: '查看本机操作记录和命令执行审计',
      child: _Panel(
        title: '操作记录',
        icon: Icons.receipt_long_rounded,
        child: Column(
          children: entries.isEmpty
              ? [const Text('暂无操作记录')]
              : entries
                  .map(
                    (entry) => _AuditLogRow(entry: entry),
                  )
                  .toList(),
        ),
      ),
    );
  }
}

class _AuditLogRow extends StatelessWidget {
  const _AuditLogRow({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  entry.action,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: entry.metadata == null ? '无详情' : '查看详情',
                onPressed: entry.metadata == null
                    ? null
                    : () => _showAuditLogDetails(context, entry),
                icon: const Icon(Icons.info_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(entry.detail, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Text(
            '创建时间：${_auditLogTimeText(entry.createdAt)}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

void _showAuditLogDetails(BuildContext context, AuditEntry entry) {
  final metadata = entry.metadata ?? const <String, Object?>{};
  final rawResponse = metadata['rawResponse'] as String?;
  final requestBody = metadata['requestBody'];
  final structuredEntries = metadata.entries
      .where((item) => item.key != 'rawResponse' && item.key != 'requestBody')
      .toList(growable: false);
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('审计详情'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AuditDetailSection(
                title: '基础信息',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText('action: ${entry.action}'),
                    SelectableText(
                      'createdAt: ${_auditLogTimeText(entry.createdAt)}',
                    ),
                  ],
                ),
              ),
              _AuditDetailSection(
                title: '摘要',
                child: SelectableText(entry.detail),
              ),
              if (structuredEntries.isNotEmpty)
                _AuditDetailSection(
                  title: '结构化字段',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: structuredEntries
                        .map(
                          (item) => SelectableText(
                            '${item.key}: ${_auditMetadataValueText(item.value)}',
                          ),
                        )
                        .toList(),
                  ),
                ),
              if (requestBody != null)
                _AuditDetailSection(
                  title: '请求参数',
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(requestBody),
                    ),
                  ),
                ),
              if (rawResponse != null)
                _AuditDetailSection(
                  title: '原始返回内容',
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(rawResponse),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class _AuditDetailSection extends StatelessWidget {
  const _AuditDetailSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

String _auditMetadataValueText(Object? value) {
  if (value is Iterable) {
    return value.join(',');
  }
  return value.toString();
}

String _reasoningEffortLabel(String? value) {
  if (value == null || value.trim().isEmpty) {
    return _reasoningEffortLabels[_reasoningEffortOffValue]!;
  }
  return _reasoningEffortLabels[value] ?? value;
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.controller,
  });

  final AppController controller;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  final scrollController = ScrollController();
  final sectionKeys = {
    '命令请求': GlobalKey(),
    '导入导出': GlobalKey(),
  };

  AppController get controller => widget.controller;

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  void scrollToSection(String title) {
    final context = sectionKeys[title]?.currentContext;
    if (context == null) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '设置',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text('命令和导入导出配置保存在本机'),
                  ],
                ),
              ),
            ],
          ),
        ),
        _SettingsCategoryBar(onSelect: scrollToSection),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _Panel(
                  key: sectionKeys['导入导出'],
                  title: '导入导出',
                  icon: Icons.ios_share_rounded,
                  action: IconButton(
                    tooltip: '导入 / 导出配置',
                    onPressed: () => _showExportDialog(context, controller),
                    icon: const Icon(Icons.open_in_new_rounded),
                  ),
                  child: const Text('配置文件和密钥导出选项集中在这里管理。'),
                ),
                _Panel(
                  title: '任务轮次',
                  icon: Icons.account_tree_rounded,
                  child: Column(
                    children: controller.currentTaskAssignments.isEmpty
                        ? [
                            _KeyValueRow(
                              label: '当前轮次',
                              value:
                                  '第 ${controller.currentConversation.currentRound} 轮',
                            ),
                            const Text('暂无成员任务'),
                          ]
                        : controller.currentTaskAssignments
                            .map(
                              (assignment) =>
                                  _TaskAssignmentCard(assignment: assignment),
                            )
                            .toList(),
                  ),
                ),
                _Panel(
                  key: sectionKeys['命令请求'],
                  title: '命令请求',
                  icon: Icons.terminal_rounded,
                  action: IconButton(
                    tooltip: '创建命令请求',
                    onPressed: () => _showCommandDialog(context, controller),
                    icon: const Icon(Icons.add_rounded),
                  ),
                  child: Column(
                    children: controller.state.commandRequests.isEmpty
                        ? [const Text('暂无命令请求')]
                        : controller.state.commandRequests
                            .map(
                              (request) => _CommandRequestCard(
                                request: request,
                                onApprove: () =>
                                    controller.updateCommandRequestStatus(
                                  request.id,
                                  CommandRequestStatus.approved,
                                ),
                                onDeny: () =>
                                    controller.updateCommandRequestStatus(
                                  request.id,
                                  CommandRequestStatus.denied,
                                ),
                                onExecute: () =>
                                    controller.executeCommandRequest(
                                  request.id,
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsCategoryBar extends StatelessWidget {
  const _SettingsCategoryBar({required this.onSelect});

  final ValueChanged<String> onSelect;

  static const items = [
    (Icons.terminal_rounded, '命令', '命令请求'),
    (Icons.ios_share_rounded, '导入导出', '导入导出'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFB),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final item in items)
            ActionChip(
              onPressed: () => onSelect(item.$3),
              avatar: Icon(item.$1, size: 16),
              label: Text(item.$2),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModelConfigPanel extends StatelessWidget {
  const _ModelConfigPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '模型配置',
      icon: Icons.memory_rounded,
      action: IconButton(
        tooltip: '新增模型',
        onPressed: () => _showModelDialog(context, controller),
        icon: const Icon(Icons.add_rounded),
      ),
      child: Column(
        children: controller.state.models
            .map(
              (model) => _KeyValueRow(
                label: model.name,
                value:
                    '${model.modelName}\n${model.baseUrl}\n流式: ${model.streaming ? '开' : '关'} · 温度: ${model.temperature} · 最大 Token: ${model.maxTokens} · 深度思考: ${_reasoningEffortLabel(model.reasoningEffort)}',
                actions: [
                  IconButton(
                    tooltip: '编辑模型',
                    onPressed: () =>
                        _showModelDialog(context, controller, model: model),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton(
                    tooltip: '删除模型',
                    onPressed: () => _runConfigAction(
                      context,
                      () => controller.deleteModel(model.id),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _RoleConfigPanel extends StatelessWidget {
  const _RoleConfigPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '角色配置',
      icon: Icons.badge_rounded,
      action: IconButton(
        tooltip: '新增角色',
        onPressed: () => _showRoleDialog(context, controller),
        icon: const Icon(Icons.add_rounded),
      ),
      child: Column(
        children: controller.state.roles
            .map(
              (role) => _KeyValueRow(
                label: role.name,
                value:
                    '${role.description}\n命令: ${role.commandPolicy.allowedCommands.join(', ')}',
                actions: [
                  IconButton(
                    tooltip: '编辑角色',
                    onPressed: () =>
                        _showRoleDialog(context, controller, role: role),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton(
                    tooltip: '删除角色',
                    onPressed: () => _runConfigAction(
                      context,
                      () => controller.deleteRole(role.id),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MemberConfigPanel extends StatelessWidget {
  const _MemberConfigPanel({
    required this.controller,
    required this.onStartChat,
  });

  final AppController controller;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '团队成员',
      icon: Icons.groups_rounded,
      action: IconButton(
        tooltip: '新增成员',
        onPressed: () => _showMemberDialog(context, controller),
        icon: const Icon(Icons.add_rounded),
      ),
      child: Column(
        children: controller.currentMembers
            .map(
              (member) => _KeyValueRow(
                label: member.name,
                value:
                    '${_roleName(controller.state, member.roleId)} · ${_modelName(controller.state, member.modelId)} · 优先级 ${member.executionPriority}',
                actions: [
                  FilledButton(
                    onPressed: () {
                      controller.startMemberChat(member.id);
                      onStartChat();
                    },
                    child: const Text('发起聊天'),
                  ),
                  IconButton(
                    tooltip: '编辑成员',
                    onPressed: () => _showMemberDialog(
                      context,
                      controller,
                      member: member,
                    ),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton(
                    tooltip: '删除成员',
                    onPressed: member.isSecretary
                        ? null
                        : () => _runConfigAction(
                              context,
                              () => controller.deleteMember(member.id),
                            ),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _WorkspacePanel extends StatelessWidget {
  const _WorkspacePanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: '项目工作区',
      icon: Icons.folder_open_rounded,
      action: Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: '创建补丁',
            onPressed: controller.state.workspaces.isEmpty
                ? null
                : () => _showWorkspacePatchDialog(context, controller),
            icon: const Icon(Icons.difference_rounded),
          ),
          IconButton(
            tooltip: '浏览文件',
            onPressed: controller.state.workspaces.isEmpty
                ? null
                : () => _showWorkspaceFilesDialog(context, controller),
            icon: const Icon(Icons.list_alt_rounded),
          ),
          IconButton(
            tooltip: '添加工作区',
            onPressed: controller.pickAndAddWorkspace,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      child: Column(
        children: controller.state.workspaces.isEmpty
            ? [const Text('还没有选择本地项目目录')]
            : controller.state.workspaces
                .map(
                  (workspace) => _KeyValueRow(
                    label: workspace.name,
                    value: workspace.path,
                  ),
                )
                .toList(),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.action,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (action != null)
            Align(
              alignment: Alignment.centerRight,
              child: action!,
            ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
    this.actions = const [],
  });

  final String label;
  final String value;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (actions.isNotEmpty)
                Wrap(
                  spacing: 2,
                  children: actions,
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}

class _TaskAssignmentCard extends StatelessWidget {
  const _TaskAssignmentCard({required this.assignment});

  final TaskAssignment assignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '第 ${assignment.round} 轮 · ${assignment.memberName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _taskStatusText(assignment.status),
                style: TextStyle(
                  color: _taskStatusColor(assignment.status),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            assignment.roleName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          Text(
            assignment.instruction,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (assignment.summary != null) ...[
            const SizedBox(height: 4),
            Text(
              assignment.summary!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskQueueBar extends StatelessWidget {
  const _TaskQueueBar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final tasks = controller.tasksForCurrentConversation;
    if (tasks.isEmpty) {
      return const SizedBox.shrink();
    }
    final running = _firstTaskWithStatus(tasks, QueuedTaskStatus.running);
    final title = running == null
        ? '队列 ${tasks.length}'
        : '队列 ${tasks.length} · ${running.title}';
    return Material(
      color: const Color(0xFFF8FAFC),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 24),
        initiallyExpanded: false,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Column(
              children: tasks
                  .map(
                    (task) => _TaskQueueTile(
                      controller: controller,
                      task: task,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskQueueTile extends StatefulWidget {
  const _TaskQueueTile({
    required this.controller,
    required this.task,
  });

  final AppController controller;
  final QueuedTask task;

  @override
  State<_TaskQueueTile> createState() => _TaskQueueTileState();
}

class _TaskQueueTileState extends State<_TaskQueueTile> {
  final noteController = TextEditingController();
  late final priorityController = TextEditingController(
    text: widget.task.priority.toString(),
  );

  @override
  void dispose() {
    noteController.dispose();
    priorityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: ExpansionTile(
        title: Text(task.title),
        subtitle: Text(
          '${_queuedTaskStatusText(task.status)} · 优先级 ${task.priority} · 备注 ${task.notes.length}',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            if (task.status == QueuedTaskStatus.running)
              IconButton(
                tooltip: '暂停任务',
                onPressed: () => widget.controller.pauseTask(task.id),
                icon: const Icon(Icons.pause_rounded),
              ),
            if (task.status == QueuedTaskStatus.paused)
              IconButton(
                tooltip: '继续任务',
                onPressed: () => widget.controller.resumeTask(task.id),
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            IconButton(
              tooltip: '删除任务',
              onPressed: () => widget.controller.deleteTask(task.id),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.originalText),
                const SizedBox(height: 8),
                if (task.notes.isNotEmpty) Text('备注：${task.notes.join('；')}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: priorityController,
                        decoration: const InputDecoration(labelText: '优先级'),
                        keyboardType: TextInputType.number,
                        onSubmitted: (value) {
                          final priority = int.tryParse(value.trim());
                          if (priority != null) {
                            widget.controller.updateTaskPriority(
                              task.id,
                              priority,
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: noteController,
                        decoration: const InputDecoration(labelText: '追加备注'),
                        onSubmitted: (_) => _appendNote(),
                      ),
                    ),
                    IconButton(
                      tooltip: '追加备注',
                      onPressed: _appendNote,
                      icon: const Icon(Icons.add_comment_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _appendNote() {
    widget.controller.appendTaskNote(widget.task.id, noteController.text);
    noteController.clear();
  }
}

class _ChatPatchConfirmationCard extends StatelessWidget {
  const _ChatPatchConfirmationCard({
    required this.patch,
    required this.onApply,
    required this.onReject,
  });

  final PatchProposal patch;
  final VoidCallback onApply;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 18,
          backgroundColor: Color(0xFF8B5CF6),
          child: Icon(
            Icons.difference_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 760),
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFC7D2FE)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '待确认修改',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text('${patch.memberName} 提议修改 ${patch.filePath}'),
                const SizedBox(height: 10),
                SelectableText(
                  patch.diff,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: onApply,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('应用修改'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('拒绝'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CommandRequestCard extends StatelessWidget {
  const _CommandRequestCard({
    required this.request,
    required this.onApprove,
    required this.onDeny,
    required this.onExecute,
  });

  final CommandRequest request;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback onExecute;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${request.memberName} · ${request.status.name}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          SelectableText(
            '${request.workingDirectory}\n\$ ${request.command}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          if (request.status == CommandRequestStatus.pending) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('批准'),
                ),
                OutlinedButton.icon(
                  onPressed: onDeny,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('拒绝'),
                ),
              ],
            ),
          ],
          if (request.status == CommandRequestStatus.approved) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onExecute,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('执行'),
            ),
          ],
          if (request.output != null && request.output!.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              request.output!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showTeamDialog(
  BuildContext context,
  AppController controller, {
  Team? team,
}) async {
  final nameController = TextEditingController(text: team?.name ?? '');
  var collaborationMode =
      team?.collaborationMode ?? TeamCollaborationMode.serial;
  final selectedMemberIds = team == null
      ? {
          for (final member in controller.state.members)
            if (!member.isSecretary) member.id,
        }
      : team.memberIds.where((memberId) {
          final member = controller.state.members.firstWhere(
            (item) => item.id == memberId,
          );
          return !member.isSecretary;
        }).toSet();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(team == null ? '新增团队' : '编辑团队'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (error != null) _DialogError(error!),
                _DialogField(
                  controller: nameController,
                  label: '团队名称',
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '协同模式',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<TeamCollaborationMode>(
                    segments: const [
                      ButtonSegment(
                        value: TeamCollaborationMode.serial,
                        label: Text('串行'),
                      ),
                      ButtonSegment(
                        value: TeamCollaborationMode.parallel,
                        label: Text('并行'),
                      ),
                    ],
                    selected: {collaborationMode},
                    onSelectionChanged: (selection) {
                      setDialogState(
                        () => collaborationMode = selection.single,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '团队成员',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(height: 6),
                ...controller.state.members
                    .where((member) => !member.isSecretary)
                    .map(
                      (member) => CheckboxListTile(
                        value: selectedMemberIds.contains(member.id),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value ?? false) {
                              selectedMemberIds.add(member.id);
                            } else {
                              selectedMemberIds.remove(member.id);
                            }
                          });
                        },
                        title: Text(member.name),
                        subtitle: Text(
                          '${_roleName(controller.state, member.roleId)} · ${_modelName(controller.state, member.modelId)}',
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      ),
                    ),
                const Text('默认秘书会自动加入每个团队。'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              try {
                if (team == null) {
                  controller.addTeam(
                    name: nameController.text,
                    memberIds: selectedMemberIds.toList(),
                    collaborationMode: collaborationMode,
                  );
                } else {
                  controller.updateTeam(
                    teamId: team.id,
                    name: nameController.text,
                    memberIds: selectedMemberIds.toList(),
                    collaborationMode: collaborationMode,
                  );
                }
                FocusScope.of(context).unfocus();
                Navigator.of(context).pop();
              } catch (exception) {
                setDialogState(() => error = exception.toString());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showModelDialog(
  BuildContext context,
  AppController controller, {
  ModelProfile? model,
}) async {
  final name = TextEditingController(text: model?.name ?? '');
  final baseUrl = TextEditingController(
    text: model?.baseUrl ?? 'https://api.openai.com/v1',
  );
  final modelName = TextEditingController(text: model?.modelName ?? '');
  final apiKey = TextEditingController(text: model?.apiKey ?? '');
  final temperature = TextEditingController(
    text: (model?.temperature ?? 0.4).toString(),
  );
  final maxTokens = TextEditingController(
    text: (model?.maxTokens ?? 1600).toString(),
  );
  var streaming = model?.streaming ?? true;
  var reasoningEffort = model?.reasoningEffort ?? _reasoningEffortOffValue;
  String? validationError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(model == null ? '新增模型配置' : '编辑模型配置'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (validationError != null) _DialogError(validationError!),
                _DialogField(controller: name, label: '名称'),
                _DialogField(controller: baseUrl, label: 'Base URL'),
                _DialogField(controller: modelName, label: '模型名称'),
                _DialogField(
                  controller: apiKey,
                  label: 'API Key',
                  obscure: true,
                ),
                SwitchListTile(
                  value: streaming,
                  onChanged: (value) => setDialogState(() => streaming = value),
                  title: const Text('流式输出'),
                  contentPadding: EdgeInsets.zero,
                ),
                DropdownButtonFormField<String>(
                  initialValue: reasoningEffort,
                  decoration: const InputDecoration(labelText: '深度思考'),
                  items: [
                    for (final value in [
                      _reasoningEffortOffValue,
                      ..._reasoningEffortValues,
                    ])
                      DropdownMenuItem(
                        value: value,
                        child: Text(_reasoningEffortLabels[value] ?? value),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setDialogState(() => reasoningEffort = value);
                  },
                ),
                _DialogField(controller: temperature, label: '温度 0-2'),
                _DialogField(controller: maxTokens, label: '最大 Token'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final parsedTemperature = double.tryParse(
                  temperature.text.trim(),
                );
                final parsedMaxTokens = int.tryParse(maxTokens.text.trim());
                if (parsedTemperature == null || parsedMaxTokens == null) {
                  throw ArgumentError('温度和最大 Token 必须是数字');
                }
                final next = ModelProfile(
                  id: model?.id ??
                      'model-${DateTime.now().microsecondsSinceEpoch}',
                  name: name.text.trim(),
                  baseUrl: baseUrl.text.trim(),
                  modelName: modelName.text.trim(),
                  apiKey: apiKey.text.trim(),
                  streaming: streaming,
                  temperature: parsedTemperature,
                  maxTokens: parsedMaxTokens,
                  reasoningEffort: reasoningEffort == _reasoningEffortOffValue
                      ? null
                      : reasoningEffort,
                );
                if (model == null) {
                  controller.addModel(next);
                } else {
                  controller.updateModel(next);
                }
                Navigator.pop(context);
              } catch (exception) {
                setDialogState(() => validationError = exception.toString());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showRoleDialog(
  BuildContext context,
  AppController controller, {
  RoleTemplate? role,
}) async {
  final name = TextEditingController(text: role?.name ?? '');
  final description = TextEditingController(
    text: role?.description ?? '自定义角色',
  );
  final identity = TextEditingController(text: role?.identityPrompt ?? '');
  final goal = TextEditingController(
    text: role?.goalPrompt ?? '按团队目标完成任务。',
  );
  final constraint = TextEditingController(
    text: role?.constraintPrompt ?? '遵守权限配置，不直接写入文件。',
  );
  final outputFormat = TextEditingController(
    text: role?.outputFormatPrompt ?? '输出结论、证据和下一步。',
  );
  final allowedCommands = TextEditingController(
    text: (role?.commandPolicy.allowedCommands ??
            const ['flutter test', 'dart analyze'])
        .join('\n'),
  );
  final blockedCommands = TextEditingController(
    text: (role?.commandPolicy.blockedCommands ?? const ['rm', 'sudo'])
        .join('\n'),
  );
  final allowedDirectories = TextEditingController(
    text: (role?.commandPolicy.allowedDirectories ?? const []).join('\n'),
  );
  var canReadProject = role?.canReadProject ?? true;
  var canProposePatch = role?.canProposePatch ?? true;
  var requiresConfirmation = role?.commandPolicy.requiresConfirmation ?? true;
  String? validationError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(role == null ? '新增角色配置' : '编辑角色配置'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (validationError != null) _DialogError(validationError!),
                _DialogField(controller: name, label: '角色名称'),
                _DialogField(controller: description, label: '角色描述'),
                _DialogField(
                  controller: identity,
                  label: '身份提示词',
                  minLines: 2,
                  maxLines: 4,
                ),
                _DialogField(
                  controller: goal,
                  label: '目标提示词',
                  minLines: 2,
                  maxLines: 4,
                ),
                _DialogField(
                  controller: constraint,
                  label: '约束提示词',
                  minLines: 2,
                  maxLines: 4,
                ),
                _DialogField(
                  controller: outputFormat,
                  label: '输出格式提示词',
                  minLines: 2,
                  maxLines: 4,
                ),
                _DialogField(
                  controller: allowedCommands,
                  label: '允许命令（一行一个）',
                  minLines: 2,
                  maxLines: 4,
                ),
                _DialogField(
                  controller: blockedCommands,
                  label: '禁止命令（一行一个）',
                  minLines: 2,
                  maxLines: 4,
                ),
                _DialogField(
                  controller: allowedDirectories,
                  label: '允许目录（一行一个，留空不限）',
                  minLines: 2,
                  maxLines: 4,
                ),
                CheckboxListTile(
                  value: requiresConfirmation,
                  onChanged: (value) =>
                      setDialogState(() => requiresConfirmation = value!),
                  title: const Text('命令需要确认'),
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: canReadProject,
                  onChanged: (value) =>
                      setDialogState(() => canReadProject = value!),
                  title: const Text('允许读取项目'),
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: canProposePatch,
                  onChanged: (value) =>
                      setDialogState(() => canProposePatch = value!),
                  title: const Text('允许生成补丁'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final next = role == null
                    ? RoleTemplate(
                        id: 'role-${DateTime.now().microsecondsSinceEpoch}',
                        name: name.text.trim(),
                        description: description.text.trim(),
                        identityPrompt: identity.text.trim(),
                        goalPrompt: goal.text.trim(),
                        constraintPrompt: constraint.text.trim(),
                        outputFormatPrompt: outputFormat.text.trim(),
                        commandPolicy: CommandPolicy(
                          allowedCommands: _splitLines(allowedCommands.text),
                          blockedCommands: _splitLines(blockedCommands.text),
                          allowedDirectories:
                              _splitLines(allowedDirectories.text),
                          requiresConfirmation: requiresConfirmation,
                        ),
                        canReadProject: canReadProject,
                        canProposePatch: canProposePatch,
                      )
                    : role.copyWith(
                        name: name.text.trim(),
                        description: description.text.trim(),
                        identityPrompt: identity.text.trim(),
                        goalPrompt: goal.text.trim(),
                        constraintPrompt: constraint.text.trim(),
                        outputFormatPrompt: outputFormat.text.trim(),
                        commandPolicy: CommandPolicy(
                          allowedCommands: _splitLines(allowedCommands.text),
                          blockedCommands: _splitLines(blockedCommands.text),
                          allowedDirectories:
                              _splitLines(allowedDirectories.text),
                          requiresConfirmation: requiresConfirmation,
                        ),
                        canReadProject: canReadProject,
                        canProposePatch: canProposePatch,
                      );
                if (role == null) {
                  controller.addRole(next);
                } else {
                  controller.updateRole(next);
                }
                Navigator.pop(context);
              } catch (exception) {
                setDialogState(() => validationError = exception.toString());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showMemberDialog(
  BuildContext context,
  AppController controller, {
  TeamMember? member,
}) async {
  final name = TextEditingController(text: member?.name ?? '');
  final priority = TextEditingController(
    text: (member?.executionPriority ?? 0).toString(),
  );
  var roleId = member?.roleId ?? controller.state.roles.first.id;
  var modelId = member?.modelId ?? controller.state.models.first.id;
  String? validationError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(member == null ? '新增团队成员' : '编辑团队成员'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (validationError != null) _DialogError(validationError!),
              _DialogField(controller: name, label: '成员名称'),
              _DialogField(controller: priority, label: '执行优先级'),
              DropdownButtonFormField<String>(
                initialValue: roleId,
                decoration: const InputDecoration(labelText: '角色'),
                items: controller.state.roles
                    .map(
                      (role) => DropdownMenuItem(
                        value: role.id,
                        child: Text(role.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => roleId = value!),
              ),
              DropdownButtonFormField<String>(
                initialValue: modelId,
                decoration: const InputDecoration(labelText: '模型'),
                items: controller.state.models
                    .map(
                      (model) => DropdownMenuItem(
                        value: model.id,
                        child: Text(model.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => modelId = value!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              try {
                final executionPriority = int.tryParse(priority.text.trim());
                if (executionPriority == null) {
                  throw ArgumentError('执行优先级必须是整数');
                }
                final next = TeamMember(
                  id: member?.id ??
                      'member-${DateTime.now().microsecondsSinceEpoch}',
                  name: name.text.trim(),
                  roleId: roleId,
                  modelId: modelId,
                  isSecretary: member?.isSecretary ?? false,
                  executionPriority: executionPriority,
                );
                if (member == null) {
                  controller.addMember(next);
                } else {
                  controller.updateMember(next);
                }
                Navigator.pop(context);
              } catch (exception) {
                setDialogState(() => validationError = exception.toString());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showWorkspacePatchDialog(
  BuildContext context,
  AppController controller,
) async {
  var workspaceId = controller.state.workspaces.first.id;
  var memberName = controller.currentMembers
      .firstWhere(
        (member) => !member.isSecretary,
        orElse: () => controller.currentMembers.first,
      )
      .name;
  final relativePath = TextEditingController();
  final proposedContent = TextEditingController();
  String? validationError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('创建补丁提案'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (validationError != null) _DialogError(validationError!),
              DropdownButtonFormField<String>(
                initialValue: workspaceId,
                decoration: const InputDecoration(labelText: '工作区'),
                items: controller.state.workspaces
                    .map(
                      (workspace) => DropdownMenuItem(
                        value: workspace.id,
                        child: Text(workspace.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setDialogState(() => workspaceId = value!),
              ),
              DropdownButtonFormField<String>(
                initialValue: memberName,
                decoration: const InputDecoration(labelText: '提案成员'),
                items: controller.currentMembers
                    .map(
                      (member) => DropdownMenuItem(
                        value: member.name,
                        child: Text(member.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => memberName = value!),
              ),
              _DialogField(controller: relativePath, label: '相对路径'),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: proposedContent,
                  minLines: 8,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: '目标文件内容',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton.icon(
            onPressed: () async {
              try {
                final content = await controller.readWorkspaceFile(
                  workspaceId: workspaceId,
                  relativePath: relativePath.text.trim(),
                );
                proposedContent.text = content;
                setDialogState(() => validationError = null);
              } catch (exception) {
                setDialogState(() => validationError = exception.toString());
              }
            },
            icon: const Icon(Icons.file_open_rounded),
            label: const Text('读取文件'),
          ),
          FilledButton.icon(
            onPressed: () async {
              try {
                await controller.proposeWorkspacePatch(
                  workspaceId: workspaceId,
                  relativePath: relativePath.text.trim(),
                  proposedContent: proposedContent.text,
                  memberName: memberName,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                }
              } catch (exception) {
                setDialogState(() => validationError = exception.toString());
              }
            },
            icon: const Icon(Icons.difference_rounded),
            label: const Text('创建补丁'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showWorkspaceFilesDialog(
  BuildContext context,
  AppController controller,
) async {
  var workspaceId = controller.state.workspaces.first.id;
  var filesFuture = controller.listWorkspaceFiles(workspaceId: workspaceId);
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('工作区文件'),
        content: SizedBox(
          width: 520,
          height: 420,
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: workspaceId,
                decoration: const InputDecoration(labelText: '工作区'),
                items: controller.state.workspaces
                    .map(
                      (workspace) => DropdownMenuItem(
                        value: workspace.id,
                        child: Text(workspace.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() {
                  workspaceId = value!;
                  filesFuture =
                      controller.listWorkspaceFiles(workspaceId: workspaceId);
                }),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder<List<String>>(
                  future: filesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _DialogError('读取文件列表失败：${snapshot.error}');
                    }
                    final files = snapshot.data ?? const [];
                    if (files.isEmpty) {
                      return const Center(child: Text('没有可显示的文件'));
                    }
                    return ListView.builder(
                      itemCount: files.length,
                      itemBuilder: (context, index) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.description_rounded),
                        title: SelectableText(files[index]),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showCommandDialog(
  BuildContext context,
  AppController controller,
) async {
  final command = TextEditingController(text: 'flutter test');
  final workingDirectory = TextEditingController(
    text: controller.state.workspaces.isEmpty
        ? Directory.current.path
        : controller.state.workspaces.first.path,
  );
  var memberId = controller.currentMembers
      .firstWhere(
        (member) => !member.isSecretary,
        orElse: () => controller.currentMembers.first,
      )
      .id;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('创建命令请求'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: memberId,
                decoration: const InputDecoration(labelText: '成员'),
                items: controller.currentMembers
                    .map(
                      (member) => DropdownMenuItem(
                        value: member.id,
                        child: Text(member.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => memberId = value!),
              ),
              _DialogField(controller: workingDirectory, label: '工作目录'),
              _DialogField(controller: command, label: '命令'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              controller.requestCommand(
                memberId: memberId,
                command: command.text.trim(),
                workingDirectory: workingDirectory.text.trim(),
              );
              Navigator.pop(context);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showExportDialog(
  BuildContext context,
  AppController controller,
) async {
  var includeSecrets = false;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('导入 / 导出配置'),
        content: CheckboxListTile(
          value: includeSecrets,
          onChanged: (value) => setDialogState(() => includeSecrets = value!),
          title: const Text('导出时包含 API Key'),
          subtitle: const Text('包含密钥的文件只适合本机迁移，请谨慎保存。'),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await controller.importConfiguration();
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.file_open_rounded),
            label: const Text('从 import.json 导入'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await controller.exportConfiguration(
                includeSecrets: includeSecrets,
              );
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            icon: const Icon(Icons.ios_share_rounded),
            label: Text(includeSecrets ? '确认导出密钥' : '导出脱敏配置'),
          ),
        ],
      ),
    ),
  );
}

class _DialogError extends StatelessWidget {
  const _DialogError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Color(0xFFBE123C)),
      ),
    );
  }
}

void _runConfigAction(
  BuildContext context,
  VoidCallback action,
) {
  try {
    action();
  } catch (exception) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(exception.toString())),
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    this.obscure = false,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        minLines: obscure ? 1 : minLines,
        maxLines: obscure ? 1 : maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

List<String> _splitLines(String text) => text
    .split(RegExp(r'[\r\n,]+'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();

String _roleName(AppState state, String roleId) =>
    state.roles.firstWhere((role) => role.id == roleId).name;

String _modelName(AppState state, String modelId) =>
    state.models.firstWhere((model) => model.id == modelId).name;

String _conversationTitle(AppController controller, Conversation conversation) {
  if (conversation.memberId == null) {
    return '群聊 · ${controller.currentTeam.name}';
  }
  return '私聊 · ${conversation.title}';
}

String _messageTimeText(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _auditLogTimeText(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute:$second';
}

String _conversationMeta(AppController controller, Conversation conversation) {
  final status = _statusText(conversation.status);
  if (conversation.memberId == null) {
    return '${controller.currentMembers.length} 位成员 · 第 ${conversation.currentRound} 轮 · $status';
  }
  final member = controller.currentMembers.firstWhere(
    (item) => item.id == conversation.memberId,
  );
  return '${_roleName(controller.state, member.roleId)} · ${_modelName(controller.state, member.modelId)} · $status';
}

String _inputHint(AppController controller, Conversation conversation) {
  if (conversation.memberId == null) {
    return '发给 ${controller.currentTeam.name}';
  }
  return '发给 ${conversation.title}';
}

String _avatarText(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
}

Color _avatarColor(String name) {
  if (name == '秘书') {
    return const Color(0xFF22C55E);
  }
  if (name.contains('测试')) {
    return const Color(0xFFF59E0B);
  }
  if (name.contains('前端')) {
    return const Color(0xFF3B82F6);
  }
  return const Color(0xFF64748B);
}

String _conversationPreview(Conversation conversation) {
  if (conversation.messages.isEmpty) {
    return '暂无消息';
  }
  final message = conversation.messages.last;
  return '${message.authorName}: ${message.content}'.replaceAll('\n', ' ');
}

String? _normalizedThinkingContent(ChatMessage message) {
  final thinkingContent = message.thinkingContent;
  if (thinkingContent == null || thinkingContent.trim().isEmpty) {
    return null;
  }
  return thinkingContent;
}

String _thinkingTitle(ChatMessage message) {
  final duration = _messageGenerationDurationText(message);
  return switch (message.generationStatus) {
    ChatMessageGenerationStatus.streaming => '思考中… $duration',
    ChatMessageGenerationStatus.failed => '思考失败 · $duration',
    ChatMessageGenerationStatus.stopped => '思考已停止 · $duration',
    ChatMessageGenerationStatus.complete =>
      message.generationDurationMs == null ? '思考过程' : '已完成思考 · $duration',
  };
}

String? _messageInlineGenerationStatus(ChatMessage message) {
  final duration = _messageGenerationDurationText(message);
  return switch (message.generationStatus) {
    ChatMessageGenerationStatus.failed => '失败 · $duration',
    ChatMessageGenerationStatus.stopped => '已停止 · $duration',
    _ => null,
  };
}

bool _isAwaitingFirstModelOutput(ChatMessage message) {
  return !message.isUser &&
      message.generationStatus == ChatMessageGenerationStatus.streaming &&
      message.content.trim().isEmpty &&
      (message.thinkingContent?.trim().isEmpty ?? true);
}

String _messageGenerationDurationText(ChatMessage message) {
  final milliseconds =
      message.generationStatus == ChatMessageGenerationStatus.streaming
          ? DateTime.now().difference(message.createdAt).inMilliseconds
          : message.generationDurationMs ?? 0;
  final seconds = (milliseconds / 1000).ceil().clamp(0, 9999);
  return '${seconds}s';
}

IconData _conversationListIcon(
  AppController controller,
  Conversation conversation,
) {
  if (conversation.memberId == null) {
    return Icons.forum_rounded;
  }
  final member = controller.state.members.firstWhere(
    (item) => item.id == conversation.memberId,
  );
  return member.isSecretary
      ? Icons.assignment_ind_rounded
      : Icons.person_rounded;
}

String _conversationListTitle(
  AppController controller,
  Conversation conversation,
) {
  if (conversation.memberId == null) {
    return controller.state.teams
        .firstWhere((team) => team.id == conversation.teamId)
        .name;
  }
  return conversation.title;
}

String _conversationListSubtitle(
  AppController controller,
  Conversation conversation,
) {
  if (conversation.memberId == null) {
    return _conversationPreview(conversation);
  }
  final member = controller.state.members.firstWhere(
    (item) => item.id == conversation.memberId,
  );
  return _privateConversationPreview(controller, conversation, member);
}

String? _conversationListBadge(
  AppController controller,
  Conversation conversation,
) {
  if (conversation.memberId == null) {
    return controller.state.teams
        .firstWhere((team) => team.id == conversation.teamId)
        .memberIds
        .length
        .toString();
  }
  final member = controller.state.members.firstWhere(
    (item) => item.id == conversation.memberId,
  );
  return member.isSecretary ? 'BOT' : null;
}

String _privateConversationPreview(
  AppController controller,
  Conversation conversation,
  TeamMember member,
) {
  if (conversation.messages.length > 1) {
    return _conversationPreview(conversation);
  }
  return _roleName(controller.state, member.roleId);
}

List<TeamMember> _typingMembers(
  AppController controller,
  Conversation conversation,
) {
  if (conversation.status != ConversationStatus.running) {
    return const [];
  }
  final streamingMemberIds = conversation.messages
      .where(
        (message) =>
            message.generationStatus == ChatMessageGenerationStatus.streaming &&
            message.memberId != null,
      )
      .map((message) => message.memberId!)
      .toSet();
  final memberId = conversation.memberId;
  if (memberId != null) {
    if (streamingMemberIds.contains(memberId)) {
      return const [];
    }
    return [
      controller.state.members.firstWhere((member) => member.id == memberId),
    ];
  }
  final runningAssignments = controller.currentTaskAssignments
      .where((assignment) => assignment.status == TaskAssignmentStatus.running)
      .toList();
  if (runningAssignments.isEmpty) {
    final fallback = controller.currentMembers.firstWhere(
      (member) => !member.isSecretary,
      orElse: () => controller.currentMembers.first,
    );
    return streamingMemberIds.contains(fallback.id) ? const [] : [fallback];
  }
  return runningAssignments
      .map(
        (assignment) => controller.state.members.firstWhere(
          (member) => member.id == assignment.memberId,
        ),
      )
      .where((member) => !streamingMemberIds.contains(member.id))
      .toList();
}

int _queuedTaskSort(QueuedTask a, QueuedTask b) {
  final priority = b.priority.compareTo(a.priority);
  if (priority != 0) {
    return priority;
  }
  return a.createdAt.compareTo(b.createdAt);
}

QueuedTask? _firstQueuedTaskOrNull(List<QueuedTask> tasks) {
  if (tasks.isEmpty) {
    return null;
  }
  return tasks.first;
}

QueuedTask? _firstTaskWithStatus(
  List<QueuedTask> tasks,
  QueuedTaskStatus status,
) {
  for (final task in tasks) {
    if (task.status == status) {
      return task;
    }
  }
  return null;
}

String _initialConversationId(AppState state) {
  if (state.queuedTasks.isNotEmpty) {
    return state.queuedTasks.first.conversationId;
  }
  return state.conversations
      .firstWhere(
        (conversation) => conversation.memberId != null,
        orElse: () => state.conversations.first,
      )
      .id;
}

String _queuedTaskStatusText(QueuedTaskStatus status) {
  return switch (status) {
    QueuedTaskStatus.pending => '待执行',
    QueuedTaskStatus.running => '执行中',
    QueuedTaskStatus.paused => '已暂停',
    QueuedTaskStatus.completed => '已完成',
    QueuedTaskStatus.failed => '失败',
  };
}

Conversation _createTeamConversation(Team team) {
  return Conversation(
    id: 'conv-${team.id}',
    title: '团队会话',
    teamId: team.id,
    memberId: null,
    messages: [
      ChatMessage(
        id: 'msg-welcome-${team.id}',
        authorName: '秘书',
        memberId: team.secretaryMemberId,
        content: '把开发任务发到这里，我会分配给团队成员并汇总结果。',
        createdAt: DateTime.now(),
      ),
    ],
  );
}

Conversation _createMemberConversation(String teamId, TeamMember member) {
  return Conversation(
    id: 'conv-$teamId-${member.id}',
    title: member.name,
    teamId: teamId,
    memberId: member.id,
    messages: [
      ChatMessage(
        id: 'msg-welcome-$teamId-${member.id}',
        authorName: member.name,
        memberId: member.id,
        content: '这里是和${member.name}的独立会话。',
        createdAt: DateTime.now(),
      ),
    ],
  );
}

bool _isGeneratedWelcomeOnlyMemberConversation(Conversation conversation) {
  final memberId = conversation.memberId;
  if (memberId == null || conversation.teamId == 'team-default') {
    return false;
  }
  if (conversation.id != 'conv-${conversation.teamId}-$memberId' ||
      conversation.messages.length != 1) {
    return false;
  }
  final message = conversation.messages.single;
  return message.id == 'msg-welcome-${conversation.teamId}-$memberId' &&
      message.memberId == memberId;
}

String _relativeWorkspacePath(String rootPath, String entityPath) {
  final normalizedRoot = rootPath.replaceAll('\\', '/');
  final normalizedEntity = entityPath.replaceAll('\\', '/');
  if (normalizedEntity == normalizedRoot) {
    return '';
  }
  return normalizedEntity.substring(normalizedRoot.length + 1);
}

bool _isHiddenWorkspacePath(String relativePath) {
  return relativePath
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .any((segment) => segment.startsWith('.'));
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final trimmed = normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
  final index = trimmed.lastIndexOf('/');
  return index >= 0 ? trimmed.substring(index + 1) : trimmed;
}

String _statusText(ConversationStatus status) {
  return switch (status) {
    ConversationStatus.idle => '待命',
    ConversationStatus.running => '运行中',
    ConversationStatus.paused => '已暂停',
    ConversationStatus.stopped => '已停止',
    ConversationStatus.failed => '失败',
  };
}

String _collaborationModeLabel(TeamCollaborationMode mode) {
  return switch (mode) {
    TeamCollaborationMode.serial => '串行',
    TeamCollaborationMode.parallel => '并行',
  };
}

String _taskStatusText(TaskAssignmentStatus status) {
  return switch (status) {
    TaskAssignmentStatus.pending => '待执行',
    TaskAssignmentStatus.running => '执行中',
    TaskAssignmentStatus.completed => '已完成',
    TaskAssignmentStatus.failed => '失败',
    TaskAssignmentStatus.cancelled => '已取消',
  };
}

Color _taskStatusColor(TaskAssignmentStatus status) {
  return switch (status) {
    TaskAssignmentStatus.pending => const Color(0xFF6B7280),
    TaskAssignmentStatus.running => const Color(0xFF2563EB),
    TaskAssignmentStatus.completed => const Color(0xFF047857),
    TaskAssignmentStatus.failed => const Color(0xFFBE123C),
    TaskAssignmentStatus.cancelled => const Color(0xFF92400E),
  };
}
