import 'dart:convert';
import 'dart:io';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/workspace/image_service.dart';
import 'package:ai_team/core/workspace/pending_image_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('savePendingImages rolls back files when a later image fails', () async {
    final root = await Directory.systemTemp.createTemp('ai_team_images_');
    addTearDown(() async => root.delete(recursive: true));
    final valid = File('${root.path}/valid.png')
      ..writeAsBytesSync(_onePixelPng);
    final missing = File('${root.path}/missing.png');
    final service = ImageService(root);

    await expectLater(
      service.savePendingImages(
        conversationId: 'conv-1',
        messageId: 'msg-1',
        images: [
          PendingImageAttachment(
            id: 'pending-1',
            source: PendingImageSource.pickedFile,
            file: valid,
          ),
          PendingImageAttachment(
            id: 'pending-2',
            source: PendingImageSource.pickedFile,
            file: missing,
          ),
        ],
      ),
      throwsA(isA<ImageServiceException>()),
    );

    final imageDir = Directory('${root.path}/images/conv-1');
    expect(imageDir.existsSync(), isFalse);
  });

  test('savePendingImages keeps pre-existing destination files on failure',
      () async {
    final root = await Directory.systemTemp.createTemp('ai_team_images_');
    addTearDown(() async => root.delete(recursive: true));
    final existingDir = Directory('${root.path}/images/conv-1')
      ..createSync(recursive: true);
    final existing = File('${existingDir.path}/msg-1-0.png')
      ..writeAsBytesSync([1, 2, 3]);
    final valid = File('${root.path}/valid.png')
      ..writeAsBytesSync(_onePixelPng);
    final missing = File('${root.path}/missing.png');
    final service = ImageService(root);

    await expectLater(
      service.savePendingImages(
        conversationId: 'conv-1',
        messageId: 'msg-1',
        images: [
          PendingImageAttachment(
            id: 'pending-1',
            source: PendingImageSource.pickedFile,
            file: valid,
          ),
          PendingImageAttachment(
            id: 'pending-2',
            source: PendingImageSource.pickedFile,
            file: missing,
          ),
        ],
      ),
      throwsA(isA<ImageServiceException>()),
    );

    expect(existing.existsSync(), isTrue);
    expect(existing.readAsBytesSync(), [1, 2, 3]);
  });

  test('savePendingImages rolls back a file when saveImage fails after copy',
      () async {
    final root = await Directory.systemTemp.createTemp('ai_team_images_');
    addTearDown(() async => root.delete(recursive: true));
    final valid = File('${root.path}/valid.png')
      ..writeAsBytesSync(_onePixelPng);
    final service = _FailsAfterCopyImageService(root);

    await expectLater(
      service.savePendingImages(
        conversationId: 'conv-1',
        messageId: 'msg-1',
        images: [
          PendingImageAttachment(
            id: 'pending-1',
            source: PendingImageSource.pickedFile,
            file: valid,
          ),
        ],
      ),
      throwsA(isA<ImageServiceException>()),
    );

    expect(
        File('${root.path}/images/conv-1/msg-1-0.png').existsSync(), isFalse);
  });

  test('deleteAttachments removes image files and ignores missing files',
      () async {
    final root = await Directory.systemTemp.createTemp('ai_team_images_');
    addTearDown(() async => root.delete(recursive: true));
    final imageDir = Directory('${root.path}/images/conv-1')
      ..createSync(recursive: true);
    final file = File('${imageDir.path}/msg-1-0.png')
      ..writeAsBytesSync(_onePixelPng);
    final service = ImageService(root);

    await service.deleteAttachments([
      _attachment('images/conv-1/msg-1-0.png'),
      _attachment('images/conv-1/missing.png'),
    ]);

    expect(file.existsSync(), isFalse);
  });

  test('readImageAsDataUrl fails explicitly when the image file is missing',
      () async {
    final root = await Directory.systemTemp.createTemp('ai_team_images_');
    addTearDown(() async => root.delete(recursive: true));
    final service = ImageService(root);

    await expectLater(
      service.readImageAsDataUrl(_attachment('images/conv-1/missing.png')),
      throwsA(isA<ImageServiceException>().having(
        (error) => error.message,
        'message',
        contains('图片文件不存在'),
      )),
    );
  });

  test('readImageAsDataUrl fails explicitly when the image file is unreadable',
      () async {
    final root = await Directory.systemTemp.createTemp('ai_team_images_');
    addTearDown(() async => root.delete(recursive: true));
    final imageDir = Directory('${root.path}/images/conv-1')
      ..createSync(recursive: true);
    final file = File('${imageDir.path}/msg-1-0.png')
      ..writeAsBytesSync(_onePixelPng);
    await Process.run('chmod', ['000', file.path]);
    addTearDown(() async {
      if (file.existsSync()) {
        await Process.run('chmod', ['600', file.path]);
      }
    });
    final service = ImageService(root);

    await expectLater(
      service.readImageAsDataUrl(_attachment('images/conv-1/msg-1-0.png')),
      throwsA(isA<ImageServiceException>().having(
        (error) => error.message,
        'message',
        contains('图片读取失败'),
      )),
    );
  }, skip: Platform.isWindows ? 'POSIX permissions required' : false);

  test('readImageAsDataUrl returns a data URL for readable image files',
      () async {
    final root = await Directory.systemTemp.createTemp('ai_team_images_');
    addTearDown(() async => root.delete(recursive: true));
    final imageDir = Directory('${root.path}/images/conv-1')
      ..createSync(recursive: true);
    File('${imageDir.path}/msg-1-0.png').writeAsBytesSync(_onePixelPng);
    final service = ImageService(root);

    final dataUrl = await service.readImageAsDataUrl(
      _attachment('images/conv-1/msg-1-0.png'),
    );

    expect(dataUrl, 'data:image/png;base64,${base64Encode(_onePixelPng)}');
  });
}

MessageAttachment _attachment(String filePath) => MessageAttachment(
      id: filePath,
      type: MessageAttachmentType.image,
      filePath: filePath,
      mimeType: 'image/png',
    );

class _FailsAfterCopyImageService extends ImageService {
  const _FailsAfterCopyImageService(super.workspaceRoot);

  @override
  Future<MessageAttachment> saveImage({
    required String conversationId,
    required String messageId,
    required File sourceFile,
    required int index,
    String? mimeType,
  }) async {
    final imageDir = imageDirectoryForConversation(conversationId);
    await imageDir.create(recursive: true);
    await sourceFile.copy('${imageDir.path}/$messageId-$index.png');
    throw const ImageServiceException('模拟复制后失败');
  }
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
