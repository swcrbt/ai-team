import 'dart:io';

import 'package:ai_team/core/workspace/image_service.dart';
import 'package:ai_team/core/workspace/pending_image_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('savePendingImages rolls back files when a later image fails', () async {
    final root = await Directory.systemTemp.createTemp('ai_team_images_');
    addTearDown(() async => root.delete(recursive: true));
    final valid = File('${root.path}/valid.png')..writeAsBytesSync(_onePixelPng);
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
