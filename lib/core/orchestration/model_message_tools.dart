part of '../orchestrator.dart';

List<ModelToolDefinition> _modelToolDefinitions({
  required RoleTemplate? role,
}) {
  return [
    const ModelToolDefinition(
      name: 'list_workspace_files',
      description: 'List non-hidden files in a configured local workspace.',
      parameters: {
        'type': 'object',
        'properties': {
          'workspaceId': {'type': 'string'},
          'maxFiles': {'type': 'integer', 'minimum': 1, 'maximum': 500},
        },
        'required': ['workspaceId'],
        'additionalProperties': false,
      },
    ),
    const ModelToolDefinition(
      name: 'read_workspace_file',
      description: 'Read a UTF-8 text file from a configured local workspace.',
      parameters: {
        'type': 'object',
        'properties': {
          'workspaceId': {'type': 'string'},
          'relativePath': {'type': 'string'},
        },
        'required': ['workspaceId', 'relativePath'],
        'additionalProperties': false,
      },
    ),
    if (role?.canProposePatch ?? true)
      const ModelToolDefinition(
        name: 'propose_workspace_patch',
        description:
            'Create a pending unified diff proposal. This does not write files.',
        parameters: {
          'type': 'object',
          'properties': {
            'workspaceId': {'type': 'string'},
            'relativePath': {'type': 'string'},
            'proposedContent': {'type': 'string'},
          },
          'required': ['workspaceId', 'relativePath', 'proposedContent'],
          'additionalProperties': false,
        },
      ),
    const ModelToolDefinition(
      name: 'request_command',
      description:
          'Request a command for the current member. The app evaluates the member role policy: commands that require confirmation become pending requests, and allowed commands may execute immediately. 默认使用当前成员；除非系统明确要求，不要填写 memberId 或成员显示名。',
      parameters: {
        'type': 'object',
        'properties': {
          'memberId': {'type': 'string'},
          'command': {'type': 'string'},
          'workingDirectory': {'type': 'string'},
        },
        'required': ['command', 'workingDirectory'],
        'additionalProperties': false,
      },
    ),
  ];
}

RoleTemplate? _roleForMember(AppState state, String? memberId) {
  if (memberId == null) {
    return null;
  }
  final member = state.members.firstWhere(
    (item) => item.id == memberId,
    orElse: () => const TeamMember(
      id: '',
      name: '',
      roleId: '',
      modelId: '',
    ),
  );
  if (member.id.isEmpty) {
    return null;
  }
  return state.roles.firstWhere(
    (item) => item.id == member.roleId,
    orElse: () => const RoleTemplate(
      id: '',
      name: '',
      description: '',
      identityPrompt: '',
      goalPrompt: '',
      constraintPrompt: '',
      outputFormatPrompt: '',
      commandPolicy: CommandPolicy(
        allowedCommands: [],
        blockedCommands: [],
        allowedDirectories: [],
        requiresConfirmation: true,
      ),
    ),
  );
}

String _appendToolSystemPrompt(
  String systemPrompt, {
  required RoleTemplate? role,
}) {
  final commandPolicy = role?.commandPolicy;
  final commandPolicyText = commandPolicy == null
      ? null
      : [
          '当前角色命令策略:',
          'allowedCommands=${jsonEncode(commandPolicy.allowedCommands)}',
          'blockedCommands=${jsonEncode(commandPolicy.blockedCommands)}',
          'allowedDirectories=${jsonEncode(commandPolicy.allowedDirectories)}',
          'requiresConfirmation=${commandPolicy.requiresConfirmation}',
          'allowedCommands 中的 "*" 表示允许所有通过安全语法检查、禁止命令检查和目录检查的命令；它本身不会关闭确认开关。',
          'requiresConfirmation=false 表示允许命令可自动执行；仍不会绕过危险语法检查、禁止命令或目录限制。',
        ].join(' ');
  return [
    systemPrompt,
    if (commandPolicyText != null) commandPolicyText,
    '需要读取本地项目、提出补丁或请求命令时，优先调用可用工具；不要伪造工具结果。补丁只会创建待确认提案；命令会按当前角色策略处理，需要确认时创建待批准请求，无需确认时可以自动执行并返回结果。',
    '涉及执行命令、磁盘占用、df、du 或系统查询时必须调用 request_command；未调用工具前不能声称已执行、已尝试执行或已运行命令。',
  ].join('\n');
}

String _guardCommandExecutionClaim({
  required String content,
  required List<ChatMessage> requestMessages,
  required List<ModelToolDefinition> toolDefinitions,
  required List<ModelToolRound> toolRounds,
}) {
  final canRequestCommand =
      toolDefinitions.any((tool) => tool.name == 'request_command');
  if (!canRequestCommand ||
      _toolRoundsContainTool(toolRounds, 'request_command') ||
      !_hasCommandIntent(requestMessages) ||
      !_claimsCommandExecution(content)) {
    return content;
  }
  return '未创建命令请求，不能声称已执行命令。请调用 request_command 创建命令请求，并等待用户审批或执行结果。';
}

bool _toolRoundsContainTool(List<ModelToolRound> rounds, String name) {
  return rounds.any(
    (round) => round.calls.any((call) => call.name == name),
  );
}

bool _hasCommandIntent(List<ChatMessage> messages) {
  final text = messages.map((message) => message.content).join('\n');
  return RegExp(
    r'(执行|运行|命令|磁盘|系统查询|\bdf\b|\bdu\b)',
    caseSensitive: false,
  ).hasMatch(text);
}

bool _claimsCommandExecution(String content) {
  return RegExp(
    r'(已|已经|尝试|试图|正在)?\s*(执行|运行|调用|尝试执行|尝试运行)',
    caseSensitive: false,
  ).hasMatch(content);
}

String _formatCommandResultMessage(CommandRequest request) {
  final output = request.output?.trim();
  return [
    '命令执行结果',
    '工作目录: ${request.workingDirectory}',
    '命令: ${request.command}',
    '状态: ${request.status.name}',
    if (output != null && output.isNotEmpty) '输出:\n$output' else '输出: <empty>',
  ].join('\n');
}

String _contentFromBlocks(List<ChatMessageContentBlock> blocks) {
  return blocks
      .map((block) {
        return switch (block.type) {
          ChatMessageContentBlockType.text => block.text ?? '',
          ChatMessageContentBlockType.toolError => block.text ?? '',
          ChatMessageContentBlockType.commandResult =>
            _formatCommandResultBlockText(block.commandResult!),
        };
      })
      .where((content) => content.trim().isNotEmpty)
      .join('\n');
}

String _formatCommandResultBlockText(CommandResultAttachment result) {
  final output = result.output.trim();
  return [
    '命令执行结果',
    '工作目录: ${result.workingDirectory}',
    '命令: ${result.command}',
    '状态: ${result.status.name}',
    if (output.isNotEmpty) '输出:\n$output' else '输出: <empty>',
  ].join('\n');
}

List<ChatMessageContentBlock> _appendTextBlock(
  List<ChatMessageContentBlock> blocks,
  String text,
) {
  if (text.trim().isEmpty) {
    return blocks;
  }
  return [
    ...blocks,
    ChatMessageContentBlock.text(text),
  ];
}

ChatMessage _messageWithBlocks(
  ChatMessage message,
  List<ChatMessageContentBlock> blocks, {
  ChatMessageGenerationStatus? generationStatus,
}) {
  return message.copyWith(
    content: _contentFromBlocks(blocks),
    contentBlocks: blocks,
    generationStatus: generationStatus,
  );
}
