import '../core/domain.dart';
import '../core/model_gateway.dart';
import 'app_controller_helpers.dart';
import 'state_lookup.dart';

typedef TaskQueueStateReader = AppState Function();
typedef TaskQueueStateCommitter = void Function(AppState state);

class TaskQueueController {
  const TaskQueueController({
    required this.readState,
    required this.commit,
    required this.gateway,
  });

  final TaskQueueStateReader readState;
  final TaskQueueStateCommitter commit;
  final ModelGateway gateway;

  AppState get state => readState();

  List<QueuedTask> tasksForConversation(String conversationId) {
    return state.queuedTasks
        .where((task) => task.conversationId == conversationId)
        .toList();
  }

  List<QueuedTask> pendingTasksForConversation(String conversationId) {
    final tasks = tasksForConversation(conversationId)
        .where((task) => task.status == QueuedTaskStatus.pending)
        .toList();
    tasks.sort(queuedTaskSort);
    return tasks;
  }

  QueuedTask? taskByIdOrNull(String taskId) {
    return queuedTaskByIdOrNull(state, taskId);
  }

  Future<void> enqueueConversationTask(
    String conversationId,
    String text, {
    int priority = 0,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final conversation = conversationByIdOrThrow(state, conversationId);
    final team = requireTeam(state, conversation.teamId);
    final secretary = state.members.firstWhere(
      (member) => member.id == team.secretaryMemberId,
    );
    final secretaryRole = requireRole(state, secretary.roleId);
    final secretaryModel = requireModel(state, secretary.modelId);
    final now = DateTime.now();
    final generating = ChatMessage(
      id: 'msg-${now.microsecondsSinceEpoch}',
      authorName: secretary.name,
      memberId: secretary.id,
      content: '正在生成任务',
      createdAt: now,
    );
    _appendMessage(conversation.id, generating);
    try {
      final title = await gateway.complete(
        model: secretaryModel,
        systemPrompt: secretaryRole.renderSystemPrompt(
          memberName: secretary.name,
          teamName: team.name,
        ),
        messages: [
          ChatMessage(
            id: 'msg-title-source-${now.microsecondsSinceEpoch}',
            authorName: '我',
            content: '请为这条任务生成一句简短标题：$trimmed',
            createdAt: now,
            isUser: true,
          ),
        ],
      );
      final createdAt = DateTime.now();
      final taskId = 'task-${createdAt.microsecondsSinceEpoch}';
      final userMessage = ChatMessage(
        id: 'msg-${createdAt.microsecondsSinceEpoch}',
        authorName: '我',
        content: trimmed,
        createdAt: createdAt,
        isUser: true,
        taskIds: [taskId],
      );
      final latestConversation = conversationByIdOrThrow(
        state,
        conversation.id,
      );
      commit(
        state.copyWith(
          queuedTasks: [
            ...state.queuedTasks,
            QueuedTask(
              id: taskId,
              conversationId: conversation.id,
              title: title.trim(),
              originalText: trimmed,
              priority: priority,
              status: QueuedTaskStatus.pending,
              createdAt: createdAt,
              updatedAt: createdAt,
              messageIds: [userMessage.id],
            ),
          ],
          conversations: state.conversations
              .map(
                (item) => item.id == conversation.id
                    ? latestConversation.copyWith(
                        messages: [
                          ...latestConversation.messages
                              .where((message) => message.id != generating.id),
                          userMessage,
                        ],
                      )
                    : item,
              )
              .toList(),
        ),
      );
    } catch (exception) {
      _replaceMessageContent(
        generating.id,
        '任务标题生成失败：$exception',
      );
    }
  }

  void updateTaskPriority(String taskId, int priority) {
    commit(
      state.copyWith(
        queuedTasks: state.queuedTasks
            .map(
              (task) => task.id == taskId
                  ? task.copyWith(
                      priority: priority,
                      updatedAt: DateTime.now(),
                    )
                  : task,
            )
            .toList(),
      ),
    );
  }

  void appendTaskNote(String taskId, String note) {
    final trimmed = note.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final task = state.queuedTasks.firstWhere((item) => item.id == taskId);
    final message = ChatMessage(
      id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
      authorName: '系统',
      content: '已为任务追加备注',
      createdAt: DateTime.now(),
      taskIds: [taskId],
    );
    commit(
      state.copyWith(
        queuedTasks: state.queuedTasks
            .map(
              (item) => item.id == taskId
                  ? item.copyWith(
                      notes: [...item.notes, trimmed],
                      messageIds: [...item.messageIds, message.id],
                      updatedAt: DateTime.now(),
                    )
                  : item,
            )
            .toList(),
        conversations: state.conversations
            .map(
              (conversation) => conversation.id == task.conversationId
                  ? conversation.copyWith(
                      messages: [...conversation.messages, message],
                    )
                  : conversation,
            )
            .toList(),
      ),
    );
  }

  void deleteTask(String taskId) {
    final task = state.queuedTasks.firstWhere((item) => item.id == taskId);
    commit(
      state.copyWith(
        queuedTasks:
            state.queuedTasks.where((item) => item.id != taskId).toList(),
        conversations: state.conversations
            .map(
              (conversation) => conversation.id == task.conversationId
                  ? conversation.copyWith(
                      messages: conversation.messages
                          .where(
                            (message) =>
                                !message.taskIds.contains(taskId) &&
                                !task.messageIds.contains(message.id),
                          )
                          .toList(),
                    )
                  : conversation,
            )
            .toList(),
      ),
    );
  }

  void updateTaskStatus(String taskId, QueuedTaskStatus status) {
    commit(
      state.copyWith(
        queuedTasks: state.queuedTasks
            .map(
              (task) => task.id == taskId
                  ? task.copyWith(
                      status: status,
                      updatedAt: DateTime.now(),
                    )
                  : task,
            )
            .toList(),
      ),
    );
  }

  void _appendMessage(String conversationId, ChatMessage message) {
    commit(
      state.copyWith(
        conversations: state.conversations
            .map(
              (conversation) => conversation.id == conversationId
                  ? conversation.copyWith(
                      messages: [...conversation.messages, message],
                    )
                  : conversation,
            )
            .toList(),
      ),
    );
  }

  void _replaceMessageContent(String messageId, String content) {
    commit(
      state.copyWith(
        conversations: state.conversations
            .map(
              (conversation) => conversation.copyWith(
                messages: conversation.messages
                    .map(
                      (message) => message.id == messageId
                          ? ChatMessage(
                              id: message.id,
                              authorName: message.authorName,
                              content: content,
                              thinkingContent: message.thinkingContent,
                              generationStatus: message.generationStatus,
                              generationDurationMs:
                                  message.generationDurationMs,
                              createdAt: message.createdAt,
                              memberId: message.memberId,
                              isUser: message.isUser,
                              taskIds: message.taskIds,
                            )
                          : message,
                    )
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
  }
}
