import 'dart:io';

import '../core/commands/command_service.dart';
import '../core/domain.dart';
import '../core/model_gateway.dart';
import '../core/orchestrator.dart';
import 'app_controller_helpers.dart';
import 'conversation_title_generator.dart';
import 'state_lookup.dart';
import 'task_queue_controller.dart';
import 'workspace_command_controller.dart';

typedef DispatchStateReader = AppState Function();
typedef DispatchStateCommitter = void Function(AppState state);
typedef DispatchConversationIdReader = String Function();
typedef DispatchNotifier = void Function();
typedef DispatchDraftCleaner = void Function(String conversationId);

class DispatchController {
  DispatchController({
    required this.readState,
    required this.commit,
    required this.taskQueue,
    required this.workspaceCommands,
    required this.titleGenerator,
    required this.orchestrator,
    required this.commandService,
    required this.selectedConversationId,
    required this.notify,
    required this.onStreamingDraft,
    required this.clearStreamingDraftsForConversation,
  });

  final DispatchStateReader readState;
  final DispatchStateCommitter commit;
  final TaskQueueController taskQueue;
  final WorkspaceCommandController workspaceCommands;
  final ConversationTitleGenerator titleGenerator;
  final TeamOrchestrator orchestrator;
  final CommandService commandService;
  final DispatchConversationIdReader selectedConversationId;
  final DispatchNotifier notify;
  final StreamingMessageDraftHandler onStreamingDraft;
  final DispatchDraftCleaner clearStreamingDraftsForConversation;

  bool isDispatching = false;
  String? error;
  String? _runningTaskId;
  ModelRequestCancellation? _activeCancellation;
  String? _activeDispatchConversationId;
  ConversationStatus? _requestedCancellationStatus;

  AppState get state => readState();

  QueuedTask? get currentRunningTask {
    final id = _runningTaskId;
    if (id == null) {
      return null;
    }
    return taskQueue.taskByIdOrNull(id);
  }

  bool isConversationDispatching(String conversationId) {
    return isDispatching && _activeDispatchConversationId == conversationId;
  }

  Future<void> runNextQueuedTask() async {
    if (_runningTaskId != null) {
      return;
    }
    final next = firstQueuedTaskOrNull(
      taskQueue.pendingTasksForConversation(selectedConversationId()),
    );
    if (next == null) {
      return;
    }
    _runningTaskId = next.id;
    isDispatching = true;
    error = null;
    final cancellation = ModelRequestCancellation();
    _activeCancellation = cancellation;
    taskQueue.updateTaskStatus(next.id, QueuedTaskStatus.running);
    try {
      final updated = await orchestrator.dispatchQueuedTask(
        state,
        taskId: next.id,
        cancellation: cancellation,
        onProgress: commit,
        onStreamingDraft: onStreamingDraft,
      );
      if (!cancellation.isCancelled) {
        commit(updated);
        taskQueue.updateTaskStatus(next.id, QueuedTaskStatus.completed);
      }
    } on ModelGatewayException {
      if (cancellation.isCancelled) {
        taskQueue.updateTaskStatus(next.id, QueuedTaskStatus.paused);
      } else {
        // 错误消息已在 orchestrator 中添加到对话中，不需要设置 error 字段
        taskQueue.updateTaskStatus(next.id, QueuedTaskStatus.failed);
      }
    } catch (exception) {
      if (cancellation.isCancelled) {
        taskQueue.updateTaskStatus(next.id, QueuedTaskStatus.paused);
      } else {
        // 错误消息已在 orchestrator 中添加到对话中，不需要设置 error 字段
        taskQueue.updateTaskStatus(next.id, QueuedTaskStatus.failed);
      }
    } finally {
      if (_runningTaskId == next.id) {
        _runningTaskId = null;
      }
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
      isDispatching = false;
      clearStreamingDraftsForConversation(next.conversationId);
      notify();
    }
  }

  void pauseTask(String taskId) {
    if (_runningTaskId == taskId) {
      _activeCancellation?.cancel();
    }
    taskQueue.updateTaskStatus(taskId, QueuedTaskStatus.paused);
  }

  Future<void> resumeTask(String taskId) async {
    taskQueue.updateTaskStatus(taskId, QueuedTaskStatus.pending);
    await runNextQueuedTask();
  }

  Future<void> dispatch(String text) async {
    await dispatchConversation(selectedConversationId(), text);
  }

