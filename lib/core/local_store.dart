import 'dart:convert';
import 'dart:io';

import 'domain.dart';

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

  static AppState importState(Map<String, Object?> json) {
    return AppState.fromJson(json);
  }
}

class JsonLocalStore {
  JsonLocalStore(this.file);

  final File file;

  Future<AppState> load() async {
    if (!await file.exists()) {
      return AppState.seed();
    }
    final raw = await file.readAsString();
    return AppState.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  Future<void> save(AppState state) async {
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file
        .writeAsString(encoder.convert(state.toJson(includeSecrets: true)));
  }

  Future<void> exportTo(
    File target,
    AppState state, {
    required bool includeSecrets,
  }) async {
    await target.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await target.writeAsString(
      encoder.convert(ConfigExporter.exportState(
        state,
        includeSecrets: includeSecrets,
      )),
    );
  }
}
