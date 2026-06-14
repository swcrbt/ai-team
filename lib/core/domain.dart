enum ConversationStatus { idle, running, paused, stopped, failed }

enum CommandDecision { allowed, requiresConfirmation, denied }

enum PatchStatus { pending, applied, rejected }

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
    final isBlocked = blockedCommands.any(
      (blocked) => normalized == blocked || normalized.startsWith('$blocked '),
    );
    if (isBlocked) {
      return CommandDecision.denied;
    }

    final directoryAllowed = allowedDirectories.isEmpty ||
        allowedDirectories.any(workingDirectory.startsWith);
    if (!directoryAllowed) {
      return CommandDecision.denied;
    }

    final commandAllowed =
        allowedCommands.any((allowed) => normalized.startsWith(allowed));
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

class ModelProfile {
  const ModelProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.modelName,
    required this.apiKey,
    this.streaming = true,
    this.temperature = 0.4,
    this.maxTokens = 1600,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String modelName;
  final String apiKey;
  final bool streaming;
  final double temperature;
  final int maxTokens;

  Map<String, Object?> toJson({bool includeSecrets = false}) {
    final json = <String, Object?>{
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'modelName': modelName,
      'streaming': streaming,
      'temperature': temperature,
      'maxTokens': maxTokens,
    };
    if (includeSecrets) {
      json['apiKey'] = apiKey;
    }
    return json;
  }

  factory ModelProfile.fromJson(Map<String, Object?> json) => ModelProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        modelName: json['modelName'] as String,
        apiKey: (json['apiKey'] as String?) ?? '',
        streaming: (json['streaming'] as bool?) ?? true,
        temperature: ((json['temperature'] as num?) ?? 0.4).toDouble(),
        maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 1600,
      );
}

class RoleTemplate {
  const RoleTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.identityPrompt,
    required this.goalPrompt,
    required this.constraintPrompt,
    required this.outputFormatPrompt,
    required this.commandPolicy,
    this.canReadProject = true,
    this.canProposePatch = true,
  });

  final String id;
  final String name;
  final String description;
  final String identityPrompt;
  final String goalPrompt;
  final String constraintPrompt;
  final String outputFormatPrompt;
  final CommandPolicy commandPolicy;
  final bool canReadProject;
  final bool canProposePatch;

  String renderSystemPrompt({
    required String memberName,
    required String teamName,
  }) {
    return [
      '成员名称: $memberName',
      '所属团队: $teamName',
      '身份: $identityPrompt',
      '目标: $goalPrompt',
      '约束: $constraintPrompt',
      '输出格式: $outputFormatPrompt',
      '可读项目: $canReadProject',
      '可生成补丁: $canProposePatch',
    ].join('\n');
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'identityPrompt': identityPrompt,
        'goalPrompt': goalPrompt,
        'constraintPrompt': constraintPrompt,
        'outputFormatPrompt': outputFormatPrompt,
        'commandPolicy': commandPolicy.toJson(),
        'canReadProject': canReadProject,
        'canProposePatch': canProposePatch,
      };

  factory RoleTemplate.fromJson(Map<String, Object?> json) => RoleTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        identityPrompt: json['identityPrompt'] as String,
        goalPrompt: json['goalPrompt'] as String,
        constraintPrompt: json['constraintPrompt'] as String,
        outputFormatPrompt: json['outputFormatPrompt'] as String,
        commandPolicy: CommandPolicy.fromJson(
            json['commandPolicy'] as Map<String, Object?>),
        canReadProject: json['canReadProject'] as bool,
        canProposePatch: json['canProposePatch'] as bool,
      );
}

class TeamMember {
  const TeamMember({
    required this.id,
    required this.name,
    required this.roleId,
    required this.modelId,
    this.isSecretary = false,
  });

  final String id;
  final String name;
  final String roleId;
  final String modelId;
  final bool isSecretary;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'roleId': roleId,
        'modelId': modelId,
        'isSecretary': isSecretary,
      };

  factory TeamMember.fromJson(Map<String, Object?> json) => TeamMember(
        id: json['id'] as String,
        name: json['name'] as String,
        roleId: json['roleId'] as String,
        modelId: json['modelId'] as String,
        isSecretary: json['isSecretary'] as bool,
      );
}

class Team {
  const Team({
    required this.id,
    required this.name,
    required this.memberIds,
    required this.secretaryMemberId,
    this.maxRounds = 8,
  });

  final String id;
  final String name;
  final List<String> memberIds;
  final String secretaryMemberId;
  final int maxRounds;

