# Team Chat Collaboration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make chat behave as a real queued multi-agent work system: user-selected team collaboration mode, secretary planning, prioritized execution queues, pause/resume/delete lifecycle, member failure retry/reassignment, task history, message linking, and safe multi-team conversation isolation.

**Architecture:** Keep the current Flutter/AppController/TeamOrchestrator shape, but introduce explicit task records that both team group chat and member private chat use. `TeamOrchestrator` remains the domain workflow owner; `Team.collaborationMode` chooses serial or parallel worker execution; `AppController` owns queue ordering, UI state transitions, pause/resume/delete, and persistence; conversation IDs and task/message links become globally safe across teams.

**Tech Stack:** Dart, Flutter desktop, `flutter_test`, existing `ModelGateway`, existing `AppState` domain model.

---

## File Structure

- Modify `lib/core/orchestrator.dart`
  - Add secretary model calls for assignment planning and final synthesis.
  - Execute members according to `Team.collaborationMode`.
  - In serial mode, pass role-specific instructions and prior member responses to each next member.
  - In parallel mode, launch member calls together from the same secretary plan context.
  - Retry failed member calls once, then reassign to the highest-priority same-role eligible member, then mark failed and continue to summary when reassignment cannot recover.
  - Keep gateway calls cancellable and resumable from persisted task state.
- Modify `lib/core/domain.dart`
  - Add `TeamCollaborationMode { serial, parallel }`.
  - Persist `Team.collaborationMode` in JSON.
  - Add numeric `TeamMember.executionPriority`, default `0`, any integer.
  - Add queued task records with priority, status, original text, notes, generated title, message links, and timestamps.
  - Replace single-message task association with `ChatMessage.taskIds: List<String>` and task `messageIds: List<String>`.
- Modify `lib/app.dart`
  - Let team creation choose serial or parallel collaboration.
  - Display the selected collaboration mode in team management.
  - Add send-priority menu, queue bar, pause/resume/delete actions, task notes, priority editing, and history navigation.
  - Make member conversation IDs include `teamId`.
  - Make `startMemberChat` select the active team's member conversation.
  - Persist paused state and continue from the first unfinished task/action.
- Modify `test/core/domain_test.dart`
  - Add domain serialization tests for collaboration mode.
  - Add domain serialization tests for member priority, queued tasks, task notes, task/message links, and paused state.
  - Add orchestrator tests for secretary planning, serial member context, parallel member launch context, synthesis, and failure behavior.
- Modify `test/app_widget_test.dart`
  - Add controller/widget tests for team creation collaboration mode, queue priority, pause/resume/delete, history, message highlighting, multi-team private-chat isolation, and failure recovery.
- Optionally modify `README.md`
  - Update wording only after behavior matches the stronger collaboration claim.

## Confirmed Product Decisions

These choices were confirmed by the user through the Superpowers one-question-at-a-time flow. Do not silently override them during implementation.

### Team Collaboration

- Creating a team shows a visible collaboration-mode control.
- New teams default to `serial`.
- Existing teams loaded from old JSON without `collaborationMode` migrate to `serial`.
- Collaboration modes:
  - `serial`: execute assignments strictly in secretary text order; later members see prior member outputs; after each member completes, secretary produces an incremental summary; after all work, secretary produces a final summary.
  - `parallel`: members execute different assigned tasks in parallel; each member sees the full prior chat history, the secretary plan, and its own assignment, but not sibling outputs from the same round; no per-member incremental summary; final summary runs after all parallel work completes.
- If a member receives multiple tasks in one round, the member runs its own tasks serially. In parallel mode, different members still run concurrently.

### Secretary Planning

- Task title generation happens before queue insertion and uses the secretary member's model.
- While title generation runs, the chat shows that the secretary is generating the task.
- If title generation succeeds, no extra chat message is added; the generated title appears in the queue.
- If title generation fails, the secretary shows an error message and the task is not queued.
- Secretary assignment format is plain text: `成员名: 具体任务`.
- If the secretary omits a member, that member is skipped for the round.
- If the secretary assigns work to a nonexistent member, request one secretary re-plan.
- If re-plan still contains nonexistent members, the whole round fails before member execution.
- If re-plan produces no valid member tasks, only the secretary replies directly to the user; no member calls run.
- The same member may receive multiple assignments and executes them in assignment order.
- Tell the secretary about member execution priority only when multiple members share the same role; otherwise avoid adding priority noise to the prompt.

### Member Priority and Failure Recovery

- Members have numeric execution priority on the member config.
- Member execution priority default is `0`.
- Member execution priority accepts any integer.
- Member priority affects same-role reassignment and secretary hints only; it does not affect user task queue order.
- On member model failure: retry the same member once.
- If retry fails, reassign to an eligible same-role member.
- Reassignment chooses the highest execution-priority same-role member; when priorities tie, choose the first same-role member that has not executed a task in the current round.
- If no same-role member exists, mark that assignment failed and let the secretary summarize successes and failures.
- In parallel mode, failed members' retry/reassignment flows also run in parallel.
- Chat shows detailed failure process: error, retry, reassignment, and final result.

### Queue, Priority, Pause, Resume, Delete

- Queues apply to both team group chats and member private chats.
- User task priority default is `0`, accepts any integer, and is set from a menu beside the send button.
- Plain send uses default priority `0`.
- Current execution is never preempted by a higher-priority new task.
- Waiting queue order is priority descending, then send-time FIFO for equal priority.
- Editing a waiting task's priority does not interrupt the current task, but affects waiting tasks' future dispatch order.
- While paused, users may send new tasks; new tasks enter the queue after the paused/current branch according to the queue ordering rules.
- Queue tasks can be deleted with confirmation.
- Waiting task priority can be edited directly in the queue.
- Waiting task original content cannot be edited. Users may append notes.
- Executing a task sends the original task plus all appended notes to the model.
- Completed tasks remain in task history.
- Completed history tasks can be deleted with confirmation.
- Paused state persists locally; after app restart, the task stays paused and can continue.
- Pause keeps completed member results and secretary incremental summaries; unfinished/not-started work stays resumable.
- Resume continues from the first unfinished/not-started task/action.
- In member private chat, pause cancels the current model request; resume re-calls that member model while preserving completed history.
- In team group chat, pause cancels the currently executing member request; resume re-executes that task.
- If pause happens during a secretary incremental summary in serial mode, resume re-executes that incremental summary.
- In parallel mode, pause keeps completed member results and only re-executes unfinished/cancelled member tasks.
- Deleting a round deletes that round's user message, secretary plan, member outputs, incremental summaries, final summary, and task records.
- Deleting a running task first pauses/cancels the active request, then shows confirmation.
- Deleting a paused task leaves the queue paused; the user must manually continue.
- Deleting a waiting task immediately re-sorts the remaining waiting queue.

### Queue UI

- Task priority entry is a small menu button on the right side of the send button.
- Queue appears at the top of the chat message area as an expandable queue bar.
- Queue bar defaults collapsed.
- Collapsed queue bar shows queue count and the currently executing task title.
- If nothing is executing but tasks are waiting, collapsed queue bar shows only queue count.
- Expanded queue shows waiting, paused, executing, and completed-history tasks.
- Completed history in the queue defaults to the latest 10 items and offers a path to the full history page.
- Queue task item fields: title, priority, status, send time, original task summary, and note count.
- Clicking a queue task expands inline details.
- Inline details show full original task, all notes, and linked chat-message jumps.
- Linked chat-message jumps scroll to the message and briefly highlight it.
- Add-note entry lives in the inline task details.
- Adding a note shows a system message: `已为任务追加备注`.
- Delete entry appears both on the task item and in inline details.
- Delete confirmation shows task title and `此操作不可撤销`.
- Priority editing appears both on the task item and in inline details.
- Priority edits update the number without snackbar/system-message feedback.

### Execution Controls

- There is no "stop" product action. Use pause and delete.
- When executing and input is empty, the main input button shows pause.
- When executing and input has content, the main input button shows send; pause appears beside the current executing task in the queue bar.
- When paused, the main input button still follows input content and can send queued tasks; continue appears on the paused task item.

### History UI

- Add a left-nav `历史` entry.
- The history page shows task history across the whole app.
- History supports filtering by conversation, status, priority range, time range, and member/role.
- History search searches task title only.
- Clicking a history task expands inline details.
- History details show linked chat-message jumps that return to the message and highlight it.
- Deleting a history task requires confirmation.
- Completed task priority is read-only in history.

### Task/Message Linking and Deletion

- `ChatMessage` uses `taskIds: List<String>`. Normal messages usually have a single task id; system messages may relate to multiple tasks.
- Task records store `messageIds: List<String>` for precise linked-message tracking.
- Deleting a task removes associated chat messages.
- If later messages referenced deleted content, keep the later messages and show `引用内容已删除` where the deleted reference appeared.
- Deleted tasks are fully removed from history and no longer displayed.

### Status Labels

- Use these user-facing status names: `待执行`, `执行中`, `已暂停`, `已完成`, `失败`.
- Do not show deleted tasks as a status because deleted tasks are removed.

