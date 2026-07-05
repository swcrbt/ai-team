export 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_team/core/domain.dart';

export 'package:flutter/gestures.dart';
export 'package:flutter/material.dart';
export 'package:flutter/services.dart';
export 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
export 'package:flutter_test/flutter_test.dart';

export 'package:ai_team/app.dart';
export 'package:ai_team/core/domain.dart';
export 'package:ai_team/core/model_gateway.dart';
export 'package:ai_team/core/orchestrator.dart';

export '../support/model_gateway_fakes.dart';

AppState stateWithLongSecretaryChat() {
  final seed = AppState.seed();
  final conversation = seed.conversations.firstWhere(
    (item) => item.id == 'conv-member-secretary',
  );
  return seed.copyWith(
    conversations: [
      conversation.copyWith(
        messages: List.generate(
          45,
          (index) => ChatMessage(
            id: 'msg-history-$index',
            authorName: '秘书',
            content: '历史消息 $index\n${'填充内容 ' * 12}',
            createdAt: DateTime(2026, 6, 14, 8).add(
              Duration(minutes: index),
            ),
          ),
        ),
      ),
      ...seed.conversations.where(
        (item) => item.id != conversation.id,
      ),
    ],
  );
}

AppState stateWithLongTeamAndSecretaryChats() {
  final seed = AppState.seed();
  final teamConversation = seed.conversations.firstWhere(
    (item) => item.id == 'conv-team-default',
  );
  final secretaryConversation = seed.conversations.firstWhere(
    (item) => item.id == 'conv-member-secretary',
  );
  return seed.copyWith(
    conversations: seed.conversations.map((conversation) {
      if (conversation.id == teamConversation.id) {
        return conversation.copyWith(
          messages: List.generate(
            45,
            (index) => ChatMessage(
              id: 'msg-team-history-$index',
              authorName: index.isEven ? '秘书' : '前端工程师',
              memberId: index.isEven ? 'member-secretary' : 'member-frontend',
              content: '群聊历史消息 $index\n${'团队填充内容 ' * 12}',
              createdAt: DateTime(2026, 6, 14, 8).add(
                Duration(minutes: index),
              ),
            ),
          ),
        );
      }
      if (conversation.id == secretaryConversation.id) {
        return conversation.copyWith(
          messages: List.generate(
            45,
            (index) => ChatMessage(
              id: 'msg-secretary-history-$index',
              authorName: '秘书',
              memberId: 'member-secretary',
              content: '秘书历史消息 $index\n${'私聊填充内容 ' * 12}',
              createdAt: DateTime(2026, 6, 14, 9).add(
                Duration(minutes: index),
              ),
            ),
          ),
        );
      }
      return conversation;
    }).toList(),
  );
}

Future<void> pumpStreamingFrames(
  WidgetTester tester, {
  required int count,
}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> pumpPopupMenuFrames(WidgetTester tester) async {
  for (var index = 0; index < 10; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

int conversationRowCount(WidgetTester tester) {
  return find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('conversation-row-');
      })
      .evaluate()
      .length;
}
