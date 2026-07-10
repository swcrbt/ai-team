import 'commands_and_tasks.dart';
import 'configuration.dart';
import 'conversations.dart';

class AppState {
  const AppState({
    required this.models,
    required this.roles,
    required this.members,
    required this.teams,
    required this.conversations,
    required this.workspaces,
    required this.taskAssignments,
    required this.queuedTasks,
    required this.commandRequests,
    required this.patchProposals,
    required this.auditLog,
  });

  final List<ModelProfile> models;
  final List<RoleTemplate> roles;
  final List<TeamMember> members;
  final List<Team> teams;
  final List<Conversation> conversations;
  final List<ProjectWorkspace> workspaces;
  final List<TaskAssignment> taskAssignments;
  final List<QueuedTask> queuedTasks;
  final List<CommandRequest> commandRequests;
  final List<PatchProposal> patchProposals;
  final List<AuditEntry> auditLog;

  AppState copyWith({
    List<ModelProfile>? models,
    List<RoleTemplate>? roles,
    List<TeamMember>? members,
    List<Team>? teams,
    List<Conversation>? conversations,
    List<ProjectWorkspace>? workspaces,
    List<TaskAssignment>? taskAssignments,
    List<QueuedTask>? queuedTasks,
    List<CommandRequest>? commandRequests,
    List<PatchProposal>? patchProposals,
    List<AuditEntry>? auditLog,
  }) {
    return AppState(
      models: models ?? this.models,
      roles: roles ?? this.roles,
      members: members ?? this.members,
      teams: teams ?? this.teams,
      conversations: conversations ?? this.conversations,
      workspaces: workspaces ?? this.workspaces,
      taskAssignments: taskAssignments ?? this.taskAssignments,
      queuedTasks: queuedTasks ?? this.queuedTasks,
      commandRequests: commandRequests ?? this.commandRequests,
      patchProposals: patchProposals ?? this.patchProposals,
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
        'taskAssignments':
            taskAssignments.map((assignment) => assignment.toJson()).toList(),
        'queuedTasks': queuedTasks.map((task) => task.toJson()).toList(),
        'commandRequests':
            commandRequests.map((request) => request.toJson()).toList(),
        'patchProposals':
            patchProposals.map((proposal) => proposal.toJson()).toList(),
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
        taskAssignments: ((json['taskAssignments'] as List?) ?? const [])
            .map(
                (item) => TaskAssignment.fromJson(item as Map<String, Object?>))
            .toList(),
        queuedTasks: ((json['queuedTasks'] as List?) ?? const [])
            .map((item) => QueuedTask.fromJson(item as Map<String, Object?>))
            .toList(),
        commandRequests: ((json['commandRequests'] as List?) ?? const [])
            .map(
                (item) => CommandRequest.fromJson(item as Map<String, Object?>))
            .toList(),
        patchProposals: ((json['patchProposals'] as List?) ?? const [])
            .map((item) => PatchProposal.fromJson(item as Map<String, Object?>))
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
        supportsImages: true,
      ),
      const ModelProfile(
        id: 'model-local',
        name: 'Local Compatible',
        baseUrl: 'http://localhost:11434/v1',
        modelName: 'qwen2.5-coder',
        apiKey: 'local',
        supportsImages: false,
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
        memberId: null,
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
      for (final member in members)
        Conversation(
          id: 'conv-${member.id}',
          title: member.name,
          teamId: 'team-default',
          memberId: member.id,
          messages: [
            ChatMessage(
              id: 'msg-welcome-${member.id}',
              authorName: member.name,
              memberId: member.id,
              content: '这里是和${member.name}的独立会话。',
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
      taskAssignments: const [],
      queuedTasks: const [],
      commandRequests: const [],
      patchProposals: const [],
      auditLog: const [],
    );
  }
}
