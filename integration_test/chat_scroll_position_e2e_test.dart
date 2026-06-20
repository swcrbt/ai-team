import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ai_team/app.dart';
import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/model_gateway.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('scroll position e2e', () {
    testWidgets('member private to group to same private restores position',
        (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, _frontendConversationId);
      final frontendOffset = await _dragMessagesAndCaptureOffset(
        tester,
        trace,
        'frontend private scrolled before group switch',
        const Offset(0, -950),
      );

      await _selectConversation(tester, _groupConversationId);
      await tester.pump();
      await trace.capture(tester, 'group restore first frame');
      await tester.pumpAndSettle();
      await trace.capture(tester, 'group restore settled');

      await tester.tap(
        find.byKey(const ValueKey('conversation-row-$_frontendConversationId')),
      );
      await tester.pump();
      await trace.capture(tester, 'frontend private restore first frame');
      await tester.pump();
      await trace.capture(tester, 'frontend private restore second frame');
      await tester.pumpAndSettle();
      await trace.capture(tester, 'frontend private restore settled');

      _expectOffsetRestored(
        tester,
        frontendOffset,
        trace,
        label: 'frontend private',
      );
    });

    testWidgets('group to member private keeps group position', (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, _groupConversationId);
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

      await _selectConversation(tester, _groupConversationId);
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

      await _selectConversation(tester, _secretaryConversationId);
      await tester.drag(_messageListFinder, const Offset(0, -1100));
      await tester.pumpAndSettle();
      final privateOffsetBeforeLeave = _messageListController(tester).offset;
      expect(privateOffsetBeforeLeave, greaterThan(0), reason: trace.dump());
      await trace.capture(tester, 'private scrolled before group switch');

      await _selectConversation(tester, _groupConversationId);
      await tester.drag(_messageListFinder, const Offset(0, -700));
      await tester.pumpAndSettle();
      await trace.capture(tester, 'group scrolled after private');

      await tester.tap(
        find.byKey(
            const ValueKey('conversation-row-$_secretaryConversationId')),
      );
      await tester.pump();
      await trace.capture(tester, 'private restore first frame');
      await tester.pumpAndSettle();
      await trace.capture(tester, 'private restore settled');

      final storedPrivateOffset =
          _appController(tester).messageScrollOffsetForConversation(
        _secretaryConversationId,
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

      await _selectConversation(tester, _groupConversationId);
      await tester.drag(_messageListFinder, const Offset(0, -700));
      await tester.pumpAndSettle();
      final groupOffset = _messageListController(tester).offset;
      expect(groupOffset, greaterThan(0), reason: trace.dump());
      await trace.capture(tester, 'group scrolled');

      await _selectConversation(tester, _secretaryConversationId);
      await tester.drag(_messageListFinder, const Offset(0, -1100));
      await tester.pumpAndSettle();
      final privateOffset = _messageListController(tester).offset;
      expect(privateOffset, greaterThan(groupOffset), reason: trace.dump());
      await trace.capture(tester, 'private scrolled');

      for (var index = 0; index < 2; index++) {
        await _selectConversation(tester, _groupConversationId);
        await trace.capture(tester, 'group restored pass $index');
        expect(
          _messageListController(tester).offset,
          closeTo(groupOffset, 1),
          reason: trace.dump(),
        );

        await _selectConversation(tester, _secretaryConversationId);
        await trace.capture(tester, 'private restored pass $index');
        expect(
          _messageListController(tester).offset,
          closeTo(privateOffset, 1),
          reason: trace.dump(),
        );
      }
    });

    testWidgets('sidebar direct switching preserves two member private chats',
        (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, _frontendConversationId);
      final frontendOffset = await _dragMessagesAndCaptureOffset(
        tester,
        trace,
        'frontend private scrolled',
        const Offset(0, -850),
      );

      await _selectConversation(tester, _testerConversationId);
      final testerOffset = await _dragMessagesAndCaptureOffset(
        tester,
        trace,
        'tester private scrolled',
        const Offset(0, -1250),
      );
      expect(testerOffset, isNot(closeTo(frontendOffset, 1)),
          reason: trace.dump());

      await _selectConversation(tester, _frontendConversationId);
      await trace.capture(tester, 'frontend private restored from tester');
      _expectOffsetRestored(
        tester,
        frontendOffset,
        trace,
        label: 'frontend private',
      );

      await _selectConversation(tester, _testerConversationId);
      await trace.capture(tester, 'tester private restored from frontend');
      _expectOffsetRestored(
        tester,
        testerOffset,
        trace,
        label: 'tester private',
      );
    });

    testWidgets(
        'group secretary and member positions survive repeated switches',
        (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, _groupConversationId);
      final groupOffset = await _dragMessagesAndCaptureOffset(
        tester,
        trace,
        'group scrolled before repeated switches',
        const Offset(0, -650),
      );

      await _selectConversation(tester, _secretaryConversationId);
      final secretaryOffset = await _dragMessagesAndCaptureOffset(
        tester,
        trace,
        'secretary scrolled before repeated switches',
        const Offset(0, -950),
      );

      await _selectConversation(tester, _frontendConversationId);
      final frontendOffset = await _dragMessagesAndCaptureOffset(
        tester,
        trace,
        'frontend scrolled before repeated switches',
        const Offset(0, -1250),
      );

      for (var index = 0; index < 2; index++) {
        await _selectConversation(tester, _groupConversationId);
        await trace.capture(tester, 'group repeated restore $index');
        _expectOffsetRestored(tester, groupOffset, trace, label: 'group');

        await _selectConversation(tester, _secretaryConversationId);
        await trace.capture(tester, 'secretary repeated restore $index');
        _expectOffsetRestored(
          tester,
          secretaryOffset,
          trace,
          label: 'secretary',
        );

        await _selectConversation(tester, _frontendConversationId);
        await trace.capture(tester, 'frontend repeated restore $index');
        _expectOffsetRestored(
          tester,
          frontendOffset,
          trace,
          label: 'frontend',
        );
      }
    });

    testWidgets('member private survives leaving chat for members page',
        (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, _frontendConversationId);
      final frontendOffset = await _dragMessagesAndCaptureOffset(
        tester,
        trace,
        'frontend private scrolled before members page',
        const Offset(0, -950),
      );

      await _openSidebarPage(tester, '成员');
      expect(_messageListFinder, findsNothing, reason: trace.dump());
      await trace.capture(tester, 'members page after frontend private');

      await _openSidebarPage(tester, '消息');
      await trace.capture(tester, 'frontend private after returning to chat');
      _expectOffsetRestored(
        tester,
        frontendOffset,
        trace,
        label: 'frontend private',
      );
    });

    testWidgets(
        'member private survives members page opening another member private',
        (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, _frontendConversationId);
      final frontendOffset = await _dragMessagesAndCaptureOffset(
        tester,
        trace,
        'frontend private scrolled before opening tester',
        const Offset(0, -950),
      );

      await _openSidebarPage(tester, '成员');
      await tester.tap(find.widgetWithText(FilledButton, '发起聊天').at(2));
      await tester.pumpAndSettle();
      await trace.capture(tester, 'tester private opened from members page');

      await _selectConversation(tester, _frontendConversationId);
      await trace.capture(tester, 'frontend private restored after tester');
      _expectOffsetRestored(
        tester,
        frontendOffset,
        trace,
        label: 'frontend private',
      );
    });

    testWidgets('member private survives settings page rebuild',
        (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, _frontendConversationId);
      final frontendOffset = await _dragMessagesAndCaptureOffset(
        tester,
        trace,
        'frontend private scrolled before settings',
        const Offset(0, -1050),
      );

      await _openSidebarPage(tester, '设置');
      expect(_messageListFinder, findsNothing, reason: trace.dump());
      await trace.capture(tester, 'settings page after frontend private');

      await _openSidebarPage(tester, '消息');
      await trace.capture(tester, 'frontend private after settings');
      _expectOffsetRestored(
        tester,
        frontendOffset,
        trace,
        label: 'frontend private',
      );
    });

    testWidgets('private position survives group message activity',
        (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, _frontendConversationId);
      final frontendOffset = await _dragMessagesAndCaptureOffset(
        tester,
        trace,
        'frontend private scrolled before group activity',
        const Offset(0, -950),
      );

      await _selectConversation(tester, _groupConversationId);
      await tester.enterText(find.byType(TextField).last, 'E2E 群聊新增消息');
      await tester.tap(find.byTooltip('发送'));
      await tester.pumpAndSettle();
      await trace.capture(tester, 'group after message activity');

      await _selectConversation(tester, _frontendConversationId);
      await trace.capture(tester, 'frontend private after group activity');
      _expectOffsetRestored(
        tester,
        frontendOffset,
        trace,
        label: 'frontend private',
      );
    });

    testWidgets('bottom and history positions restore without changing intent',
        (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, _frontendConversationId);
      await tester.drag(_messageListFinder, const Offset(0, -10000));
      await tester.pumpAndSettle();
      final bottomOffset = _messageListController(tester).offset;
      final bottomMax = _messageListController(tester).position.maxScrollExtent;
      expect(bottomOffset, closeTo(bottomMax, 1), reason: trace.dump());
      await trace.capture(tester, 'frontend private pinned at bottom');

      await _selectConversation(tester, _groupConversationId);
      final groupHistoryOffset = await _dragMessagesAndCaptureOffset(
        tester,
        trace,
        'group scrolled to history',
        const Offset(0, -650),
      );

      await _selectConversation(tester, _frontendConversationId);
      await trace.capture(tester, 'frontend private bottom restored');
      final restoredBottomController = _messageListController(tester);
      expect(
        restoredBottomController.offset,
        closeTo(restoredBottomController.position.maxScrollExtent, 1),
        reason: 'frontend private did not remain at bottom\n${trace.dump()}',
      );
      expect(bottomOffset, greaterThan(0), reason: trace.dump());

      await _selectConversation(tester, _groupConversationId);
      await trace.capture(
          tester, 'group history restored after bottom private');
      _expectOffsetRestored(
        tester,
        groupHistoryOffset,
        trace,
        label: 'group history',
      );
    });

    testWidgets('secretary private bottom scroll follows content growth while away',
        (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, _secretaryConversationId);
      await tester.drag(_messageListFinder, const Offset(0, -10000));
      await tester.pumpAndSettle();
      await trace.capture(tester, 'secretary private initially at bottom');
      final initialController = _messageListController(tester);
      expect(
        initialController.offset,
        closeTo(initialController.position.maxScrollExtent, 1),
        reason: trace.dump(),
      );
      final savedBottomMax =
          _messageListController(tester).position.maxScrollExtent;

      await tester.tap(
        find.byKey(const ValueKey('conversation-row-$_groupConversationId')),
      );
      await tester.pumpAndSettle();
      await trace.capture(tester, 'group selected before secretary grows');

      final appController = _appController(tester);
      final currentState = appController.state;
      appController.state = currentState.copyWith(
        conversations: currentState.conversations.map((conversation) {
          if (conversation.id != _secretaryConversationId) {
            return conversation;
          }
          return conversation.copyWith(
            messages: [
              ...conversation.messages,
              ChatMessage(
                id: 'e2e-secretary-grown-while-away',
                authorName: '秘书',
                memberId: 'member-secretary',
                content: 'E2E 离开期间新增的秘书长回复\n${'长内容 ' * 240}',
                createdAt: DateTime(2026, 6, 20, 12),
              ),
            ],
          );
        }).toList(),
      );
      (appController as dynamic).notifyListeners();
      await tester.pumpAndSettle();
      await trace.capture(tester, 'group after secretary growth completed');

      await _selectConversation(tester, _secretaryConversationId);
      await trace.capture(tester, 'secretary private restored after growth');
      final restoredController = _messageListController(tester);
      expect(
        restoredController.position.maxScrollExtent,
        greaterThan(savedBottomMax + 1),
        reason: trace.dump(),
      );
      expect(
        restoredController.offset,
        closeTo(restoredController.position.maxScrollExtent, 1),
        reason: 'secretary private did not restore to current bottom\n'
            '${trace.dump()}',
      );
    });

    testWidgets('streaming private manual history survives group switch',
        (tester) async {
      final trace = _ScrollTrace();
      final gateway = _ScriptedStreamingGateway(
        deltas: List.generate(
          8,
          (index) => ModelStreamDelta(
            contentDelta: '私聊流式片段 $index ${'内容 ' * 8}\n',
          ),
        ),
        pauseAfterDeltaIndex: 1,
      );
      await _pumpE2eApp(tester, modelGateway: gateway);

      await _selectConversation(tester, _frontendConversationId);
      await tester.drag(_messageListFinder, const Offset(0, -10000));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'E2E 私聊流式切换');
      await tester.tap(find.byTooltip('发送'));
      await gateway.paused.future.timeout(const Duration(seconds: 2));
      await tester.pump();
      await tester.drag(_messageListFinder, const Offset(0, 900));
      await tester.pump();
      final manualOffset = _messageListController(tester).offset;
      expect(
        manualOffset,
        lessThan(_messageListController(tester).position.maxScrollExtent - 96),
        reason: trace.dump(),
      );
      await trace.capture(tester, 'frontend streaming manual history');

      await _selectConversation(tester, _groupConversationId);
      await trace.capture(tester, 'group during frontend streaming');

      gateway.resume();
      await gateway.completed.future.timeout(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await trace.capture(tester, 'group after frontend streaming completes');

      await _selectConversation(tester, _frontendConversationId);
      await trace.capture(tester, 'frontend after streaming group switch');
      _expectOffsetRestored(
        tester,
        manualOffset,
        trace,
        label: 'frontend streaming manual history',
      );
    });

    testWidgets('back to bottom settle frames do not pollute another chat',
        (tester) async {
      final trace = _ScrollTrace();
      await _pumpE2eApp(tester);

      await _selectConversation(tester, _frontendConversationId);
      await tester.drag(_messageListFinder, const Offset(0, -10000));
      await tester.pumpAndSettle();
      await tester.drag(_messageListFinder, const Offset(0, 900));
      await tester.pump();
      expect(find.byTooltip('回到底部'), findsOneWidget, reason: trace.dump());
      await trace.capture(tester, 'frontend before back to bottom');

      await tester.tap(find.byTooltip('回到底部'));
      await tester.pump();
      final frontendBottomOffset = _messageListController(tester).offset;
      await trace.capture(tester, 'frontend immediately after back to bottom');

      await tester.tap(
        find.byKey(const ValueKey('conversation-row-$_testerConversationId')),
      );
      await tester.pump();
      await trace.capture(tester, 'tester first frame after pending settle');
      await tester.pumpAndSettle();
      await trace.capture(tester, 'tester settled after pending settle');

      await _selectConversation(tester, _frontendConversationId);
      await trace.capture(tester, 'frontend restored after pending settle');
      _expectOffsetRestored(
        tester,
        frontendBottomOffset,
        trace,
        label: 'frontend after back to bottom',
      );
    });
  });
}

