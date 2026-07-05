import 'commands_and_tasks.dart';

/// 模型 API 协议类型
enum ModelProtocol {
  /// chat/completions 协议（OpenAI 传统标准）
  chatCompletions,
  
  /// responses 协议（OpenAI 新标准）
  responses,
  
  /// messages 协议（Anthropic Claude API）
  anthropic,
}

class ModelProfile {
  static const defaultContextWindowTokens = 32000;

  const ModelProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.modelName,
    required this.apiKey,
    this.streaming = true,
    this.temperature = 0.4,
    this.maxTokens = 1600,
    this.contextWindowTokens = defaultContextWindowTokens,
    this.reasoningEffort,
    this.protocol = ModelProtocol.chatCompletions,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String modelName;
  final String apiKey;
  final bool streaming;
  final double temperature;
  final int maxTokens;
  final int contextWindowTokens;
  final String? reasoningEffort;
  final ModelProtocol protocol;

  ModelProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? modelName,
    String? apiKey,
    bool? streaming,
    double? temperature,
    int? maxTokens,
    int? contextWindowTokens,
    String? reasoningEffort,
    ModelProtocol? protocol,
  }) =>
      ModelProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        modelName: modelName ?? this.modelName,
        apiKey: apiKey ?? this.apiKey,
        streaming: streaming ?? this.streaming,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
        contextWindowTokens: contextWindowTokens ?? this.contextWindowTokens,
        reasoningEffort: reasoningEffort ?? this.reasoningEffort,
        protocol: protocol ?? this.protocol,
      );

  Map<String, Object?> toJson({bool includeSecrets = false}) {
    final json = <String, Object?>{
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'modelName': modelName,
      'streaming': streaming,
      'temperature': temperature,
      'maxTokens': maxTokens,
      if (contextWindowTokens != defaultContextWindowTokens)
        'contextWindowTokens': contextWindowTokens,
      'protocol': protocol.name,
      if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
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
        contextWindowTokens: (json['contextWindowTokens'] as num?)?.toInt() ??
            ModelProfile.defaultContextWindowTokens,
        reasoningEffort: _optionalJsonString(json['reasoningEffort']),
        protocol: _parseProtocol(json['protocol']),
      );
}

ModelProtocol _parseProtocol(Object? value) {
  if (value is String) {
    try {
      return ModelProtocol.values.byName(value);
    } catch (_) {
      // 向后兼容：默认 chatCompletions
    }
  }
  return ModelProtocol.chatCompletions;
}

String? _optionalJsonString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value;
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

  RoleTemplate copyWith({
    String? id,
    String? name,
    String? description,
    String? identityPrompt,
    String? goalPrompt,
    String? constraintPrompt,
    String? outputFormatPrompt,
    CommandPolicy? commandPolicy,
    bool? canReadProject,
    bool? canProposePatch,
  }) {
    return RoleTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      identityPrompt: identityPrompt ?? this.identityPrompt,
      goalPrompt: goalPrompt ?? this.goalPrompt,
      constraintPrompt: constraintPrompt ?? this.constraintPrompt,
      outputFormatPrompt: outputFormatPrompt ?? this.outputFormatPrompt,
      commandPolicy: commandPolicy ?? this.commandPolicy,
      canReadProject: canReadProject ?? this.canReadProject,
      canProposePatch: canProposePatch ?? this.canProposePatch,
    );
  }

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
    this.executionPriority = 0,
  });

  final String id;
  final String name;
  final String roleId;
  final String modelId;
  final bool isSecretary;
  final int executionPriority;

  TeamMember copyWith({
    String? id,
    String? name,
    String? roleId,
    String? modelId,
    bool? isSecretary,
    int? executionPriority,
  }) {
    return TeamMember(
      id: id ?? this.id,
      name: name ?? this.name,
      roleId: roleId ?? this.roleId,
      modelId: modelId ?? this.modelId,
      isSecretary: isSecretary ?? this.isSecretary,
      executionPriority: executionPriority ?? this.executionPriority,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'roleId': roleId,
        'modelId': modelId,
        'isSecretary': isSecretary,
        'executionPriority': executionPriority,
      };

  factory TeamMember.fromJson(Map<String, Object?> json) => TeamMember(
        id: json['id'] as String,
        name: json['name'] as String,
        roleId: json['roleId'] as String,
        modelId: json['modelId'] as String,
        isSecretary: (json['isSecretary'] as bool?) ?? false,
        executionPriority: (json['executionPriority'] as num?)?.toInt() ?? 0,
      );
}

class Team {
  const Team({
    required this.id,
    required this.name,
    required this.memberIds,
    required this.secretaryMemberId,
    this.maxRounds = 8,
    this.collaborationMode = TeamCollaborationMode.serial,
  });

  final String id;
  final String name;
  final List<String> memberIds;
  final String secretaryMemberId;
  final int maxRounds;
  final TeamCollaborationMode collaborationMode;

  Team copyWith({
    String? name,
    List<String>? memberIds,
    int? maxRounds,
    TeamCollaborationMode? collaborationMode,
  }) =>
      Team(
        id: id,
        name: name ?? this.name,
        memberIds: memberIds ?? this.memberIds,
        secretaryMemberId: secretaryMemberId,
        maxRounds: maxRounds ?? this.maxRounds,
        collaborationMode: collaborationMode ?? this.collaborationMode,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'memberIds': memberIds,
        'secretaryMemberId': secretaryMemberId,
        'maxRounds': maxRounds,
        'collaborationMode': collaborationMode.name,
      };

  factory Team.fromJson(Map<String, Object?> json) => Team(
        id: json['id'] as String,
        name: json['name'] as String,
        memberIds: List<String>.from(json['memberIds'] as List),
        secretaryMemberId: json['secretaryMemberId'] as String,
        maxRounds: (json['maxRounds'] as num?)?.toInt() ?? 8,
        collaborationMode: TeamCollaborationMode.values.byName(
          json['collaborationMode'] as String? ??
              TeamCollaborationMode.serial.name,
        ),
      );
}