## Task Breakdown Status

The detailed task breakdown below was drafted before the queue, pause/resume, delete, member priority, retry/reassignment, history, and message-linking requirements were confirmed. It is now a **legacy draft** and must not be executed as-is.

Execute the **Canonical Implementation Plan** below. Ignore the legacy draft after it unless a human explicitly asks to compare old and new plans.

## Canonical Implementation Plan

### Task 1: Domain Model and JSON Migration

**Files:**
- Modify: `lib/core/domain.dart`
- Test: `test/core/domain_test.dart`

- [ ] **Step 1: Add failing domain tests**

Add tests for team mode migration, member priority, queued task JSON, notes, and task/message links:

```dart
test('team mode and member priority persist with backward-compatible defaults', () {
  final oldTeam = Team.fromJson({
    'id': 'team-old',
    'name': '旧团队',
    'memberIds': ['member-secretary'],
    'secretaryMemberId': 'member-secretary',
    'maxRounds': 8,
  });
  expect(oldTeam.collaborationMode, TeamCollaborationMode.serial);

  final member = TeamMember.fromJson({
    'id': 'member-a',
    'name': '成员 A',
    'roleId': 'role-frontend',
    'modelId': 'model-main',
    'isSecretary': false,
  });
  expect(member.executionPriority, 0);

  final restored = Team.fromJson(oldTeam.copyWith(
    collaborationMode: TeamCollaborationMode.parallel,
  ).toJson());
  expect(restored.collaborationMode, TeamCollaborationMode.parallel);
});

test('queued task persists priority notes status and message links', () {
  final task = QueuedTask(
    id: 'task-1',
    conversationId: 'conv-team-default',
    title: '实现登录页',
    originalText: '实现登录页并补测试',
    notes: const ['补充移动端适配', '优先检查失败态'],
    priority: 10,
    status: QueuedTaskStatus.paused,
    createdAt: DateTime(2026, 6, 14, 10),
    updatedAt: DateTime(2026, 6, 14, 11),
    messageIds: const ['msg-1', 'msg-2'],
  );

  final restored = QueuedTask.fromJson(task.toJson());

  expect(restored.title, '实现登录页');
  expect(restored.notes, ['补充移动端适配', '优先检查失败态']);
  expect(restored.priority, 10);
  expect(restored.status, QueuedTaskStatus.paused);
  expect(restored.messageIds, ['msg-1', 'msg-2']);
});

test('chat messages persist related task ids', () {
  final message = ChatMessage(
    id: 'msg-1',
    authorName: '系统',
    content: '已为任务追加备注',
    createdAt: DateTime(2026, 6, 14),
    taskIds: const ['task-1', 'task-2'],
  );

  final restored = ChatMessage.fromJson(message.toJson());

  expect(restored.taskIds, ['task-1', 'task-2']);
});
```

- [ ] **Step 2: Run domain tests and confirm failure**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "team mode and member priority persist with backward-compatible defaults"
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "queued task persists priority notes status and message links"
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "chat messages persist related task ids"
```

Expected: all fail because the new fields/types do not exist.

- [ ] **Step 3: Add enums**

In `lib/core/domain.dart`, add:

```dart
enum TeamCollaborationMode { serial, parallel }

enum QueuedTaskStatus { pending, running, paused, completed, failed }
```

- [ ] **Step 4: Extend `TeamMember`**

Add `executionPriority`:

```dart
class TeamMember {
  const TeamMember({
    required this.id,
    required this.name,
    required this.roleId,
    required this.modelId,
    this.isSecretary = false,
    this.executionPriority = 0,
  });

  final int executionPriority;
}
```

Update `copyWith`, `toJson`, and `fromJson`:

```dart
executionPriority: executionPriority ?? this.executionPriority,
```

```dart
'executionPriority': executionPriority,
```

```dart
executionPriority: (json['executionPriority'] as num?)?.toInt() ?? 0,
```

- [ ] **Step 5: Extend `Team`**

Add `collaborationMode`:

```dart
class Team {
  const Team({
    required this.id,
    required this.name,
    required this.memberIds,
    required this.secretaryMemberId,
    this.maxRounds = 8,
    this.collaborationMode = TeamCollaborationMode.serial,
  });

  final TeamCollaborationMode collaborationMode;
}
```

Update `copyWith`, `toJson`, and `fromJson`:

```dart
Team copyWith({
  List<String>? memberIds,
  int? maxRounds,
  TeamCollaborationMode? collaborationMode,
}) => Team(
      id: id,
      name: name,
      memberIds: memberIds ?? this.memberIds,
      secretaryMemberId: secretaryMemberId,
      maxRounds: maxRounds ?? this.maxRounds,
      collaborationMode: collaborationMode ?? this.collaborationMode,
    );
```

```dart
'collaborationMode': collaborationMode.name,
```

```dart
collaborationMode: TeamCollaborationMode.values.byName(
  json['collaborationMode'] as String? ?? TeamCollaborationMode.serial.name,
),
```

- [ ] **Step 6: Extend `ChatMessage`**

Add:

```dart
this.taskIds = const [],
```

```dart
final List<String> taskIds;
```

Persist:

```dart
'taskIds': taskIds,
```

Restore with migration:

```dart
taskIds: List<String>.from(json['taskIds'] as List? ?? const []),
```

- [ ] **Step 7: Add `QueuedTask`**

Add to `lib/core/domain.dart`:

```dart
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
```

- [ ] **Step 8: Add queued tasks to `AppState`**

Add field:

```dart
final List<QueuedTask> queuedTasks;
```

Update constructor, `copyWith`, `toJson`, `fromJson`, and `seed()` with `queuedTasks: const []`. In `fromJson`, use backward-compatible default:

```dart
queuedTasks: (json['queuedTasks'] as List? ?? const [])
    .map((item) => QueuedTask.fromJson(item as Map<String, Object?>))
    .toList(),
```

- [ ] **Step 9: Run targeted tests**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "team mode and member priority persist with backward-compatible defaults"
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "queued task persists priority notes status and message links"
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "chat messages persist related task ids"
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add lib/core/domain.dart test/core/domain_test.dart
git commit -m "Model queued chat collaboration state

Constraint: Queue, pause, history, and message deletion require durable task records.
Rejected: Encoding task lifecycle only in chat messages | It cannot support priority, resume, history, or precise deletion.
Confidence: high
Scope-risk: moderate
Directive: Keep task lifecycle state in QueuedTask and use ChatMessage.taskIds only for message association.
Tested: /Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name \"team mode and member priority persist with backward-compatible defaults\"; /Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name \"queued task persists priority notes status and message links\"; /Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name \"chat messages persist related task ids\"
Not-tested: Full Flutter widget suite."
```

### Task 2: Queue Controller Behavior

**Files:**
- Modify: `lib/app.dart`
- Modify: `test/app_widget_test.dart`

- [ ] **Step 1: Add controller tests for enqueue, sorting, notes, and deletion**

```dart
test('controller enqueues titled tasks by priority without preempting running work',
    () async {
  final gateway = ScriptedTitleGateway(title: '登录任务');
  final controller = AppController(
    AppState.seed(),
    TeamOrchestrator(gateway),
  );
  addTearDown(controller.dispose);
  controller.startTeamChat('team-default');

  await controller.enqueueCurrentConversationTask('低优先级', priority: 0);
  await controller.enqueueCurrentConversationTask('高优先级', priority: 10);
  await controller.enqueueCurrentConversationTask('同优先级', priority: 10);

  expect(
    controller.pendingTasksForCurrentConversation.map((task) => task.originalText),
    ['高优先级', '同优先级', '低优先级'],
  );
});

test('controller appends task notes and links the system message', () {
  final controller = AppController(
    AppState.seed().copyWith(
      queuedTasks: [
        QueuedTask(
          id: 'task-1',
          conversationId: 'conv-team-default',
          title: '登录任务',
          originalText: '实现登录',
          priority: 0,
          status: QueuedTaskStatus.pending,
          createdAt: DateTime(2026, 6, 14),
          updatedAt: DateTime(2026, 6, 14),
        ),
      ],
    ),
    TeamOrchestrator(FakeModelGateway()),
  );
  addTearDown(controller.dispose);
  controller.startTeamChat('team-default');

  controller.appendTaskNote('task-1', '补充移动端');

  final task = controller.state.queuedTasks.single;
  expect(task.notes, ['补充移动端']);
  expect(controller.currentConversation.messages.last.content, '已为任务追加备注');
  expect(controller.currentConversation.messages.last.taskIds, ['task-1']);
  expect(task.messageIds, contains(controller.currentConversation.messages.last.id));
});

test('controller deletes a queued task and associated messages after confirmation path',
    () {
  final message = ChatMessage(
    id: 'msg-task',
    authorName: '我',
    content: '实现登录',
    createdAt: DateTime(2026, 6, 14),
    isUser: true,
    taskIds: const ['task-1'],
  );
  final state = AppState.seed().copyWith(
    queuedTasks: [
      QueuedTask(
        id: 'task-1',
        conversationId: 'conv-team-default',
        title: '登录任务',
        originalText: '实现登录',
        priority: 0,
        status: QueuedTaskStatus.pending,
        createdAt: DateTime(2026, 6, 14),
        updatedAt: DateTime(2026, 6, 14),
        messageIds: const ['msg-task'],
      ),
    ],
    conversations: [
      AppState.seed()
          .conversations
          .firstWhere((conversation) => conversation.id == 'conv-team-default')
          .copyWith(messages: [message]),
      ...AppState.seed()
          .conversations
          .where((conversation) => conversation.id != 'conv-team-default'),
    ],
  );
  final controller = AppController(state, TeamOrchestrator(FakeModelGateway()));
  addTearDown(controller.dispose);
  controller.startTeamChat('team-default');

  controller.deleteTask('task-1');

  expect(controller.state.queuedTasks, isEmpty);
  expect(controller.currentConversation.messages, isEmpty);
});
```

