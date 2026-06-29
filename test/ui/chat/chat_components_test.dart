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
}
