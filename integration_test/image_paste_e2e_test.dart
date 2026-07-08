import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ai_team/ui/app_shell.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/model_gateway.dart';
import 'package:ai_team/core/storage_directories.dart';
import 'package:ai_team/core/workspace/image_paste_service.dart';
import 'package:ai_team/core/workspace/pending_image_attachment.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('图片粘贴 E2E', () {
    testWidgets('应用启动成功', (tester) async {
      await _pumpAppWithImageSupport(tester);

      expect(find.byKey(const ValueKey('chat-input-conv-member-secretary')), findsOneWidget);
    });

    testWidgets('粘贴图片后发送的用户消息保留图片', (tester) async {
      final image = await _createTestImage();
      await _pumpAppWithImageSupport(
        tester,
        clipboardImages: [_pendingImage(image)],
      );

      await _enterTextAndPaste(tester, 'conv-member-secretary', '测试图片');
      expect(find.byTooltip('移除图片 1'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await _pumpUntil(tester, find.bySemanticsLabel('消息图片 1'));

      expect(find.text('测试图片'), findsOneWidget);
      expect(find.bySemanticsLabel('消息图片 1'), findsOneWidget);
    });

    testWidgets('不支持图片的模型拒绝图片粘贴', (tester) async {
      final image = await _createTestImage();
      await _pumpAppWithoutImageSupport(
        tester,
        clipboardImages: [_pendingImage(image)],
      );

      await _enterTextAndPaste(tester, 'conv-member-secretary', '只粘贴文字');

      expect(find.text('当前模型不支持图片输入'), findsOneWidget);
      expect(find.byTooltip('移除图片 1'), findsNothing);
    });
  });
}

Future<void> _pumpAppWithImageSupport(
  WidgetTester tester, {
  List<PendingImageAttachment> clipboardImages = const [],
}) async {
  final tempRoot = await Directory.systemTemp.createTemp('ai_team_e2e_');
  await tester.pumpWidget(
    AiTeamApp(
      initialState: AppState.seed(),
      modelGateway: _FakeGateway(),
      storageDirectories: StorageDirectories(
        stateDirectory: tempRoot.path,
        auditDirectory: '${tempRoot.path}/audit',
        conversationDirectory: '${tempRoot.path}/conversations',
        cacheDirectory: '${tempRoot.path}/cache',
      ),
      imagePasteServiceFactory: (_) => _FakeImagePasteService(
        clipboardImages: clipboardImages,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _pumpAppWithoutImageSupport(
  WidgetTester tester, {
  List<PendingImageAttachment> clipboardImages = const [],
}) async {
  final tempRoot = await Directory.systemTemp.createTemp('ai_team_e2e_');
  final seed = AppState.seed();
  final disabledMain = seed.models
      .firstWhere((model) => model.id == 'model-main')
      .copyWith(supportsImages: false);
  final state = seed.copyWith(
    models: seed.models
        .map((model) => model.id == disabledMain.id ? disabledMain : model)
        .toList(),
  );
  await tester.pumpWidget(
    AiTeamApp(
      initialState: state,
      modelGateway: _FakeGateway(),
      storageDirectories: StorageDirectories(
        stateDirectory: tempRoot.path,
        auditDirectory: '${tempRoot.path}/audit',
        conversationDirectory: '${tempRoot.path}/conversations',
        cacheDirectory: '${tempRoot.path}/cache',
      ),
      imagePasteServiceFactory: (_) => _FakeImagePasteService(
        clipboardImages: clipboardImages,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _enterTextAndPaste(
  WidgetTester tester,
  String conversationId,
  String text,
) async {
  final input = find.byKey(ValueKey('chat-input-$conversationId'));
  await tester.tap(input);
  await tester.enterText(input, text);
  Actions.invoke(
    tester.element(input),
    const PasteTextIntent(SelectionChangedCause.keyboard),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  expect(finder, findsOneWidget);
}

Future<File> _createTestImage() async {
  final file = File('${Directory.systemTemp.path}/test_${DateTime.now().millisecondsSinceEpoch}.png');
  // 1x1 PNG
  await file.writeAsBytes([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);
  return file;
}

PendingImageAttachment _pendingImage(File file) {
  return PendingImageAttachment(
    id: 'pending-${file.path.hashCode}',
    source: PendingImageSource.clipboardImage,
    file: file,
    mimeType: 'image/png',
    fileSize: file.lengthSync(),
    width: 1,
    height: 1,
  );
}

class _FakeGateway implements ModelGateway {
  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    return '收到消息';
  }
}

class _FakeImagePasteService extends ImagePasteService {
  _FakeImagePasteService({this.clipboardImages = const []});

  final List<PendingImageAttachment> clipboardImages;

  @override
  Future<List<PendingImageAttachment>> readClipboardImageCandidates() async {
    return clipboardImages;
  }
}
