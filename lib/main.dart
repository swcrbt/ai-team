import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/local_store.dart';
import 'core/model_gateway.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = JsonLocalStore.applicationSupportStore(
    await getApplicationSupportDirectory(),
  );
  await _migrateLegacyState(store);
  final state = await store.load();
  runApp(AiTeamApp(
    initialState: state,
    modelGateway: OpenAiCompatibleGateway(),
    onStateChanged: store.save,
  ));
}

Future<void> _migrateLegacyState(JsonLocalStore targetStore) async {
  if (await targetStore.file.exists()) {
    return;
  }
  final legacyStore = JsonLocalStore.defaultStore();
  if (!await legacyStore.file.exists()) {
    return;
  }
  await targetStore.file.parent.create(recursive: true);
  await legacyStore.file.copy(targetStore.file.path);
  final legacySecrets = Directory('${legacyStore.file.parent.path}/secrets');
  final targetSecrets = Directory('${targetStore.file.parent.path}/secrets');
  if (await legacySecrets.exists() && !await targetSecrets.exists()) {
    await targetSecrets.create(recursive: true);
    await for (final entity in legacySecrets.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final relative = entity.path.substring(legacySecrets.path.length + 1);
      final copy = File('${targetSecrets.path}/$relative');
      await copy.parent.create(recursive: true);
      await entity.copy(copy.path);
    }
  }
}
