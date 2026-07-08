import 'dart:io';

import 'package:ai_team/core/workspace/image_paste_service.dart';
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

      final fromFileUrl = await service.parsePastedImagePath(image.uri.toString());
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

    test('parses shell escaped image paths with spaces', () async {
      final dir = await Directory.systemTemp.createTemp('ai_team_paste_space_');
      addTearDown(() async => dir.delete(recursive: true));
      final image = File('${dir.path}/a b.png');
      await image.writeAsBytes(_onePixelPng);
      final service = ImagePasteService();

      final result = await service.parsePastedImagePath(
        image.path.replaceAll(' ', r'\ '),
      );

      expect(result.isImagePath, isTrue);
      expect(result.path, image.path);
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
}

const _onePixelPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];
