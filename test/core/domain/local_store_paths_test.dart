import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/local_store.dart';
import 'package:ai_team/core/secret_store.dart';
import 'package:ai_team/core/storage_directories.dart';

void main() {
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

    test('storage directory config defaults under application support',
        () async {
      final temp = await Directory.systemTemp.createTemp('ai_team_storage_');
      addTearDown(() async => temp.delete(recursive: true));
      final store = StorageDirectoryConfigStore.applicationSupport(temp);

      final directories = await store.load();

      expect(directories.stateDirectory, temp.path);
      expect(directories.auditDirectory, '${temp.path}/audit');
      expect(directories.conversationDirectory, '${temp.path}/conversations');
      expect(directories.cacheDirectory, '${temp.path}/cache');
    });

    test('storage directory config saves and copies existing data', () async {
      final temp = await Directory.systemTemp.createTemp('ai_team_storage_');
      addTearDown(() async => temp.delete(recursive: true));
      final store = StorageDirectoryConfigStore.applicationSupport(temp);
      final source = StorageDirectories(
        stateDirectory: '${temp.path}/old-state',
        auditDirectory: '${temp.path}/old-audit',
        conversationDirectory: '${temp.path}/old-conversations',
        cacheDirectory: '${temp.path}/old-cache',
      );
      final target = StorageDirectories(
        stateDirectory: '${temp.path}/new-state',
        auditDirectory: '${temp.path}/new-audit',
        conversationDirectory: '${temp.path}/new-conversations',
        cacheDirectory: '${temp.path}/new-cache',
      );
      await File(source.stateFilePath).create(recursive: true);
      await File(source.stateFilePath).writeAsString('{"ok":true}');
      await File('${source.auditDirectory}/audit.jsonl')
          .create(recursive: true);
      await File('${source.auditDirectory}/audit.jsonl').writeAsString('event');

      await store.copyExistingData(from: source, to: target);
      await store.save(target);
      final loaded = await store.load();

      expect(await File(target.stateFilePath).readAsString(), '{"ok":true}');
      expect(
        await File('${target.auditDirectory}/audit.jsonl').readAsString(),
        'event',
      );
      expect(loaded.stateDirectory, target.stateDirectory);
      expect(loaded.auditDirectory, target.auditDirectory);
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
}