- [ ] **Step 2: Add title gateway test helper**

```dart
class ScriptedTitleGateway implements ModelGateway {
  ScriptedTitleGateway({required this.title, this.fail = false});

  final String title;
  final bool fail;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    if (fail) {
      throw const ModelGatewayException('标题生成失败');
    }
    return title;
  }
}
```

- [ ] **Step 3: Implement queue selectors**

In `AppController`:

```dart
List<QueuedTask> get tasksForCurrentConversation => state.queuedTasks
    .where((task) => task.conversationId == currentConversation.id)
    .toList();

List<QueuedTask> get pendingTasksForCurrentConversation {
  final tasks = tasksForCurrentConversation
      .where((task) => task.status == QueuedTaskStatus.pending)
      .toList();
  tasks.sort(_queuedTaskSort);
  return tasks;
}

int _queuedTaskSort(QueuedTask a, QueuedTask b) {
  final priority = b.priority.compareTo(a.priority);
  if (priority != 0) {
    return priority;
  }
  return a.createdAt.compareTo(b.createdAt);
}
```

- [ ] **Step 4: Implement title generation and enqueue**

Add:

```dart
Future<void> enqueueCurrentConversationTask(
  String text, {
  int priority = 0,
}) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return;
  }
  final conversation = currentConversation;
  final team = _requireTeam(conversation.teamId);
  final secretary = state.members.firstWhere(
    (member) => member.id == team.secretaryMemberId,
  );
  final secretaryRole = _requireRole(secretary.roleId);
  final secretaryModel = _requireModel(secretary.modelId);
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
    final title = await orchestrator.gateway.complete(
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
    final taskId = 'task-${DateTime.now().microsecondsSinceEpoch}';
    final userMessage = ChatMessage(
      id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
      authorName: '我',
      content: trimmed,
      createdAt: DateTime.now(),
      isUser: true,
      taskIds: [taskId],
    );
    _replaceMessageContent(generating.id, null);
    _commit(state.copyWith(
      queuedTasks: [
        ...state.queuedTasks,
        QueuedTask(
          id: taskId,
          conversationId: conversation.id,
          title: title.trim(),
          originalText: trimmed,
          priority: priority,
          status: QueuedTaskStatus.pending,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          messageIds: [userMessage.id],
        ),
      ],
      conversations: _replaceConversationInList(
        state.conversations,
        currentConversation.copyWith(
          messages: [
            ...currentConversation.messages
                .where((message) => message.id != generating.id),
            userMessage,
          ],
        ),
      ),
    ));
  } catch (exception) {
    _replaceMessageContent(generating.id, '任务标题生成失败：$exception');
  }
}
```

If `orchestrator.gateway` is private, add a `generateTaskTitle` method on `TeamOrchestrator` instead of exposing the gateway directly.

- [ ] **Step 5: Implement note append, priority edit, delete**

Add controller methods:

```dart
void updateTaskPriority(String taskId, int priority) {
  _commit(state.copyWith(
    queuedTasks: state.queuedTasks
        .map((task) => task.id == taskId
            ? task.copyWith(priority: priority, updatedAt: DateTime.now())
            : task)
        .toList(),
  ));
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
  _commit(state.copyWith(
    queuedTasks: state.queuedTasks
        .map((item) => item.id == taskId
            ? item.copyWith(
                notes: [...item.notes, trimmed],
                messageIds: [...item.messageIds, message.id],
                updatedAt: DateTime.now(),
              )
            : item)
        .toList(),
    conversations: _appendMessageToConversation(
      state.conversations,
      task.conversationId,
      message,
    ),
  ));
}

void deleteTask(String taskId) {
  final task = state.queuedTasks.firstWhere((item) => item.id == taskId);
  _commit(state.copyWith(
    queuedTasks: state.queuedTasks.where((item) => item.id != taskId).toList(),
    conversations: state.conversations
        .map((conversation) => conversation.id == task.conversationId
            ? conversation.copyWith(
                messages: conversation.messages
                    .where((message) => !message.taskIds.contains(taskId))
                    .toList(),
              )
            : conversation)
        .toList(),
  ));
}
```

- [ ] **Step 6: Run targeted tests**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "controller enqueues titled tasks by priority without preempting running work"
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "controller appends task notes and links the system message"
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "controller deletes a queued task and associated messages after confirmation path"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/app.dart test/app_widget_test.dart
git commit -m "Add prioritized chat task queues

Constraint: Both team and member chats need durable task queues with priority and notes.
Rejected: Dispatching raw text immediately | It cannot support paused queues, history, or priority.
Confidence: medium
Scope-risk: broad
Directive: Route all user work through QueuedTask before model execution.
Tested: targeted queue controller tests
Not-tested: Full Flutter widget suite."
```

### Task 3: Pause, Resume, and Running Task Lifecycle

**Files:**
- Modify: `lib/app.dart`
- Modify: `test/app_widget_test.dart`

- [ ] **Step 1: Add controller tests for pause/resume**

```dart
test('team pause cancels active request and resume reruns unfinished task',
    () async {
  final gateway = BlockingModelGateway();
  final controller = AppController(
    AppState.seed().copyWith(
      queuedTasks: [
        QueuedTask(
          id: 'task-1',
          conversationId: 'conv-team-default',
          title: '长任务',
          originalText: '执行长任务',
          priority: 0,
          status: QueuedTaskStatus.pending,
          createdAt: DateTime(2026, 6, 14),
          updatedAt: DateTime(2026, 6, 14),
        ),
      ],
    ),
    TeamOrchestrator(gateway),
  );
  addTearDown(controller.dispose);
  controller.startTeamChat('team-default');

  final run = controller.runNextQueuedTask();
  await gateway.started.future.timeout(const Duration(seconds: 1));
  controller.pauseTask('task-1');
  await run;

  expect(gateway.cancellation!.isCancelled, isTrue);
  expect(controller.state.queuedTasks.single.status, QueuedTaskStatus.paused);
});
```

- [ ] **Step 2: Implement running task state**

Add controller fields:

```dart
String? _runningTaskId;
ModelRequestCancellation? _activeCancellation;
```

Add:

```dart
QueuedTask? get currentRunningTask {
  final id = _runningTaskId;
  if (id == null) {
    return null;
  }
  return state.queuedTasks.where((task) => task.id == id).firstOrNull;
}
```

If `firstOrNull` is unavailable, use a local loop helper.

- [ ] **Step 3: Implement run/pause/resume methods**

```dart
Future<void> runNextQueuedTask() async {
  if (_runningTaskId != null) {
    return;
  }
  final next = pendingTasksForCurrentConversation.firstOrNull;
  if (next == null) {
    return;
  }
  _runningTaskId = next.id;
  final cancellation = ModelRequestCancellation();
  _activeCancellation = cancellation;
  _updateTaskStatus(next.id, QueuedTaskStatus.running);
  try {
    await orchestrator.dispatchQueuedTask(
      state,
      taskId: next.id,
      cancellation: cancellation,
      onProgress: _commit,
    );
    _updateTaskStatus(next.id, QueuedTaskStatus.completed);
  } on ModelGatewayException {
    if (cancellation.isCancelled) {
      _updateTaskStatus(next.id, QueuedTaskStatus.paused);
    } else {
      _updateTaskStatus(next.id, QueuedTaskStatus.failed);
    }
  } finally {
    if (_runningTaskId == next.id) {
      _runningTaskId = null;
      _activeCancellation = null;
    }
    notifyListeners();
  }
}

void pauseTask(String taskId) {
  if (_runningTaskId == taskId) {
    _activeCancellation?.cancel();
  }
  _updateTaskStatus(taskId, QueuedTaskStatus.paused);
}

Future<void> resumeTask(String taskId) async {
  _updateTaskStatus(taskId, QueuedTaskStatus.pending);
  await runNextQueuedTask();
}
```

- [ ] **Step 4: Run lifecycle tests**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "team pause cancels active request and resume reruns unfinished task"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app.dart test/app_widget_test.dart
git commit -m "Support pausable queued task execution

Constraint: Pause must persist and resume from unfinished work.
Rejected: Stop/cancel as terminal user action | Product uses pause and delete instead.
Confidence: medium
Scope-risk: moderate
Directive: Do not reintroduce stop controls; model cancellation is an implementation detail of pause/delete.
Tested: targeted pause/resume controller test
Not-tested: Full Flutter widget suite."
```

