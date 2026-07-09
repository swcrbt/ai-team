import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/local_store.dart';
import 'package:ai_team/core/secret_store.dart';

void main() {
  group('secure local persistence', () {
    test('saves api keys in secret store and restores them', () async {
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

    test('keeps api keys durable when secret storage throws', () async {
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
                apiKey: 'secret-that-survives-restart',
              ),
        ],
      );

      await store.save(state);
      final raw = await stateFile.readAsString();
      final loaded = await store.load();

      expect(raw, contains('Persisted model'));
      expect(raw, contains('https://persist.example/v1'));
      expect(raw, contains('secret-that-survives-restart'));
      expect(loaded.models.single.apiKey, 'secret-that-survives-restart');
    });

    test('keeps api keys durable when secret storage write is not readable',
        () async {
      final temp =
          await Directory.systemTemp.createTemp('ai_team_secret_noop_');
      addTearDown(() async => temp.delete(recursive: true));
      final stateFile = File('${temp.path}/state.json');
      final store = JsonLocalStore(
        stateFile,
        secretStore: UnreadableWriteSecretStore(),
      );
      final state = AppState.seed().copyWith(
        models: [
          AppState.seed().models.first.copyWith(
                name: 'No-op secure model',
                baseUrl: 'https://noop.example/v1',
                apiKey: 'secret-from-noop-store',
              ),
        ],
      );

      await store.save(state);
      final raw = await stateFile.readAsString();
      final loaded = await store.load();

      expect(raw, contains('"apiKey": "secret-from-noop-store"'));
      expect(loaded.models.single.apiKey, 'secret-from-noop-store');
    });

    test('loads legacy api keys from local state when secret storage fails',
        () async {
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
      await stateFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          ConfigExporter.exportState(state, includeSecrets: true),
        ),
      );
      final store = JsonLocalStore(
        stateFile,
        secretStore: ThrowingSecretStore(),
      );

      final loaded = await store.load();

      expect(loaded.models.single.name, 'Loaded model');
      expect(loaded.models.single.baseUrl, 'https://loaded.example/v1');
      expect(loaded.models.single.apiKey, 'loaded-secret');
    });

    test('redacts legacy api keys on next successful save', () async {
      final temp =
          await Directory.systemTemp.createTemp('ai_team_secret_migrate_');
      addTearDown(() async => temp.delete(recursive: true));
      final stateFile = File('${temp.path}/state.json');
      final state = AppState.seed().copyWith(
        models: [
          AppState.seed().models.first.copyWith(
                name: 'Legacy model',
                baseUrl: 'https://legacy.example/v1',
                apiKey: 'legacy-secret',
              ),
        ],
      );
      await stateFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          ConfigExporter.exportState(state, includeSecrets: true),
        ),
      );
      final store = JsonLocalStore(
        stateFile,
        secretStore: MemorySecretStore(),
      );

      final loaded = await store.load();
      await store.save(loaded);
      final raw = await stateFile.readAsString();

      expect(loaded.models.single.apiKey, 'legacy-secret');
      expect(raw, contains('Legacy model'));
      expect(raw, isNot(contains('legacy-secret')));
      expect(raw, isNot(contains('"apiKey"')));
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

class UnreadableWriteSecretStore implements SecretStore {
  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> delete(String key) async {}
}
