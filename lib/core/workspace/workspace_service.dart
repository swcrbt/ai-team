import 'dart:io';

import '../domain.dart';

class WorkspaceService {
  const WorkspaceService();

  Future<List<String>> listFiles(
    AppState state, {
    required String workspaceId,
    int maxFiles = 500,
  }) async {
    final root = rootFor(state, workspaceId);
    if (!await root.exists()) {
      throw StateError('工作区不存在: ${root.path}');
    }
    final rootPath = root.absolute.path;
    final files = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (files.length >= maxFiles) {
        break;
      }
      final path = entity.absolute.path;
      final relative = relativePath(rootPath, path);
      if (isHiddenPath(relative)) {
        continue;
      }
      if (entity is File) {
        files.add(relative);
      }
    }
    files.sort();
    return files;
  }

  Future<String> readFile(
    AppState state, {
    required String workspaceId,
    required String relativePath,
  }) async {
    final file = fileFor(
      state,
      workspaceId: workspaceId,
      relativePath: relativePath,
    );
    if (!await file.exists()) {
      throw StateError('文件不存在: $relativePath');
    }
    return file.readAsString();
  }

  Future<PatchProposal> proposePatch(
    AppState state, {
    required String workspaceId,
    required String relativePath,
    required String proposedContent,
    required String memberName,
    required String id,
  }) async {
    final file = fileFor(
      state,
      workspaceId: workspaceId,
      relativePath: relativePath,
    );
    final originalContent =
        await file.exists() ? await file.readAsString() : '';
    return PatchProposal.fromFileChange(
      id: id,
      filePath: file.path,
      originalContent: originalContent,
      proposedContent: proposedContent,
      memberName: memberName,
    );
  }

  Directory rootFor(AppState state, String workspaceId) {
    final workspace =
        state.workspaces.firstWhere((item) => item.id == workspaceId);
    return Directory(workspace.path).absolute;
  }

  File fileFor(
    AppState state, {
    required String workspaceId,
    required String relativePath,
  }) {
    if (relativePath.trim().isEmpty ||
        relativePath.startsWith('/') ||
        relativePath.split('/').contains('..')) {
      throw ArgumentError('非法相对路径: $relativePath');
    }
    final root = rootFor(state, workspaceId).absolute.path;
    final file = File('$root/$relativePath').absolute;
    if (!file.path.startsWith('$root/')) {
      throw ArgumentError('文件路径越过工作区边界: $relativePath');
    }
    return file;
  }

  static String relativePath(String rootPath, String entityPath) {
    final normalizedRoot = rootPath.replaceAll('\\', '/');
    final normalizedEntity = entityPath.replaceAll('\\', '/');
    if (normalizedEntity == normalizedRoot) {
      return '';
    }
    return normalizedEntity.substring(normalizedRoot.length + 1);
  }

  static bool isHiddenPath(String relativePath) {
    return relativePath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .any((segment) => segment.startsWith('.'));
  }
}
