import 'dart:io';

import '../domain.dart';

typedef CommandRunner = Future<ProcessResult> Function(
  String command,
  String workingDirectory,
);

class CommandService {
  const CommandService({CommandRunner? runner}) : _runner = runner;

  final CommandRunner? _runner;

  CommandRunner get runner => _runner ?? defaultCommandRunner;

  Future<CommandRunResult> run(CommandRequest request) async {
    try {
      final result = await runner(request.command, request.workingDirectory);
      return CommandRunResult(
        status: result.exitCode == 0
            ? CommandRequestStatus.executed
            : CommandRequestStatus.failed,
        output: outputFromProcessResult(result),
        exitCode: result.exitCode,
      );
    } catch (error) {
      return CommandRunResult(
        status: CommandRequestStatus.failed,
        output: error.toString(),
        exitCode: null,
      );
    }
  }

  static String outputFromProcessResult(ProcessResult result) {
    return [
      if (result.stdout.toString().trim().isNotEmpty)
        result.stdout.toString().trim(),
      if (result.stderr.toString().trim().isNotEmpty)
        result.stderr.toString().trim(),
    ].join('\n');
  }
}

class CommandRunResult {
  const CommandRunResult({
    required this.status,
    required this.output,
    required this.exitCode,
  });

  final CommandRequestStatus status;
  final String output;
  final int? exitCode;
}

Future<ProcessResult> defaultCommandRunner(
  String command,
  String workingDirectory,
) {
  if (Platform.isWindows) {
    return Process.run(
      'cmd',
      ['/c', command],
      workingDirectory: workingDirectory,
      runInShell: false,
    );
  }
  return Process.run(
    '/bin/sh',
    ['-c', command],
    workingDirectory: workingDirectory,
    runInShell: false,
  );
}
