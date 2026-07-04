import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/workspace/workspace_service.dart';

void main() {
  group('WorkspaceService', () {
    test('lists safe non-hidden relative file paths', () async {
      final directory = await Directory.systemTemp.createTemp('ai-team-ws-');
      addTearDown(() => directory.delete(recursive: true));
      await File('${directory.path}/README.md').writeAsString('hello');
      await Directory('${directory.path}/lib').create();
      await File(
        '${directory.path}/lib/main.dart',
      ).writeAsString('void main() {}');
      await Directory('${directory.path}/.git').create();
      await File('${directory.path}/.git/config').writeAsString('hidden');

      const service = WorkspaceService();
      final files = await service.listFiles(
        _stateWithWorkspace(directory.path),
        workspaceId: 'workspace-1',
      );

      expect(files, ['README.md', 'lib/main.dart']);
    });

    test('uses project language for missing roots', () async {
      final directory = await Directory.systemTemp.createTemp('ai-team-ws-');
      await directory.delete();

      const service = WorkspaceService();

      expect(
        service.listFiles(
          _stateWithWorkspace(directory.path),
          workspaceId: 'workspace-1',
        ),
        throwsA(
          isA<StateError>()
              .having((error) => error.message, 'message', contains('项目不存在'))
              .having(
                (error) => error.message,
                'message',
                isNot(contains('工作区')),
              ),
        ),
      );
    });

    test('rejects paths that escape the workspace root', () {
      const service = WorkspaceService();
      final state = _stateWithWorkspace(Directory.current.path);

      expect(
        () => service.fileFor(
          state,
          workspaceId: 'workspace-1',
          relativePath: '../outside.txt',
        ),
        throwsArgumentError,
      );
    });

    test('creates patch proposals without applying files', () async {
      final directory = await Directory.systemTemp.createTemp('ai-team-ws-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/notes.txt');
      await file.writeAsString('old');

      const service = WorkspaceService();
      final proposal = await service.proposePatch(
        _stateWithWorkspace(directory.path),
        workspaceId: 'workspace-1',
        relativePath: 'notes.txt',
        proposedContent: 'new',
        memberName: '测试工程师',
        id: 'patch-1',
      );

      expect(proposal.filePath, file.absolute.path);
      expect(proposal.originalContent, 'old');
      expect(proposal.proposedContent, 'new');
      expect(proposal.status, PatchStatus.pending);
      expect(await file.readAsString(), 'old');
    });
  });
}

AppState _stateWithWorkspace(String path) {
  return AppState.seed().copyWith(
    workspaces: [
      ProjectWorkspace(id: 'workspace-1', name: 'workspace', path: path),
    ],
  );
}