### Task 4: Team Orchestrator Semantics

**Files:**
- Modify: `lib/core/orchestrator.dart`
- Modify: `test/core/domain_test.dart`

- [ ] **Step 1: Add recording gateway tests for serial and parallel**

```dart
test('serial team mode runs assignments in secretary order with incremental summaries',
    () async {
  final gateway = ScriptedRecordingGateway([
    '前端工程师: 实现界面\n测试工程师: 编写测试',
    '前端结果',
    '阶段汇总：前端完成',
    '测试结果',
    '阶段汇总：测试完成',
    '最终汇总：全部完成',
  ]);

  final updated = await TeamOrchestrator(gateway).dispatchTeamTask(
    AppState.seed(),
    teamId: 'team-default',
    userText: '实现登录',
  );

  expect(gateway.calls.map((call) => call.systemPrompt).join('\n'),
      contains('秘书'));
  expect(updated.conversations
      .firstWhere((conversation) => conversation.id == 'conv-team-default')
      .messages
      .map((message) => message.content), contains('最终汇总：全部完成'));
});

test('parallel team mode does not pass same-round sibling outputs to workers',
    () async {
  final seed = AppState.seed().copyWith(
    teams: [
      AppState.seed()
          .teams
          .first
          .copyWith(collaborationMode: TeamCollaborationMode.parallel),
    ],
  );
  final gateway = ScriptedRecordingGateway([
    '前端工程师: 实现界面\n测试工程师: 编写测试',
    '前端结果',
    '测试结果',
    '最终汇总：全部完成',
  ]);

  await TeamOrchestrator(gateway).dispatchTeamTask(
    seed,
    teamId: 'team-default',
    userText: '实现登录',
  );

  expect(gateway.calls[2].messages.map((message) => message.content).join('\n'),
      isNot(contains('前端结果')));
});
```

- [ ] **Step 2: Add failure recovery test**

```dart
test('member failure retries once then reassigns to same-role priority member',
    () async {
  final state = AppState.seed().copyWith(
    members: [
      ...AppState.seed().members,
      const TeamMember(
        id: 'member-frontend-backup',
        name: '前端工程师 B',
        roleId: 'role-frontend',
        modelId: 'model-main',
        executionPriority: 10,
      ),
    ],
    teams: [
      AppState.seed().teams.first.copyWith(memberIds: [
        'member-secretary',
        'member-frontend',
        'member-frontend-backup',
        'member-tester',
      ]),
    ],
  );
  final gateway = FailsThenSucceedsRecordingGateway();

  final updated = await TeamOrchestrator(gateway).dispatchTeamTask(
    state,
    teamId: 'team-default',
    userText: '实现登录',
  );

  expect(gateway.memberNames, contains('前端工程师 B'));
  expect(updated.conversations
      .firstWhere((conversation) => conversation.id == 'conv-team-default')
      .messages
      .map((message) => message.content)
      .join('\n'), contains('转派'));
});
```

- [ ] **Step 3: Implement assignment parser**

Represent assignments as ordered items, not one instruction per member:

```dart
class ParsedAssignment {
  const ParsedAssignment({
    required this.member,
    required this.instruction,
  });

  final TeamMember member;
  final String instruction;
}
```

Parser behavior:

```dart
List<ParsedAssignment> _parseAssignments({
  required String plan,
  required List<TeamMember> members,
}) {
  final assignments = <ParsedAssignment>[];
  for (final line in plan.split('\n')) {
    final separator = line.indexOf(':');
    if (separator <= 0) {
      continue;
    }
    final name = line.substring(0, separator).trim();
    final instruction = line.substring(separator + 1).trim();
    final member = members.where((item) => item.name == name).firstOrNull;
    if (member == null || instruction.isEmpty) {
      continue;
    }
    assignments.add(ParsedAssignment(member: member, instruction: instruction));
  }
  return assignments;
}
```

Also return invalid names from a companion parser helper so the orchestrator can request one re-plan and fail the round when the second plan is still invalid.

- [ ] **Step 4: Implement serial execution**

Serial loop:

```dart
for (final assignment in assignments) {
  final result = await _runAssignmentWithRecovery(
    state: state,
    team: team,
    assignment: assignment,
    messages: messages,
    cancellation: cancellation,
  );
  messages.add(result.message);
  final incremental = await _runSecretarySummary(
    type: _SummaryType.incremental,
    messages: messages,
    cancellation: cancellation,
  );
  messages.add(incremental);
  onProgress?.call(_replaceConversationMessages(workingState, conversation, messages));
}
```

- [ ] **Step 5: Implement parallel execution**

Group by member so the same member's tasks stay serial:

```dart
final assignmentsByMember = <String, List<ParsedAssignment>>{};
for (final assignment in assignments) {
  assignmentsByMember.putIfAbsent(assignment.member.id, () => []).add(assignment);
}
final results = await Future.wait(assignmentsByMember.values.map((memberTasks) async {
  final memberResults = <ChatMessage>[];
  for (final assignment in memberTasks) {
    final result = await _runAssignmentWithRecovery(
      state: state,
      team: team,
      assignment: assignment,
      messages: planContextMessages,
      cancellation: cancellation,
    );
    memberResults.add(result.message);
  }
  return memberResults;
}));
for (final group in results) {
  messages.addAll(group);
}
messages.add(await _runSecretarySummary(
  type: _SummaryType.finalSummary,
  messages: messages,
  cancellation: cancellation,
));
```

- [ ] **Step 6: Implement retry and reassignment**

```dart
Future<_AssignmentResult> _runAssignmentWithRecovery({
  required AppState state,
  required Team team,
  required ParsedAssignment assignment,
  required List<ChatMessage> messages,
  ModelRequestCancellation? cancellation,
}) async {
  try {
    return await _runAssignment(...);
  } catch (firstError) {
    _appendSystemProcessMessage('执行失败，正在重试：$firstError');
    try {
      return await _runAssignment(...);
    } catch (secondError) {
      final replacement = _findReplacementMember(
        state: state,
        team: team,
        failedMember: assignment.member,
        alreadyExecutedMemberIds: _executedMemberIds,
      );
      if (replacement == null) {
        return _AssignmentResult.failed(
          message: _systemMessage('任务失败：$secondError'),
        );
      }
      _appendSystemProcessMessage(
        '${assignment.member.name} 重试失败，已转派给 ${replacement.name}',
      );
      return await _runAssignment(
        assignment: ParsedAssignment(
          member: replacement,
          instruction: assignment.instruction,
        ),
        messages: messages,
      );
    }
  }
}
```

Replacement selection sorts by `executionPriority` descending, then team member order, and filters same role, non-secretary, not already executed in this round.

- [ ] **Step 7: Run orchestrator tests**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "serial team mode runs assignments in secretary order with incremental summaries"
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "parallel team mode does not pass same-round sibling outputs to workers"
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "member failure retries once then reassigns to same-role priority member"
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/core/orchestrator.dart test/core/domain_test.dart
git commit -m "Implement selected team collaboration semantics

