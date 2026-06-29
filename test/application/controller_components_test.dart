import 'package:ai_team/application/conversation_sessions.dart';
import 'package:ai_team/application/streaming_draft_registry.dart';
import 'package:ai_team/application/workspace_command_controller.dart';
import 'package:ai_team/core/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StreamingDraftRegistry', () {
    test('publishes and clears per-conversation draft listenables', () {
      final registry = StreamingDraftRegistry();
      final listenable = registry.listenable('msg-stream');

      registry.update(
        conversationId: 'conv-1',
        message: ChatMessage(
          id: 'msg-stream',
          authorName: '成员',
          content: 'draft',
          createdAt: DateTime(2026, 1, 1),
          generationStatus: ChatMessageGenerationStatus.streaming,
        ),
      );

      expect(listenable.value?.conversationId, 'conv-1');
      expect(listenable.value?.message.content, 'draft');

      registry.clearConversation('conv-1');

      expect(listenable.value, isNull);
      registry.dispose();
    });
  });

  group('ConversationSessionStore', () {
    test('keeps conversation visibility and pin ordering outside controller',
        () {
      final state = AppState.seed();
      final store = ConversationSessionStore()..sync(state);

      expect(
        store
            .visibleConversations(state,
                selectedConversationId: 'conv-team-default')
            .map((conversation) => conversation.id),
        contains('conv-team-default'),
      );
      store.activate(state, 'conv-member-frontend');
      store.togglePinned(state, 'conv-member-frontend');

      final visibleIds = store
          .visibleConversations(state,
              selectedConversationId: 'conv-member-frontend')
          .map((conversation) => conversation.id)
          .toList();

      expect(visibleIds.first, 'conv-member-frontend');
      expect(store.isPinned('conv-member-frontend'), isTrue);
    });
  });

  group('WorkspaceCommandController', () {
    test('owns command request state transitions outside AppController', () {
      var state = AppState.seed();
      final controller = WorkspaceCommandController(
        readState: () => state,
        commit: (nextState) => state = nextState,
      );

      final request = controller.requestCommand(
        memberId: 'member-frontend',
        command: 'flutter test',
        workingDirectory: '/tmp',
      );

      expect(state.commandRequests.single.id, request.id);

      controller.updateCommandRequestStatus(
        request.id,
        CommandRequestStatus.approved,
      );

      expect(
        state.commandRequests.single.status,
        CommandRequestStatus.approved,
      );
    });
  });
}
