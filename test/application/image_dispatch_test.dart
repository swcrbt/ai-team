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
      final harness = _buildDispatchHarnessWithTeamImagesDisabled();
      final originalMessagesLength = harness.conversation.messages.length;

      await expectLater(
        harness.controller.dispatchConversation(
          harness.conversation.id,
          '看图',
          images: [File('/tmp/missing.png')],
        ),
        throwsA(isA<StateError>()),
      );

      // 验证消息没有被写入
      expect(harness.conversation.messages.length, originalMessagesLength);
    });

    test('dispatch rejects prepared image attachments when current model does not support images', () async {
      final harness = _buildDispatchHarnessWithTeamImagesDisabled();
      final originalMessagesLength = harness.conversation.messages.length;

      await expectLater(
        harness.controller.dispatchConversation(
          harness.conversation.id,
          '看图',
          preparedAttachments: const [
            MessageAttachment(
              id: 'attachment-1',
              type: MessageAttachmentType.image,
              filePath: '/tmp/test.png',
              mimeType: 'image/png',
              fileSize: 10,
            ),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      expect(harness.conversation.messages.length, originalMessagesLength);
    });

    test('dispatch returns false when conversation is paused before user message commit', () async {
      final harness = _buildDispatchHarness(
        conversationStatus: ConversationStatus.paused,
      );
      final originalMessagesLength = harness.conversation.messages.length;

      final committed = await harness.controller.dispatchConversation(
        harness.conversation.id,
        '看图',
        preparedAttachments: const [
          MessageAttachment(
            id: 'attachment-1',
            type: MessageAttachmentType.image,
            filePath: '/tmp/test.png',
            mimeType: 'image/png',
            fileSize: 10,
          ),
        ],
      );

      expect(committed, isFalse);
      expect(harness.conversation.messages.length, originalMessagesLength);
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

_DispatchHarness _buildDispatchHarnessWithTeamImagesDisabled() {
  return _buildDispatchHarness(teamSupportsImages: false);
}

_DispatchHarness _buildDispatchHarness({
  bool teamSupportsImages = true,
  ConversationStatus conversationStatus = ConversationStatus.idle,
}) {
  var state = AppState.seed();
  final conversationId = state.conversations.first.id;
  final team = state.teams.firstWhere((item) => item.id == 'team-default');
  final secretary = state.members.firstWhere(
    (item) => item.id == team.secretaryMemberId,
  );
  final secretaryModel = state.models
      .firstWhere((item) => item.id == secretary.modelId)
      .copyWith(supportsImages: teamSupportsImages);
  state = state.copyWith(
    models: state.models
        .map((item) => item.id == secretaryModel.id ? secretaryModel : item)
        .toList(),
    conversations: state.conversations
        .map(
          (item) => item.id == conversationId
              ? item.copyWith(status: conversationStatus)
              : item,
        )
        .toList(),
  );

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
    selectedConversationId: () => conversationId,
    notify: () {},
    onStreamingDraft: ({required conversationId, required message}) {},
    clearStreamingDraftsForConversation: (_) {},
  );

  return _DispatchHarness(
    controller: controller,
    readState: () => state,
    conversationId: conversationId,
  );
}

class _DispatchHarness {
  const _DispatchHarness({
    required this.controller,
    required this.readState,
    required this.conversationId,
  });

  final DispatchController controller;
  final AppState Function() readState;
  final String conversationId;

  Conversation get conversation => readState().conversations.firstWhere(
        (item) => item.id == conversationId,
      );
}