Constraint: Serial and parallel modes have different context and summary rules.
Rejected: One fixed orchestration path | It ignores team-level collaboration choice.
Confidence: medium
Scope-risk: broad
Directive: Keep secretary planning, failure recovery, and summary behavior covered by recording-gateway tests.
Tested: targeted orchestrator tests
Not-tested: Full Flutter widget suite."
```

### Task 5: Team and Member Configuration UI

**Files:**
- Modify: `lib/app.dart`
- Modify: `test/app_widget_test.dart`

- [ ] **Step 1: Add widget tests**

```dart
testWidgets('team dialog defaults to serial mode and can select parallel',
    (tester) async {
  await tester.pumpWidget(AiTeamApp(
    initialState: AppState.seed(),
    modelGateway: FakeModelGateway(),
  ));
  await tester.tap(find.byTooltip('团队'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('新增团队'));
  await tester.pumpAndSettle();

  expect(find.widgetWithText(SegmentedButton<TeamCollaborationMode>, '串行'),
      findsOneWidget);

  await tester.enterText(find.widgetWithText(TextField, '团队名称'), '并行小队');
  await tester.tap(find.text('并行'));
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await tester.pumpAndSettle();

  expect(find.textContaining('并行协同'), findsOneWidget);
});

testWidgets('member dialog edits execution priority', (tester) async {
  await tester.pumpWidget(AiTeamApp(
    initialState: AppState.seed(),
    modelGateway: FakeModelGateway(),
  ));
  await tester.tap(find.byTooltip('成员'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('编辑成员').first);
  await tester.pumpAndSettle();

  await tester.enterText(find.widgetWithText(TextField, '执行优先级'), '20');
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await tester.pumpAndSettle();

  expect(find.textContaining('优先级 20'), findsOneWidget);
});
```

- [ ] **Step 2: Add team segmented control**

In `_showTeamDialog`:

```dart
var collaborationMode = TeamCollaborationMode.serial;
```

Add:

```dart
SegmentedButton<TeamCollaborationMode>(
  segments: const [
    ButtonSegment(value: TeamCollaborationMode.serial, label: Text('串行')),
    ButtonSegment(value: TeamCollaborationMode.parallel, label: Text('并行')),
  ],
  selected: {collaborationMode},
  onSelectionChanged: (selection) {
    setDialogState(() => collaborationMode = selection.single);
  },
)
```

Pass it into `addTeam`.

- [ ] **Step 3: Add member priority field**

In `_showMemberDialog`, add a `TextEditingController` initialized from `member?.executionPriority ?? 0`, validate with `int.tryParse`, and pass `executionPriority` into `TeamMember`.

- [ ] **Step 4: Run widget tests**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "team dialog defaults to serial mode and can select parallel"
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "member dialog edits execution priority"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/app.dart test/app_widget_test.dart
git commit -m "Expose collaboration and member priority settings

Constraint: Users must choose team collaboration behavior and configure member execution priority.
Rejected: Hidden orchestration defaults | They make product behavior surprising.
Confidence: high
Scope-risk: moderate
Directive: Keep visible defaults aligned with product decisions.
Tested: targeted team/member widget tests
Not-tested: Full Flutter widget suite."
```

### Task 6: Queue UI and Message Navigation

**Files:**
- Modify: `lib/app.dart`
- Modify: `test/app_widget_test.dart`

- [ ] **Step 1: Add widget tests for queue bar and controls**

```dart
testWidgets('chat shows collapsed queue bar with count and running title',
    (tester) async {
  final state = AppState.seed().copyWith(
    queuedTasks: [
      QueuedTask(
        id: 'task-1',
        conversationId: 'conv-team-default',
        title: '登录任务',
        originalText: '实现登录',
        priority: 0,
        status: QueuedTaskStatus.running,
        createdAt: DateTime(2026, 6, 14),
        updatedAt: DateTime(2026, 6, 14),
      ),
      QueuedTask(
        id: 'task-2',
        conversationId: 'conv-team-default',
        title: '测试任务',
        originalText: '补测试',
        priority: 0,
        status: QueuedTaskStatus.pending,
        createdAt: DateTime(2026, 6, 14, 1),
        updatedAt: DateTime(2026, 6, 14, 1),
      ),
    ],
  );
  await tester.pumpWidget(AiTeamApp(
    initialState: state,
    modelGateway: FakeModelGateway(),
  ));

  expect(find.textContaining('队列 2'), findsOneWidget);
  expect(find.textContaining('登录任务'), findsOneWidget);
});
```

- [ ] **Step 2: Add queue bar component**

Create private widgets inside `lib/app.dart`:

```dart
class _TaskQueueBar extends StatelessWidget {
  const _TaskQueueBar({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final tasks = controller.tasksForCurrentConversation;
    if (tasks.isEmpty) {
      return const SizedBox.shrink();
    }
    final running = tasks.where((task) => task.status == QueuedTaskStatus.running)
        .firstOrNull;
    return ExpansionTile(
      title: Text(running == null
          ? '队列 ${tasks.length}'
          : '队列 ${tasks.length} · ${running.title}'),
      children: tasks.map((task) => _TaskQueueTile(
        controller: controller,
        task: task,
      )).toList(),
    );
  }
}
```

Use a local helper when `firstOrNull` is unavailable.

- [ ] **Step 3: Add queue tile and inline details**

Show title, priority, status, send time, original summary, note count, delete button, priority input, inline details, note button, and message jump links.

Status text helper:

```dart
String _queuedTaskStatusText(QueuedTaskStatus status) => switch (status) {
  QueuedTaskStatus.pending => '待执行',
  QueuedTaskStatus.running => '执行中',
  QueuedTaskStatus.paused => '已暂停',
  QueuedTaskStatus.completed => '已完成',
  QueuedTaskStatus.failed => '失败',
};
```

- [ ] **Step 4: Add input priority menu**

Place a small menu button to the right of the send button. Plain send uses `0`; menu send calls enqueue with chosen integer.

- [ ] **Step 5: Add pause/continue/delete controls**

Rules:
- executing + empty input: main button pauses
- executing + non-empty input: main button sends, queue row shows pause
- paused: queue row shows continue
- delete running task pauses/cancels first, then confirmation

- [ ] **Step 6: Add message jump/highlight**

Assign `GlobalKey`s per visible message id in `_ChatPaneState`, scroll with `Scrollable.ensureVisible`, and briefly store `highlightedMessageId`.

- [ ] **Step 7: Run widget tests**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "chat shows collapsed queue bar with count and running title"
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/app.dart test/app_widget_test.dart
git commit -m "Add chat task queue controls

Constraint: Queue actions must stay visible inside the chat workflow.
Rejected: Background-only queueing | Users need pause, continue, notes, delete, and links.
Confidence: medium
Scope-risk: broad
Directive: Keep queue controls compact and preserve existing chat layout.
Tested: targeted queue widget tests
Not-tested: Full Flutter widget suite."
```

### Task 7: History Page

**Files:**
- Modify: `lib/app.dart`
- Modify: `test/app_widget_test.dart`

- [ ] **Step 1: Add widget tests**

```dart
testWidgets('history page lists all app tasks and filters by title',
    (tester) async {
  final state = AppState.seed().copyWith(
    queuedTasks: [
      QueuedTask(
        id: 'task-1',
        conversationId: 'conv-team-default',
        title: '登录任务',
        originalText: '实现登录',
        priority: 0,
        status: QueuedTaskStatus.completed,
        createdAt: DateTime(2026, 6, 14),
        updatedAt: DateTime(2026, 6, 14),
      ),
      QueuedTask(
        id: 'task-2',
        conversationId: 'conv-member-secretary',
        title: '文档任务',
        originalText: '写文档',
        priority: 0,
        status: QueuedTaskStatus.completed,
        createdAt: DateTime(2026, 6, 14),
        updatedAt: DateTime(2026, 6, 14),
      ),
    ],
  );
  await tester.pumpWidget(AiTeamApp(
    initialState: state,
    modelGateway: FakeModelGateway(),
  ));

  await tester.tap(find.byTooltip('历史'));
  await tester.pumpAndSettle();
  expect(find.text('登录任务'), findsOneWidget);
  expect(find.text('文档任务'), findsOneWidget);

  await tester.enterText(find.widgetWithText(TextField, '搜索标题'), '登录');
  await tester.pumpAndSettle();
  expect(find.text('登录任务'), findsOneWidget);
  expect(find.text('文档任务'), findsNothing);
});
```

- [ ] **Step 2: Add `_MainView.history` and sidebar entry**

Add history enum value and a sidebar button with tooltip `历史`.

- [ ] **Step 3: Implement `_HistoryPage`**

Show all tasks across the app. Add filters for conversation, status, priority range, time range, member/role, and title-only search. Clicking a row expands inline details. Completed task priority is read-only.

- [ ] **Step 4: Add history deletion with confirmation**

Use the same `deleteTask` path. Deleted tasks are removed and no longer shown.

- [ ] **Step 5: Run history tests**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "history page lists all app tasks and filters by title"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/app.dart test/app_widget_test.dart
git commit -m "Add task history workspace

Constraint: Completed tasks remain reviewable across all conversations.
Rejected: Queue-only history | Users need global filtering and search.
Confidence: medium
Scope-risk: moderate
Directive: Search title only unless product requirements change.
Tested: targeted history widget test
Not-tested: Full Flutter widget suite."
```

### Task 8: Multi-Team Private Chat Isolation

**Files:**
- Modify: `lib/app.dart`
- Modify: `test/app_widget_test.dart`

- [ ] **Step 1: Add failing test**

```dart
test('controller starts member chat in the active team without conversation id collisions', () {
  final controller = AppController(
    AppState.seed(),
    TeamOrchestrator(FakeModelGateway()),
  );
  addTearDown(controller.dispose);

  final mobileTeam = controller.addTeam(
    name: '移动端小队',
    memberIds: const ['member-frontend', 'member-tester'],
    collaborationMode: TeamCollaborationMode.serial,
  );

  controller.startTeamChat(mobileTeam.id);
  controller.startMemberChat('member-frontend');

  expect(controller.currentConversation.teamId, mobileTeam.id);
  expect(controller.currentConversation.memberId, 'member-frontend');
  expect(
    controller.state.conversations.map((conversation) => conversation.id).toSet().length,
    controller.state.conversations.length,
  );
});
```

- [ ] **Step 2: Make member conversation IDs include team id**

```dart
id: 'conv-$teamId-${member.id}',
```

and:

```dart
id: 'msg-welcome-$teamId-${member.id}',
```

- [ ] **Step 3: Run targeted test**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "controller starts member chat in the active team without conversation id collisions"
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/app.dart test/app_widget_test.dart
git commit -m "Isolate private chats across teams

Constraint: Teams may reuse the same members.
Rejected: Member-only private conversation ids | They collide across teams.
Confidence: high
Scope-risk: narrow
Directive: Conversation ids created at runtime must be globally unique.
Tested: targeted multi-team private chat test
Not-tested: Full Flutter widget suite."
```

### Task 9: Documentation and Full Verification

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README capability bullets**

Replace the team chat and queue bullets with:

```markdown
- 团队会话：创建团队时可选择串行或并行协同；用户任务先生成标题进入队列，秘书分工后成员按团队协同模式执行，秘书按规则生成增量或最终汇总。
- 任务队列：群聊和私聊都支持任务优先级、暂停继续、删除确认、追加备注、历史记录和关联聊天跳转。
- 成员调度：成员可配置执行优先级；失败时自动重试一次，仍失败则按同角色优先级转派，无法转派时记录失败并进入汇总。
```

- [ ] **Step 2: Run full tests**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test
```

Expected: `All tests passed!`

- [ ] **Step 3: Run analyzer**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: Optional macOS build**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter build macos --debug
```

Expected: build succeeds. If local toolchain/signing blocks it, record the exact failure in the final report and `Not-tested`.

- [ ] **Step 5: Final commit**

```bash
git add README.md
git commit -m "Document queued collaboration workflow

Constraint: Documentation must describe the implemented queue and collaboration behavior.
Rejected: Vague team-chat wording | It hides priority, pause, history, and reassignment semantics.
Confidence: high
Scope-risk: narrow
Directive: Update README when collaboration lifecycle semantics change.
Tested: /Users/swcrbt/develop/flutter/bin/flutter test; /Users/swcrbt/develop/flutter/bin/flutter analyze
Not-tested: macOS debug build if local toolchain blocks it."
```

### Plan Self-Review

- Spec coverage: covers confirmed collaboration modes, secretary planning, title generation, queue priority, pause/resume/delete, member priority, retry/reassignment, queue UI, history UI, task/message linking, multi-team private chat isolation, and verification.
- Placeholder scan: no `TBD`, `TODO`, or "handle edge cases later" items remain in the canonical plan.
- Type consistency: new concepts are named consistently as `TeamCollaborationMode`, `QueuedTask`, `QueuedTaskStatus`, `TeamMember.executionPriority`, `ChatMessage.taskIds`, and `QueuedTask.messageIds`.
- Scope note: this is a broad feature set. Implement task-by-task with commits and do not start UI work until the domain and controller tests pass.

## Legacy Draft Below - Do Not Execute

## Task 1: Add Team Collaboration Mode to the Domain

**Files:**
- Modify: `lib/core/domain.dart`
- Modify: `test/core/domain_test.dart`
- Test: `test/core/domain_test.dart`

- [ ] **Step 1: Add failing serialization test**

```dart
test('team collaboration mode is persisted in configuration json', () {
  const team = Team(
    id: 'team-parallel',
    name: '并行小队',
    memberIds: ['member-secretary', 'member-frontend', 'member-tester'],
    secretaryMemberId: 'member-secretary',
    collaborationMode: TeamCollaborationMode.parallel,
  );

  final restored = Team.fromJson(team.toJson());

  expect(restored.collaborationMode, TeamCollaborationMode.parallel);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "team collaboration mode is persisted in configuration json"
```

Expected: FAIL because `TeamCollaborationMode` and `Team.collaborationMode` do not exist yet.

- [ ] **Step 3: Add enum and Team field**

In `lib/core/domain.dart`, add the enum next to the other domain enums:

```dart
enum TeamCollaborationMode { serial, parallel }
```

Update `Team`:

```dart
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
    List<String>? memberIds,
    int? maxRounds,
    TeamCollaborationMode? collaborationMode,
  }) =>
      Team(
        id: id,
        name: name,
        memberIds: memberIds ?? this.memberIds,
        secretaryMemberId: secretaryMemberId,
        maxRounds: maxRounds ?? this.maxRounds,
        collaborationMode: collaborationMode ?? this.collaborationMode,
      );
}
```

- [ ] **Step 4: Persist mode in Team JSON with backward compatibility**

```dart
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
      maxRounds: (json['maxRounds'] as num).toInt(),
      collaborationMode: TeamCollaborationMode.values.byName(
        json['collaborationMode'] as String? ?? TeamCollaborationMode.serial.name,
      ),
    );
