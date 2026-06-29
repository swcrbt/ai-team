import 'dart:convert';

import '../commands/command_service.dart';
import '../domain.dart';
import '../model_gateway.dart';
import '../workspace/workspace_service.dart';
import 'assignment_helpers.dart';

Future<ToolExecutionOutcome> executeModelToolCalls({
  required AppState state,
  required String conversationId,
  required String? memberId,
  required String? messageId,
  required List<ModelToolCall> calls,
  required CommandRunner commandRunner,
  ModelRequestCancellation? cancellation,
}) async {
  var workingState = state;
  final results = <ModelToolResult>[];
  final displayBlocks = <ChatMessageContentBlock>[];
  for (final call in calls) {
    final result = await _executeModelToolCall(
      state: workingState,
      conversationId: conversationId,
      activeMemberId: memberId,
      messageId: messageId,
      call: call,
      commandRunner: commandRunner,
      cancellation: cancellation,
    );
    workingState = result.workingState;
    results.add(result.result);
    displayBlocks.addAll(result.displayBlocks);
  }
  return ToolExecutionOutcome(
    workingState: workingState,
    round: ModelToolRound(calls: calls, results: results),
    displayBlocks: displayBlocks,
  );
}

Future<SingleToolExecutionOutcome> _executeModelToolCall({
  required AppState state,
  required String conversationId,
  required String? activeMemberId,
  required String? messageId,
  required ModelToolCall call,
  required CommandRunner commandRunner,
  ModelRequestCancellation? cancellation,
}) async {
  if (cancellation?.isCancelled == true) {
    return _toolFailure(state, call, '工具调用已取消');
  }
  try {
    final arguments = _decodeToolArguments(call.arguments);
    switch (call.name) {
      case 'list_workspace_files':
        final files = await _listWorkspaceFiles(
          state,
          workspaceId: _requiredString(arguments, 'workspaceId'),
          maxFiles: _optionalPositiveInt(arguments, 'maxFiles') ?? 500,
        );
        return _toolSuccess(
          state,
          call,
          {
            'files': files,
          },
        );
      case 'read_workspace_file':
        final content = await _readWorkspaceFile(
          state,
          workspaceId: _requiredString(arguments, 'workspaceId'),
          relativePath: _requiredString(arguments, 'relativePath'),
        );
        return _toolSuccess(
          state,
          call,
          {
            'content': content,
          },
        );
      case 'propose_workspace_patch':
        return await _proposeWorkspacePatchTool(
          state,
          call,
          activeMemberId: activeMemberId,
          arguments: arguments,
        );
      case 'request_command':
        return _requestCommandTool(
          state,
          call,
          conversationId: conversationId,
          activeMemberId: activeMemberId,
          messageId: messageId,
          commandRunner: commandRunner,
          arguments: arguments,
        );
      default:
        return _toolFailure(state, call, '未知工具: ${call.name}');
    }
  } catch (error) {
    return _toolFailure(state, call, error.toString());
  }
}

Future<SingleToolExecutionOutcome> _proposeWorkspacePatchTool(
  AppState state,
  ModelToolCall call, {
  required String? activeMemberId,
  required Map<String, Object?> arguments,
}) async {
  final member = _memberForTool(state, activeMemberId);
  final role = state.roles.firstWhere((item) => item.id == member.roleId);
  if (!role.canProposePatch) {
    return _toolFailure(state, call, '${member.name} 不允许生成补丁');
  }
  final proposal = await const WorkspaceService().proposePatch(
    state,
    workspaceId: _requiredString(arguments, 'workspaceId'),
    relativePath: _requiredString(arguments, 'relativePath'),
    proposedContent: _requiredString(arguments, 'proposedContent'),
    memberName: member.name,
    id: orchestrationId('patch'),
  );
  final nextState = state.copyWith(
    patchProposals: [...state.patchProposals, proposal],
    auditLog: [
      ...state.auditLog,
      AuditEntry(
        id: orchestrationId('audit'),
        action: 'patch_proposed',
        detail: '${proposal.memberName}: ${proposal.filePath}',
        createdAt: DateTime.now(),
      ),
    ],
  );
  return _toolSuccess(
    nextState,
    call,
    {
      'patchId': proposal.id,
      'status': proposal.status.name,
      'filePath': proposal.filePath,
      'diff': proposal.diff,
    },
  );
}

