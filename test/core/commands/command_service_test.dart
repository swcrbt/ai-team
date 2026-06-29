import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/commands/command_service.dart';
import 'package:ai_team/core/domain.dart';

void main() {
  group('CommandService', () {
    test('combines stdout and stderr while trimming empty output', () {
      final output = CommandService.outputFromProcessResult(
        ProcessResult(1, 1, ' ok \n', ' warning \n'),
      );

      expect(output, 'ok\nwarning');
    });

    test('maps process exit codes to command request statuses', () async {
      final service = CommandService(
        runner: (command, workingDirectory) async {
          return ProcessResult(2, 3, 'failure', '');
        },
      );
      final result = await service.run(_approvedRequest());

      expect(result.status, CommandRequestStatus.failed);
      expect(result.exitCode, 3);
      expect(result.output, 'failure');
    });
  });
}

CommandRequest _approvedRequest() {
  return CommandRequest.pending(
    id: 'command-1',
    memberName: '测试工程师',
    command: 'flutter test',
    workingDirectory: Directory.current.path,
    decision: CommandDecision.allowed,
  ).copyWith(status: CommandRequestStatus.approved);
}