```

- [ ] **Step 5: Run targeted domain test**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "team collaboration mode is persisted in configuration json"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/domain.dart test/core/domain_test.dart
git commit -m "Persist team collaboration mode

Constraint: Team creation must let users choose serial or parallel AI collaboration.
Rejected: Hard-coding serial execution | The user needs an explicit team-level choice.
Confidence: high
Scope-risk: narrow
Directive: New team orchestration behavior must branch from Team.collaborationMode.
Tested: /Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name \"team collaboration mode is persisted in configuration json\"
Not-tested: Full Flutter widget suite."
```

## Task 2: Add Collaboration Mode to Team Creation UI

**Files:**
- Modify: `lib/app.dart`
- Modify: `test/app_widget_test.dart`
- Test: `test/app_widget_test.dart`

- [ ] **Step 1: Add failing controller test for explicit mode selection**

```dart
test('controller creates a team with the selected collaboration mode', () {
  final controller = AppController(
    AppState.seed(),
    TeamOrchestrator(FakeModelGateway()),
  );
  addTearDown(controller.dispose);

  final team = controller.addTeam(
    name: '并行小队',
    memberIds: const ['member-frontend', 'member-tester'],
    collaborationMode: TeamCollaborationMode.parallel,
  );

  expect(team.collaborationMode, TeamCollaborationMode.parallel);
  expect(
    controller.state.teams.firstWhere((item) => item.id == team.id).collaborationMode,
    TeamCollaborationMode.parallel,
  );
});
```

- [ ] **Step 2: Update AppController.addTeam signature**

```dart
Team addTeam({
  required String name,
  required List<String> memberIds,
  required TeamCollaborationMode collaborationMode,
}) {
  // existing validation stays the same
  final team = Team(
    id: 'team-$timestamp',
    name: trimmedName,
    memberIds: uniqueMemberIds.toList(),
    secretaryMemberId: secretary.id,
    collaborationMode: collaborationMode,
  );
  // existing commit stays the same
}
```

- [ ] **Step 3: Update existing addTeam test calls**

Every existing `controller.addTeam(...)` test call must pass one of:

```dart
collaborationMode: TeamCollaborationMode.serial,
```

or

```dart
collaborationMode: TeamCollaborationMode.parallel,
```

- [ ] **Step 4: Add failing widget test for create-team mode choice**

```dart
testWidgets('team management creates a team with selected collaboration mode',
    (tester) async {
  await tester.pumpWidget(
    AiTeamApp(
      initialState: AppState.seed(),
      modelGateway: FakeModelGateway(),
    ),
  );

  await tester.tap(find.byTooltip('团队'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('新增团队'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, '团队名称'), '并行小队');
  await tester.tap(find.text('并行'));
  await tester.tap(find.widgetWithText(FilledButton, '保存'));
  await tester.pumpAndSettle();

  expect(find.text('并行小队'), findsOneWidget);
  expect(find.textContaining('并行协同'), findsOneWidget);
});
```

- [ ] **Step 5: Add segmented control to team dialog**

In `_showTeamDialog`, keep local state:

```dart
var collaborationMode = TeamCollaborationMode.serial;
```

Add UI before the member checklist:

```dart
Align(
  alignment: Alignment.centerLeft,
  child: Text(
    '协同模式',
    style: Theme.of(context).textTheme.titleSmall,
  ),
),
const SizedBox(height: 6),
SegmentedButton<TeamCollaborationMode>(
  segments: const [
    ButtonSegment(
      value: TeamCollaborationMode.serial,
      label: Text('串行'),
      icon: Icon(Icons.route_rounded),
    ),
    ButtonSegment(
      value: TeamCollaborationMode.parallel,
      label: Text('并行'),
      icon: Icon(Icons.account_tree_rounded),
    ),
  ],
  selected: {collaborationMode},
  onSelectionChanged: (selection) {
    setDialogState(() => collaborationMode = selection.single);
  },
),
```

Pass the selected value into `controller.addTeam`.

- [ ] **Step 6: Display mode in team list**

Add helper:

```dart
String _collaborationModeText(TeamCollaborationMode mode) {
  return switch (mode) {
    TeamCollaborationMode.serial => '串行协同',
    TeamCollaborationMode.parallel => '并行协同',
  };
}
```

Update `_TeamCard` value to include the mode:

```dart
value:
    '${_collaborationModeText(team.collaborationMode)} · ${members.map((member) => member.name).join('、')}',
```

- [ ] **Step 7: Run targeted tests**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "controller creates a team with the selected collaboration mode"
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "team management creates a team with selected collaboration mode"
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/app.dart test/app_widget_test.dart
git commit -m "Let teams choose collaboration mode

