import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'core/domain.dart';
import 'core/file_dialogs.dart';
import 'core/local_store.dart';
import 'core/model_gateway.dart';
import 'core/orchestrator.dart';
import 'core/patching.dart';

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
  final ValueChanged<AppState>? onStateChanged;
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
  final ValueChanged<AppState>? onStateChanged;
  final FileDialogService fileDialogs;

  @override
  State<AiTeamHome> createState() => _AiTeamHomeState();
}

class _AiTeamHomeState extends State<AiTeamHome> {
  late AppController controller;
  _MainView mainView = _MainView.chat;
  String? focusedSettingsSection;

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
                          controller.selectConversation(
                            controller.teamConversation.id,
                          );
                          setState(() => mainView = _MainView.chat);
                        },
                        onProject: () => setState(() {
                          mainView = _MainView.settings;
                          focusedSettingsSection = '项目工作区';
                        }),
                        onSettings: () => setState(() {
                          mainView = _MainView.settings;
                          focusedSettingsSection = null;
                        }),
                      ),
                    ),
                    if (mainView == _MainView.settings)
                      Expanded(
                        child: _SettingsPage(
                          controller: controller,
                          focusedSection: focusedSettingsSection,
                          onBack: () =>
                              setState(() => mainView = _MainView.chat),
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
                            setState(() {
                              mainView = _MainView.chat;
                              focusedSettingsSection = null;
                            });
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

enum _MainView { chat, settings }

class AppController extends ChangeNotifier {
  AppController(
    AppState initialState,
    this.orchestrator, {
    this.onStateChanged,
    this.fileDialogs = const SystemFileDialogService(),
    JsonLocalStore? exportStore,
  })  : state = _ensureMemberConversations(initialState),
        exportStore = exportStore ?? JsonLocalStore.defaultStore(),
        selectedConversationId =
            _initialConversationId(_ensureMemberConversations(initialState));

  AppState state;
  String selectedConversationId;
  final TeamOrchestrator orchestrator;
  final ValueChanged<AppState>? onStateChanged;
  final FileDialogService fileDialogs;
  final JsonLocalStore exportStore;
  bool isDispatching = false;
  String? error;
  ModelRequestCancellation? _activeCancellation;
  ConversationStatus? _requestedCancellationStatus;

  Team get currentTeam => state.teams.first;

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

  Conversation get currentConversation => state.conversations.firstWhere(
        (item) => item.id == selectedConversationId,
        orElse: () => state.conversations.firstWhere(
          (item) => item.teamId == currentTeam.id && item.memberId == null,
        ),
      );

  Conversation get teamConversation => state.conversations.firstWhere(
        (item) => item.teamId == currentTeam.id && item.memberId == null,
      );

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
    notifyListeners();
  }

  bool _canDispatchCurrentConversation() {
    final status = currentConversation.status;
    if (status == ConversationStatus.paused) {
      error = '当前会话已暂停，请先点击继续。';
      return false;
    }
    if (status == ConversationStatus.stopped) {
      error = '当前会话已停止，不能继续调度。';
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
            teamId: currentTeam.id,
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
        conversations: [
          ...state.conversations,
          _createMemberConversation(currentTeam.id, member),
        ],
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
    _commit(
      state.copyWith(
        conversations: state.conversations
            .map((item) => item.id == updated.id ? updated : item)
            .toList(),
        taskAssignments: _cancelOpenAssignments(
          state.taskAssignments,
          updated.id,
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

  void _commit(AppState nextState) {
    state = _ensureMemberConversations(nextState);
    if (!state.conversations.any((item) => item.id == selectedConversationId)) {
      selectedConversationId = _initialConversationId(state);
    }
    onStateChanged?.call(state);
    notifyListeners();
  }

  ModelProfile _requireModel(String modelId) {
    return state.models.firstWhere(
      (model) => model.id == modelId,
      orElse: () => throw StateError('模型不存在: $modelId'),
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
    required this.onProject,
    required this.onSettings,
  });

  final _MainView selectedView;
  final VoidCallback onChat;
  final VoidCallback onTeam;
  final VoidCallback onProject;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF25324A),
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
          _SidebarButton(
            icon: Icons.chat_bubble_rounded,
            label: '消息',
            selected: selectedView == _MainView.chat,
            onPressed: onChat,
          ),
          _SidebarButton(
            icon: Icons.groups_rounded,
            label: '团队',
            selected: false,
            onPressed: onTeam,
          ),
          _SidebarButton(
            icon: Icons.folder_copy_rounded,
            label: '项目',
            selected: false,
            onPressed: onProject,
          ),
          const Spacer(),
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
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _RailSection(
                  title: '群聊',
                  children: [
                    _RailTile(
                      icon: Icons.forum_rounded,
                      title: controller.currentTeam.name,
                      subtitle:
                          _conversationPreview(controller.teamConversation),
                      badge: '${controller.currentMembers.length}',
                      selected: selectedView == _MainView.chat &&
                          controller.selectedConversationId ==
                              controller.teamConversation.id,
                      onTap: () =>
                          onSelectConversation(controller.teamConversation.id),
                    ),
                  ],
                ),
                _RailSection(
                  title: '私聊',
                  children: controller.currentMembers
                      .map(
                        (member) => _RailTile(
                          icon: member.isSecretary
                              ? Icons.assignment_ind_rounded
                              : Icons.person_rounded,
                          title: member.name,
                          subtitle: _memberConversationPreview(
                            controller,
                            member,
                          ),
                          badge: member.isSecretary ? 'BOT' : null,
                          selected: selectedView == _MainView.chat &&
                              controller.selectedConversationId ==
                                  controller
                                      .conversationForMember(member.id)
                                      .id,
                          onTap: () => onSelectConversation(
                            controller.conversationForMember(member.id).id,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailSection extends StatelessWidget {
  const _RailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 6),
            child: Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(0),
          side: selected
              ? const BorderSide(color: Color(0xFFE5E7EB))
              : BorderSide.none,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: selected
                ? const Border(
                    left: BorderSide(color: Color(0xFF2563EB), width: 3),
                  )
                : null,
          ),
          child: ListTile(
            dense: true,
            minLeadingWidth: 38,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onTap: onTap,
            leading: CircleAvatar(
              radius: 20,
              backgroundColor:
                  selected ? const Color(0xFFDCFCE7) : const Color(0xFFEFF6FF),
              child: Icon(icon, size: 18, color: const Color(0xFF2563EB)),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
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

class _ChatPaneState extends State<_ChatPane> {
  final textController = TextEditingController();

  @override
  void dispose() {
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.controller.currentConversation;
    final pendingPatches = widget.controller.patchProposals
        .where((patch) => patch.status == PatchStatus.pending)
        .toList();
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
              _StatusButton(
                icon: Icons.pause_rounded,
                label: '暂停',
                onPressed: widget.controller.isDispatching
                    ? widget.controller.pauseConversation
                    : null,
              ),
            ],
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: const Color(0xFFFCFCFD),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
              itemCount: conversation.messages.length + pendingPatches.length,
              itemBuilder: (context, index) {
                if (index < conversation.messages.length) {
                  return _MessageBubble(message: conversation.messages[index]);
                }
                final patch =
                    pendingPatches[index - conversation.messages.length];
                return _ChatPatchConfirmationCard(
                  patch: patch,
                  onApply: () => widget.controller.applyPatch(patch),
                  onReject: () => widget.controller.rejectPatch(patch),
                );
              },
            ),
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
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
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
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final alignRight = message.isUser;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 680),
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: alignRight ? const Color(0xFFE8F1FF) : Colors.white,
        border: Border.all(
          color: alignRight ? const Color(0xFFCFE0FF) : const Color(0xFFE5E7EB),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!alignRight) ...[
            Text(
              message.authorName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
          ],
          Text(message.content),
        ],
      ),
    );
    return Row(
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
        Flexible(child: bubble),
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
    );
  }
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.controller,
    required this.focusedSection,
    required this.onBack,
  });

  final AppController controller;
  final String? focusedSection;
  final VoidCallback onBack;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  final scrollController = ScrollController();
  final sectionKeys = {
    '模型配置': GlobalKey(),
    '角色配置': GlobalKey(),
    '团队成员': GlobalKey(),
    '项目工作区': GlobalKey(),
    '命令请求': GlobalKey(),
    '导入导出': GlobalKey(),
    '审计日志': GlobalKey(),
  };

  AppController get controller => widget.controller;

  VoidCallback get onBack => widget.onBack;

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    scrollToFocusedSection();
  }

  @override
  void didUpdateWidget(covariant _SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusedSection != oldWidget.focusedSection) {
      scrollToFocusedSection();
    }
  }

  void scrollToFocusedSection() {
    final section = widget.focusedSection;
    if (section == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      scrollToSection(section);
    });
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
          child: Row(
            children: [
              IconButton(
                tooltip: '返回聊天',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 8),
              const Expanded(
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
                    Text('模型、角色、团队和本地项目配置保存在本机'),
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
                  key: sectionKeys['模型配置'],
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
                                '${model.modelName}\n${model.baseUrl}\n流式: ${model.streaming ? '开' : '关'} · 温度: ${model.temperature} · 最大 Token: ${model.maxTokens}',
                            actions: [
                              IconButton(
                                tooltip: '编辑模型',
                                onPressed: () => _showModelDialog(
                                    context, controller,
                                    model: model),
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
                ),
                _Panel(
                  key: sectionKeys['角色配置'],
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
                                onPressed: () => _showRoleDialog(
                                    context, controller,
                                    role: role),
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
                ),
                _Panel(
                  key: sectionKeys['团队成员'],
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
                                '${_roleName(controller.state, member.roleId)} · ${_modelName(controller.state, member.modelId)}',
                            actions: [
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
                                          () => controller
                                              .deleteMember(member.id),
                                        ),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                        )
                        .toList(),
                  ),
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
                  key: sectionKeys['项目工作区'],
                  title: '项目工作区',
                  icon: Icons.folder_open_rounded,
                  action: Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        tooltip: '创建补丁',
                        onPressed: controller.state.workspaces.isEmpty
                            ? null
                            : () =>
                                _showWorkspacePatchDialog(context, controller),
                        icon: const Icon(Icons.difference_rounded),
                      ),
                      IconButton(
                        tooltip: '浏览文件',
                        onPressed: controller.state.workspaces.isEmpty
                            ? null
                            : () =>
                                _showWorkspaceFilesDialog(context, controller),
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
                _Panel(
                  key: sectionKeys['审计日志'],
                  title: '审计日志',
                  icon: Icons.receipt_long_rounded,
                  child: Column(
                    children: controller.state.auditLog.isEmpty
                        ? [const Text('暂无操作记录')]
                        : controller.state.auditLog
                            .map(
                              (entry) => _KeyValueRow(
                                label: entry.action,
                                value: entry.detail,
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
    (Icons.memory_rounded, '模型', '模型配置'),
    (Icons.badge_rounded, '角色', '角色配置'),
    (Icons.groups_rounded, '成员', '团队成员'),
    (Icons.folder_open_rounded, '项目', '项目工作区'),
    (Icons.terminal_rounded, '命令', '命令请求'),
    (Icons.ios_share_rounded, '导入导出', '导入导出'),
    (Icons.receipt_long_rounded, '审计', '审计日志'),
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
  String? validationError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(model == null ? '新增模型配置' : '编辑模型配置'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (validationError != null) _DialogError(validationError!),
              _DialogField(controller: name, label: '名称'),
              _DialogField(controller: baseUrl, label: 'Base URL'),
              _DialogField(controller: modelName, label: '模型名称'),
              _DialogField(controller: apiKey, label: 'API Key', obscure: true),
              SwitchListTile(
                value: streaming,
                onChanged: (value) => setDialogState(() => streaming = value),
                title: const Text('流式输出'),
                contentPadding: EdgeInsets.zero,
              ),
              _DialogField(controller: temperature, label: '温度 0-2'),
              _DialogField(controller: maxTokens, label: '最大 Token'),
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
                final next = TeamMember(
                  id: member?.id ??
                      'member-${DateTime.now().microsecondsSinceEpoch}',
                  name: name.text.trim(),
                  roleId: roleId,
                  modelId: modelId,
                  isSecretary: member?.isSecretary ?? false,
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

String _memberConversationPreview(
  AppController controller,
  TeamMember member,
) {
  final conversation = controller.conversationForMember(member.id);
  if (conversation.messages.length > 1) {
    return _conversationPreview(conversation);
  }
  return _roleName(controller.state, member.roleId);
}

String _initialConversationId(AppState state) {
  return state.conversations
      .firstWhere(
        (conversation) => conversation.memberId == null,
        orElse: () => state.conversations.first,
      )
      .id;
}

Conversation _createMemberConversation(String teamId, TeamMember member) {
  return Conversation(
    id: 'conv-${member.id}',
    title: member.name,
    teamId: teamId,
    memberId: member.id,
    messages: [
      ChatMessage(
        id: 'msg-welcome-${member.id}',
        authorName: member.name,
        memberId: member.id,
        content: '这里是和${member.name}的独立会话。',
        createdAt: DateTime.now(),
      ),
    ],
  );
}

AppState _ensureMemberConversations(AppState state) {
  final conversations = [...state.conversations];
  var changed = false;
  for (final team in state.teams) {
    for (final memberId in team.memberIds) {
      final hasConversation = conversations.any(
        (conversation) =>
            conversation.teamId == team.id && conversation.memberId == memberId,
      );
      if (hasConversation) {
        continue;
      }
      final member = state.members.firstWhere((item) => item.id == memberId);
      conversations.add(_createMemberConversation(team.id, member));
      changed = true;
    }
  }
  return changed ? state.copyWith(conversations: conversations) : state;
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
