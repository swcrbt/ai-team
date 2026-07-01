import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/domain.dart';

void main() {
  group('role command policy', () {
    test('allows whitelisted commands and blocks blacklist matches', () {
      const policy = CommandPolicy(
        allowedCommands: ['flutter test', 'dart analyze'],
        blockedCommands: ['rm', 'sudo'],
        allowedDirectories: ['/workspace/app'],
        requiresConfirmation: true,
      );

      expect(
        policy.evaluate('flutter test', workingDirectory: '/workspace/app'),
        CommandDecision.requiresConfirmation,
      );
      expect(
        policy.evaluate('rm -rf .', workingDirectory: '/workspace/app'),
        CommandDecision.denied,
      );
      expect(
        policy.evaluate('flutter test', workingDirectory: '/tmp/app'),
        CommandDecision.denied,
      );
      expect(
        policy.evaluate(
          'flutter test; rm -rf .',
          workingDirectory: '/workspace/app',
        ),
        CommandDecision.denied,
      );
      expect(
        policy.evaluate('flutter test', workingDirectory: '/workspace/app2'),
        CommandDecision.denied,
      );
      expect(
        policy.evaluate(
          'flutter test --coverage',
          workingDirectory: '/workspace/app/packages/core',
        ),
        CommandDecision.requiresConfirmation,
      );
    });

    test('treats wildcard command allow as safe policy wildcard only', () {
      const policy = CommandPolicy(
        allowedCommands: ['*'],
        blockedCommands: ['rm'],
        allowedDirectories: ['/workspace/app'],
        requiresConfirmation: true,
      );

      expect(
        policy.evaluate('df -h /', workingDirectory: '/workspace/app'),
        CommandDecision.requiresConfirmation,
      );
      expect(
        policy.evaluate('rm -rf .', workingDirectory: '/workspace/app'),
        CommandDecision.denied,
      );
      expect(
        policy.evaluate(
          'du -xhd1 / 2>/dev/null | sort -h',
          workingDirectory: '/workspace/app',
        ),
        CommandDecision.denied,
      );
      expect(
        policy.evaluate('df -h /', workingDirectory: '/tmp/app'),
        CommandDecision.denied,
      );
    });

    test('wildcard command allow still honors confirmation flag', () {
      const policy = CommandPolicy(
        allowedCommands: ['*'],
        blockedCommands: [],
        allowedDirectories: [],
        requiresConfirmation: false,
      );

      expect(
        policy.evaluate('df -h /', workingDirectory: '/workspace/app'),
        CommandDecision.allowed,
      );
    });

    test('allowed command requests start approved instead of pending', () {
      final request = CommandRequest.pending(
        id: 'command-allowed',
        memberName: '秘书',
        command: 'df -h /',
        workingDirectory: '/',
        decision: CommandDecision.allowed,
      );

      expect(request.status, CommandRequestStatus.approved);
    });
  });
}