Constraint: Users must choose whether AI members collaborate serially or in parallel.
Rejected: Inferring a single default mode | It hides a material product decision.
Confidence: high
Scope-risk: narrow
Directive: Team orchestration must respect Team.collaborationMode.
Tested: /Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name \"controller creates a team with the selected collaboration mode\"; /Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name \"team management creates a team with selected collaboration mode\"
Not-tested: Full Flutter widget suite."
```

## Task 3: Lock Down Real Orchestration Semantics

**Files:**
- Modify: `test/core/domain_test.dart`
- Test: `test/core/domain_test.dart`

- [ ] **Step 1: Add a recording gateway test double near existing test helpers**

```dart
class ScriptedRecordingGateway implements ModelGateway {
  ScriptedRecordingGateway(this.responses);

  final List<String> responses;
  final calls = <RecordedGatewayCall>[];

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    calls.add(RecordedGatewayCall(
      modelId: model.id,
      systemPrompt: systemPrompt,
      messages: List<ChatMessage>.from(messages),
    ));
    if (calls.length > responses.length) {
      throw StateError('Unexpected gateway call ${calls.length}');
    }
    return responses[calls.length - 1];
  }
}

class RecordedGatewayCall {
  const RecordedGatewayCall({
    required this.modelId,
    required this.systemPrompt,
    required this.messages,
  });

  final String modelId;
  final String systemPrompt;
  final List<ChatMessage> messages;
}
```

- [ ] **Step 2: Add failing test for secretary plan, member context, and final synthesis**

```dart
test('team task uses secretary planning and synthesis around member work', () async {
  final gateway = ScriptedRecordingGateway([
    '前端工程师: 实现登录界面\n测试工程师: 补充登录回归测试',
    '前端结果：完成登录页面状态流',
    '测试结果：补齐登录页面 widget 测试',
    '汇总：登录页面和测试都已完成',
  ]);
  final orchestrator = TeamOrchestrator(gateway);

  final updated = await orchestrator.dispatchTeamTask(
    AppState.seed(),
    teamId: 'team-default',
    userText: '实现登录页面并补测试',
  );

  expect(gateway.calls, hasLength(4));
  expect(gateway.calls[0].modelId, 'model-main');
  expect(gateway.calls[0].systemPrompt, contains('秘书'));
  expect(gateway.calls[0].messages.last.content, '实现登录页面并补测试');
  expect(gateway.calls[1].systemPrompt, contains('前端工程师'));
  expect(gateway.calls[1].messages.map((message) => message.content).join('\n'),
      contains('实现登录界面'));
  expect(gateway.calls[2].systemPrompt, contains('测试工程师'));
  expect(gateway.calls[2].messages.map((message) => message.content).join('\n'),
      contains('前端结果：完成登录页面状态流'));
  expect(gateway.calls[3].systemPrompt, contains('秘书'));
  expect(gateway.calls[3].messages.map((message) => message.content).join('\n'),
      contains('测试结果：补齐登录页面 widget 测试'));

  final conversation = updated.conversations
      .firstWhere((conversation) => conversation.id == 'conv-team-default');
  expect(conversation.messages.last.authorName, '秘书');
  expect(conversation.messages.last.content, '汇总：登录页面和测试都已完成');
  expect(updated.taskAssignments.map((assignment) => assignment.instruction), [
    '实现登录界面',
    '补充登录回归测试',
  ]);
});
```

- [ ] **Step 3: Run test to verify it fails**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "team task uses secretary planning and synthesis around member work"
```

Expected: FAIL because the current orchestrator makes only two worker gateway calls and uses hard-coded secretary messages.

## Task 4: Implement Secretary Plan, Member Work, Secretary Synthesis

**Files:**
- Modify: `lib/core/orchestrator.dart`
- Test: `test/core/domain_test.dart`

- [ ] **Step 1: Add private helpers to parse secretary assignments**

```dart
Map<String, String> _parseAssignments({
  required String plan,
  required List<TeamMember> workerMembers,
  required String fallbackInstruction,
}) {
  final assignments = {
    for (final member in workerMembers) member.id: fallbackInstruction,
  };
  for (final line in plan.split('\n')) {
    final separator = line.indexOf(':');
    if (separator <= 0) {
      continue;
    }
    final name = line.substring(0, separator).trim();
    final instruction = line.substring(separator + 1).trim();
    if (instruction.isEmpty) {
      continue;
    }
    for (final member in workerMembers) {
      if (name == member.name || name.contains(member.name)) {
        assignments[member.id] = instruction;
      }
    }
  }
  return assignments;
}

List<ChatMessage> _appendSystemContext(
  List<ChatMessage> messages,
  String authorName,
  String content,
) {
  return [
    ...messages,
    ChatMessage(
      id: _id('msg'),
      authorName: authorName,
      content: content,
      createdAt: DateTime.now(),
    ),
  ];
}
```

- [ ] **Step 2: Call secretary model before creating assignments**

Replace the hard-coded assignment-only path with:

```dart
final secretaryRole =
    state.roles.firstWhere((item) => item.id == secretary.roleId);
final secretaryModel =
    state.models.firstWhere((item) => item.id == secretary.modelId);
_ensureModelReady(member: secretary, model: secretaryModel);
final planPromptMessages = [
  ...conversation.messages,
  ChatMessage(
    id: _id('msg'),
    authorName: '我',
    content: userText,
    createdAt: now,
    isUser: true,
  ),
];
final plan = await gateway.complete(
  model: secretaryModel,
  systemPrompt: secretaryRole.renderSystemPrompt(
    memberName: secretary.name,
    teamName: team.name,
  ),
  messages: _appendSystemContext(
    planPromptMessages,
    '系统',
    '请按“成员名: 具体任务”的格式给每位非秘书成员分配任务。',
  ),
  cancellation: cancellation,
);
final instructions = _parseAssignments(
  plan: plan,
  workerMembers: workerMembers,
  fallbackInstruction: userText,
);
```

- [ ] **Step 3: Store secretary plan as visible message and per-member assignment instructions**

Use `instructions[member.id] ?? userText` when creating each `TaskAssignment.instruction`, and add the secretary plan as the visible secretary message.

```dart
final messages = [
  ...planPromptMessages,
  ChatMessage(
    id: _id('msg'),
    authorName: secretary.name,
    memberId: secretary.id,
    content: plan,
    createdAt: now.add(const Duration(milliseconds: 1)),
  ),
];
```

- [ ] **Step 4: Implement serial member execution**

When `team.collaborationMode == TeamCollaborationMode.serial`, keep the current ordered loop. Before each worker call, pass messages plus a system context message. Because each completed member response is appended to `messages`, the next member sees prior member output.

```dart
final memberMessages = _appendSystemContext(
  messages,
  '系统',
  '你的本轮任务：${assignment.instruction}',
);
final content = await gateway.complete(
  model: model,
  systemPrompt: role.renderSystemPrompt(
    memberName: member.name,
    teamName: team.name,
  ),
  messages: memberMessages,
  cancellation: cancellation,
);
```

- [ ] **Step 5: Implement parallel member execution**

When `team.collaborationMode == TeamCollaborationMode.parallel`, start all member gateway calls from the same secretary-plan context. Do not include other members' results in each member's prompt because they do not exist yet.

```dart
Future<_MemberResult> runMember(
  TeamMember member,
  TaskAssignment assignment,
) async {
  final role = state.roles.firstWhere((item) => item.id == member.roleId);
  final model = state.models.firstWhere((item) => item.id == member.modelId);
  _ensureModelReady(member: member, model: model);
  final content = await gateway.complete(
    model: model,
    systemPrompt: role.renderSystemPrompt(
      memberName: member.name,
      teamName: team.name,
    ),
    messages: _appendSystemContext(
      messages,
      '系统',
      '你的本轮任务：${assignment.instruction}',
    ),
    cancellation: cancellation,
  );
  return _MemberResult(member: member, assignment: assignment, content: content);
}

final results = team.collaborationMode == TeamCollaborationMode.parallel
    ? await Future.wait([
        for (var index = 0; index < workerMembers.length; index++)
          runMember(workerMembers[index], assignments[index]),
      ])
    : <_MemberResult>[];
```

Add a private result holder:

```dart
class _MemberResult {
  const _MemberResult({
    required this.member,
    required this.assignment,
    required this.content,
  });

  final TeamMember member;
  final TaskAssignment assignment;
  final String content;
}
```

Append parallel results to `messages` in assignment order after `Future.wait` returns, then mark assignments completed.

- [ ] **Step 6: Replace hard-coded final summary with a secretary gateway call**

```dart
final summary = await gateway.complete(
  model: secretaryModel,
  systemPrompt: secretaryRole.renderSystemPrompt(
    memberName: secretary.name,
    teamName: team.name,
  ),
  messages: _appendSystemContext(
    messages,
    '系统',
    '请综合本轮成员输出，给出面向用户的简洁汇总，包含完成情况、风险和下一步。',
  ),
  cancellation: cancellation,
);
messages.add(ChatMessage(
  id: _id('msg'),
  authorName: secretary.name,
  memberId: secretary.id,
  content: summary,
  createdAt: DateTime.now(),
));
```

- [ ] **Step 7: Add failing test for parallel mode context**

