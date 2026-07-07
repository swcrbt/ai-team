import 'dart:io';

import 'package:ai_team/application/app_controller.dart';
import 'package:ai_team/application/conversation_title_generator.dart';
import 'package:ai_team/application/dispatch_controller.dart';
import 'package:ai_team/application/task_queue_controller.dart';
import 'package:ai_team/application/workspace_command_controller.dart';
import 'package:ai_team/core/commands.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/orchestrator.dart';
import 'package:ai_team/core/storage_directories.dart';
import 'package:ai_team/core/workspace/image_service.dart';
import 'package:flutter_test/flutter_test.dart';

// 用于测试的 one-pixel PNG
final _onePixelPng = <int>[
  137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1,
  0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84,
  8, 153, 99, 0, 1, 0, 0, 5, 0, 1, 13, 10, 46, 180, 0, 0, 0, 0, 73, 69, 78,
  68, 174, 66, 96, 130,
];

void main() {
  group('图片附件提交门禁', () {
    test('dispatch rejects image attachments when current model does not support images', () async {
      var state = AppState.seed();
      final conversation = state.conversations.first;
      
      // 创建不支持图片的模型
      final disabledModel = state.models.first.copyWith(supportsImages: false);
      state = state.copyWith(
        models: [disabledModel, ...state.models.skip(1)],
      );
      
      // 确保会话使用不支持图片的模型
      final member = state.members.firstWhere(
        (m) => m.id == conversation.memberId,
        orElse: () => state.members.first,
      );
      final updatedMember = member.copyWith(modelId: disabledModel.id);
      state = state.copyWith(
        members: state.members
            .map((m) => m.id == updatedMember.id ? updatedMember : m)
            .toList(),
      );
      
      var notifyCount = 0;
      final taskQueue = TaskQueueController(
        readState: () => state,
        commit: (nextState) => state = nextState,
        gateway: FakeModelGateway(),
      );
      final workspaceCommands = WorkspaceCommandController(
        readState: () => state,
        commit: (nextState) => state = nextState,
      );
      final titleGenerator = ConversationTitleGenerator(
        readState: () => state,
        commit: (nextState) => state = nextState,
        gateway: FakeModelGateway(),
      );
      final controller = DispatchController(
        readState: () => state,
        commit: (nextState) => state = nextState,
        taskQueue: taskQueue,
        workspaceCommands: workspaceCommands,
        titleGenerator: titleGenerator,
        orchestrator: TeamOrchestrator(FakeModelGateway()),
        commandService: const CommandService(),
        imageService: ImageService(Directory.systemTemp),
        selectedConversationId: () => conversation.id,
        notify: () => notifyCount++,
        onStreamingDraft: ({required conversationId, required message}) {},
        clearStreamingDraftsForConversation: (_) {},
      );

      final originalMessagesLength = conversation.messages.length;

      await expectLater(
        controller.dispatchConversation(
          conversation.id,
          '看图',
          images: [File('/tmp/missing.png')],
        ),
        throwsA(isA<StateError>()),
      );

      // 验证消息没有被写入
      expect(
        state.conversations
            .firstWhere((c) => c.id == conversation.id)
            .messages
            .length,
        originalMessagesLength,
      );
    });
  });

  group('会话删除清理', () {
    test('delete conversation cleans conversation image directory', () async {
      final tempRoot = await Directory.systemTemp.createTemp('ai_team_delete_test_');
      addTearDown(() async => tempRoot.delete(recursive: true));

      final controller = AppController(
        AppState.seed(),
        TeamOrchestrator(FakeModelGateway()),
        storageDirectories: StorageDirectories(
          stateDirectory: tempRoot.path,
          auditDirectory: '${tempRoot.path}/audit',
          conversationDirectory: '${tempRoot.path}/conversations',
          cacheDirectory: '${tempRoot.path}/cache',
        ),
      );

      final conversationId = controller.currentConversation.id;
      final dir = Directory('${tempRoot.path}/images/$conversationId');
      dir.createSync(recursive: true);
      File('${dir.path}/orphan.png').writeAsBytesSync(_onePixelPng);

      expect(dir.existsSync(), isTrue);

      controller.deleteConversationSession(conversationId);
      
      // 等待异步清理完成（轮询直到目录被删除或超时）
      await Future.doWhile(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return dir.existsSync();
      }).timeout(const Duration(seconds: 2));

      expect(dir.existsSync(), isFalse);
    });
  });
}
