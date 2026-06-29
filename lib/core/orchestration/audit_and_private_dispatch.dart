part of '../orchestrator.dart';

AppState _appendModelRequestDiagnostic(
  AppState state, {
  required String conversationId,
  required String? memberId,
  required ModelProfile model,
  required Map<String, Object?> requestBody,
}) {
  final requestUrl = openAiCompatibleChatCompletionsEndpoint(model).toString();
  final detail = [
    'conversation=$conversationId',
    if (memberId != null) 'member=$memberId',
    'model=${model.modelName}',
    'url=$requestUrl',
    'modelProfileName=${model.name}',
    'streaming=${model.streaming}',
  ].join(' ');
  final metadata = <String, Object?>{
    'conversation': conversationId,
    if (memberId != null) 'member': memberId,
    'model': model.modelName,
    'requestUrl': requestUrl,
    'modelProfileName': model.name,
    'streaming': model.streaming,
    'requestBody': requestBody,
  };
  return state.copyWith(
    auditLog: [
      ...state.auditLog,
      AuditEntry(
        id: _id('audit'),
        action: 'model_request_diagnostic',
        detail: detail,
        metadata: metadata,
        createdAt: DateTime.now(),
      ),
    ],
  );
}

AppState _appendModelResponseDiagnostic(
  AppState state, {
  required String conversationId,
  required String messageId,
  required String? memberId,
  required ModelProfile model,
  required ModelResponseDiagnostics diagnostics,
}) {
  final thinkingFieldKeys = diagnostics.thinkingFieldKeys.isEmpty
      ? 'none'
      : diagnostics.thinkingFieldKeys.join(',');
  final requestUrl = diagnostics.requestUrl ??
      openAiCompatibleChatCompletionsEndpoint(model).toString();
  final detail = [
    'conversation=$conversationId',
    'message=$messageId',
    if (memberId != null) 'member=$memberId',
    'model=${model.modelName}',
    'url=$requestUrl',
    'modelProfileName=${model.name}',
    'streaming=${diagnostics.streaming}',
    'contentChars=${diagnostics.contentLength}',
    'thinkingChars=${diagnostics.thinkingContentLength}',
    'thinkingFieldKeys=$thinkingFieldKeys',
    'contentDeltas=${diagnostics.contentDeltaCount}',
    'thinkingDeltas=${diagnostics.thinkingDeltaCount}',
    'toolCalls=${diagnostics.toolCallCount}',
  ].join(' ');
  final metadata = <String, Object?>{
    'conversation': conversationId,
    'message': messageId,
    if (memberId != null) 'member': memberId,
    'model': model.modelName,
    'requestUrl': requestUrl,
    'modelProfileName': model.name,
    'streaming': diagnostics.streaming,
    'contentChars': diagnostics.contentLength,
    'thinkingChars': diagnostics.thinkingContentLength,
    'thinkingFieldKeys': diagnostics.thinkingFieldKeys,
    'contentDeltas': diagnostics.contentDeltaCount,
    'thinkingDeltas': diagnostics.thinkingDeltaCount,
    'toolCalls': diagnostics.toolCallCount,
    if (diagnostics.rawToolCalls.isNotEmpty)
      'rawToolCalls': diagnostics.rawToolCalls,
    if (diagnostics.requestBody != null) 'requestBody': diagnostics.requestBody,
    if (diagnostics.rawResponse != null) 'rawResponse': diagnostics.rawResponse,
  };
  return state.copyWith(
    auditLog: [
      ...state.auditLog,
      AuditEntry(
        id: _id('audit'),
        action: 'model_response_diagnostic',
        detail: detail,
        metadata: metadata,
        createdAt: DateTime.now(),
      ),
    ],
  );
}

AppState _appendSecretaryPrivateDispatchAudit(
  AppState state, {
  required TeamMember secretary,
  required TeamMember target,
  required Conversation sourceConversation,
  required Conversation targetConversation,
  required String userText,
  required String status,
  required ModelProfile targetModel,
  required int responseChars,
  String? error,
}) {
  return state.copyWith(
    auditLog: [
      ...state.auditLog,
      AuditEntry(
        id: _id('audit'),
        action: 'secretary_private_member_dispatch',
        detail: 'secretary=${secretary.id} target=${target.id} status=$status',
        metadata: {
          'secretary': secretary.id,
          'targetMember': target.id,
          'sourceConversation': sourceConversation.id,
          'targetConversation': targetConversation.id,
          'text': userText,
          'status': status,
          'targetModel': targetModel.modelName,
          'targetModelProfileName': targetModel.name,
          'responseChars': responseChars,
          if (error != null) 'error': error,
        },
        createdAt: DateTime.now(),
      ),
    ],
  );
}

List<TeamMember> _mentionedDispatchMembers({
  required AppState state,
  required Team team,
  required String userText,
}) {
  final matches = <({TeamMember member, int index})>[];
  for (final member in state.members) {
    if (!team.memberIds.contains(member.id) ||
        member.id == team.secretaryMemberId) {
      continue;
    }
    final index = userText.indexOf(member.name);
    if (index >= 0) {
      matches.add((member: member, index: index));
    }
  }
  matches.sort((a, b) {
    final byIndex = a.index.compareTo(b.index);
    if (byIndex != 0) {
      return byIndex;
    }
    return team.memberIds
        .indexOf(a.member.id)
        .compareTo(team.memberIds.indexOf(b.member.id));
  });
  return matches.map((match) => match.member).toList();
}
