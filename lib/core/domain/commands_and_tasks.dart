import 'diff.dart';

enum ConversationStatus { idle, running, paused, stopped, failed }

enum ChatMessageGenerationStatus { complete, streaming, failed, stopped }

enum TeamCollaborationMode { serial, parallel }

enum CommandDecision { allowed, requiresConfirmation, denied }

enum CommandRequestStatus { pending, approved, denied, executed, failed }

enum PatchStatus { pending, applied, rejected }

enum TaskAssignmentStatus { pending, running, completed, failed, cancelled }

enum QueuedTaskStatus { pending, running, paused, completed, failed }

class TaskAssignment {
  const TaskAssignment({
    required this.id,
    required this.conversationId,
    required this.round,
    required this.memberId,
    required this.memberName,
    required this.roleName,
    required this.instruction,
    required this.status,
    required this.createdAt,
    this.summary,
    this.completedAt,
  });

  final String id;
  final String conversationId;
  final int round;
  final String memberId;
  final String memberName;
  final String roleName;
  final String instruction;
  final TaskAssignmentStatus status;
  final DateTime createdAt;
  final String? summary;
  final DateTime? completedAt;

  TaskAssignment copyWith({
    TaskAssignmentStatus? status,
    String? summary,
    DateTime? completedAt,
  }) {
    return TaskAssignment(
      id: id,
      conversationId: conversationId,
      round: round,
      memberId: memberId,
      memberName: memberName,
      roleName: roleName,
      instruction: instruction,
      status: status ?? this.status,
      createdAt: createdAt,
      summary: summary ?? this.summary,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'round': round,
        'memberId': memberId,
        'memberName': memberName,
        'roleName': roleName,
        'instruction': instruction,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'summary': summary,
        'completedAt': completedAt?.toIso8601String(),
      };

  factory TaskAssignment.fromJson(Map<String, Object?> json) => TaskAssignment(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        round: (json['round'] as num).toInt(),
        memberId: json['memberId'] as String,
        memberName: json['memberName'] as String,
        roleName: json['roleName'] as String,
        instruction: json['instruction'] as String,
        status: TaskAssignmentStatus.values.byName(json['status'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        summary: json['summary'] as String?,
        completedAt: json['completedAt'] == null
            ? null
            : DateTime.parse(json['completedAt'] as String),
      );
}

class PatchProposal {
  const PatchProposal({
    required this.id,
    required this.filePath,
    required this.originalContent,
    required this.proposedContent,
    required this.memberName,
    required this.diff,
    this.status = PatchStatus.pending,
  });

  factory PatchProposal.fromFileChange({
    required String id,
    required String filePath,
    required String originalContent,
    required String proposedContent,
    required String memberName,
  }) {
    return PatchProposal(
      id: id,
      filePath: filePath,
      originalContent: originalContent,
      proposedContent: proposedContent,
      memberName: memberName,
      diff: createUnifiedDiff(filePath, originalContent, proposedContent),
    );
  }

  factory PatchProposal.fromJson(Map<String, Object?> json) => PatchProposal(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        originalContent: json['originalContent'] as String,
        proposedContent: json['proposedContent'] as String,
        memberName: json['memberName'] as String,
        diff: json['diff'] as String,
        status: PatchStatus.values.byName(json['status'] as String),
      );

  final String id;
  final String filePath;
  final String originalContent;
  final String proposedContent;
  final String memberName;
  final String diff;
  final PatchStatus status;

  PatchProposal copyWith({PatchStatus? status}) => PatchProposal(
        id: id,
        filePath: filePath,
        originalContent: originalContent,
        proposedContent: proposedContent,
        memberName: memberName,
        diff: diff,
        status: status ?? this.status,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'filePath': filePath,
        'originalContent': originalContent,
        'proposedContent': proposedContent,
        'memberName': memberName,
        'diff': diff,
        'status': status.name,
      };
}

class CommandPolicy {
  const CommandPolicy({
    required this.allowedCommands,
    required this.blockedCommands,
    required this.allowedDirectories,
    required this.requiresConfirmation,
  });

  final List<String> allowedCommands;
  final List<String> blockedCommands;
  final List<String> allowedDirectories;
  final bool requiresConfirmation;

  CommandDecision evaluate(
    String command, {
    required String workingDirectory,
  }) {
    final normalized = command.trim();
    if (normalized.isEmpty || _hasUnsafeShellSyntax(normalized)) {
      return CommandDecision.denied;
    }

    final isBlocked = blockedCommands.any(
      (blocked) => _matchesCommandPrefix(normalized, blocked),
    );
    if (isBlocked) {
      return CommandDecision.denied;
    }

    final directoryAllowed = allowedDirectories.isEmpty ||
        allowedDirectories.any(
          (directory) => _isSameOrChildPath(workingDirectory, directory),
        );
    if (!directoryAllowed) {
      return CommandDecision.denied;
    }

    final commandAllowed = allowedCommands.any(
      (allowed) =>
          allowed.trim() == '*' || _matchesCommandPrefix(normalized, allowed),
    );
    if (!commandAllowed) {
      return CommandDecision.denied;
    }

    return requiresConfirmation
        ? CommandDecision.requiresConfirmation
        : CommandDecision.allowed;
  }

  Map<String, Object?> toJson() => {
        'allowedCommands': allowedCommands,
        'blockedCommands': blockedCommands,
        'allowedDirectories': allowedDirectories,
        'requiresConfirmation': requiresConfirmation,
      };

  factory CommandPolicy.fromJson(Map<String, Object?> json) => CommandPolicy(
        allowedCommands: List<String>.from(json['allowedCommands'] as List),
        blockedCommands: List<String>.from(json['blockedCommands'] as List),
        allowedDirectories:
            List<String>.from(json['allowedDirectories'] as List),
        requiresConfirmation: json['requiresConfirmation'] as bool,
      );
}

bool _matchesCommandPrefix(String command, String policyCommand) {
  final normalizedPolicy = policyCommand.trim();
  return command == normalizedPolicy ||
      command.startsWith('$normalizedPolicy ');
}

bool _hasUnsafeShellSyntax(String command) {
  return RegExp(r'[;&|<>`$]|\r|\n').hasMatch(command);
}

bool _isSameOrChildPath(String path, String allowedRoot) {
  final normalizedPath = _normalizePath(path);
  final normalizedRoot = _normalizePath(allowedRoot);
  return normalizedPath == normalizedRoot ||
      normalizedPath.startsWith('$normalizedRoot/') ||
      normalizedPath.startsWith('$normalizedRoot\\');
}

String _normalizePath(String path) {
  var normalized = path.trim();
  while (normalized.endsWith('/') || normalized.endsWith('\\')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

class CommandRequest {
  const CommandRequest({
    required this.id,
    required this.memberName,
    required this.command,
    required this.workingDirectory,
    required this.decision,
    required this.status,
    required this.createdAt,
    this.output,
    this.conversationId,
    this.memberId,
    this.toolCallId,
    this.messageId,
  });

  factory CommandRequest.pending({
    required String id,
    required String memberName,
    required String command,
    required String workingDirectory,
    required CommandDecision decision,
    String? conversationId,
    String? memberId,
    String? toolCallId,
    String? messageId,
  }) {
    return CommandRequest(
      id: id,
      memberName: memberName,
      command: command,
      workingDirectory: workingDirectory,
      decision: decision,
      status: switch (decision) {
        CommandDecision.allowed => CommandRequestStatus.approved,
        CommandDecision.requiresConfirmation => CommandRequestStatus.pending,
        CommandDecision.denied => CommandRequestStatus.denied,
      },
      createdAt: DateTime.now(),
      conversationId: conversationId,
      memberId: memberId,
      toolCallId: toolCallId,
      messageId: messageId,
    );
  }

  final String id;
  final String memberName;
  final String command;
  final String workingDirectory;
  final CommandDecision decision;
  final CommandRequestStatus status;
  final DateTime createdAt;
  final String? output;
  final String? conversationId;
  final String? memberId;
  final String? toolCallId;
  final String? messageId;

  CommandRequest copyWith({
    CommandRequestStatus? status,
    String? output,
    String? messageId,
  }) {
    return CommandRequest(
      id: id,
      memberName: memberName,
      command: command,
      workingDirectory: workingDirectory,
      decision: decision,
      status: status ?? this.status,
      createdAt: createdAt,
      output: output ?? this.output,
      conversationId: conversationId,
      memberId: memberId,
      toolCallId: toolCallId,
      messageId: messageId ?? this.messageId,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'memberName': memberName,
        'command': command,
        'workingDirectory': workingDirectory,
        'decision': decision.name,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'output': output,
        'conversationId': conversationId,
        'memberId': memberId,
        'toolCallId': toolCallId,
        'messageId': messageId,
      };

  factory CommandRequest.fromJson(Map<String, Object?> json) => CommandRequest(
        id: json['id'] as String,
        memberName: json['memberName'] as String,
        command: json['command'] as String,
        workingDirectory: json['workingDirectory'] as String,
        decision: CommandDecision.values.byName(json['decision'] as String),
        status: CommandRequestStatus.values.byName(json['status'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        output: json['output'] as String?,
        conversationId: json['conversationId'] as String?,
        memberId: json['memberId'] as String?,
        toolCallId: json['toolCallId'] as String?,
        messageId: json['messageId'] as String?,
      );
}

enum MessageAttachmentType { image }

class MessageAttachment {
  const MessageAttachment({
    required this.id,
    required this.type,
    required this.filePath,
    this.mimeType,
    this.fileSize,
    this.width,
    this.height,
  });

  final String id;
  final MessageAttachmentType type;
  final String filePath;
  final String? mimeType;
  final int? fileSize;
  final int? width;
  final int? height;

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'filePath': filePath,
        if (mimeType != null) 'mimeType': mimeType,
        if (fileSize != null) 'fileSize': fileSize,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
      };

  factory MessageAttachment.fromJson(Map<String, Object?> json) =>
      MessageAttachment(
        id: json['id'] as String,
        type: MessageAttachmentType.values.byName(
          json['type'] as String? ?? MessageAttachmentType.image.name,
        ),
        filePath: json['filePath'] as String,
        mimeType: json['mimeType'] as String?,
        fileSize: (json['fileSize'] as num?)?.toInt(),
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
      );
}

enum ChatMessageContentBlockType { text, commandResult, toolError }

class CommandResultAttachment {
  const CommandResultAttachment({
    required this.requestId,
    required this.status,
    required this.workingDirectory,
    required this.command,
    required this.output,
  });

  final String requestId;
  final CommandRequestStatus status;
  final String workingDirectory;
  final String command;
  final String output;

  Map<String, Object?> toJson() => {
        'requestId': requestId,
        'status': status.name,
        'workingDirectory': workingDirectory,
        'command': command,
        'output': output,
      };

  factory CommandResultAttachment.fromJson(Map<String, Object?> json) =>
      CommandResultAttachment(
        requestId: json['requestId'] as String,
        status: CommandRequestStatus.values.byName(json['status'] as String),
        workingDirectory: json['workingDirectory'] as String,
        command: json['command'] as String,
        output: json['output'] as String? ?? '',
      );
}

class ChatMessageContentBlock {
  const ChatMessageContentBlock.text(this.text)
      : type = ChatMessageContentBlockType.text,
        commandResult = null;

  const ChatMessageContentBlock.toolError(this.text)
      : type = ChatMessageContentBlockType.toolError,
        commandResult = null;

  const ChatMessageContentBlock.commandResult(CommandResultAttachment result)
      : type = ChatMessageContentBlockType.commandResult,
        text = null,
        commandResult = result;

  final ChatMessageContentBlockType type;
  final String? text;
  final CommandResultAttachment? commandResult;

  Map<String, Object?> toJson() => {
        'type': type.name,
        if (text != null) 'text': text,
        if (commandResult != null) 'commandResult': commandResult!.toJson(),
      };

  factory ChatMessageContentBlock.fromJson(Map<String, Object?> json) {
    final type = ChatMessageContentBlockType.values.byName(
      json['type'] as String? ?? ChatMessageContentBlockType.text.name,
    );
    return switch (type) {
      ChatMessageContentBlockType.text =>
        ChatMessageContentBlock.text(json['text'] as String? ?? ''),
      ChatMessageContentBlockType.toolError =>
        ChatMessageContentBlock.toolError(json['text'] as String? ?? ''),
      ChatMessageContentBlockType.commandResult =>
        ChatMessageContentBlock.commandResult(
          CommandResultAttachment.fromJson(
            json['commandResult'] as Map<String, Object?>,
          ),
        ),
    };
  }
}