Future<SingleToolExecutionOutcome> _requestCommandTool(
  AppState state,
  ModelToolCall call, {
  required String conversationId,
  required String? activeMemberId,
  required String? messageId,
  required CommandRunner commandRunner,
  required Map<String, Object?> arguments,
}) async {
  final member = _resolveCommandToolMember(
    state,
    activeMemberId: activeMemberId,
    requestedMember: _optionalString(arguments, 'memberId'),
  );
  if (member == null) {
    final requestedMember = _optionalString(arguments, 'memberId');
    return _toolFailure(
      state,
      call,
      requestedMember == null
          ? '成员工具调用缺少当前成员'
          : activeMemberId != null && activeMemberId.trim().isNotEmpty
              ? '不允许跨成员请求命令: $requestedMember'
              : '未知或不允许的成员: $requestedMember',
    );
  }
  final role = state.roles
      .where((item) => item.id == member.roleId)
      .cast<RoleTemplate?>()
      .firstWhere((item) => item != null, orElse: () => null);
  if (role == null) {
    return _toolFailure(state, call, '成员缺少角色配置: ${member.name}');
  }
  final command = _requiredString(arguments, 'command');
  final workingDirectory = _requiredString(arguments, 'workingDirectory');
  final decision = role.commandPolicy.evaluate(
    command,
    workingDirectory: workingDirectory,
  );
  final request = CommandRequest.pending(
    id: orchestrationId('command'),
    memberName: member.name,
    command: command,
    workingDirectory: workingDirectory,
    decision: decision,
    conversationId: conversationId,
    memberId: member.id,
    toolCallId: call.id,
    messageId: messageId,
  );
  var nextState = state.copyWith(
    commandRequests: [...state.commandRequests, request],
    auditLog: [
      ...state.auditLog,
      AuditEntry(
        id: orchestrationId('audit'),
        action: decision == CommandDecision.denied
            ? 'command_denied'
            : 'command_requested',
        detail: '${member.name}: $command',
        createdAt: DateTime.now(),
      ),
    ],
  );
  if (decision == CommandDecision.allowed) {
    final runResult = await CommandService(runner: commandRunner).run(request);
    final updatedRequest = request.copyWith(
      status: runResult.status,
      output: runResult.output,
    );
    nextState = nextState.copyWith(
      commandRequests: nextState.commandRequests
          .map((item) => item.id == request.id ? updatedRequest : item)
          .toList(),
      auditLog: [
        ...nextState.auditLog,
        AuditEntry(
          id: orchestrationId('audit'),
          action: runResult.status == CommandRequestStatus.executed
              ? 'command_executed'
              : 'command_failed',
          detail: '${request.command} exit=${runResult.exitCode}',
          createdAt: DateTime.now(),
        ),
      ],
    );
    return _toolSuccess(
      nextState,
      call,
      {
        'requestId': updatedRequest.id,
        'decision': updatedRequest.decision.name,
        'status': updatedRequest.status.name,
        'conversationId': updatedRequest.conversationId,
        'memberId': updatedRequest.memberId,
        'output': updatedRequest.output ?? '',
        'exitCode': runResult.exitCode,
        'requiresUserAction': false,
      },
      displayBlocks: [
        ChatMessageContentBlock.commandResult(
          CommandResultAttachment(
            requestId: updatedRequest.id,
            status: updatedRequest.status,
            workingDirectory: updatedRequest.workingDirectory,
            command: updatedRequest.command,
            output: updatedRequest.output ?? '',
          ),
        ),
      ],
    );
  }
  return _toolSuccess(
    nextState,
    call,
    {
      'requestId': request.id,
      'decision': request.decision.name,
      'status': request.status.name,
      'conversationId': request.conversationId,
      'memberId': request.memberId,
      'requiresUserAction': request.status == CommandRequestStatus.pending &&
          request.decision == CommandDecision.requiresConfirmation,
    },
  );
}

