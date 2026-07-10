import 'dart:io';

import 'package:ai_team/core/workspace/image_paste_service.dart';
import 'package:ai_team/core/workspace/pending_image_attachment.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImagePasteService path parsing', () {
    test('parses file urls and quoted paths only when image exists', () async {
      final dir = await Directory.systemTemp.createTemp('ai_team_paste_');
      addTearDown(() async => dir.delete(recursive: true));
      final image = File('${dir.path}/sample.png');
      await image.writeAsBytes(_onePixelPng);
      final service = ImagePasteService();

      final fromFileUrl = await service.parsePastedImagePath(
        image.uri.toString(),
      );
      expect(fromFileUrl.path, image.path);
      expect(fromFileUrl.isImagePath, isTrue);

      final fromQuoted = await service.parsePastedImagePath('"${image.path}"');
      expect(fromQuoted.path, image.path);
      expect(fromQuoted.isImagePath, isTrue);
    });

    test('treats non image text as normal paste text', () async {
      final service = ImagePasteService();

      final result = await service.parsePastedImagePath('hello world');

      expect(result.isImagePath, isFalse);
      expect(result.path, isNull);
    });

    test('parses shell escaped paths with spaces before plain text filtering', () async {
      final dir = await Directory.systemTemp.createTemp('ai_team_paste_');
      addTearDown(() async => dir.delete(recursive: true));
      final image = File('${dir.path}/sample image.png');
      await image.writeAsBytes(_onePixelPng);
      final service = ImagePasteService();

      final result = await service.parsePastedImagePath(
        image.path.replaceAll(' ', r'\ '),
      );

      expect(result.path, image.path);
      expect(result.isImagePath, isTrue);
    });

    test('does not leave a temporary file when bytes fail to decode', () async {
      final existingTempFiles = Directory.systemTemp
          .listSync()
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last.startsWith(
                'ai_team_clipboard_image_',
              ))
          .map((file) => file.path)
          .toSet();
      final service = ImagePasteService();

      final attachment = await service.attachmentFromBytes(
        Uint8List.fromList([1, 2, 3]),
        extension: '.png',
        source: PendingImageSource.clipboardImage,
      );

      final newTempFiles = Directory.systemTemp
          .listSync()
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last.startsWith(
                'ai_team_clipboard_image_',
              ))
          .where((file) => !existingTempFiles.contains(file.path));
      expect(attachment.status, PendingImageStatus.failed);
      expect(newTempFiles, isEmpty);
    });

    test('insertText replaces selection and clears composing', () {
      const value = TextEditingValue(
        text: 'hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
        composing: TextRange(start: 0, end: 5),
      );

      final next = ImagePasteService.insertText(value, 'Dart');

      expect(next.text, 'hello Dart');
      expect(next.selection, const TextSelection.collapsed(offset: 10));
      expect(next.composing, TextRange.empty);
    });
  });

  group('ImagePasteService clipboard candidate parsing', () {
    test('prefers file uri over image bytes for the same item', () async {
      final dir = await Directory.systemTemp.createTemp('ai_team_paste_');
      addTearDown(() async => dir.delete(recursive: true));
      final image = File('${dir.path}/clipboard.png');
      await image.writeAsBytes(_onePixelPng);
      final service = ImagePasteService();

      final attachments = await service.attachmentsFromClipboardItems([
        ImageClipboardItem(
          fileUri: image.uri,
          imageBytesByExtension: {'.png': Uint8List.fromList(_onePixelPng)},
        ),
      ]);

      expect(attachments, hasLength(1));
      expect(attachments.single.source, PendingImageSource.clipboardFile);
      expect(attachments.single.file.path, image.path);
      expect(attachments.single.ownedTemporaryFile, isFalse);
    });

    test('falls back to image bytes when file uri is absent', () async {
      final service = ImagePasteService();

      final attachments = await service.attachmentsFromClipboardItems([
        ImageClipboardItem(
          imageBytesByExtension: {'.png': Uint8List.fromList(_onePixelPng)},
        ),
      ]);
      addTearDown(() async {
        if (attachments.single.file.existsSync()) {
          await attachments.single.file.delete();
        }
      });

      expect(attachments, hasLength(1));
      expect(attachments.single.source, PendingImageSource.clipboardImage);
      expect(attachments.single.status, PendingImageStatus.ready);
      expect(attachments.single.ownedTemporaryFile, isTrue);
    });

    test('filters non image items and reports corrupt file uri images', () async {
      final dir = await Directory.systemTemp.createTemp('ai_team_paste_');
      addTearDown(() async => dir.delete(recursive: true));
      final text = File('${dir.path}/note.txt');
      await text.writeAsString('not an image');
      final corruptImage = File('${dir.path}/bad.png');
      await corruptImage.writeAsBytes([1, 2, 3]);
      final service = ImagePasteService();

      final attachments = await service.attachmentsFromClipboardItems([
        ImageClipboardItem(fileUri: text.uri),
        ImageClipboardItem(fileUri: corruptImage.uri),
      ]);

      expect(attachments, hasLength(1));
      expect(attachments.single.source, PendingImageSource.clipboardFile);
      expect(attachments.single.status, PendingImageStatus.failed);
      expect(attachments.single.errorMessage, '图片无法解码');
    });
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
