import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/local_store.dart';
import 'package:ai_team/core/orchestrator.dart';
import 'package:ai_team/core/patching.dart';
import 'package:ai_team/core/secret_store.dart';

void main() {
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
    test('saves app state without api keys and restores them from secrets',
        () async {
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

      expect(raw, isNot(contains('sk-local-placeholder')));
      expect(raw, isNot(contains('"apiKey"')));
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

    test('persists non-secret configuration when secret storage fails',
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
      expect(raw, isNot(contains('secret-that-stays-out-of-json')));
    });

    test('loads non-secret configuration when secret storage fails', () async {
      final temp =
          await Directory.systemTemp.createTemp('ai_team_secret_load_');
      addTearDown(() async => temp.delete(recursive: true));
      final stateFile = File('${temp.path}/state.json');
      final state = AppState.seed().copyWith(
        models: [
          AppState.seed().models.first.copyWith(
                name: 'Loaded model',
                baseUrl: 'https://loaded.example/v1',
                apiKey: '',
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
      expect(loaded.models.single.apiKey, isEmpty);
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
