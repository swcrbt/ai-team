import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/local_store.dart';
import 'package:ai_team/core/orchestrator.dart';
import 'package:ai_team/core/patching.dart';

void main() {
  group('configuration export', () {
    test('exports model metadata without api keys by default', () {
      final state = AppState.seed();

      final exported = ConfigExporter.exportState(state, includeSecrets: false);

      expect(exported['models'], hasLength(2));
      expect(exported['models'].first, isNot(contains('apiKey')));
      expect(exported['roles'], isNotEmpty);
      expect(exported['teams'], isNotEmpty);
    });

    test('exports api keys only when explicitly requested', () {
      final state = AppState.seed();

      final exported = ConfigExporter.exportState(state, includeSecrets: true);

      expect(exported['models'].first['apiKey'], isNotEmpty);
    });
  });

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
    });
  });

  group('secretary orchestration', () {
    test('creates visible secretary and member messages for a team task',
        () async {
      final state = AppState.seed();
      final orchestrator = TeamOrchestrator(FakeModelGateway());

      final updated = await orchestrator.dispatchTeamTask(
        state,
        teamId: 'team-default',
        userText: '实现登录页面并补测试',
      );

      final messages = updated.conversations
          .firstWhere((conversation) => conversation.id == 'conv-team-default')
          .messages;

      expect(messages.map((message) => message.authorName), contains('我'));
      expect(messages.map((message) => message.authorName), contains('秘书'));
      expect(messages.any((message) => message.authorName == '前端工程师'), isTrue);
      expect(messages.last.content, contains('汇总'));
    });

    test('does not exceed the team max round limit', () async {
      final state = AppState.seed().copyWith(
        teams: [
          AppState.seed().teams.first.copyWith(maxRounds: 1),
        ],
      );
      final orchestrator = TeamOrchestrator(FakeModelGateway());

      final updated = await orchestrator.dispatchTeamTask(
        state,
        teamId: 'team-default',
        userText: '持续协作直到完成',
      );

      final conversation = updated.conversations
          .firstWhere((conversation) => conversation.id == 'conv-team-default');
      expect(conversation.currentRound, 1);
      expect(conversation.status, ConversationStatus.paused);
    });
  });

  group('patch proposals', () {
    test('generates a unified diff and applies only after approval', () async {
      final temp = await Directory.systemTemp.createTemp('ai_team_patch_test_');
      addTearDown(() async => temp.delete(recursive: true));
      final file = File('${temp.path}/lib.txt');
      await file.writeAsString('old line\n');
      final proposal = PatchProposal.fromFileChange(
        id: 'patch-1',
        filePath: file.path,
        originalContent: 'old line\n',
        proposedContent: 'new line\n',
        memberName: '开发工程师',
      );

      expect(proposal.status, PatchStatus.pending);
      expect(proposal.diff, contains('-old line'));
      expect(proposal.diff, contains('+new line'));
      expect(await file.readAsString(), 'old line\n');

      final applied = await PatchApplier().apply(proposal);

      expect(applied.status, PatchStatus.applied);
      expect(await file.readAsString(), 'new line\n');
    });
  });
}