const _groupConversationId = 'conv-team-default';
const _secretaryConversationId = 'conv-member-secretary';
const _frontendConversationId = 'conv-member-frontend';
const _testerConversationId = 'conv-member-tester';
const _diagnosticConversationIds = [
  _groupConversationId,
  _secretaryConversationId,
  _frontendConversationId,
  _testerConversationId,
];

Finder get _messageListFinder =>
    find.byKey(const ValueKey('chat-message-list'));

Future<void> _pumpE2eApp(
  WidgetTester tester, {
  ModelGateway? modelGateway,
}) async {
  await tester.pumpWidget(
    AiTeamApp(
      initialState: _stateWithLongTeamAndSecretaryChats(),
      modelGateway: modelGateway ?? _NoopModelGateway(),
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

Future<void> _openSidebarPage(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

Future<double> _dragMessagesAndCaptureOffset(
  WidgetTester tester,
  _ScrollTrace trace,
  String label,
  Offset dragOffset,
) async {
  await tester.drag(_messageListFinder, dragOffset);
  await tester.pumpAndSettle();
  final offset = _messageListController(tester).offset;
  expect(offset, greaterThan(0), reason: trace.dump());
  await trace.capture(tester, label);
  return offset;
}

void _expectOffsetRestored(
  WidgetTester tester,
  double expectedOffset,
  _ScrollTrace trace, {
  required String label,
}) {
  expect(
    _messageListController(tester).offset,
    closeTo(expectedOffset, 1),
    reason: '$label did not restore\n${trace.dump()}',
  );
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
    final visibleRows =
        controller.visibleConversations.map((item) => item.id).join(',');
    final storedOffsets = _diagnosticConversationIds
        .map(
          (id) => '$id=${controller.messageScrollOffsetForConversation(id)}'
              ':pinned=${controller.messageScrollPinnedToBottomForConversation(id)}',
        )
        .join(';');
    final hasBackToBottom = find.byTooltip('回到底部').evaluate().isNotEmpty;
    if (_messageListFinder.evaluate().isEmpty) {
      _entries.add(
        '$label | conversation=$conversationId | list=absent | '
        'backToBottom=$hasBackToBottom | rows=$visibleRows | '
        'stored={$storedOffsets}',
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
      'backToBottom=$hasBackToBottom | rows=$visibleRows | '
      'stored={$storedOffsets}',
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
      if (conversation.id == 'conv-member-tester') {
        return conversation.copyWith(
          messages: List.generate(
            45,
            (index) => ChatMessage(
              id: 'e2e-tester-history-$index',
              authorName: '测试工程师',
              memberId: 'member-tester',
              content: 'E2E 测试私聊历史消息 $index\n${'测试填充内容 ' * 12}',
              createdAt: DateTime(2026, 6, 20, 11).add(
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

class _ScriptedStreamingGateway implements MetadataModelGateway {
  _ScriptedStreamingGateway({
    required this.deltas,
    this.pauseAfterDeltaIndex,
  });

  final List<ModelStreamDelta> deltas;
  final int? pauseAfterDeltaIndex;
  final Completer<void> paused = Completer<void>();
  final Completer<void> completed = Completer<void>();
  final Completer<void> _resume = Completer<void>();
  static const _deltaDelay = Duration(milliseconds: 15);

  void resume() {
    if (!_resume.isCompleted) {
      _resume.complete();
    }
  }

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    final completion = await completeWithMetadata(
      model: model,
      systemPrompt: systemPrompt,
      messages: messages,
      cancellation: cancellation,
    );
    return completion.content;
  }

  @override
  Future<ModelCompletion> completeWithMetadata({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
    ModelStreamDeltaHandler? onDelta,
  }) async {
    final content = StringBuffer();
    for (var index = 0; index < deltas.length; index++) {
      cancellation?.throwIfCancelled();
      final delta = deltas[index];
      onDelta?.call(delta);
      if (delta.contentDelta != null) {
        content.write(delta.contentDelta);
      }
      if (pauseAfterDeltaIndex == index) {
        if (!paused.isCompleted) {
          paused.complete();
        }
        await _resume.future;
      }
      await Future<void>.delayed(_deltaDelay);
    }
    if (!completed.isCompleted) {
      completed.complete();
    }
    return ModelCompletion(content: content.toString());
  }
}
