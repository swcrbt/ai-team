import 'dart:io';

import 'package:ai_team/application/app_controller.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/orchestrator.dart';
import 'package:ai_team/core/storage_directories.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/model_gateway_fakes.dart';

void main() {
  group('队列图片归属', () {
    test('queued task reuses queued user message with attachments', () async {
      final tempDir = await Directory.systemTemp.createTemp('ai_team_queue_');
      addTearDown(() async => tempDir.delete(recursive: true));
      
      final image = File('${tempDir.path}/test.png')
        ..writeAsBytesSync(_onePixelPng);
      
      final controller = AppController(
        AppState.seed(),
        TeamOrchestrator(ScriptedTitleGateway(title: '分析图片任务')),
        storageDirectories: StorageDirectories(
          stateDirectory: tempDir.path,
          auditDirectory: '${tempDir.path}/audit',
          conversationDirectory: '${tempDir.path}/conversations',
          cacheDirectory: '${tempDir.path}/cache',
        ),
      );
      
      final conversation = controller.currentConversation;

      await controller.enqueueCurrentConversationTask('分析这张图', images: [image]);
      
      final queuedConversation = controller.conversationById(conversation.id);
      final queuedUserMessages = queuedConversation.messages
          .where((message) => message.isUser)
          .toList();
      expect(queuedUserMessages, hasLength(1));
      expect(queuedUserMessages.single.attachments, hasLength(1));

      await controller.runNextQueuedTask();
      
      final completedConversation = controller.conversationById(conversation.id);
      final userMessages = completedConversation.messages
          .where((message) => message.isUser)
          .toList();
      expect(userMessages, hasLength(1));
      expect(userMessages.single.attachments, hasLength(1));
    });
  });
}

// 1x1 透明 PNG (67 bytes)
const _onePixelPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1 dimensions
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, // bit depth, color type, etc.
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, // IDAT chunk
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, // compressed data
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, // more data
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND chunk
  0x42, 0x60, 0x82,
];
