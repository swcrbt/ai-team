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
                final railWidth =
                    (constraints.maxWidth * 0.24).clamp(180.0, 244.0);
                final inspectorWidth =
                    (constraints.maxWidth * 0.32).clamp(248.0, 332.0);
                return Row(
                  children: [
                    SizedBox(
                      width: railWidth,
                      child: _ConversationRail(controller: controller),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _ChatPane(controller: controller),
                    ),
                    const VerticalDivider(width: 1),
                    SizedBox(
                      width: inspectorWidth,
                      child: _InspectorPane(controller: controller),
                    ),
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

  Future<void> dispatch(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isDispatching) {
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
  }

  void _validateRole(RoleTemplate role) {
    if (role.name.trim().isEmpty) {
      throw ArgumentError('角色名称不能为空');
    }
    if (role.identityPrompt.trim().isEmpty) {
      throw ArgumentError('角色身份提示词不能为空');
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

class _ConversationRail extends StatelessWidget {
  const _ConversationRail({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF7F8FA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.hub_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'AI Team',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
              ],
            ),
          ),
          _RailSection(
            title: '团队',
            children: [
              _RailTile(
                icon: Icons.forum_rounded,
                title: '团队会话',
                subtitle: controller.currentTeam.name,
                selected: controller.selectedConversationId ==
                    controller.teamConversation.id,
                onTap: () => controller
                    .selectConversation(controller.teamConversation.id),
              ),
            ],
          ),
          _RailSection(
            title: '成员私聊',
            children: controller.currentMembers
                .map(
                  (member) => _RailTile(
                    icon: member.isSecretary
                        ? Icons.assignment_ind_rounded
                        : Icons.person_rounded,
                    title: member.name,
                    subtitle: _roleName(controller.state, member.roleId),
                    selected: controller.selectedConversationId ==
                        controller.conversationForMember(member.id).id,
                    onTap: () => controller.selectConversation(
                      controller.conversationForMember(member.id).id,
                    ),
                  ),
                )
                .toList(),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: () => _showExportDialog(context, controller),
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('导入 / 导出配置'),
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
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: selected
              ? const BorderSide(color: Color(0xFFE5E7EB))
              : BorderSide.none,
        ),
        child: ListTile(
          dense: true,
          onTap: onTap,
          leading: Icon(icon, size: 18),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle:
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    return Column(
      children: [
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${conversation.title} · ${widget.controller.currentTeam.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '第 ${conversation.currentRound} 轮 · ${_statusText(conversation.status)}',
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
              _StatusButton(
                icon: Icons.play_arrow_rounded,
                label: '继续',
                onPressed: conversation.status == ConversationStatus.paused
                    ? widget.controller.resumeConversation
                    : null,
              ),
              _StatusButton(
                icon: Icons.stop_rounded,
                label: '停止',
                onPressed: conversation.status != ConversationStatus.stopped
                    ? widget.controller.stopConversation
                    : null,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: conversation.messages.length,
            itemBuilder: (context, index) {
              return _MessageBubble(message: conversation.messages[index]);
            },
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
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: textController,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: '像飞书聊天一样描述任务，秘书会自动分配给团队成员',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: widget.controller.isDispatching ? null : _submit,
                child: widget.controller.isDispatching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
              ),
            ],
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
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 680),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: alignRight ? const Color(0xFFEFF6FF) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.authorName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(message.content),
          ],
        ),
      ),
    );
  }
}

class _InspectorPane extends StatelessWidget {
  const _InspectorPane({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _Panel(
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
                      value: '${model.modelName}\n${model.baseUrl}',
                      actions: [
                        IconButton(
                          tooltip: '编辑模型',
                          onPressed: () => _showModelDialog(context, controller,
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
          ),
          _Panel(
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
                                    () => controller.deleteMember(member.id),
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
          ),
          _Panel(
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
                          onDeny: () => controller.updateCommandRequestStatus(
                            request.id,
                            CommandRequestStatus.denied,
                          ),
                          onExecute: () => controller.executeCommandRequest(
                            request.id,
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          _Panel(
            title: '补丁确认',
            icon: Icons.difference_rounded,
            child: Column(
              children: controller.patchProposals
                  .map(
                    (patch) => _PatchCard(
                      patch: patch,
                      onApply: () => controller.applyPatch(patch),
                      onReject: () => controller.rejectPatch(patch),
                    ),
                  )
                  .toList(),
            ),
          ),
          _Panel(
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
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
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

class _PatchCard extends StatelessWidget {
  const _PatchCard({
    required this.patch,
    required this.onApply,
    required this.onReject,
  });

  final PatchProposal patch;
  final VoidCallback onApply;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${patch.memberName} · ${patch.status.name}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          SelectableText(
            patch.diff,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: patch.status == PatchStatus.pending ? onApply : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text('应用'),
              ),
              OutlinedButton.icon(
                onPressed:
                    patch.status == PatchStatus.pending ? onReject : null,
                icon: const Icon(Icons.close_rounded),
                label: const Text('拒绝'),
              ),
            ],
          ),
        ],
      ),
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
                final next = ModelProfile(
                  id: model?.id ??
                      'model-${DateTime.now().microsecondsSinceEpoch}',
                  name: name.text.trim(),
                  baseUrl: baseUrl.text.trim(),
                  modelName: modelName.text.trim(),
                  apiKey: apiKey.text.trim(),
                  streaming: model?.streaming ?? true,
                  temperature: model?.temperature ?? 0.4,
                  maxTokens: model?.maxTokens ?? 1600,
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
  final identity = TextEditingController(text: role?.identityPrompt ?? '');
  String? validationError;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(role == null ? '新增角色配置' : '编辑角色配置'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (validationError != null) _DialogError(validationError!),
              _DialogField(controller: name, label: '角色名称'),
              _DialogField(controller: identity, label: '身份提示词'),
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
                final next = role == null
                    ? RoleTemplate(
                        id: 'role-${DateTime.now().microsecondsSinceEpoch}',
                        name: name.text.trim(),
                        description: '自定义角色',
                        identityPrompt: identity.text.trim(),
                        goalPrompt: '按团队目标完成任务。',
                        constraintPrompt: '遵守权限配置，不直接写入文件。',
                        outputFormatPrompt: '输出结论、证据和下一步。',
                        commandPolicy: const CommandPolicy(
                          allowedCommands: ['flutter test', 'dart analyze'],
                          blockedCommands: ['rm', 'sudo'],
                          allowedDirectories: [],
                          requiresConfirmation: true,
                        ),
                      )
                    : role.copyWith(
                        name: name.text.trim(),
                        identityPrompt: identity.text.trim(),
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
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

String _roleName(AppState state, String roleId) =>
    state.roles.firstWhere((role) => role.id == roleId).name;

String _modelName(AppState state, String modelId) =>
    state.models.firstWhere((model) => model.id == modelId).name;

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
