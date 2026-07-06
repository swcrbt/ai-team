import 'dart:io';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/workspace/image_service.dart';
import 'package:ai_team/ui/chat/message_image_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('messageImageAttachments keeps only image attachments in display order',
      () {
    final images = messageImageAttachments(const [
      MessageAttachment(
        id: 'file-1',
        type: MessageAttachmentType.file,
        filePath: 'notes.txt',
      ),
      MessageAttachment(
        id: 'image-1',
        type: MessageAttachmentType.image,
        filePath: 'first.png',
      ),
      MessageAttachment(
        id: 'image-2',
        type: MessageAttachmentType.image,
        filePath: 'second.png',
      ),
    ]);

    expect(images.map((attachment) => attachment.id), [
      'image-1',
      'image-2',
    ]);
  });

  testWidgets('message image grid shows placeholder for missing file', (tester) async {
    final root = await Directory.systemTemp.createTemp('ai_team_missing_image_');
    addTearDown(() async => root.delete(recursive: true));
    final service = ImageService(root);

    await tester.pumpWidget(MaterialApp(
      home: MessageImageGrid(
        imageService: service,
        attachments: const [
          MessageAttachment(
            id: 'image-1',
            type: MessageAttachmentType.image,
            filePath: 'images/conv/missing.png',
            fileName: 'missing.png',
          ),
        ],
      ),
    ));

    expect(find.byIcon(Icons.broken_image), findsOneWidget);
  });

  testWidgets('message image grid uses fixed size and semantic labels', (tester) async {
    final root = await Directory.systemTemp.createTemp('ai_team_image_semantics_');
    addTearDown(() async => root.delete(recursive: true));
    final service = ImageService(root);

    await tester.pumpWidget(MaterialApp(
      home: MessageImageGrid(
        imageService: service,
        attachments: const [
          MessageAttachment(
            id: 'image-1',
            type: MessageAttachmentType.image,
            filePath: 'images/conv/test.png',
            fileName: 'test.png',
          ),
        ],
      ),
    ));

    // 验证有 Semantics 标签
    expect(find.bySemanticsLabel('消息图片 1'), findsOneWidget);
    
    // 验证使用 SizedBox 固定尺寸
    final sizedBox = tester.widget<SizedBox>(find.byType(SizedBox).first);
    expect(sizedBox.width, 300); // 单张图片宽度
    expect(sizedBox.height, 200); // 单张图片高度
  });
}
