import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ai_team/app.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/model_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('scroll position e2e', () {
    testWidgets('group to member private keeps group position', (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, 'conv-team-default');
      await trace.capture(tester, 'selected group chat');

      final groupController = _messageListController(tester);
      await tester.drag(_messageListFinder, const Offset(0, -900));
      await tester.pumpAndSettle();
      final groupOffsetBeforeLeave = groupController.offset;
      expect(groupOffsetBeforeLeave, greaterThan(0), reason: trace.dump());
      await trace.capture(tester, 'group scrolled before leaving');

      await tester.tap(find.byTooltip('成员'));
      await tester.pumpAndSettle();
      expect(_messageListFinder, findsNothing, reason: trace.dump());
      await trace.capture(tester, 'members page opened');

      await tester.tap(find.widgetWithText(FilledButton, '发起聊天').at(1));
      await tester.pumpAndSettle();
      await trace.capture(tester, 'frontend private opened from members page');

      await _selectConversation(tester, 'conv-team-default');
      await trace.capture(tester, 'group restored after private open');

      expect(
        _messageListController(tester).offset,
        closeTo(groupOffsetBeforeLeave, 1),
        reason: trace.dump(),
      );
    });

    testWidgets('group to private restores existing private position',
        (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, 'conv-member-secretary');
      await tester.drag(_messageListFinder, const Offset(0, -1100));
      await tester.pumpAndSettle();
      final privateOffsetBeforeLeave = _messageListController(tester).offset;
      expect(privateOffsetBeforeLeave, greaterThan(0), reason: trace.dump());
      await trace.capture(tester, 'private scrolled before group switch');

      await _selectConversation(tester, 'conv-team-default');
      await tester.drag(_messageListFinder, const Offset(0, -700));
      await tester.pumpAndSettle();
      await trace.capture(tester, 'group scrolled after private');

      await tester.tap(
        find.byKey(const ValueKey('conversation-row-conv-member-secretary')),
      );
      await tester.pump();
      await trace.capture(tester, 'private restore first frame');
      await tester.pumpAndSettle();
      await trace.capture(tester, 'private restore settled');

      final storedPrivateOffset =
          _appController(tester).messageScrollOffsetForConversation(
        'conv-member-secretary',
      );
      expect(
        storedPrivateOffset,
        isNot(anyOf(isNull, closeTo(0, 1))),
        reason: trace.dump(),
      );
      expect(
        _messageListController(tester).offset,
        closeTo(privateOffsetBeforeLeave, 1),
        reason: trace.dump(),
      );
    });

    testWidgets('sidebar direct switching preserves both positions',
        (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, 'conv-team-default');
      await tester.drag(_messageListFinder, const Offset(0, -700));
      await tester.pumpAndSettle();
      final groupOffset = _messageListController(tester).offset;
      expect(groupOffset, greaterThan(0), reason: trace.dump());
      await trace.capture(tester, 'group scrolled');

      await _selectConversation(tester, 'conv-member-secretary');
      await tester.drag(_messageListFinder, const Offset(0, -1100));
      await tester.pumpAndSettle();
      final privateOffset = _messageListController(tester).offset;
      expect(privateOffset, greaterThan(groupOffset), reason: trace.dump());
      await trace.capture(tester, 'private scrolled');

      for (var index = 0; index < 2; index++) {
        await _selectConversation(tester, 'conv-team-default');
        await trace.capture(tester, 'group restored pass $index');
        expect(
          _messageListController(tester).offset,
          closeTo(groupOffset, 1),
          reason: trace.dump(),
        );

        await _selectConversation(tester, 'conv-member-secretary');
        await trace.capture(tester, 'private restored pass $index');
        expect(
          _messageListController(tester).offset,
          closeTo(privateOffset, 1),
          reason: trace.dump(),
        );
      }
    });
  });
}

Finder get _messageListFinder =>
    find.byKey(const ValueKey('chat-message-list'));

Future<void> _pumpE2eApp(WidgetTester tester) async {
  await tester.pumpWidget(
    AiTeamApp(
      initialState: _stateWithLongTeamAndSecretaryChats(),
      modelGateway: _NoopModelGateway(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectConversation(
  WidgetTester tester,
  String conversationId,
) async {
  await tester.tap(find.byKey(ValueKey('conversation-row-$conversationId')));
  await tester.pumpAndSettle();
}

ScrollController _messageListController(WidgetTester tester) {
  return tester.widget<ListView>(_messageListFinder).controller!;
}

AppController _appController(WidgetTester tester) {
  final homeState = tester.state<State>(find.byType(AiTeamHome));
  return (homeState as dynamic).controller as AppController;
}

class _ScrollTrace {
  final _entries = <String>[];

  Future<void> capture(WidgetTester tester, String label) async {
    final controller = _appController(tester);
    final conversationId = controller.selectedConversationId;
    final stored =
        controller.messageScrollOffsetForConversation(conversationId);
    if (_messageListFinder.evaluate().isEmpty) {
      _entries.add(
        '$label | conversation=$conversationId | list=absent | stored=$stored',
      );
      return;
    }
    final scrollController = _messageListController(tester);
    final hasClients = scrollController.hasClients;
    _entries.add(
      '$label | conversation=$conversationId | '
      'hasClients=$hasClients | '
      'offset=${hasClients ? scrollController.offset : 'none'} | '
      'max=${hasClients ? scrollController.position.maxScrollExtent : 'none'} | '
      'stored=$stored',
    );
  }

  String dump() => _entries.join('\n');
}

AppState _stateWithLongTeamAndSecretaryChats() {
  final seed = AppState.seed();
  return seed.copyWith(
    conversations: seed.conversations.map((conversation) {
      if (conversation.id == 'conv-team-default') {
        return conversation.copyWith(
          messages: List.generate(
            45,
            (index) => ChatMessage(
              id: 'e2e-team-history-$index',
              authorName: index.isEven ? '秘书' : '前端工程师',
              memberId: index.isEven ? 'member-secretary' : 'member-frontend',
              content: 'E2E 群聊历史消息 $index\n${'团队填充内容 ' * 12}',
              createdAt: DateTime(2026, 6, 20, 8).add(
                Duration(minutes: index),
              ),
            ),
          ),
        );
      }
      if (conversation.id == 'conv-member-secretary') {
        return conversation.copyWith(
          messages: List.generate(
            45,
            (index) => ChatMessage(
              id: 'e2e-secretary-history-$index',
              authorName: '秘书',
              memberId: 'member-secretary',
              content: 'E2E 秘书私聊历史消息 $index\n${'私聊填充内容 ' * 12}',
              createdAt: DateTime(2026, 6, 20, 9).add(
                Duration(minutes: index),
              ),
            ),
          ),
        );
      }
      if (conversation.id == 'conv-member-frontend') {
        return conversation.copyWith(
          messages: List.generate(
            45,
            (index) => ChatMessage(
              id: 'e2e-frontend-history-$index',
              authorName: '前端工程师',
              memberId: 'member-frontend',
              content: 'E2E 前端私聊历史消息 $index\n${'前端填充内容 ' * 12}',
              createdAt: DateTime(2026, 6, 20, 10).add(
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

class _NoopModelGateway implements ModelGateway {
  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    return 'noop';
  }
}
