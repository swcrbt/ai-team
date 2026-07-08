import 'dart:io';

import 'package:ai_team/core/workspace/image_paste_service.dart';
import 'package:ai_team/core/workspace/pending_image_attachment.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImagePasteService 文本插入', () {
    test('insertText inserts at cursor position', () {
      const value = TextEditingValue(
        text: 'hello ',
        selection: TextSelection.collapsed(offset: 6),
      );

      final result = ImagePasteService.insertText(value, 'world');

      expect(result.text, 'hello world');
      expect(result.selection.baseOffset, 11);
    });

    test('insertText replaces selection', () {
      const value = TextEditingValue(
        text: 'hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
      );

      final result = ImagePasteService.insertText(value, 'Flutter');

      expect(result.text, 'hello Flutter');
      expect(result.selection.baseOffset, 13);
    });
  });

  group('FakeImagePasteService', () {
    test('returns configured clipboard text result', () async {
      final service = FakeImagePasteService(
        clipboardText: 'test',
        isImagePath: false,
      );

      final result = await service.parsePastedImagePath('test');

      expect(result.isImagePath, false);
    });

    test('returns configured image path result', () async {
      final service = FakeImagePasteService(
        clipboardText: '/path/to/image.png',
        isImagePath: true,
        imagePath: '/path/to/image.png',
      );

      final result = await service.parsePastedImagePath('/path/to/image.png');

      expect(result.isImagePath, true);
      expect(result.path, '/path/to/image.png');
    });

    test('returns configured clipboard images', () async {
      final file = File('/tmp/test.png');
      final service = FakeImagePasteService(
        clipboardImages: [
          PendingImageAttachment(
            id: 'test-1',
            source: PendingImageSource.clipboardImage,
            file: file,
            ownedTemporaryFile: true,
            fileSize: 100,
            width: 10,
            height: 10,
          ),
        ],
      );

      final result = await service.readClipboardImageCandidates();

      expect(result.length, 1);
      expect(result[0].id, 'test-1');
    });
  });

}

/// 假的图片粘贴服务
class FakeImagePasteService extends ImagePasteService {
  FakeImagePasteService({
    this.clipboardText = '',
    this.isImagePath = false,
    this.imagePath,
    this.clipboardImages = const [],
    this.errorMessage,
  });

  final String clipboardText;
  final bool isImagePath;
  final String? imagePath;
  final List<PendingImageAttachment> clipboardImages;
  final String? errorMessage;

  @override
  Future<List<PendingImageAttachment>> readClipboardImageCandidates() async {
    return clipboardImages;
  }

  @override
  Future<ImagePathParseResult> parsePastedImagePath(String text) async {
    if (errorMessage != null) {
      return ImagePathParseResult.error(errorMessage!);
    }
    if (isImagePath && imagePath != null) {
      return ImagePathParseResult.image(imagePath!);
    }
    return const ImagePathParseResult.notImagePath();
  }
}
