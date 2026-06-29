import 'dart:io';

import '../core/commands/command_service.dart';
import '../core/domain.dart';
import '../core/patching.dart';
import '../core/workspace/workspace_service.dart';
import 'app_controller_helpers.dart';

typedef AppStateReader = AppState Function();
typedef AppStateCommitter = void Function(AppState state);

class WorkspaceCommandController {
  const WorkspaceCommandController({
    required this.readState,
    required this.commit,
    this.workspaceService = const WorkspaceService(),
    this.commandService = const CommandService(),
  });

  final AppStateReader readState;
  final AppStateCommitter commit;
  final WorkspaceService workspaceService;
  final CommandService commandService;

  AppState get state => readState();

  void addWorkspacePath(String path) {
    final normalized = Directory(path).absolute.path;
    final workspace = ProjectWorkspace(
      id: 'workspace-${DateTime.now().microsecondsSinceEpoch}',
      name: pathBasename(normalized),
      path: normalized,
    );
    commit(
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
    commit(
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
    commit(
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
    commit(
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
    commit(
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

  Future<String?> applyPatch(PatchProposal proposal) async {
    final index =
        state.patchProposals.indexWhere((item) => item.id == proposal.id);
    if (index < 0) {
      return null;
    }
    try {
      final applied = await PatchApplier().apply(proposal);
      final proposals = [...state.patchProposals];
      proposals[index] = applied;
      commit(
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
      return null;
    } catch (exception) {
      return exception.toString();
    }
  }

  void rejectPatch(PatchProposal proposal) {
    final index =
        state.patchProposals.indexWhere((item) => item.id == proposal.id);
    if (index < 0) {
      return;
    }
    final proposals = [...state.patchProposals];
    proposals[index] = proposal.copyWith(status: PatchStatus.rejected);
    commit(
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