  Future<void> dispatchConversation(
    String conversationId,
    String text,
  ) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || isDispatching) {
      return;
    }
    if (!_canDispatchConversation(conversationId)) {
      notify();
      return;
    }
    isDispatching = true;
    error = null;
    final cancellation = ModelRequestCancellation();
    _activeCancellation = cancellation;
    _activeDispatchConversationId = conversationId;
    _requestedCancellationStatus = null;
    notify();
    try {
      final conversation = conversationByIdOrThrow(state, conversationId);
      final shouldGenerateTitle =
          titleGenerator.shouldGenerateAfterFirstUserMessage(conversation);
      if (conversation.memberId == null) {
        commit(
          await orchestrator.dispatchTeamTask(
            state,
            teamId: conversation.teamId,
            conversationId: conversation.id,
            userText: trimmed,
            cancellation: cancellation,
            onProgress: commit,
            onStreamingDraft: onStreamingDraft,
          ),
        );
      } else if (orchestrator
          .secretaryPrivateDispatchTargets(
            state,
            conversationId: conversation.id,
            userText: trimmed,
          )
          .isNotEmpty) {
        commit(
          await orchestrator.dispatchSecretaryPrivateMemberTask(
            state,
            conversationId: conversation.id,
            userText: trimmed,
            cancellation: cancellation,
            onProgress: commit,
            onStreamingDraft: onStreamingDraft,
          ),
        );
      } else {
        commit(
          await orchestrator.dispatchMemberChat(
            state,
            conversationId: conversation.id,
            userText: trimmed,
            cancellation: cancellation,
            onProgress: commit,
            onStreamingDraft: onStreamingDraft,
          ),
        );
      }
      if (shouldGenerateTitle) {
        await titleGenerator.generateAfterFirstUserMessage(
          conversationId: conversationId,
          firstUserMessage: trimmed,
        );
      }
    } catch (exception) {
      if (cancellation.isCancelled) {
        _commitCancelledDispatch(
          conversationId,
          _requestedCancellationStatus ?? ConversationStatus.stopped,
        );
        return;
      }
      error = exception.toString();
      final conversation = conversationByIdOrThrow(state, conversationId);
      final failed = conversation.copyWith(
        status: ConversationStatus.failed,
        messages: [
          ...conversation.messages,
          ChatMessage(
            id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
            authorName: '系统',
            content: '模型调用失败：$error',
            createdAt: DateTime.now(),
          ),
        ],
      );
      commit(
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
      if (_activeDispatchConversationId == conversationId) {
        _activeDispatchConversationId = null;
      }
      _requestedCancellationStatus = null;
      clearStreamingDraftsForConversation(conversationId);
      notify();
    }
  }

  void pauseConversation() {
    pauseConversationById(selectedConversationId());
  }

  void pauseConversationById(String conversationId) {
    if (isConversationDispatching(conversationId)) {
      _cancelActiveDispatch(conversationId, ConversationStatus.paused);
      return;
    }
    _setConversationStatus(conversationId, ConversationStatus.paused);
  }

  void resumeConversation() {
    _setConversationStatus(selectedConversationId(), ConversationStatus.idle);
  }

  void stopConversation() {
    stopConversationById(selectedConversationId());
  }

  void stopConversationById(String conversationId) {
    if (isConversationDispatching(conversationId)) {
      _cancelActiveDispatch(conversationId, ConversationStatus.stopped);
      return;
    }
    _setConversationStatus(conversationId, ConversationStatus.stopped);
  }

  Future<void> approveExecuteCommandRequestAndContinue(
    String requestId, {
    Future<ProcessResult> Function(String command, String workingDirectory)?
        runner,
  }) async {
    if (isDispatching) {
      return;
    }
    isDispatching = true;
    error = null;
    final cancellation = ModelRequestCancellation();
    _activeCancellation = cancellation;
    _requestedCancellationStatus = null;
    notify();
    try {
      var request =
          state.commandRequests.firstWhere((item) => item.id == requestId);
      if (request.status == CommandRequestStatus.pending) {
        workspaceCommands.updateCommandRequestStatus(
          requestId,
          CommandRequestStatus.approved,
        );
        request =
            state.commandRequests.firstWhere((item) => item.id == requestId);
      }
      final commandRunner = runner ?? commandService.runner;
      final executed = await workspaceCommands.executeCommandRequest(
        request.id,
        runner: commandRunner,
      );
      final conversationId = executed.conversationId;
      if (conversationId != null && conversationId.trim().isNotEmpty) {
        _activeDispatchConversationId = conversationId;
        commit(
          await orchestrator.continueMemberChatAfterCommandResult(
            state,
            conversationId: conversationId,
            request: executed,
            cancellation: cancellation,
            onProgress: commit,
            onStreamingDraft: onStreamingDraft,
          ),
        );
      }
    } catch (exception) {
      if (cancellation.isCancelled) {
        final conversationId = _activeDispatchConversationId;
        if (conversationId != null) {
          _commitCancelledDispatch(
            conversationId,
            _requestedCancellationStatus ?? ConversationStatus.stopped,
          );
        }
        return;
      }
      error = exception.toString();
      notify();
    } finally {
      isDispatching = false;
      if (identical(_activeCancellation, cancellation)) {
        _activeCancellation = null;
      }
      _activeDispatchConversationId = null;
      _requestedCancellationStatus = null;
      notify();
    }
  }

  bool _canDispatchConversation(String conversationId) {
    final status = conversationByIdOrThrow(state, conversationId).status;
    if (status == ConversationStatus.paused) {
      error = '当前会话已暂停，请先点击继续。';
      return false;
    }
    return true;
  }

  void _setConversationStatus(
    String conversationId,
    ConversationStatus status,
  ) {
    final updated =
        conversationByIdOrThrow(state, conversationId).copyWith(status: status);
    commit(
      state.copyWith(
        conversations: state.conversations
            .map((item) => item.id == updated.id ? updated : item)
            .toList(),
      ),
    );
  }

  void _cancelActiveDispatch(
    String conversationId,
    ConversationStatus status,
  ) {
    _requestedCancellationStatus = status;
    _activeCancellation?.cancel();
    _setConversationStatus(conversationId, status);
  }

  void _commitCancelledDispatch(
    String conversationId,
    ConversationStatus status,
  ) {
    final action = status == ConversationStatus.paused
        ? 'team_task_paused'
        : 'team_task_stopped';
    final content = status == ConversationStatus.paused
        ? '任务已暂停，继续后可以重新发起下一轮协作。'
        : '任务已停止，本轮未完成的模型请求已取消。';
    final conversation = conversationByIdOrThrow(state, conversationId);
    final now = DateTime.now();
    final updated = conversation.copyWith(
      status: status,
      messages: [
        ..._stopStreamingMessages(conversation.messages, now),
        ChatMessage(
          id: 'msg-${now.microsecondsSinceEpoch}',
          authorName: '系统',
          content: content,
          createdAt: now,
        ),
      ],
    );
    final cancelledAssignments = _cancelOpenAssignments(
      state.taskAssignments,
      updated.id,
    );
    commit(
      state.copyWith(
        conversations: state.conversations
            .map((item) => item.id == updated.id ? updated : item)
            .toList(),
        taskAssignments: _ensureCancelledAssignment(
          cancelledAssignments,
          updated,
        ),
        auditLog: [
          ...state.auditLog,
          AuditEntry(
            id: 'audit-${DateTime.now().microsecondsSinceEpoch}',
            action: action,
            detail: requireTeam(state, conversation.teamId).id,
            createdAt: DateTime.now(),
          ),
        ],
      ),
    );
  }

  List<ChatMessage> _stopStreamingMessages(
    List<ChatMessage> messages,
    DateTime stoppedAt,
  ) {
    return messages
        .map(
          (message) => message.generationStatus ==
                  ChatMessageGenerationStatus.streaming
              ? message.copyWith(
                  generationStatus: ChatMessageGenerationStatus.stopped,
                  generationDurationMs: message.generationDurationMs ??
                      stoppedAt.difference(message.createdAt).inMilliseconds,
                )
              : message,
        )
        .toList();
  }

  List<TaskAssignment> _cancelOpenAssignments(
    List<TaskAssignment> assignments,
    String conversationId,
  ) {
    return assignments
        .map(
          (assignment) => assignment.conversationId == conversationId &&
                  (assignment.status == TaskAssignmentStatus.pending ||
                      assignment.status == TaskAssignmentStatus.running)
              ? assignment.copyWith(
                  status: TaskAssignmentStatus.cancelled,
                  completedAt: DateTime.now(),
                )
              : assignment,
        )
        .toList();
  }

  List<TaskAssignment> _ensureCancelledAssignment(
    List<TaskAssignment> assignments,
    Conversation conversation,
  ) {
    final hasCancelled = assignments.any(
      (assignment) =>
          assignment.conversationId == conversation.id &&
          assignment.status == TaskAssignmentStatus.cancelled,
    );
    if (hasCancelled) {
      return assignments;
    }
    final team = requireTeam(state, conversation.teamId);
    final teamMembers = state.members
        .where((member) => team.memberIds.contains(member.id))
        .toList();
    final member = conversation.memberId == null
        ? teamMembers.firstWhere(
            (item) => !item.isSecretary,
            orElse: () => teamMembers.first,
          )
        : requireMember(state, conversation.memberId!);
    final role = requireRole(state, member.roleId);
    return [
      ...assignments,
      TaskAssignment(
        id: 'task-cancelled-${DateTime.now().microsecondsSinceEpoch}',
        conversationId: conversation.id,
        round: conversation.currentRound + 1,
        memberId: member.id,
        memberName: member.name,
        roleName: role.name,
        instruction: '请求已取消',
        status: TaskAssignmentStatus.cancelled,
        createdAt: DateTime.now(),
        completedAt: DateTime.now(),
      ),
    ];
  }
}
