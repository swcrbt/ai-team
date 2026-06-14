import 'dart:convert';
import 'dart:io';

import 'domain.dart';
import 'secret_store.dart';

class ConfigExporter {
  static Map<String, dynamic> exportState(
    AppState state, {
    required bool includeSecrets,
  }) {
    return {
      'schemaVersion': 1,
      ...state.toJson(includeSecrets: includeSecrets),
    };
  }

  static Future<Map<String, dynamic>> exportStateWithSecrets(
    AppState state, {
    required bool includeSecrets,
    required SecretStore secretStore,
  }) async {
    if (!includeSecrets) {
      return exportState(state, includeSecrets: false);
    }
    final models = <ModelProfile>[];
    for (final model in state.models) {
      models.add(model.copyWith(
        apiKey: await secretStore.read(model.id) ?? model.apiKey,
      ));
    }
    return exportState(
      state.copyWith(models: models),
      includeSecrets: true,
    );
  }

  static AppState importState(Map<String, Object?> json) {
    return AppState.fromJson(json);
  }
}

class JsonLocalStore {
  JsonLocalStore(this.file, {SecretStore? secretStore})
      : secretStore = secretStore ?? FlutterSecretStore();

  factory JsonLocalStore.defaultStore({
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? Directory.current.path;
    return JsonLocalStore(File('$home/.ai_team/state.json'));
  }

  final File file;
  final SecretStore secretStore;

  Future<AppState> load() async {
    if (!await file.exists()) {
      return AppState.seed();
    }
    final raw = await file.readAsString();
    final state = AppState.fromJson(jsonDecode(raw) as Map<String, Object?>);
    final models = <ModelProfile>[];
    for (final model in state.models) {
      models.add(model.copyWith(
        apiKey: await secretStore.read(model.id) ?? model.apiKey,
      ));
    }
    return state.copyWith(models: models);
  }

  Future<void> save(AppState state) async {
    for (final model in state.models) {
      if (model.apiKey.isNotEmpty) {
        await secretStore.write(model.id, model.apiKey);
      }
    }
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(state.toJson(includeSecrets: false)),
    );
  }

  Future<void> exportTo(
    File target,
    AppState state, {
    required bool includeSecrets,
  }) async {
    await target.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await target.writeAsString(
      encoder.convert(await ConfigExporter.exportStateWithSecrets(
        state,
        includeSecrets: includeSecrets,
        secretStore: secretStore,
      )),
    );
  }
}
