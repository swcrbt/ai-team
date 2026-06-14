import 'domain.dart';
import 'model_gateway.dart';

class TeamOrchestrator {
  TeamOrchestrator(this.gateway);

  final ModelGateway gateway;

  Future<AppState> dispatchTeamTask(
    AppState state, {
    required String teamId,
    required String userText,
    ModelRequestCancellation? cancellation,
    void Function(AppState state)? onProgress,
  }) async {
    final team = state.teams.firstWhere((item) => item.id == teamId);
    final conversation =
        state.conversations.firstWhere((item) => item.teamId == teamId);
    final secretary =
        state.members.firstWhere((item) => item.id == team.secretaryMemberId);
    final workerMembers = state.members
        .where((member) =>
            team.memberIds.contains(member.id) && member.id != secretary.id)
        .toList();
    final now = DateTime.now();
    final messages = [
      ...conversation.messages,
      ChatMessage(
        id: _id('msg'),
        authorName: '我',
        content: userText,
        createdAt: now,
        isUser: true,
      ),
      ChatMessage(
        id: _id('msg'),
        authorName: secretary.name,
        memberId: secretary.id,
        content:
            '我会把任务拆给 ${workerMembers.map((member) => member.name).join('、')}，并在团队会话中汇总。',
        createdAt: now.add(const Duration(milliseconds: 1)),
      ),
    ];
    var workingState = _replaceConversation(
      state,
      conversation.copyWith(
        messages: messages,
        status: ConversationStatus.running,
      ),
    );
    onProgress?.call(workingState);

    final round = conversation.currentRound + 1;
    for (final member in workerMembers) {
      cancellation?.throwIfCancelled();
      final role = state.roles.firstWhere((item) => item.id == member.roleId);
      final model =
          state.models.firstWhere((item) => item.id == member.modelId);
      final content = await gateway.complete(
        model: model,
        systemPrompt: role.renderSystemPrompt(
          memberName: member.name,
          teamName: team.name,
        ),
        messages: messages,
        cancellation: cancellation,
      );
      cancellation?.throwIfCancelled();
      messages.add(ChatMessage(
        id: _id('msg'),
        authorName: member.name,
        memberId: member.id,
        content: content,
        createdAt: DateTime.now(),
      ));
      workingState = _replaceConversation(
        workingState,
        conversation.copyWith(
          messages: messages,
          status: ConversationStatus.running,
        ),
      );
      onProgress?.call(workingState);
    }

    cancellation?.throwIfCancelled();
    messages.add(ChatMessage(
      id: _id('msg'),
      authorName: secretary.name,
      memberId: secretary.id,
      content: '汇总：已完成第 $round 轮协作，成员给出了实现与验证建议。需要修改本地项目时会先生成补丁等待确认。',
      createdAt: DateTime.now(),
    ));

    final nextStatus = round >= team.maxRounds
        ? ConversationStatus.paused
        : ConversationStatus.idle;
    final updatedConversation = conversation.copyWith(
      messages: messages,
      currentRound: round,
      status: nextStatus,
    );
    return _replaceConversation(
      workingState,
      updatedConversation,
    ).copyWith(
      auditLog: [
        ...workingState.auditLog,
        AuditEntry(
          id: _id('audit'),
          action: 'team_task_dispatched',
          detail: 'team=$teamId round=$round text=$userText',
          createdAt: DateTime.now(),
        ),
      ],
    );
  }
}

AppState _replaceConversation(AppState state, Conversation conversation) {
  return state.copyWith(
    conversations: state.conversations
        .map((item) => item.id == conversation.id ? conversation : item)
        .toList(),
  );
}

class FakeModelGateway implements ModelGateway {
  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final latestUser = messages.lastWhere((message) => message.isUser).content;
    if (systemPrompt.contains('测试工程师')) {
      return '测试工程师：为“$latestUser”补充单元测试、Widget 测试和回归验收。';
    }
    return '前端工程师：为“$latestUser”实现 Flutter 桌面界面、状态流和补丁提案。';
  }
}

String _id(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';
