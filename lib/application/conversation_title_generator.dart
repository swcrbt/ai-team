import '../core/domain.dart';
import '../core/model_gateway.dart';
import 'app_controller_helpers.dart';
import 'state_lookup.dart';

typedef ConversationTitleStateReader = AppState Function();
typedef ConversationTitleStateCommitter = void Function(AppState state);

class ConversationTitleGenerator {
  const ConversationTitleGenerator({
    required this.readState,
    required this.commit,
    required this.gateway,
  });

  final ConversationTitleStateReader readState;
  final ConversationTitleStateCommitter commit;
  final ModelGateway gateway;

  AppState get state => readState();

  bool shouldGenerateAfterFirstUserMessage(Conversation conversation) {
    return conversation.title.trim().isEmpty &&
        !conversation.messages.any((message) => message.isUser);
  }

  Future<void> generateAfterFirstUserMessage({
    required String conversationId,
    required String firstUserMessage,
  }) async {
    final conversation = conversationByIdOrThrow(state, conversationId);
    final titleMember = _titleMemberForConversation(conversation);
    final role = requireRole(state, titleMember.roleId);
    final model = requireModel(state, titleMember.modelId);
    try {
      final generated = await gateway.complete(
        model: model,
        systemPrompt: role.renderSystemPrompt(
          memberName: titleMember.name,
          teamName: requireTeam(state, conversation.teamId).name,
        ),
        messages: [
          ChatMessage(
            id: 'msg-title-source-${DateTime.now().microsecondsSinceEpoch}',
            authorName: '我',
            content: '请为这段聊天生成一个 3-8 个字的会话标题，只返回标题：$firstUserMessage',
            createdAt: DateTime.now(),
            isUser: true,
          ),
        ],
      );
      final normalizedTitle = normalizeGeneratedConversationTitle(
        generated,
        conversation: conversationByIdOrThrow(state, conversationId),
        firstUserMessage: firstUserMessage,
      );
      if (normalizedTitle == null) {
        return;
      }
      final latestConversation = conversationByIdOrThrow(state, conversationId);
      commit(
        state.copyWith(
          conversations: state.conversations
              .map(
                (item) => item.id == conversationId
                    ? latestConversation.copyWith(title: normalizedTitle)
                    : item,
              )
              .toList(),
        ),
      );
    } catch (_) {
      return;
    }
  }

  TeamMember _titleMemberForConversation(Conversation conversation) {
    if (conversation.memberId != null) {
      return requireMember(state, conversation.memberId!);
    }
    final team = requireTeam(state, conversation.teamId);
    return requireMember(state, team.secretaryMemberId);
  }
}
