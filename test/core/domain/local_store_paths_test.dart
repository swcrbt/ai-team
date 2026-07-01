import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/local_store.dart';
import 'package:ai_team/core/secret_store.dart';

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
