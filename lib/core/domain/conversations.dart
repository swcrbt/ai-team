import 'commands_and_tasks.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.authorName,
    required this.content,
    required this.createdAt,
    this.thinkingContent,
    this.generationStatus = ChatMessageGenerationStatus.complete,
    this.generationDurationMs,
    this.memberId,
    this.isUser = false,
    this.taskIds = const [],
    this.inputTokens,
    this.outputTokens,
    this.cachedTokens,
    this.totalTokens,
    List<ChatMessageContentBlock>? contentBlocks = const [],
  }) : _contentBlocks = contentBlocks;

  final String id;
  final String authorName;
  final String content;
  final String? thinkingContent;
  final ChatMessageGenerationStatus generationStatus;
  final int? generationDurationMs;
  final DateTime createdAt;
  final String? memberId;
  final bool isUser;
  final List<String> taskIds;
  final int? inputTokens;
  final int? outputTokens;
  final int? cachedTokens;
  final int? totalTokens;
  final List<ChatMessageContentBlock>? _contentBlocks;

  List<ChatMessageContentBlock> get contentBlocks => _contentBlocks ?? const [];

  ChatMessage copyWith({
    String? content,
    String? thinkingContent,
    ChatMessageGenerationStatus? generationStatus,
    int? generationDurationMs,
    int? inputTokens,
    int? outputTokens,
    int? cachedTokens,
    int? totalTokens,
    List<ChatMessageContentBlock>? contentBlocks,
  }) {
    return ChatMessage(
      id: id,
      authorName: authorName,
      content: content ?? this.content,
      thinkingContent: thinkingContent ?? this.thinkingContent,
      generationStatus: generationStatus ?? this.generationStatus,
      generationDurationMs: generationDurationMs ?? this.generationDurationMs,
      createdAt: createdAt,
      memberId: memberId,
      isUser: isUser,
      taskIds: taskIds,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      cachedTokens: cachedTokens ?? this.cachedTokens,
      totalTokens: totalTokens ?? this.totalTokens,
      contentBlocks: contentBlocks ?? this.contentBlocks,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'authorName': authorName,
        'content': content,
        'thinkingContent': thinkingContent,
        'generationStatus': generationStatus.name,
        'generationDurationMs': generationDurationMs,
        'createdAt': createdAt.toIso8601String(),
        'memberId': memberId,
        'isUser': isUser,
        'taskIds': taskIds,
        if (inputTokens != null) 'inputTokens': inputTokens,
        if (outputTokens != null) 'outputTokens': outputTokens,
        if (cachedTokens != null) 'cachedTokens': cachedTokens,
        if (totalTokens != null) 'totalTokens': totalTokens,
        'contentBlocks': contentBlocks.map((block) => block.toJson()).toList(),
      };

  factory ChatMessage.fromJson(Map<String, Object?> json) => ChatMessage(
        id: json['id'] as String,
        authorName: json['authorName'] as String,
        content: json['content'] as String,
        thinkingContent: json['thinkingContent'] as String?,
        generationStatus: ChatMessageGenerationStatus.values.byName(
          json['generationStatus'] as String? ??
              ChatMessageGenerationStatus.complete.name,
        ),
        generationDurationMs: (json['generationDurationMs'] as num?)?.toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        memberId: json['memberId'] as String?,
        isUser: (json['isUser'] as bool?) ?? false,
        taskIds: List<String>.from(json['taskIds'] as List? ?? const []),
        inputTokens: (json['inputTokens'] as num?)?.toInt(),
        outputTokens: (json['outputTokens'] as num?)?.toInt(),
        cachedTokens: (json['cachedTokens'] as num?)?.toInt(),
        totalTokens: (json['totalTokens'] as num?)?.toInt(),
        contentBlocks: (json['contentBlocks'] as List? ?? const [])
            .map(
              (item) => ChatMessageContentBlock.fromJson(
                  item as Map<String, Object?>),
            )
            .toList(),
      );
}

class QueuedTask {
  const QueuedTask({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.originalText,
    required this.priority,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.notes = const [],
    this.messageIds = const [],
  });

  final String id;
  final String conversationId;
  final String title;
  final String originalText;
  final List<String> notes;
  final int priority;
  final QueuedTaskStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> messageIds;

  QueuedTask copyWith({
    String? title,
    List<String>? notes,
    int? priority,
    QueuedTaskStatus? status,
    DateTime? updatedAt,
    List<String>? messageIds,
  }) {
    return QueuedTask(
      id: id,
      conversationId: conversationId,
      title: title ?? this.title,
      originalText: originalText,
      notes: notes ?? this.notes,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageIds: messageIds ?? this.messageIds,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'title': title,
        'originalText': originalText,
        'notes': notes,
        'priority': priority,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messageIds': messageIds,
      };

  factory QueuedTask.fromJson(Map<String, Object?> json) => QueuedTask(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        title: json['title'] as String,
        originalText: json['originalText'] as String,
        notes: List<String>.from(json['notes'] as List? ?? const []),
        priority: (json['priority'] as num?)?.toInt() ?? 0,
        status: QueuedTaskStatus.values.byName(json['status'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        messageIds: List<String>.from(json['messageIds'] as List? ?? const []),
      );
}

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.teamId,
    required this.messages,
    this.memberId,
    this.currentRound = 0,
    this.status = ConversationStatus.idle,
  });

  final String id;
  final String title;
  final String teamId;
  final String? memberId;
  final List<ChatMessage> messages;
  final int currentRound;
  final ConversationStatus status;

  Conversation copyWith({
    String? title,
    List<ChatMessage>? messages,
    String? memberId,
    int? currentRound,
    ConversationStatus? status,
  }) {
    return Conversation(
      id: id,
      title: title ?? this.title,
      teamId: teamId,
      memberId: memberId ?? this.memberId,
      messages: messages ?? this.messages,
      currentRound: currentRound ?? this.currentRound,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'teamId': teamId,
        'memberId': memberId,
        'messages': messages.map((message) => message.toJson()).toList(),
        'currentRound': currentRound,
        'status': status.name,
      };

  factory Conversation.fromJson(Map<String, Object?> json) => Conversation(
        id: json['id'] as String,
        title: json['title'] as String,
        teamId: json['teamId'] as String,
        memberId: json['memberId'] as String?,
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
    this.metadata,
  });

  final String id;
  final String action;
  final String detail;
  final Map<String, Object?>? metadata;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'action': action,
        'detail': detail,
        'metadata': metadata,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AuditEntry.fromJson(Map<String, Object?> json) {
    final metadata = json['metadata'];
    return AuditEntry(
      id: json['id'] as String,
      action: json['action'] as String,
      detail: json['detail'] as String,
      metadata: metadata is Map ? Map<String, Object?>.from(metadata) : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