TeamMember? _resolveCommandToolMember(
  AppState state, {
  required String? activeMemberId,
  required String? requestedMember,
}) {
  TeamMember? activeMember;
  if (activeMemberId != null && activeMemberId.trim().isNotEmpty) {
    activeMember = state.members
        .where((member) => member.id == activeMemberId)
        .cast<TeamMember?>()
        .firstWhere((member) => member != null, orElse: () => null);
  }
  final requested = requestedMember?.trim();
  if (requested == null || requested.isEmpty) {
    return activeMember;
  }
  if (activeMember != null &&
      (requested == activeMember.id || requested == activeMember.name)) {
    return activeMember;
  }
  if (activeMember != null) {
    return null;
  }
  return state.members
      .where((member) => member.id == requested)
      .cast<TeamMember?>()
      .firstWhere((member) => member != null, orElse: () => null);
}

Map<String, Object?> _decodeToolArguments(String arguments) {
  final decoded = jsonDecode(arguments);
  if (decoded is! Map) {
    throw const FormatException('工具参数必须是 JSON object');
  }
  return Map<String, Object?>.from(decoded);
}

String _requiredString(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value is! String || value.trim().isEmpty) {
    throw ArgumentError('$key 不能为空');
  }
  return value;
}

String? _optionalString(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value;
}

int? _optionalPositiveInt(Map<String, Object?> arguments, String key) {
  final value = arguments[key];
  if (value == null) {
    return null;
  }
  if (value is! num || value <= 0) {
    throw ArgumentError('$key 必须是正整数');
  }
  return value.toInt();
}

TeamMember _memberForTool(AppState state, String? memberId) {
  if (memberId == null || memberId.trim().isEmpty) {
    throw ArgumentError('成员工具调用缺少 memberId');
  }
  return state.members.firstWhere((item) => item.id == memberId);
}

Future<List<String>> _listWorkspaceFiles(
  AppState state, {
  required String workspaceId,
  required int maxFiles,
}) async {
  return const WorkspaceService().listFiles(
    state,
    workspaceId: workspaceId,
    maxFiles: maxFiles,
  );
}

Future<String> _readWorkspaceFile(
  AppState state, {
  required String workspaceId,
  required String relativePath,
}) async {
  return const WorkspaceService().readFile(
    state,
    workspaceId: workspaceId,
    relativePath: relativePath,
  );
}

SingleToolExecutionOutcome _toolSuccess(
  AppState state,
  ModelToolCall call,
  Map<String, Object?> payload, {
  List<ChatMessageContentBlock> displayBlocks = const [],
}) {
  return SingleToolExecutionOutcome(
    workingState: state,
    result: ModelToolResult(
      toolCallId: call.id,
      name: call.name,
      content: toolResultJson(ok: true, payload: payload),
    ),
    displayBlocks: displayBlocks,
  );
}

SingleToolExecutionOutcome _toolFailure(
  AppState state,
  ModelToolCall call,
  String error,
) {
  return SingleToolExecutionOutcome(
    workingState: state,
    result: ModelToolResult(
      toolCallId: call.id,
      name: call.name,
      content: toolResultJson(ok: false, error: error),
    ),
  );
}

String toolResultJson({
  required bool ok,
  Map<String, Object?> payload = const {},
  String? error,
}) {
  return jsonEncode({
    'ok': ok,
    ...payload,
    if (error != null) 'error': error,
  });
}
