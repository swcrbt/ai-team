import 'dart:io';

import 'package:ai_team/application/conversation_title_generator.dart';
import 'package:ai_team/application/dispatch_controller.dart';
import 'package:ai_team/application/task_queue_controller.dart';
import 'package:ai_team/application/workspace_command_controller.dart';
import 'package:ai_team/core/commands.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/orchestrator.dart';
import 'package:ai_team/core/workspace/image_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/model_gateway_fakes.dart';

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

      final originalMessages = conversation.messages;

      await expectLater(
        controller.dispatchConversation(
          conversation.id,
          '看图',
          images: [File('/tmp/missing.png')],
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        state.conversations
            .firstWhere((c) => c.id == conversation.id)
            .messages,
        originalMessages,
      );
    });
  });
}