  Team copyWith({int? maxRounds}) => Team(
        id: id,
        name: name,
        memberIds: memberIds,
        secretaryMemberId: secretaryMemberId,
        maxRounds: maxRounds ?? this.maxRounds,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'memberIds': memberIds,
        'secretaryMemberId': secretaryMemberId,
        'maxRounds': maxRounds,
      };

  factory Team.fromJson(Map<String, Object?> json) => Team(
        id: json['id'] as String,
        name: json['name'] as String,
        memberIds: List<String>.from(json['memberIds'] as List),
        secretaryMemberId: json['secretaryMemberId'] as String,
        maxRounds: (json['maxRounds'] as num).toInt(),
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.authorName,
    required this.content,
    required this.createdAt,
    this.memberId,
    this.isUser = false,
  });

  final String id;
  final String authorName;
  final String content;
  final DateTime createdAt;
  final String? memberId;
  final bool isUser;

  Map<String, Object?> toJson() => {
        'id': id,
        'authorName': authorName,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'memberId': memberId,
        'isUser': isUser,
      };

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
        id: json['id'] as String,
        authorName: json['authorName'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        memberId: json['memberId'] as String?,
        isUser: json['isUser'] as bool,
      );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.teamId,
    required this.messages,
    this.currentRound = 0,
    this.status = ConversationStatus.idle,
  });

  final String id;
  final String title;
  final String teamId;
  final List<ChatMessage> messages;
  final int currentRound;
  final ConversationStatus status;

  Conversation copyWith({
    List<ChatMessage>? messages,
    int? currentRound,
    ConversationStatus? status,
  }) {
    return Conversation(
      id: id,
      title: title,
      teamId: teamId,
      messages: messages ?? this.messages,
      currentRound: currentRound ?? this.currentRound,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'teamId': teamId,
        'messages': messages.map((message) => message.toJson()).toList(),
        'currentRound': currentRound,
        'status': status.name,
      };

  factory Conversation.fromJson(Map<String, Object?> json) => Conversation(
        id: json['id'] as String,
        title: json['title'] as String,
        teamId: json['teamId'] as String,
        messages: (json['messages'] as List)
            .map((item) => ChatMessage.fromJson(item as Map<String, Object?>))
            .toList(),
        currentRound: (json['currentRound'] as num).toInt(),
        status: ConversationStatus.values.byName(json['status'] as String),
      );
}

class ProjectWorkspace {
  const ProjectWorkspace({
    required this.id,
    required this.name,
    required this.path,
  });

