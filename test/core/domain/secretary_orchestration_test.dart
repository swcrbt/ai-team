import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/model_gateway.dart';
import 'package:ai_team/core/orchestrator.dart';

import 'domain_test_support.dart';

void main() {
  group('secretary orchestration', () {
    test('creates visible secretary and member messages for a team task',
        () async {
      final state = AppState.seed();
      final orchestrator = TeamOrchestrator(FakeModelGateway());

      final updated = await orchestrator.dispatchTeamTask(
        state,
        teamId: 'team-default',
        userText: '实现登录页面并补测试',
      );

      final messages = updated.conversations
          .firstWhere((conversation) => conversation.id == 'conv-team-default')
          .messages;

      expect(messages.map((message) => message.authorName), contains('我'));
      expect(messages.map((message) => message.authorName), contains('秘书'));
      expect(messages.any((message) => message.authorName == '前端工程师'), isTrue);
      expect(messages.last.content, contains('汇总'));
      expect(updated.taskAssignments, hasLength(2));
      expect(
        updated.taskAssignments.map((assignment) => assignment.status),
        everyElement(TaskAssignmentStatus.completed),
      );
      expect(
        updated.taskAssignments.map((assignment) => assignment.round),
        everyElement(1),
      );
    });

    test('does not exceed the team max round limit', () async {
      final state = AppState.seed().copyWith(
        teams: [
          AppState.seed().teams.first.copyWith(maxRounds: 1),
        ],
      );
      final orchestrator = TeamOrchestrator(FakeModelGateway());

      final updated = await orchestrator.dispatchTeamTask(
        state,
        teamId: 'team-default',
        userText: '持续协作直到完成',
      );

      final conversation = updated.conversations
          .firstWhere((conversation) => conversation.id == 'conv-team-default');
      expect(conversation.currentRound, 1);
      expect(conversation.status, ConversationStatus.paused);
    });

    test('rejects member chat before gateway call when model api key is empty',
        () async {
      final state = AppState.seed().copyWith(
        models: [
          AppState.seed().models.first.copyWith(apiKey: ''),
        ],
      );
      final orchestrator = TeamOrchestrator(FakeModelGateway());

      await expectLater(
        orchestrator.dispatchMemberChat(
          state,
          conversationId: 'conv-member-secretary',
          userText: '验证模型配置',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('API Key'),
          ),
        ),
      );
    });

    test('member chat audits request body before gateway failures', () async {
      final progressStates = <AppState>[];

      await expectLater(
        TeamOrchestrator(AlwaysFailingGateway()).dispatchMemberChat(
          AppState.seed(),
          conversationId: 'conv-member-secretary',
          userText: '失败也要记录请求',
          onProgress: progressStates.add,
        ),
        throwsA(isA<ModelGatewayException>()),
      );

      final requestAuditState = progressStates.lastWhere(
        (state) => state.auditLog
            .any((entry) => entry.action == 'model_request_diagnostic'),
      );
      final requestLog = requestAuditState.auditLog.lastWhere(
        (entry) => entry.action == 'model_request_diagnostic',
      );

      expect(requestLog.detail, contains('member=member-secretary'));
      expect(requestLog.detail,
          contains('url=https://api.openai.com/v1/chat/completions'));
      expect(requestLog.detail, isNot(contains('失败也要记录请求')));
      expect(requestLog.metadata!['requestUrl'],
          'https://api.openai.com/v1/chat/completions');
      expect(requestLog.metadata!['requestBody'], isA<Map>());
      expect(jsonEncode(requestLog.metadata), contains('失败也要记录请求'));
      expect(jsonEncode(requestLog.metadata), isNot(contains('test-secret')));
      expect(jsonEncode(requestLog.metadata), isNot(contains('apiKey')));
      expect(
        jsonEncode(requestLog.metadata),
        isNot(contains('Authorization')),
      );
    });

    test('member chat persists real thinking content from metadata gateway',
        () async {
      final gateway = ScriptedMetadataGateway(
        const ModelCompletion(
          content: '正式成员回复',
          thinkingContent: '真实成员 reasoning',
          diagnostics: ModelResponseDiagnostics(
            streaming: false,
            contentLength: 6,
            thinkingContentLength: 12,
            thinkingFieldKeys: ['reasoning_content'],
            rawResponse:
                '{"choices":[{"message":{"content":"正式成员回复","reasoning_content":"真实成员 reasoning"}}]}',
            requestBody: {
              'model': 'team-model',
              'messages': [
                {'role': 'system', 'content': 'system prompt'},
                {'role': 'user', 'content': '解释实现方案'},
              ],
            },
          ),
        ),
      );

      final updated = await TeamOrchestrator(gateway).dispatchMemberChat(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '解释实现方案',
      );

      final messages = updated.conversations
          .firstWhere(
            (conversation) => conversation.id == 'conv-member-secretary',
          )
          .messages;
      expect(messages.last.content, '正式成员回复');
      expect(messages.last.thinkingContent, '真实成员 reasoning');
      final requestLog = updated.auditLog.firstWhere(
        (entry) => entry.action == 'model_request_diagnostic',
      );
      final diagnosticLog = updated.auditLog.lastWhere(
        (entry) => entry.action == 'model_response_diagnostic',
      );
      expect(updated.auditLog.indexOf(requestLog),
          lessThan(updated.auditLog.indexOf(diagnosticLog)));
      expect(requestLog.detail, contains('member=member-secretary'));
      expect(requestLog.detail, contains('model=gpt-4.1'));
      expect(requestLog.detail,
          contains('url=https://api.openai.com/v1/chat/completions'));
      expect(requestLog.detail, isNot(contains('model-main')));
      expect(requestLog.detail, contains('streaming=true'));
      expect(requestLog.detail, isNot(contains('解释实现方案')));
      expect(requestLog.metadata!['requestUrl'],
          'https://api.openai.com/v1/chat/completions');
      expect(requestLog.metadata!['requestBody'], isA<Map>());
      final requestBody =
          requestLog.metadata!['requestBody'] as Map<String, Object?>;
      expect(
        requestBody,
        containsPair('model', 'gpt-4.1'),
      );
      final requestMessages = requestBody['messages'] as List;
      expect(
        requestMessages.map((item) => (item as Map)['content']),
        isNot(contains('秘书: ')),
      );
      expect(jsonEncode(requestLog.metadata), contains('解释实现方案'));
      expect(requestLog.metadata!['model'], 'gpt-4.1');
      expect(jsonEncode(requestLog.metadata), isNot(contains('model-main')));
      expect(jsonEncode(requestLog.metadata), isNot(contains('test-secret')));
      expect(jsonEncode(requestLog.metadata), isNot(contains('apiKey')));
      expect(
        jsonEncode(requestLog.metadata),
        isNot(contains('Authorization')),
      );
      expect(diagnosticLog.detail, contains('member=member-secretary'));
      expect(diagnosticLog.detail, contains('model=gpt-4.1'));
      expect(diagnosticLog.detail,
          contains('url=https://api.openai.com/v1/chat/completions'));
      expect(diagnosticLog.detail, isNot(contains('model-main')));
      expect(diagnosticLog.detail, contains('streaming=false'));
      expect(diagnosticLog.detail,
          contains('thinkingFieldKeys=reasoning_content'));
      expect(diagnosticLog.detail, contains('thinkingChars=12'));
      expect(diagnosticLog.detail, isNot(contains('真实成员 reasoning')));
      expect(diagnosticLog.detail, isNot(contains('正式成员回复')));
      expect(diagnosticLog.metadata, isNotNull);
      expect(
        diagnosticLog.metadata!['rawResponse'],
        contains('真实成员 reasoning'),
      );
      expect(diagnosticLog.metadata!['requestBody'], isA<Map>());
      expect(
        diagnosticLog.metadata!['requestBody'],
        containsPair('model', 'team-model'),
      );
      expect(
          jsonEncode(diagnosticLog.metadata), isNot(contains('test-secret')));
      expect(jsonEncode(diagnosticLog.metadata), isNot(contains('apiKey')));
      expect(
        jsonEncode(diagnosticLog.metadata),
        isNot(contains('Authorization')),
      );
      expect(diagnosticLog.metadata!['streaming'], isFalse);
      expect(diagnosticLog.metadata!['model'], 'gpt-4.1');
      expect(diagnosticLog.metadata!['requestUrl'],
          'https://api.openai.com/v1/chat/completions');
      expect(jsonEncode(diagnosticLog.metadata), isNot(contains('model-main')));
      expect(diagnosticLog.metadata!['message'], messages.last.id);
      expect(diagnosticLog.metadata!['member'], 'member-secretary');
    });

    test('member chat streams partial thinking and content through progress',
        () async {
      final gateway = ScriptedStreamingMetadataGateway(
        deltas: const [
          ModelStreamDelta(thinkingDelta: '先分析'),
          ModelStreamDelta(contentDelta: '正式'),
          ModelStreamDelta(contentDelta: '回复'),
        ],
      );
      final progressStates = <AppState>[];

      final updated = await TeamOrchestrator(gateway).dispatchMemberChat(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '解释实现方案',
        onProgress: progressStates.add,
      );

      final streamingMessages = progressStates
          .expand((state) => state.conversations)
          .where((conversation) => conversation.id == 'conv-member-secretary')
          .expand((conversation) => conversation.messages)
          .where((message) =>
              message.memberId == 'member-secretary' &&
              message.generationStatus == ChatMessageGenerationStatus.streaming)
          .toList();
      expect(
        streamingMessages.map((message) => message.thinkingContent),
        contains('先分析'),
      );
      expect(
        streamingMessages.map((message) => message.content),
        contains('正式回复'),
      );

      final finalMessage = updated.conversations
          .firstWhere(
            (conversation) => conversation.id == 'conv-member-secretary',
          )
          .messages
          .last;
      expect(finalMessage.content, '正式回复');
      expect(finalMessage.thinkingContent, '先分析');
      expect(
          finalMessage.generationStatus, ChatMessageGenerationStatus.complete);
      expect(finalMessage.generationDurationMs, isNonZero);
    });

    test('secretary private chat dispatches mentioned member privately',
        () async {
      final gateway = ScriptedRecordingGateway(['测试结果：妈妈今年 42 岁']);

      final updated =
          await TeamOrchestrator(gateway).dispatchSecretaryPrivateMemberTask(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '分配任务给测试工程师，询问 7 年前妈妈年龄是儿子的 6 倍。',
      );

      final secretaryConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-secretary',
      );
      final testerConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-tester',
      );

      expect(
        testerConversation.messages.map((message) => message.content),
        contains(
          contains('任务分配：分配任务给测试工程师，询问 7 年前妈妈年龄是儿子的 6 倍。'),
        ),
      );
      expect(testerConversation.messages.last.authorName, '测试工程师');
      expect(testerConversation.messages.last.content, contains('妈妈今年 42 岁'));
      expect(secretaryConversation.messages.last.authorName, '秘书');
      expect(secretaryConversation.messages.last.content, contains('测试工程师'));
      expect(
          secretaryConversation.messages.last.content, contains('妈妈今年 42 岁'));
      expect(gateway.calls, hasLength(1));
      expect(gateway.calls.single.systemPrompt, contains('成员名称: 测试工程师'));

      final audit = updated.auditLog.lastWhere(
        (entry) => entry.action == 'secretary_private_member_dispatch',
      );
      expect(audit.metadata!['secretary'], 'member-secretary');
      expect(audit.metadata!['targetMember'], 'member-tester');
      expect(audit.metadata!['sourceConversation'], 'conv-member-secretary');
      expect(audit.metadata!['targetConversation'], 'conv-member-tester');
      expect(jsonEncode(audit.metadata), contains('7 年前妈妈年龄'));
      expect(
          jsonEncode(audit.metadata), isNot(contains('sk-local-placeholder')));
      expect(jsonEncode(audit.metadata), isNot(contains('apiKey')));
    });

    test('secretary private dispatch sends one user task to member model',
        () async {
      final gateway = ScriptedRecordingGateway(['测试完成']);

      final updated =
          await TeamOrchestrator(gateway).dispatchSecretaryPrivateMemberTask(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '分配任务给测试工程师，询问1+1等于多少',
      );

      final modelMessages = gateway.calls.single.messages;
      final taskMessages = modelMessages
          .where((message) => message.content.contains('任务分配：'))
          .toList();
      expect(taskMessages, hasLength(1));
      expect(modelMessages.last.isUser, isTrue);
      expect(
        modelMessages.last.content,
        '任务分配：分配任务给测试工程师，询问1+1等于多少',
      );

      final testerConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-tester',
      );
      expect(
        testerConversation.messages
            .where((message) => message.content.contains('任务分配：'))
            .length,
        1,
      );

      final requestAudit = updated.auditLog.lastWhere(
        (entry) =>
            entry.action == 'model_request_diagnostic' &&
            entry.metadata?['member'] == 'member-tester',
      );
      final requestBody =
          requestAudit.metadata!['requestBody'] as Map<String, Object?>;
      final messages = requestBody['messages'] as List<Object?>;
      final encodedTaskMessages = messages
          .where((message) => (message as Map<String, Object?>)['content']
              .toString()
              .contains('任务分配：'))
          .cast<Map<String, Object?>>()
          .toList();
      expect(encodedTaskMessages, hasLength(1));
      expect(messages.last, containsPair('role', 'user'));
    });

    test('secretary private dispatch reports waiting before member replies',
        () async {
      final gateway = BlockingRecordingGateway();
      final progressStates = <AppState>[];
      final initialConversation = AppState.seed().conversations.firstWhere(
            (conversation) => conversation.id == 'conv-member-secretary',
          );

      final future =
          TeamOrchestrator(gateway).dispatchSecretaryPrivateMemberTask(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '分配任务给测试工程师，先验算问题。',
        onProgress: progressStates.add,
      );
      await gateway.started.future.timeout(const Duration(seconds: 1));

      final waitingState = progressStates.lastWhere(
        (state) => state.conversations
            .firstWhere(
              (conversation) => conversation.id == 'conv-member-secretary',
            )
            .messages
            .any((message) => message.content.contains('等待回复')),
      );
      final secretaryConversation = waitingState.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-secretary',
      );
      final waitingMessage = secretaryConversation.messages.last;
      expect(
        secretaryConversation.messages,
        hasLength(initialConversation.messages.length + 2),
      );
      expect(waitingMessage.authorName, '秘书');
      expect(waitingMessage.content, '已分配给测试工程师，等待回复中');
      expect(
        waitingMessage.generationStatus,
        ChatMessageGenerationStatus.streaming,
      );

      gateway.finish('测试结果');
      final updated = await future;
      final completedConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-secretary',
      );
      final completedMessage = completedConversation.messages.last;
      expect(
        completedConversation.messages,
        hasLength(secretaryConversation.messages.length),
      );
      expect(completedMessage.id, waitingMessage.id);
      expect(
        completedMessage.generationStatus,
        ChatMessageGenerationStatus.complete,
      );
      expect(completedMessage.content, contains('测试结果'));
      expect(completedMessage.content, isNot(contains('等待回复中')));
    });

    test('secretary private dispatch exposes member model failures', () async {
      final updated = await TeamOrchestrator(AlwaysFailingGateway())
          .dispatchSecretaryPrivateMemberTask(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '分配任务给测试工程师，验证异常路径。',
      );

      final secretaryConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-secretary',
      );
      final testerConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-tester',
      );
      final initialSecretaryConversation =
          AppState.seed().conversations.firstWhere(
                (conversation) => conversation.id == 'conv-member-secretary',
              );
      expect(
        secretaryConversation.messages,
        hasLength(initialSecretaryConversation.messages.length + 2),
      );
      expect(
        secretaryConversation.messages.last.content,
        contains('调度失败'),
      );
      expect(
        secretaryConversation.messages
            .any((message) => message.content.contains('等待回复中')),
        isFalse,
      );
      expect(testerConversation.messages.last.content, contains('任务失败'));
      expect(
          testerConversation.messages.last.content, contains('forced failure'));

      final audit = updated.auditLog.lastWhere(
        (entry) => entry.action == 'secretary_private_member_dispatch',
      );
      expect(audit.metadata!['status'], 'failed');
      expect(audit.metadata!['targetModel'], 'qwen2.5-coder');
      expect(jsonEncode(audit.metadata), isNot(contains('model-local')));
      expect(audit.metadata!['error'], contains('forced failure'));
      expect(audit.metadata!['responseChars'], 0);
      expect(jsonEncode(audit.metadata), isNot(contains('apiKey')));
    });

    test('secretary private dispatch treats empty member replies as failure',
        () async {
      final updated = await TeamOrchestrator(ScriptedRecordingGateway(['']))
          .dispatchSecretaryPrivateMemberTask(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '分配任务给测试工程师，检查空回复。',
      );

      final secretaryConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-secretary',
      );
      final testerConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-tester',
      );
      expect(
        secretaryConversation.messages.last.content,
        contains('成员未返回内容'),
      );
      expect(testerConversation.messages.last.content, contains('成员未返回内容'));
      final audit = updated.auditLog.lastWhere(
        (entry) => entry.action == 'secretary_private_member_dispatch',
      );
      expect(audit.metadata!['status'], 'failed');
      expect(audit.metadata!['responseChars'], 0);
      expect(audit.metadata!['error'], contains('成员未返回内容'));
    });

    test('secretary private dispatch summarizes full long member replies',
        () async {
      final longReply = [
        '测试结论：1+1 等于 2。',
        '覆盖场景 A：整数加法保持交换律。',
        '覆盖场景 B：零值参与计算时结果稳定。',
        '覆盖场景 C：负数参与计算时仍遵循算术规则。',
        '覆盖场景 D：连续多次计算不会改变结果。',
        '最终建议：保留这个完整结论作为秘书私聊汇总的尾部证据。',
      ].join('\n');

      final updated = await TeamOrchestrator(ScriptedRecordingGateway([
        longReply,
      ])).dispatchSecretaryPrivateMemberTask(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '分配任务给测试工程师，验证长回复汇总。',
      );

      final secretaryConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-secretary',
      );
      final summary = secretaryConversation.messages.last.content;
      expect(summary, contains('已私聊调度成员并汇总结果：'));
      expect(summary, contains('- 测试工程师：'));
      expect(summary, contains('测试结论：1+1 等于 2。'));
      expect(summary, contains('最终建议：保留这个完整结论作为秘书私聊汇总的尾部证据。'));
      expect(summary, isNot(contains('...')));
    });

    test('secretary private dispatch summarizes multiline members separately',
        () async {
      const testerReply = '测试首行\n测试尾行：完整保留';
      const frontendReply = '前端首行\n前端尾行：完整保留';

      final updated = await TeamOrchestrator(ScriptedRecordingGateway([
        testerReply,
        frontendReply,
      ])).dispatchSecretaryPrivateMemberTask(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '请测试工程师和前端工程师分别处理这个问题。',
      );

      final secretaryConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-secretary',
      );
      final summary = secretaryConversation.messages.last.content;
      expect(summary, contains('- 测试工程师：\n  测试首行\n  测试尾行：完整保留'));
      expect(summary, contains('- 前端工程师：\n  前端首行\n  前端尾行：完整保留'));
    });

    test(
        'secretary private dispatch keeps successful summary full after failure',
        () async {
      final frontendReply = [
        '前端执行结果首行。',
        '中间说明：这里包含足够长的内容用于确认不会被截断。',
        '尾部证据：失败成员不会影响成功成员完整汇总。',
      ].join('\n');
      final gateway = ScriptedOutcomeGateway([
        const ModelGatewayException('测试模型不可用'),
        frontendReply,
      ]);

      final updated =
          await TeamOrchestrator(gateway).dispatchSecretaryPrivateMemberTask(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '请测试工程师和前端工程师分别处理这个问题。',
      );

      final secretaryConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-secretary',
      );
      final summary = secretaryConversation.messages.last.content;
      expect(summary, contains('- 测试工程师：调度失败：测试模型不可用'));
      expect(summary, contains('前端执行结果首行。'));
      expect(summary, contains('尾部证据：失败成员不会影响成功成员完整汇总。'));
      expect(summary, isNot(contains('...')));
    });

    test(
        'secretary private dispatch keeps response diagnostics for empty reply',
        () async {
      final updated = await TeamOrchestrator(
        ScriptedMetadataGateway(
          const ModelCompletion(
            content: '',
            diagnostics: ModelResponseDiagnostics(
              streaming: true,
              contentLength: 0,
              thinkingContentLength: 0,
              contentDeltaCount: 1,
              rawResponse: 'data: {"choices":[{"delta":{"content":""}}]}\n\n'
                  'data: [DONE]\n',
              requestBody: {'model': 'test-model'},
            ),
          ),
        ),
      ).dispatchSecretaryPrivateMemberTask(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '分配任务给测试工程师，检查空回复。',
      );

      final responseAudit = updated.auditLog.lastWhere(
        (entry) =>
            entry.action == 'model_response_diagnostic' &&
            entry.metadata?['member'] == 'member-tester',
      );
      expect(responseAudit.metadata!['contentChars'], 0);
      expect(
        responseAudit.metadata!['rawResponse'],
        contains('data: [DONE]'),
      );
      expect(responseAudit.metadata!['requestBody'],
          containsPair('model', 'test-model'));

      final dispatchAudit = updated.auditLog.lastWhere(
        (entry) => entry.action == 'secretary_private_member_dispatch',
      );
      expect(dispatchAudit.metadata!['status'], 'failed');
      expect(dispatchAudit.metadata!['error'], contains('成员未返回内容'));
    });

    test('secretary private dispatch handles multiple mentioned members',
        () async {
      final gateway = ScriptedRecordingGateway(['测试结果', '前端结果']);

      final updated =
          await TeamOrchestrator(gateway).dispatchSecretaryPrivateMemberTask(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '请测试工程师和前端工程师分别处理这个问题。',
      );

      final testerConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-tester',
      );
      final frontendConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-frontend',
      );
      final secretaryConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-secretary',
      );
      final initialSecretaryConversation =
          AppState.seed().conversations.firstWhere(
                (conversation) => conversation.id == 'conv-member-secretary',
              );

      expect(testerConversation.messages.last.content, '测试结果');
      expect(frontendConversation.messages.last.content, '前端结果');
      expect(
        secretaryConversation.messages,
        hasLength(initialSecretaryConversation.messages.length + 2),
      );
      expect(
        secretaryConversation.messages
            .any((message) => message.content.contains('等待回复中')),
        isFalse,
      );
      expect(
        gateway.calls.map((call) => call.systemPrompt).join('\n'),
        contains('成员名称: 测试工程师'),
      );
      expect(
        gateway.calls.map((call) => call.systemPrompt).join('\n'),
        contains('成员名称: 前端工程师'),
      );
      expect(
        updated.auditLog
            .where(
              (entry) => entry.action == 'secretary_private_member_dispatch',
            )
            .map((entry) => entry.metadata!['targetMember']),
        ['member-tester', 'member-frontend'],
      );
    });

    test('secretary private dispatch continues when one member fails',
        () async {
      final gateway = ScriptedOutcomeGateway([
        const ModelGatewayException('测试模型不可用'),
        '前端完成',
      ]);

      final updated =
          await TeamOrchestrator(gateway).dispatchSecretaryPrivateMemberTask(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '请测试工程师和前端工程师分别处理这个问题。',
      );

      final secretaryConversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-secretary',
      );
      final initialSecretaryConversation =
          AppState.seed().conversations.firstWhere(
                (conversation) => conversation.id == 'conv-member-secretary',
              );
      expect(
        secretaryConversation.messages,
        hasLength(initialSecretaryConversation.messages.length + 2),
      );
      expect(secretaryConversation.messages.last.content, contains('测试模型不可用'));
      expect(secretaryConversation.messages.last.content, contains('前端完成'));
      expect(
        secretaryConversation.messages
            .any((message) => message.content.contains('等待回复中')),
        isFalse,
      );
      expect(
        updated.auditLog
            .where(
              (entry) => entry.action == 'secretary_private_member_dispatch',
            )
            .map((entry) => entry.metadata!['status']),
        ['failed', 'completed'],
      );
    });

    test(
        'serial team mode runs assignments in secretary order with incremental summaries',
        () async {
      final gateway = ScriptedRecordingGateway([
        '前端工程师: 实现界面\n测试工程师: 编写测试',
        '前端结果',
        '阶段汇总：前端完成',
        '测试结果',
        '阶段汇总：测试完成',
        '最终汇总：全部完成',
      ]);

      final updated = await TeamOrchestrator(gateway).dispatchTeamTask(
        AppState.seed(),
        teamId: 'team-default',
        userText: '实现登录',
      );

      expect(
        gateway.calls.map((call) => call.systemPrompt).join('\n'),
        contains('秘书'),
      );
      expect(
        updated.conversations
            .firstWhere(
              (conversation) => conversation.id == 'conv-team-default',
            )
            .messages
            .map((message) => message.content),
        contains('最终汇总：全部完成'),
      );
    });

    test(
        'parallel team mode does not pass same-round sibling outputs to workers',
        () async {
      final seed = AppState.seed().copyWith(
        teams: [
          AppState.seed().teams.first.copyWith(
                collaborationMode: TeamCollaborationMode.parallel,
              ),
        ],
      );
      final gateway = ScriptedRecordingGateway([
        '前端工程师: 实现界面\n测试工程师: 编写测试',
        '前端结果',
        '测试结果',
        '最终汇总：全部完成',
      ]);

      await TeamOrchestrator(gateway).dispatchTeamTask(
        seed,
        teamId: 'team-default',
        userText: '实现登录',
      );

      expect(
        gateway.calls[2].messages.map((message) => message.content).join('\n'),
        isNot(contains('前端结果')),
      );
    });

    test(
        'member failure retries once then reassigns to same-role priority member',
        () async {
      final state = AppState.seed().copyWith(
        members: [
          ...AppState.seed().members,
          const TeamMember(
            id: 'member-frontend-backup',
            name: '前端工程师 B',
            roleId: 'role-frontend',
            modelId: 'model-main',
            executionPriority: 10,
          ),
        ],
        teams: [
          AppState.seed().teams.first.copyWith(memberIds: [
            'member-secretary',
            'member-frontend',
            'member-frontend-backup',
            'member-tester',
          ]),
        ],
      );
      final gateway = FailsThenSucceedsRecordingGateway();

      final updated = await TeamOrchestrator(gateway).dispatchTeamTask(
        state,
        teamId: 'team-default',
        userText: '实现登录',
      );

      expect(gateway.memberNames, contains('前端工程师 B'));
      expect(
        updated.conversations
            .firstWhere(
              (conversation) => conversation.id == 'conv-team-default',
            )
            .messages
            .map((message) => message.content)
            .join('\n'),
        contains('转派'),
      );
    });
  });
}
