import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/domain.dart';
import '../app_helpers.dart';

class TaskQueueBar extends StatelessWidget {
  const TaskQueueBar({
    super.key,
    required this.controller,
    required this.conversationId,
  });

  final AppController controller;
  final String conversationId;

  @override
  Widget build(BuildContext context) {
    final tasks = controller.tasksForConversation(conversationId);
    if (tasks.isEmpty) {
      return const SizedBox.shrink();
    }
    final running = firstTaskWithStatus(tasks, QueuedTaskStatus.running);
    final title = running == null
        ? '队列 ${tasks.length}'
        : '队列 ${tasks.length} · ${running.title}';
    return Material(
      color: const Color(0xFFF8FAFC),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 24),
        initiallyExpanded: false,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Column(
              children: tasks
                  .map(
                    (task) => _TaskQueueTile(
                      controller: controller,
                      task: task,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskQueueTile extends StatefulWidget {
  const _TaskQueueTile({
    required this.controller,
    required this.task,
  });

  final AppController controller;
  final QueuedTask task;

  @override
  State<_TaskQueueTile> createState() => _TaskQueueTileState();
}

class _TaskQueueTileState extends State<_TaskQueueTile> {
  final noteController = TextEditingController();
  late final priorityController = TextEditingController(
    text: widget.task.priority.toString(),
  );

  @override
  void dispose() {
    noteController.dispose();
    priorityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: ExpansionTile(
        title: Text(task.title),
        subtitle: Text(
          '${queuedTaskStatusText(task.status)} · 优先级 ${task.priority} · 备注 ${task.notes.length}',
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            if (task.status == QueuedTaskStatus.running)
              IconButton(
                tooltip: '暂停任务',
                onPressed: () => widget.controller.pauseTask(task.id),
                icon: const Icon(Icons.pause_rounded),
              ),
            if (task.status == QueuedTaskStatus.paused)
              IconButton(
                tooltip: '继续任务',
                onPressed: () => widget.controller.resumeTask(task.id),
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            IconButton(
              tooltip: '删除任务',
              onPressed: () => widget.controller.deleteTask(task.id),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.originalText),
                const SizedBox(height: 8),
                if (task.notes.isNotEmpty) Text('备注：${task.notes.join('；')}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: priorityController,
                        decoration: const InputDecoration(labelText: '优先级'),
                        keyboardType: TextInputType.number,
                        onSubmitted: (value) {
                          final priority = int.tryParse(value.trim());
                          if (priority != null) {
                            widget.controller.updateTaskPriority(
                              task.id,
                              priority,
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: noteController,
                        decoration: const InputDecoration(labelText: '追加备注'),
                        onSubmitted: (_) => _appendNote(),
                      ),
                    ),
                    IconButton(
                      tooltip: '追加备注',
                      onPressed: _appendNote,
                      icon: const Icon(Icons.add_comment_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _appendNote() {
    widget.controller.appendTaskNote(widget.task.id, noteController.text);
    noteController.clear();
  }
}

class ChatPatchConfirmationCard extends StatelessWidget {
  const ChatPatchConfirmationCard({
    super.key,
    required this.patch,
    required this.onApply,
    required this.onReject,
  });

  final PatchProposal patch;
  final VoidCallback onApply;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 18,
          backgroundColor: Color(0xFF8B5CF6),
          child: Icon(
            Icons.difference_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 760),
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFC7D2FE)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '待确认修改',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text('${patch.memberName} 提议修改 ${patch.filePath}'),
                const SizedBox(height: 10),
                SelectableText(
                  patch.diff,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: onApply,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('应用修改'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onReject,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('拒绝'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ChatCommandRequestCard extends StatelessWidget {
  const ChatCommandRequestCard({
    super.key,
    required this.request,
    required this.onApproveExecute,
    required this.onReject,
  });

  final CommandRequest request;
  final VoidCallback onApproveExecute;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final title = switch (request.status) {
      CommandRequestStatus.pending => '待确认命令',
      CommandRequestStatus.approved => '已允许命令',
      CommandRequestStatus.executed => '命令已执行',
      CommandRequestStatus.failed => '命令执行失败',
      CommandRequestStatus.denied => '命令已拒绝',
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                request.memberName,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            '${request.workingDirectory}\n\$ ${request.command}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          if (request.status == CommandRequestStatus.pending ||
              request.status == CommandRequestStatus.approved) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onApproveExecute,
                  icon: Icon(
                    request.status == CommandRequestStatus.pending
                        ? Icons.check_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    request.status == CommandRequestStatus.pending
                        ? '批准并执行'
                        : '执行',
                  ),
                ),
                if (request.status == CommandRequestStatus.pending)
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('拒绝'),
                  ),
              ],
            ),
          ],
          if (request.output != null && request.output!.isNotEmpty) ...[
            const SizedBox(height: 12),
            SelectableText(
              request.output!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
