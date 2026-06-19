import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/local_store.dart';
import 'package:ai_team/core/model_gateway.dart';
import 'package:ai_team/core/orchestrator.dart';
import 'package:ai_team/core/patching.dart';
import 'package:ai_team/core/secret_store.dart';

void main() {
  group('queued collaboration domain', () {
    test(
        'team mode and member priority persist with backward-compatible defaults',
        () {
      final oldTeam = Team.fromJson({
        'id': 'team-old',
        'name': '旧团队',
        'memberIds': ['member-secretary'],
        'secretaryMemberId': 'member-secretary',
        'maxRounds': 8,
      });
      expect(oldTeam.collaborationMode, TeamCollaborationMode.serial);

      final member = TeamMember.fromJson({
        'id': 'member-a',
        'name': '成员 A',
        'roleId': 'role-frontend',
        'modelId': 'model-main',
        'isSecretary': false,
      });
      expect(member.executionPriority, 0);

      final restored = Team.fromJson(oldTeam
          .copyWith(
            collaborationMode: TeamCollaborationMode.parallel,
          )
          .toJson());
      expect(restored.collaborationMode, TeamCollaborationMode.parallel);
    });

    test('queued task persists priority notes status and message links', () {
      final task = QueuedTask(
        id: 'task-1',
        conversationId: 'conv-team-default',
        title: '实现登录页',
        originalText: '实现登录页并补测试',
        notes: const ['补充移动端适配', '优先检查失败态'],
        priority: 10,
        status: QueuedTaskStatus.paused,
        createdAt: DateTime(2026, 6, 14, 10),
        updatedAt: DateTime(2026, 6, 14, 11),
        messageIds: const ['msg-1', 'msg-2'],
      );

      final restored = QueuedTask.fromJson(task.toJson());

      expect(restored.title, '实现登录页');
      expect(restored.notes, ['补充移动端适配', '优先检查失败态']);
      expect(restored.priority, 10);
      expect(restored.status, QueuedTaskStatus.paused);
      expect(restored.messageIds, ['msg-1', 'msg-2']);
    });

    test('chat messages persist related task ids', () {
      final message = ChatMessage(
        id: 'msg-1',
        authorName: '系统',
        content: '已为任务追加备注',
        createdAt: DateTime(2026, 6, 14),
        taskIds: const ['task-1', 'task-2'],
      );

      final restored = ChatMessage.fromJson(message.toJson());

      expect(restored.taskIds, ['task-1', 'task-2']);
    });

    test('chat messages persist real model thinking content', () {
      final message = ChatMessage(
        id: 'msg-thinking',
        authorName: '前端工程师',
        content: '结论内容',
        thinkingContent: '真实 reasoning 字段内容',
        createdAt: DateTime(2026, 6, 15),
      );

      final restored = ChatMessage.fromJson(message.toJson());

      expect(restored.content, '结论内容');
      expect(restored.thinkingContent, '真实 reasoning 字段内容');
    });

    test('audit entries persist structured metadata', () {
      final entry = AuditEntry(
        id: 'audit-raw-response',
        action: 'model_response_diagnostic',
        detail: 'thinkingChars=0',
        metadata: const {
          'rawResponse': '{"choices":[{"message":{"content":"answer"}}]}',
          'streaming': false,
          'model': 'model-main',
        },
        createdAt: DateTime(2026, 6, 19, 10),
      );

      final restored = AuditEntry.fromJson(entry.toJson());

      expect(restored.metadata, isNotNull);
      expect(
        restored.metadata!['rawResponse'],
        '{"choices":[{"message":{"content":"answer"}}]}',
      );
      expect(restored.metadata!['streaming'], isFalse);
      expect(restored.metadata!['model'], 'model-main');
    });

    test('model profiles persist optional reasoning effort', () {
      const profile = ModelProfile(
        id: 'model-reasoning',
        name: 'Reasoning Model',
        baseUrl: 'https://api.openai.com/v1',
        modelName: 'gpt-reasoning',
        apiKey: 'secret',
        reasoningEffort: 'high',
      );

      final restored = ModelProfile.fromJson(profile.toJson());
      final legacy = ModelProfile.fromJson({
        'id': 'model-legacy',
        'name': 'Legacy',
        'baseUrl': 'https://api.openai.com/v1',
        'modelName': 'legacy-model',
        'apiKey': 'secret',
      });

      expect(restored.reasoningEffort, 'high');
      expect(restored.toJson()['reasoningEffort'], 'high');
      expect(legacy.reasoningEffort, isNull);
    });
  });

  group('configuration export', () {
    test('exports model metadata without api keys by default', () {
      final state = AppState.seed();

      final exported = ConfigExporter.exportState(state, includeSecrets: false);

      expect(exported['models'], hasLength(2));
      expect(exported['models'].first, isNot(contains('apiKey')));
      expect(exported['roles'], isNotEmpty);
      expect(exported['teams'], isNotEmpty);
    });

    test('exports api keys only when explicitly requested', () {
      final state = AppState.seed();

      final exported = ConfigExporter.exportState(state, includeSecrets: true);

      expect(exported['models'].first['apiKey'], isNotEmpty);
    });

    test('round trips workspaces, command requests, and patch proposals', () {
      final state = AppState.seed().copyWith(
        workspaces: const [
          ProjectWorkspace(
            id: 'workspace-1',
            name: 'App',
            path: '/workspace/app',
          ),
        ],
        taskAssignments: [
          TaskAssignment(
            id: 'task-1',
            conversationId: 'conv-team-default',
            round: 1,
            memberId: 'member-frontend',
            memberName: '前端工程师',
            roleName: '前端工程师',
            instruction: '实现登录页面',
            status: TaskAssignmentStatus.completed,
            createdAt: DateTime(2026, 1, 2),
            summary: '已完成界面建议',
            completedAt: DateTime(2026, 1, 2, 0, 1),
          ),
        ],
        commandRequests: [
          CommandRequest.pending(
            id: 'command-1',
            memberName: '测试工程师',
            command: 'flutter test',
            workingDirectory: '/workspace/app',
            decision: CommandDecision.requiresConfirmation,
          ),
        ],
        patchProposals: const [
          PatchProposal(
            id: 'patch-1',
            filePath: '/workspace/app/lib/main.dart',
            originalContent: 'old',
            proposedContent: 'new',
            memberName: '前端工程师',
            diff: '--- file\n+++ file\n@@\n-old\n+new\n',
          ),
        ],
      );

      final exported = ConfigExporter.exportState(state, includeSecrets: false);
      final imported = ConfigExporter.importState(exported);

      expect(imported.workspaces.single.path, '/workspace/app');
      expect(imported.taskAssignments.single.memberName, '前端工程师');
      expect(
        imported.taskAssignments.single.status,
        TaskAssignmentStatus.completed,
      );
      expect(imported.commandRequests.single.command, 'flutter test');
      expect(
          imported.commandRequests.single.status, CommandRequestStatus.pending);
      expect(imported.patchProposals.single.memberName, '前端工程师');
      expect(imported.patchProposals.single.status, PatchStatus.pending);
      expect(
        ConfigExporter.importState(
          ConfigExporter.exportState(AppState.seed(), includeSecrets: false),
        ).conversations.any(
              (conversation) => conversation.memberId == 'member-frontend',
            ),
        isTrue,
      );
      expect(
        AppState.fromJson(
          ConfigExporter.exportState(AppState.seed(), includeSecrets: false)
            ..remove('taskAssignments'),
        ).taskAssignments,
        isEmpty,
      );
    });
  });

  group('secure local persistence', () {
    test('saves api keys in local app state and restores them', () async {
      final temp = await Directory.systemTemp.createTemp('ai_team_store_');
      addTearDown(() async => temp.delete(recursive: true));
      final secrets = MemorySecretStore();
      final store = JsonLocalStore(
        File('${temp.path}/state.json'),
        secretStore: secrets,
      );
      final state = AppState.seed();

      await store.save(state);
      final raw = await File('${temp.path}/state.json').readAsString();
      final loaded = await store.load();

      expect(raw, contains('sk-local-placeholder'));
      expect(raw, contains('"apiKey"'));
      expect(loaded.models.first.apiKey, 'sk-local-placeholder');
      expect(await secrets.read('model-main'), 'sk-local-placeholder');
    });

    test('saves state through a temporary file without leaving temp artifacts',
        () async {
      final temp = await Directory.systemTemp.createTemp('ai_team_atomic_');
      addTearDown(() async => temp.delete(recursive: true));
      final stateFile = File('${temp.path}/state.json');
      final store = JsonLocalStore(
        stateFile,
        secretStore: MemorySecretStore(),
      );

      await store.save(AppState.seed());

      final files = temp.listSync().whereType<File>().toList();
      expect(await stateFile.exists(), isTrue);
      expect(files.map((file) => file.path), isNot(contains('.tmp')));
      expect(await stateFile.readAsString(), contains('"models"'));
    });

    test('persists api keys in local state when secret storage fails',
        () async {
      final temp =
          await Directory.systemTemp.createTemp('ai_team_secret_fail_');
      addTearDown(() async => temp.delete(recursive: true));
      final stateFile = File('${temp.path}/state.json');
      final store = JsonLocalStore(
        stateFile,
        secretStore: ThrowingSecretStore(),
      );
      final state = AppState.seed().copyWith(
        models: [
          AppState.seed().models.first.copyWith(
                name: 'Persisted model',
                baseUrl: 'https://persist.example/v1',
                apiKey: 'secret-that-stays-out-of-json',
              ),
        ],
      );

      await store.save(state);
      final raw = await stateFile.readAsString();

      expect(raw, contains('Persisted model'));
      expect(raw, contains('https://persist.example/v1'));
      expect(raw, contains('secret-that-stays-out-of-json'));
    });

    test('loads api keys from local state when secret storage fails', () async {
      final temp =
          await Directory.systemTemp.createTemp('ai_team_secret_load_');
      addTearDown(() async => temp.delete(recursive: true));
      final stateFile = File('${temp.path}/state.json');
      final state = AppState.seed().copyWith(
        models: [
          AppState.seed().models.first.copyWith(
                name: 'Loaded model',
                baseUrl: 'https://loaded.example/v1',
                apiKey: 'loaded-secret',
              ),
        ],
      );
      await JsonLocalStore(
        stateFile,
        secretStore: MemorySecretStore(),
      ).save(state);
      final store = JsonLocalStore(
        stateFile,
        secretStore: ThrowingSecretStore(),
      );

      final loaded = await store.load();

      expect(loaded.models.single.name, 'Loaded model');
      expect(loaded.models.single.baseUrl, 'https://loaded.example/v1');
      expect(loaded.models.single.apiKey, 'loaded-secret');
    });

    test('backs up corrupt state files and falls back to seed state', () async {
      final temp = await Directory.systemTemp.createTemp('ai_team_corrupt_');
      addTearDown(() async => temp.delete(recursive: true));
      final stateFile = File('${temp.path}/state.json');
      await stateFile.writeAsString('{not valid json');
      final store = JsonLocalStore(
        stateFile,
        secretStore: MemorySecretStore(),
      );

      final loaded = await store.load();
      final backups = temp
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('state.json.corrupt'))
          .toList();

      expect(loaded.teams.single.name, '默认开发团队');
      expect(backups, hasLength(1));
      expect(await stateFile.exists(), isFalse);
    });

    test('exports secrets only when explicitly requested from secret store',
        () async {
      final secrets = MemorySecretStore();
      await secrets.write('model-main', 'real-secret');
      final state = AppState.seed().copyWith(
        models: [
          const ModelProfile(
            id: 'model-main',
            name: 'OpenAI Compatible',
            baseUrl: 'https://api.openai.com/v1',
            modelName: 'gpt-4.1',
            apiKey: '',
          ),
        ],
      );

      final redacted = await ConfigExporter.exportStateWithSecrets(
        state,
        includeSecrets: false,
        secretStore: secrets,
      );
      final withSecrets = await ConfigExporter.exportStateWithSecrets(
        state,
        includeSecrets: true,
        secretStore: secrets,
      );

      expect(redacted['models'].first, isNot(contains('apiKey')));
      expect(withSecrets['models'].first['apiKey'], 'real-secret');
    });
  });

  group('local store paths', () {
    test('uses the user home directory for production data by default', () {
      final store = JsonLocalStore.defaultStore(
        environment: {'HOME': '/Users/example'},
      );

      expect(store.file.path, '/Users/example/.ai_team/state.json');
    });

    test('uses application support for desktop app state', () {
      final store = JsonLocalStore.applicationSupportStore(
        Directory('/Users/example/Library/Application Support/ai_team'),
        secretStore: MemorySecretStore(),
      );

      expect(
        store.file.path,
        '/Users/example/Library/Application Support/ai_team/state.json',
      );
    });

    test('recovers richer legacy state when app support state is sparse',
        () async {
      final temp = await Directory.systemTemp.createTemp('ai_team_migrate_');
      addTearDown(() async => temp.delete(recursive: true));
      final target = JsonLocalStore(
        File('${temp.path}/Application Support/com.example.aiTeam/state.json'),
        secretStore: MemorySecretStore(),
      );
      final legacy = JsonLocalStore(
        File('${temp.path}/.ai_team/state.json'),
        secretStore: MemorySecretStore(),
      );
      final richerLegacy = AppState.seed().copyWith(
        models: [
          AppState.seed().models.first.copyWith(apiKey: 'legacy-key'),
        ],
        conversations: [
          AppState.seed().conversations.first.copyWith(
            messages: [
              ...AppState.seed().conversations.first.messages,
              ChatMessage(
                id: 'msg-legacy',
                authorName: '我',
                content: '旧聊天记录',
                createdAt: DateTime(2026, 6, 17),
                isUser: true,
              ),
            ],
          ),
        ],
      );
      await legacy.save(richerLegacy);
      await target.save(AppState.seed().copyWith(
        models: [
          AppState.seed().models.first.copyWith(apiKey: ''),
        ],
      ));

      final recovered = await JsonLocalStore.loadWithLegacyRecovery(
        targetStore: target,
        legacyStore: legacy,
      );

      expect(recovered.models.first.apiKey, 'legacy-key');
      expect(
        recovered.conversations
            .expand((conversation) => conversation.messages)
            .map((message) => message.content),
        contains('旧聊天记录'),
      );
    });
  });

  group('role command policy', () {
    test('allows whitelisted commands and blocks blacklist matches', () {
      const policy = CommandPolicy(
        allowedCommands: ['flutter test', 'dart analyze'],
        blockedCommands: ['rm', 'sudo'],
        allowedDirectories: ['/workspace/app'],
        requiresConfirmation: true,
      );

      expect(
        policy.evaluate('flutter test', workingDirectory: '/workspace/app'),
        CommandDecision.requiresConfirmation,
      );
      expect(
        policy.evaluate('rm -rf .', workingDirectory: '/workspace/app'),
        CommandDecision.denied,
      );
      expect(
        policy.evaluate('flutter test', workingDirectory: '/tmp/app'),
        CommandDecision.denied,
      );
      expect(
        policy.evaluate(
          'flutter test; rm -rf .',
          workingDirectory: '/workspace/app',
        ),
        CommandDecision.denied,
      );
      expect(
        policy.evaluate('flutter test', workingDirectory: '/workspace/app2'),
        CommandDecision.denied,
      );
      expect(
        policy.evaluate(
          'flutter test --coverage',
          workingDirectory: '/workspace/app/packages/core',
        ),
        CommandDecision.requiresConfirmation,
      );
    });
  });

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
      expect(requestLog.detail, isNot(contains('失败也要记录请求')));
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
      expect(requestLog.detail, contains('model=model-main'));
      expect(requestLog.detail, contains('streaming=true'));
      expect(requestLog.detail, isNot(contains('解释实现方案')));
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
      expect(jsonEncode(requestLog.metadata), isNot(contains('test-secret')));
      expect(jsonEncode(requestLog.metadata), isNot(contains('apiKey')));
      expect(
        jsonEncode(requestLog.metadata),
        isNot(contains('Authorization')),
      );
      expect(diagnosticLog.detail, contains('member=member-secretary'));
      expect(diagnosticLog.detail, contains('model=model-main'));
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
      expect(diagnosticLog.metadata!['model'], 'model-main');
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

      expect(testerConversation.messages.last.content, '测试结果');
      expect(frontendConversation.messages.last.content, '前端结果');
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

  group('patch proposals', () {
    test('generates a unified diff and applies only after approval', () async {
      final temp = await Directory.systemTemp.createTemp('ai_team_patch_test_');
      addTearDown(() async => temp.delete(recursive: true));
      final file = File('${temp.path}/lib.txt');
      await file.writeAsString('old line\n');
      final proposal = PatchProposal.fromFileChange(
        id: 'patch-1',
        filePath: file.path,
        originalContent: 'old line\n',
        proposedContent: 'new line\n',
        memberName: '开发工程师',
      );

      expect(proposal.status, PatchStatus.pending);
      expect(proposal.diff, contains('-old line'));
      expect(proposal.diff, contains('+new line'));
      expect(await file.readAsString(), 'old line\n');

      final applied = await PatchApplier().apply(proposal);

      expect(applied.status, PatchStatus.applied);
      expect(await file.readAsString(), 'new line\n');
    });
  });
}