  final String id;
  final String name;
  final String path;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'path': path,
      };

  factory ProjectWorkspace.fromJson(Map<String, Object?> json) =>
      ProjectWorkspace(
        id: json['id'] as String,
        name: json['name'] as String,
        path: json['path'] as String,
      );
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.detail,
    required this.createdAt,
  });

  final String id;
  final String action;
  final String detail;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'action': action,
        'detail': detail,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AuditEntry.fromJson(Map<String, Object?> json) => AuditEntry(
        id: json['id'] as String,
        action: json['action'] as String,
        detail: json['detail'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class AppState {
  const AppState({
    required this.models,
    required this.roles,
    required this.members,
    required this.teams,
    required this.conversations,
    required this.workspaces,
    required this.auditLog,
  });

  final List<ModelProfile> models;
  final List<RoleTemplate> roles;
  final List<TeamMember> members;
  final List<Team> teams;
  final List<Conversation> conversations;
  final List<ProjectWorkspace> workspaces;
  final List<AuditEntry> auditLog;

  AppState copyWith({
    List<ModelProfile>? models,
    List<RoleTemplate>? roles,
    List<TeamMember>? members,
    List<Team>? teams,
    List<Conversation>? conversations,
    List<ProjectWorkspace>? workspaces,
    List<AuditEntry>? auditLog,
  }) {
    return AppState(
      models: models ?? this.models,
      roles: roles ?? this.roles,
      members: members ?? this.members,
      teams: teams ?? this.teams,
      conversations: conversations ?? this.conversations,
      workspaces: workspaces ?? this.workspaces,
      auditLog: auditLog ?? this.auditLog,
    );
  }

  Map<String, Object?> toJson({bool includeSecrets = false}) => {
        'models': models
            .map((model) => model.toJson(includeSecrets: includeSecrets))
            .toList(),
        'roles': roles.map((role) => role.toJson()).toList(),
        'members': members.map((member) => member.toJson()).toList(),
        'teams': teams.map((team) => team.toJson()).toList(),
        'conversations':
            conversations.map((conversation) => conversation.toJson()).toList(),
        'workspaces':
            workspaces.map((workspace) => workspace.toJson()).toList(),
        'auditLog': auditLog.map((entry) => entry.toJson()).toList(),
      };

  factory AppState.fromJson(Map<String, Object?> json) => AppState(
        models: (json['models'] as List)
            .map((item) => ModelProfile.fromJson(item as Map<String, Object?>))
            .toList(),
        roles: (json['roles'] as List)
            .map((item) => RoleTemplate.fromJson(item as Map<String, Object?>))
            .toList(),
        members: (json['members'] as List)
            .map((item) => TeamMember.fromJson(item as Map<String, Object?>))
            .toList(),
        teams: (json['teams'] as List)
            .map((item) => Team.fromJson(item as Map<String, Object?>))
            .toList(),
        conversations: (json['conversations'] as List)
            .map((item) => Conversation.fromJson(item as Map<String, Object?>))
            .toList(),
        workspaces: (json['workspaces'] as List)
            .map((item) =>
                ProjectWorkspace.fromJson(item as Map<String, Object?>))
            .toList(),
        auditLog: (json['auditLog'] as List)
            .map((item) => AuditEntry.fromJson(item as Map<String, Object?>))
            .toList(),
      );

  factory AppState.seed() {
    const policy = CommandPolicy(
      allowedCommands: ['flutter test', 'dart analyze', 'rg', 'ls'],
      blockedCommands: ['rm', 'sudo', 'git push'],
      allowedDirectories: [],
      requiresConfirmation: true,
    );
    final roles = [
      const RoleTemplate(
        id: 'role-secretary',
        name: '秘书',
        description: '负责拆分任务、协调成员并汇总结果。',
        identityPrompt: '你是开发团队秘书，负责理解任务、分工和汇总。',
        goalPrompt: '把用户目标拆成可执行子任务并推动团队完成。',
        constraintPrompt: '不要直接修改文件；需要变更时创建补丁提案。',
        outputFormatPrompt: '先给分工，再给进展，最后给汇总。',
        commandPolicy: policy,
      ),
      const RoleTemplate(
        id: 'role-frontend',
        name: '前端工程师',
        description: '负责 Flutter UI、状态和交互实现。',
        identityPrompt: '你是资深 Flutter 前端工程师。',
        goalPrompt: '实现清晰、稳定、可测试的桌面端界面。',
        constraintPrompt: '遵循现有结构，输出需要用户确认的补丁。',
        outputFormatPrompt: '说明改动、风险和验证方式。',
        commandPolicy: policy,
      ),
      const RoleTemplate(
        id: 'role-tester',
        name: '测试工程师',
        description: '负责测试策略、回归用例和验收。',
        identityPrompt: '你是严谨的测试工程师。',
        goalPrompt: '补齐关键路径测试并指出风险。',
        constraintPrompt: '优先使用非破坏性命令。',
        outputFormatPrompt: '列出测试、证据和未覆盖风险。',
        commandPolicy: policy,
      ),
    ];
    final models = [
      const ModelProfile(
        id: 'model-main',
        name: 'OpenAI Compatible',
        baseUrl: 'https://api.openai.com/v1',
        modelName: 'gpt-4.1',
        apiKey: 'sk-local-placeholder',
      ),
      const ModelProfile(
        id: 'model-local',
        name: 'Local Compatible',
        baseUrl: 'http://localhost:11434/v1',
        modelName: 'qwen2.5-coder',
        apiKey: 'local',
      ),
    ];
    final members = [
      const TeamMember(
        id: 'member-secretary',
        name: '秘书',
        roleId: 'role-secretary',
        modelId: 'model-main',
        isSecretary: true,
      ),
      const TeamMember(
        id: 'member-frontend',
        name: '前端工程师',
        roleId: 'role-frontend',
        modelId: 'model-main',
      ),
      const TeamMember(
        id: 'member-tester',
        name: '测试工程师',
        roleId: 'role-tester',
        modelId: 'model-local',
      ),
    ];
    final teams = [
      const Team(
        id: 'team-default',
        name: '默认开发团队',
        memberIds: ['member-secretary', 'member-frontend', 'member-tester'],
        secretaryMemberId: 'member-secretary',
      ),
    ];
    final conversations = [
      Conversation(
        id: 'conv-team-default',
        title: '团队会话',
        teamId: 'team-default',
        messages: [
          ChatMessage(
            id: 'msg-welcome',
            authorName: '秘书',
            memberId: 'member-secretary',
            content: '把开发任务发到这里，我会分配给团队成员并汇总结果。',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      ),
    ];
    return AppState(
      models: models,
      roles: roles,
      members: members,
      teams: teams,
      conversations: conversations,
      workspaces: const [],
      auditLog: const [],
    );
  }
}
