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

  static Future<AppState> loadWithLegacyRecovery({
    required JsonLocalStore targetStore,
    required JsonLocalStore legacyStore,
  }) async {
    final targetState = await targetStore.load();
    if (!await legacyStore.file.exists()) {
      return targetState;
    }
    final legacyState = await legacyStore.load();
    final recovered = _mergeRecoveredState(
      target: targetState,
      legacy: legacyState,
    );
    if (_stateRecoveryScore(recovered) > _stateRecoveryScore(targetState)) {
      await targetStore.save(recovered);
    }
    return recovered;
  }

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

AppState _mergeRecoveredState({
  required AppState target,
  required AppState legacy,
}) {
  return target.copyWith(
    models: _mergeModels(target.models, legacy.models),
    conversations: _mergeConversations(
      target.conversations,
      legacy.conversations,
    ),
    auditLog: _mergeAuditLog(target.auditLog, legacy.auditLog),
  );
}

List<ModelProfile> _mergeModels(
  List<ModelProfile> target,
  List<ModelProfile> legacy,
) {
  final legacyById = {
    for (final model in legacy) model.id: model,
  };
  final merged = <ModelProfile>[];
  final seen = <String>{};
  for (final model in target) {
    seen.add(model.id);
    final legacyModel = legacyById[model.id];
    merged.add(
      model.apiKey.isEmpty &&
              legacyModel != null &&
              legacyModel.apiKey.isNotEmpty
          ? model.copyWith(apiKey: legacyModel.apiKey)
          : model,
    );
  }
  for (final model in legacy) {
    if (seen.add(model.id)) {
      merged.add(model);
    }
  }
  return merged;
}

List<Conversation> _mergeConversations(
  List<Conversation> target,
  List<Conversation> legacy,
) {
  final legacyById = {
    for (final conversation in legacy) conversation.id: conversation,
  };
  final merged = <Conversation>[];
  final seen = <String>{};
  for (final conversation in target) {
    seen.add(conversation.id);
    final legacyConversation = legacyById[conversation.id];
    merged.add(legacyConversation == null
        ? conversation
        : conversation.copyWith(
            messages: _mergeMessages(
              conversation.messages,
              legacyConversation.messages,
            ),
            currentRound:
                conversation.currentRound >= legacyConversation.currentRound
                    ? conversation.currentRound
                    : legacyConversation.currentRound,
          ));
  }
  for (final conversation in legacy) {
    if (seen.add(conversation.id)) {
      merged.add(conversation);
    }
  }
  return merged;
}

List<ChatMessage> _mergeMessages(
  List<ChatMessage> target,
  List<ChatMessage> legacy,
) {
  final byId = <String, ChatMessage>{
    for (final message in legacy) message.id: message,
    for (final message in target) message.id: message,
  };
  final messages = byId.values.toList()
    ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
  return messages;
}

List<AuditEntry> _mergeAuditLog(
  List<AuditEntry> target,
  List<AuditEntry> legacy,
) {
  final byId = <String, AuditEntry>{
    for (final entry in legacy) entry.id: entry,
    for (final entry in target) entry.id: entry,
  };
  final entries = byId.values.toList()
    ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
  return entries;
}

int _stateRecoveryScore(AppState state) {
  final apiKeyChars = state.models.fold<int>(
    0,
    (total, model) => total + model.apiKey.length,
  );
  final messageCount = state.conversations.fold<int>(
    0,
    (total, conversation) => total + conversation.messages.length,
  );
  return apiKeyChars + messageCount + state.auditLog.length;
}