class ThrowingSecretStore implements SecretStore {
  @override
  Future<void> write(String key, String value) async {
    throw StateError('secret storage unavailable');
  }

  @override
  Future<String?> read(String key) async {
    throw StateError('secret storage unavailable');
  }

  @override
  Future<void> delete(String key) async {
    throw StateError('secret storage unavailable');
  }
}

class ModelCall {
  const ModelCall({
    required this.systemPrompt,
    required this.messages,
  });

  final String systemPrompt;
  final List<ChatMessage> messages;
}

class ScriptedRecordingGateway implements ModelGateway {
  ScriptedRecordingGateway(this.responses);

  final List<String> responses;
  final List<ModelCall> calls = [];
  var _index = 0;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    calls.add(ModelCall(
      systemPrompt: systemPrompt,
      messages: [...messages],
    ));
    cancellation?.throwIfCancelled();
    return responses[_index++];
  }
}

class FailsThenSucceedsRecordingGateway implements ModelGateway {
  final List<String> memberNames = [];

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final memberName =
        RegExp(r'成员名称: ([^\n]+)').firstMatch(systemPrompt)?.group(1);
    if (memberName != null) {
      memberNames.add(memberName);
    }
    if (systemPrompt.contains('秘书')) {
      return '前端工程师: 实现界面';
    }
    if (memberName == '前端工程师') {
      throw const ModelGatewayException('前端失败');
    }
    return '$memberName 完成';
  }
}

class AlwaysFailingGateway implements ModelGateway {
  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    throw const ModelGatewayException('forced failure');
  }
}

class ScriptedMetadataGateway implements MetadataModelGateway {
  ScriptedMetadataGateway(this.completion);

  final ModelCompletion completion;

  @override
  Future<String> complete({
    required ModelProfile model,
    required String systemPrompt,
    required List<ChatMessage> messages,
    ModelRequestCancellation? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
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
    cancellation?.throwIfCancelled();
    return completion;
  }
}

class ScriptedStreamingMetadataGateway implements MetadataModelGateway {
  ScriptedStreamingMetadataGateway({required this.deltas});

  final List<ModelStreamDelta> deltas;

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
    final thinking = StringBuffer();
    for (final delta in deltas) {
      cancellation?.throwIfCancelled();
      onDelta?.call(delta);
      if (delta.contentDelta != null) {
        content.write(delta.contentDelta);
      }
      if (delta.thinkingDelta != null) {
        thinking.write(delta.thinkingDelta);
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    return ModelCompletion(
      content: content.toString(),
      thinkingContent: thinking.toString(),
    );
  }
}
