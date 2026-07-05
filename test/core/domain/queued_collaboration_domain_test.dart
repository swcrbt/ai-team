import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/domain.dart';

void main() {
  group('queued collaboration domain', () {
    test(
        'team mode and member priority persist with backward-compatible defaults',
        () {
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

      final restored = Team.fromJson(oldTeam
          .copyWith(
            collaborationMode: TeamCollaborationMode.parallel,
          )
          .toJson());
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

    test('chat messages persist real model thinking content', () {
      final message = ChatMessage(
        id: 'msg-thinking',
        authorName: '前端工程师',
        content: '结论内容',
        thinkingContent: '真实 reasoning 字段内容',
        createdAt: DateTime(2026, 6, 15),
      );

      final restored = ChatMessage.fromJson(message.toJson());

      expect(restored.content, '结论内容');
      expect(restored.thinkingContent, '真实 reasoning 字段内容');
    });

    test('chat messages persist structured command result blocks', () {
      final message = ChatMessage(
        id: 'msg-command',
        authorName: '秘书',
        content: '我先查看一下\n根目录已使用 42G',
        createdAt: DateTime(2026, 6, 29),
        contentBlocks: const [
          ChatMessageContentBlock.text('我先查看一下'),
          ChatMessageContentBlock.commandResult(
            CommandResultAttachment(
              requestId: 'command-df',
              status: CommandRequestStatus.executed,
              workingDirectory: '/',
              command: 'df -h /',
              output: 'Filesystem 42Gi /',
            ),
          ),
          ChatMessageContentBlock.text('根目录已使用 42G'),
        ],
      );

      final restored = ChatMessage.fromJson(message.toJson());

      expect(restored.contentBlocks, hasLength(3));
      expect(restored.contentBlocks.first.text, '我先查看一下');
      expect(restored.contentBlocks[1].commandResult?.command, 'df -h /');
      expect(restored.contentBlocks[1].commandResult?.output, contains('42Gi'));
      expect(restored.contentBlocks.last.text, '根目录已使用 42G');
    });

    test('chat messages normalize null content blocks from dynamic state', () {
      final message = Function.apply(
        ChatMessage.new,
        const [],
        {
          #id: 'msg-null-blocks',
          #authorName: '秘书',
          #content: '旧运行态消息',
          #createdAt: DateTime(2026, 6, 29),
          #contentBlocks: null,
        },
      ) as ChatMessage;

      expect(message.contentBlocks, isEmpty);
      expect(message.toJson()['contentBlocks'], isEmpty);
    });

    test('audit entries persist structured metadata', () {
      final entry = AuditEntry(
        id: 'audit-raw-response',
        action: 'model_response_diagnostic',
        detail: 'thinkingChars=0',
        metadata: const {
          'rawResponse': '{"choices":[{"message":{"content":"answer"}}]}',
          'streaming': false,
          'model': 'model-main',
        },
        createdAt: DateTime(2026, 6, 19, 10),
      );

      final restored = AuditEntry.fromJson(entry.toJson());

      expect(restored.metadata, isNotNull);
      expect(
        restored.metadata!['rawResponse'],
        '{"choices":[{"message":{"content":"answer"}}]}',
      );
      expect(restored.metadata!['streaming'], isFalse);
      expect(restored.metadata!['model'], 'model-main');
    });

    test('model profiles persist optional reasoning effort', () {
      const profile = ModelProfile(
        id: 'model-reasoning',
        name: 'Reasoning Model',
        baseUrl: 'https://api.openai.com/v1',
        modelName: 'gpt-reasoning',
        apiKey: 'secret',
        reasoningEffort: 'high',
      );

      final restored = ModelProfile.fromJson(profile.toJson());
      final legacy = ModelProfile.fromJson({
        'id': 'model-legacy',
        'name': 'Legacy',
        'baseUrl': 'https://api.openai.com/v1',
        'modelName': 'legacy-model',
        'apiKey': 'secret',
      });

      expect(restored.reasoningEffort, 'high');
      expect(restored.toJson()['reasoningEffort'], 'high');
      expect(legacy.reasoningEffort, isNull);
    });
  });
}
