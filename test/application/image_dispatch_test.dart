import 'dart:io';

import 'package:ai_team/application/app_controller.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/model_gateway.dart';
import 'package:ai_team/core/orchestrator.dart';
import 'package:ai_team/core/storage_directories.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/domain/domain_test_support.dart';

void main() {
  test(
      'dispatch rejects image attachments when current model does not support images',
      () async {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(ScriptedRecordingGateway(['不会调用'])),
    );
    addTearDown(controller.dispose);
    final conversation = controller.currentConversation;
    final disabledModel = controller.state.models.first.copyWith(
      supportsImages: false,
    );
    controller.updateModel(disabledModel);

    await expectLater(
      controller.dispatchConversation(
        conversation.id,
        '看图',
        images: [File('/tmp/missing.png')],
      ),
      throwsA(isA<StateError>()),
    );

    expect(controller.conversationById(conversation.id).messages,
        conversation.messages);
  });

  test('reports model image capability for team and member conversations', () {
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(ScriptedRecordingGateway(['不会调用'])),
    );
    addTearDown(controller.dispose);

    expect(
      controller.modelSupportsImagesForConversation('conv-team-default'),
      isTrue,
    );
    expect(
      controller.modelSupportsImagesForConversation('conv-member-tester'),
      isFalse,
    );
  });

  test('dispatch saves image files as user message attachments', () async {
    final temp =
        await Directory.systemTemp.createTemp('ai_team_image_dispatch_');
    addTearDown(() async => temp.delete(recursive: true));
    final source = File('${temp.path}/source.png')
      ..writeAsBytesSync(_onePixelPng);
    final controller = AppController(
      AppState.seed(),
      TeamOrchestrator(ScriptedRecordingGateway(['成员回复'])),
      storageDirectories: StorageDirectories.defaults(temp),
    );
    addTearDown(controller.dispose);

    await controller.dispatchConversation(
      'conv-member-secretary',
      '看图',
      images: [source],
    );

    final conversation = controller.conversationById('conv-member-secretary');
    final userMessage = conversation.messages.firstWhere(
      (message) => message.isUser && message.content == '看图',
    );
    expect(userMessage.content, isNot(contains('[Image')));
    expect(userMessage.attachments, hasLength(1));
    expect(userMessage.attachments.single.type, MessageAttachmentType.image);
    expect(
      File('${temp.path}/conversations/${userMessage.attachments.single.filePath}')
          .existsSync(),
      isTrue,
    );
  });

  test(
      'orchestrator uses external user message id, prepared attachments, and commit callback',
      () async {
    final progressStates = <AppState>[];
    var committedCount = 0;
    const attachment = MessageAttachment(
      id: 'image-msg-external-0',
      type: MessageAttachmentType.image,
      filePath: 'images/conv-member-secretary/msg-external-0.png',
      mimeType: 'image/png',
    );
    final cancellation = ModelRequestCancellation()..cancel();

    await expectLater(
      TeamOrchestrator(ScriptedRecordingGateway(['成员回复'])).dispatchMemberChat(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '看图',
        userMessageId: 'msg-external',
        preparedAttachments: const [attachment],
        cancellation: cancellation,
        onProgress: progressStates.add,
        onUserMessageCommitted: () => committedCount++,
      ),
      throwsA(isA<ModelGatewayException>()),
    );

    final committedState = progressStates.firstWhere(
      (state) => state.conversations
          .firstWhere(
              (conversation) => conversation.id == 'conv-member-secretary')
          .messages
          .any((message) => message.id == 'msg-external'),
    );
    final committedMessage = committedState.conversations
        .firstWhere(
            (conversation) => conversation.id == 'conv-member-secretary')
        .messages
        .firstWhere((message) => message.id == 'msg-external');

    expect(committedCount, 1);
    expect(committedMessage.attachments, [attachment]);
  });
}

const _onePixelPng = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];
