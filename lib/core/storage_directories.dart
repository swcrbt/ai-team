import 'dart:convert';
import 'dart:io';

class StorageDirectories {
  const StorageDirectories({
    required this.stateDirectory,
    required this.auditDirectory,
    required this.conversationDirectory,
    required this.cacheDirectory,
  });

  factory StorageDirectories.defaults(Directory applicationSupportDirectory) {
    final root = applicationSupportDirectory.path;
    return StorageDirectories(
      stateDirectory: root,
      auditDirectory: '$root/audit',
      conversationDirectory: '$root/conversations',
      cacheDirectory: '$root/cache',
    );
  }

  final String stateDirectory;
  final String auditDirectory;
  final String conversationDirectory;
  final String cacheDirectory;

  String get stateFilePath => '$stateDirectory/state.json';

  StorageDirectories copyWith({
    String? stateDirectory,
    String? auditDirectory,
    String? conversationDirectory,
    String? cacheDirectory,
  }) {
    return StorageDirectories(
      stateDirectory: stateDirectory ?? this.stateDirectory,
      auditDirectory: auditDirectory ?? this.auditDirectory,
      conversationDirectory:
          conversationDirectory ?? this.conversationDirectory,
      cacheDirectory: cacheDirectory ?? this.cacheDirectory,
    );
  }

  Map<String, Object?> toJson() => {
        'stateDirectory': stateDirectory,
        'auditDirectory': auditDirectory,
        'conversationDirectory': conversationDirectory,
        'cacheDirectory': cacheDirectory,
      };

  factory StorageDirectories.fromJson(
    Map<String, Object?> json,
    Directory fallbackRoot,
  ) {
    final fallback = StorageDirectories.defaults(fallbackRoot);
    return StorageDirectories(
      stateDirectory:
          _stringValue(json['stateDirectory']) ?? fallback.stateDirectory,
      auditDirectory:
          _stringValue(json['auditDirectory']) ?? fallback.auditDirectory,
      conversationDirectory: _stringValue(json['conversationDirectory']) ??
          fallback.conversationDirectory,
      cacheDirectory:
          _stringValue(json['cacheDirectory']) ?? fallback.cacheDirectory,
    );
  }
}

class StorageDirectoryConfigStore {
  const StorageDirectoryConfigStore({
    required this.file,
    required this.defaultRoot,
  });

  factory StorageDirectoryConfigStore.applicationSupport(
    Directory applicationSupportDirectory,
  ) {
    return StorageDirectoryConfigStore(
      file:
          File('${applicationSupportDirectory.path}/storage_directories.json'),
      defaultRoot: applicationSupportDirectory,
    );
  }

  final File file;
  final Directory defaultRoot;

  StorageDirectories get defaults => StorageDirectories.defaults(defaultRoot);

  Future<StorageDirectories> load() async {
    if (!await file.exists()) {
      return defaults;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        return StorageDirectories.fromJson(
          Map<String, Object?>.from(decoded),
          defaultRoot,
        );
      }
    } on FormatException {
      await _backupCorruptConfig();
    } on TypeError {
      await _backupCorruptConfig();
    }
    return defaults;
  }

  Future<void> save(StorageDirectories directories) async {
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(encoder.convert(directories.toJson()));
    if (await file.exists()) {
      await file.delete();
    }
    await temp.rename(file.path);
  }

  Future<void> copyExistingData({
    required StorageDirectories from,
    required StorageDirectories to,
  }) async {
    await _copyFileIfPresent(from.stateFilePath, to.stateFilePath);
    await _copyDirectoryIfPresent(from.auditDirectory, to.auditDirectory);
    await _copyDirectoryIfPresent(
      from.conversationDirectory,
      to.conversationDirectory,
    );
    await _copyDirectoryIfPresent(from.cacheDirectory, to.cacheDirectory);
  }

  Future<void> _backupCorruptConfig() async {
    if (!await file.exists()) {
      return;
    }
    final timestamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    await file.rename('${file.path}.corrupt-$timestamp');
  }
}

Future<void> _copyFileIfPresent(String sourcePath, String targetPath) async {
  final source = File(sourcePath);
  if (!await source.exists()) {
    return;
  }
  final target = File(targetPath);
  if (await target.exists()) {
    return;
  }
  await target.parent.create(recursive: true);
  await source.copy(target.path);
}

Future<void> _copyDirectoryIfPresent(
  String sourcePath,
  String targetPath,
) async {
  final source = Directory(sourcePath);
  if (!await source.exists()) {
    return;
  }
  final target = Directory(targetPath);
  await target.create(recursive: true);
  await for (final entity in source.list(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final relativePath = entity.path.substring(source.path.length + 1);
    final copy = File('${target.path}/$relativePath');
    if (await copy.exists()) {
      continue;
    }
    await copy.parent.create(recursive: true);
    await entity.copy(copy.path);
  }
}

String? _stringValue(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value;
}
