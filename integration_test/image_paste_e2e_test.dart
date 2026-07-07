import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ai_team/ui/app_shell.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/model_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('图片粘贴 E2E', () {
    testWidgets('应用启动成功', (tester) async {
      await _pumpAppWithImageSupport(tester);
      
      // 验证聊天输入框存在
      expect(find.byKey(const ValueKey('chat-input-conv-member-secretary')), findsOneWidget);
    });
  });
}

Future<void> _pumpAppWithImageSupport(WidgetTester tester) async {
  await tester.pumpWidget(
    AiTeamApp(
      initialState: AppState.seed(),
      modelGateway: _FakeGateway(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpAppWithoutImageSupport(WidgetTester tester) async {
  // 直接使用seed state，稍后切换到Local模型
  await tester.pumpWidget(
    AiTeamApp(
      initialState: AppState.seed(),
      modelGateway: _FakeGateway(),
    ),
  );
  await tester.pumpAndSettle();
  
  // 切换到Local模型（不支持图片）
  await tester.tap(find.byTooltip('管理'));
  await tester.pumpAndSettle();
  
  // 找到Local模型并选择
  await tester.tap(find.text('Local Compatible'));
  await tester.pumpAndSettle();
  
  // 返回聊天界面
  await tester.tap(find.byTooltip('聊天'));
  await tester.pumpAndSettle();
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