```dart
test('parallel team mode does not pass member outputs into sibling member calls',
    () async {
  final seed = AppState.seed().copyWith(
    teams: [
      AppState.seed()
          .teams
          .first
          .copyWith(collaborationMode: TeamCollaborationMode.parallel),
    ],
  );
  final gateway = ScriptedRecordingGateway([
    '前端工程师: 实现界面\n测试工程师: 编写测试',
    '前端并行结果',
    '测试并行结果',
    '汇总：并行完成',
  ]);
  final orchestrator = TeamOrchestrator(gateway);

  await orchestrator.dispatchTeamTask(
    seed,
    teamId: 'team-default',
    userText: '并行处理登录页',
  );

  expect(gateway.calls, hasLength(4));
  expect(
    gateway.calls[2].messages.map((message) => message.content).join('\n'),
    isNot(contains('前端并行结果')),
  );
});
```

- [ ] **Step 8: Run targeted orchestrator tests**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "team task uses secretary planning and synthesis around member work"
/Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name "parallel team mode does not pass member outputs into sibling member calls"
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/core/orchestrator.dart test/core/domain_test.dart
git commit -m "Make team chat coordination model-driven

Constraint: Respect each team's selected serial or parallel collaboration mode.
Rejected: Hard-coded secretary summaries | It cannot reflect member output.
Confidence: high
Scope-risk: moderate
Directive: Keep orchestration behavior covered by gateway-call recording tests.
Tested: /Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name \"team task uses secretary planning and synthesis around member work\"; /Users/swcrbt/develop/flutter/bin/flutter test test/core/domain_test.dart --plain-name \"parallel team mode does not pass member outputs into sibling member calls\"
Not-tested: Full Flutter widget suite."
```

## Task 5: Fix Multi-Team Private Conversation Isolation

**Files:**
- Modify: `lib/app.dart`
- Modify: `test/app_widget_test.dart`
- Test: `test/app_widget_test.dart`

- [ ] **Step 1: Add failing controller test**

```dart
test('controller starts member chat in the active team without conversation id collisions', () {
  final controller = AppController(
    AppState.seed(),
    TeamOrchestrator(FakeModelGateway()),
  );
  addTearDown(controller.dispose);

  final mobileTeam = controller.addTeam(
    name: '移动端小队',
    memberIds: const ['member-frontend', 'member-tester'],
    collaborationMode: TeamCollaborationMode.serial,
  );

  controller.startTeamChat(mobileTeam.id);
  controller.startMemberChat('member-frontend');

  expect(controller.currentConversation.teamId, mobileTeam.id);
  expect(controller.currentConversation.memberId, 'member-frontend');
  expect(
    controller.state.conversations
        .map((conversation) => conversation.id)
        .toSet()
        .length,
    controller.state.conversations.length,
  );
});
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "controller starts member chat in the active team without conversation id collisions"
```

Expected: FAIL because member conversation IDs are currently `conv-${member.id}`.

- [ ] **Step 3: Change member conversation IDs to include team ID**

Modify `_createMemberConversation`:

```dart
Conversation _createMemberConversation(String teamId, TeamMember member) {
  return Conversation(
    id: 'conv-$teamId-${member.id}',
    title: member.name,
    teamId: teamId,
    memberId: member.id,
    messages: [
      ChatMessage(
        id: 'msg-welcome-$teamId-${member.id}',
        authorName: member.name,
        memberId: member.id,
        content: '这里是和${member.name}的独立会话。',
        createdAt: DateTime.now(),
      ),
    ],
  );
}
```

- [ ] **Step 4: Preserve old seeded IDs through lookup, not creation**

Do not migrate existing seed fixture IDs unless tests require it. Keep all runtime selection through `conversationForMember`, which already matches by `teamId` and `memberId`.

- [ ] **Step 5: Run targeted app test**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "controller starts member chat in the active team without conversation id collisions"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/app.dart test/app_widget_test.dart
git commit -m "Isolate private chats across teams

Constraint: Teams can reuse the same members.
Rejected: Selecting private chats by member-only conversation id | It collides across teams.
Confidence: high
Scope-risk: narrow
Directive: Conversation IDs created at runtime must be globally unique.
Tested: /Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name \"controller starts member chat in the active team without conversation id collisions\"
Not-tested: Full Flutter widget suite."
```

## Task 6: Make Failure State Consistent

**Files:**
- Modify: `lib/app.dart`
- Modify: `test/app_widget_test.dart`
- Test: `test/app_widget_test.dart`

- [ ] **Step 1: Add failing gateway test double**

```dart
class FailingAfterStartGateway implements ModelGateway {
  var calls = 0;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    calls += 1;
    throw const ModelGatewayException('boom');
  }
}
```

- [ ] **Step 2: Add failing controller test**

```dart
test('controller marks open team assignments failed when model dispatch fails', () async {
  final controller = AppController(
    AppState.seed(),
    TeamOrchestrator(FailingAfterStartGateway()),
  );
  addTearDown(controller.dispose);
  controller.startTeamChat('team-default');

  await controller.dispatch('请触发失败');

  expect(controller.currentConversation.status, ConversationStatus.failed);
  expect(
    controller.currentTaskAssignments
        .where((assignment) =>
            assignment.status == TaskAssignmentStatus.pending ||
            assignment.status == TaskAssignmentStatus.running)
        .toList(),
    isEmpty,
  );
  expect(
    controller.currentTaskAssignments
        .map((assignment) => assignment.status)
        .toSet(),
    contains(TaskAssignmentStatus.failed),
  );
});
```

- [ ] **Step 3: Run test to verify it fails**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "controller marks open team assignments failed when model dispatch fails"
```

Expected: FAIL because non-cancel failures currently leave open assignments unchanged.

- [ ] **Step 4: Add open-assignment failure helper**

In `AppController`, add:

```dart
List<TaskAssignment> _failOpenAssignments(
  List<TaskAssignment> assignments,
  String conversationId,
) {
  return assignments
      .map(
        (assignment) => assignment.conversationId == conversationId &&
                (assignment.status == TaskAssignmentStatus.pending ||
                    assignment.status == TaskAssignmentStatus.running)
            ? assignment.copyWith(
                status: TaskAssignmentStatus.failed,
                completedAt: DateTime.now(),
              )
            : assignment,
      )
      .toList();
}
```

- [ ] **Step 5: Use it in the non-cancel catch path**

In `dispatch`, when building the failed state, include:

```dart
taskAssignments: _failOpenAssignments(
  state.taskAssignments,
  failed.id,
),
```

- [ ] **Step 6: Run targeted failure test**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name "controller marks open team assignments failed when model dispatch fails"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/app.dart test/app_widget_test.dart
git commit -m "Close team task state on model failure

Constraint: UI task panels derive directly from TaskAssignment.status.
Rejected: Only marking the conversation failed | It leaves stale running tasks visible.
Confidence: high
Scope-risk: narrow
Directive: Every terminal conversation failure must terminalize open assignments.
Tested: /Users/swcrbt/develop/flutter/bin/flutter test test/app_widget_test.dart --plain-name \"controller marks open team assignments failed when model dispatch fails\"
Not-tested: Full Flutter widget suite."
```

## Task 7: Regression Pass and Documentation Alignment

**Files:**
- Modify: `README.md`
- Test: all tests and analyzer

- [ ] **Step 1: Update README behavior claim**

Ensure the team chat line describes user-selected serial or parallel collaboration:

```markdown
- 团队会话：创建团队时可选择串行或并行协同；用户向团队发任务后，秘书先生成成员分工，成员按团队协同模式响应，秘书再基于成员输出生成汇总。
```

- [ ] **Step 2: Run full test suite**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter test
```

Expected: `All tests passed!`

- [ ] **Step 3: Run analyzer**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 4: Optional macOS debug build**

Run:

```bash
/Users/swcrbt/develop/flutter/bin/flutter build macos --debug
```

Expected: debug build succeeds. If local signing/toolchain blocks the build, record the exact error in `Not-tested`.

- [ ] **Step 5: Final commit**

```bash
git add README.md
git commit -m "Document model-driven team collaboration

Constraint: Documentation must match implemented behavior.
Rejected: Keeping vague secretary wording | It hides the actual collaboration contract.
Confidence: high
Scope-risk: narrow
Directive: Update docs whenever orchestration semantics change.
Tested: /Users/swcrbt/develop/flutter/bin/flutter test; /Users/swcrbt/develop/flutter/bin/flutter analyze
Not-tested: macOS debug build if local toolchain blocks it."
```

## Self-Review

- Spec coverage: covers team-level serial/parallel collaboration mode, secretary planning, member execution context, secretary synthesis, multi-team private chat isolation, failure cleanup, tests, and README alignment.
- Placeholder scan: no `TBD`, `TODO`, or vague "handle edge cases" steps remain.
- Type consistency: all snippets use existing `ModelGateway`, `ModelProfile`, `ChatMessage`, `TaskAssignment`, `TaskAssignmentStatus`, `ConversationStatus`, `AppController`, and `TeamOrchestrator` names, plus newly introduced `TeamCollaborationMode`.
- Scope check: plan is one subsystem, the team-chat collaboration workflow, and each task is independently testable.
