import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/local_store.dart';
import 'core/model_gateway.dart';
import 'core/storage_directories.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final applicationSupportDirectory = await getApplicationSupportDirectory();
  final storageConfigStore = StorageDirectoryConfigStore.applicationSupport(
    applicationSupportDirectory,
  );
  final storageDirectories = await storageConfigStore.load();
  final store = JsonLocalStore(
    File(storageDirectories.stateFilePath),
  );
  final legacyStore = JsonLocalStore.defaultStore();
  await _migrateLegacyState(store, legacyStore);
  final state = await JsonLocalStore.loadWithLegacyRecovery(
    targetStore: store,
    legacyStore: legacyStore,
  );
  runApp(AiTeamApp(
    initialState: state,
    modelGateway: OpenAiCompatibleGateway(),
    onStateChanged: store.save,
    storageDirectories: storageDirectories,
    storageDirectoryConfigStore: storageConfigStore,
  ));
}

Future<void> _migrateLegacyState(
  JsonLocalStore targetStore,
  JsonLocalStore legacyStore,
) async {
  if (await targetStore.file.exists()) {
    return;
  }
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
