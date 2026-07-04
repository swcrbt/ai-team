import 'dart:ui';

import 'package:ai_team/ui/chat/chat_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SplitSendButton exposes send and stop states', (tester) async {
    var sent = 0;
    var stopped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitSendButton(
            isDispatching: false,
            isConversationDispatching: false,
            onSend: () => sent++,
            onStop: () => stopped++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));

    expect(sent, 1);
    expect(stopped, 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SplitSendButton(
            isDispatching: true,
            isConversationDispatching: true,
            onSend: () => sent++,
            onStop: () => stopped++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));

    expect(sent, 1);
    expect(stopped, 1);
  });

  testWidgets('TokenUsageMeter shows input output and cache hit popover',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: TokenUsageMeter(
              data: TokenUsageData(
                contextWindowTokens: 32000,
                inputTokens: 3100,
                outputTokens: 1700,
                cachedTokens: 800,
                totalTokens: 4800,
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer();
    await gesture.moveTo(tester.getCenter(find.byKey(
      const ValueKey('token-usage-meter'),
    )));
    await tester.pumpAndSettle();

    expect(find.text('输入 tokens'), findsOneWidget);
    expect(find.text('输出 tokens'), findsOneWidget);
    expect(find.text('命中缓存'), findsOneWidget);
    expect(find.text('4.8k / 32k'), findsOneWidget);
  });
}
