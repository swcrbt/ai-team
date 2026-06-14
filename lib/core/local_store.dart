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

  factory JsonLocalStore.applicationSupportStore(
    Directory applicationSupportDirectory, {
    SecretStore? secretStore,
  }) {
    return JsonLocalStore(
      File('${applicationSupportDirectory.path}/state.json'),
      secretStore: secretStore,
    );
  }

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
    late AppState state;
    try {
      final raw = await file.readAsString();
      state = AppState.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on FormatException {
      await _backupCorruptState();
      return AppState.seed();
    } on TypeError {
      await _backupCorruptState();
      return AppState.seed();
    }
    final models = <ModelProfile>[];
    for (final model in state.models) {
      String? apiKey;
      try {
        apiKey = await secretStore.read(model.id);
      } catch (_) {
        apiKey = null;
      }
      models.add(model.copyWith(
        apiKey: apiKey ?? model.apiKey,
      ));
    }
    return state.copyWith(models: models);
  }

  Future<void> _backupCorruptState() async {
    if (!await file.exists()) {
      return;
    }
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    await file.rename('${file.path}.corrupt-$timestamp');
  }

  Future<void> save(AppState state) async {
    for (final model in state.models) {
      if (model.apiKey.isNotEmpty) {
        try {
          await secretStore.write(model.id, model.apiKey);
        } catch (_) {
          // Keep non-secret configuration durable even if the platform secret
          // store is unavailable. API keys still stay out of the JSON file.
        }
      }
    }
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    final tempFile = File('${file.path}.tmp');
    await tempFile.writeAsString(
      encoder.convert(state.toJson(includeSecrets: true)),
    );
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
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
