import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/model_gateway.dart';
import 'package:ai_team/core/orchestrator.dart';
import 'package:ai_team/core/patching.dart';

import 'domain_test_support.dart';

void main() {
  group('patch proposals', () {
    test('member chat executes read file tool before final reply', () async {
      final temp = await Directory.systemTemp.createTemp('ai_team_tool_read_');
      addTearDown(() async => temp.delete(recursive: true));
      await File('${temp.path}/README.md').writeAsString('tool file content');
      final state = AppState.seed().copyWith(
        workspaces: [
          ProjectWorkspace(
            id: 'workspace-1',
            name: 'Fixture',
            path: temp.path,
          ),
        ],
      );
      final gateway = ScriptedToolGateway(
        toolCall: const ModelToolCall(
          id: 'call-read',
          name: 'read_workspace_file',
          arguments: '{"workspaceId":"workspace-1","relativePath":"README.md"}',
        ),
        finalReply: '读取完成',
      );

      final updated = await TeamOrchestrator(gateway).dispatchMemberChat(
        state,
        conversationId: 'conv-member-secretary',
        userText: '读取 README',
      );

      expect(gateway.firstTools.map((tool) => tool.name),
          contains('read_workspace_file'));
      expect(gateway.toolRounds, hasLength(1));
      expect(
        gateway.toolRounds.single.results.single.content,
        contains('tool file content'),
      );
      expect(
        updated.conversations
            .firstWhere(
              (conversation) => conversation.id == 'conv-member-secretary',
            )
            .messages
            .last
            .content,
        '读取完成',
      );
    });

    test('member chat propose patch tool creates pending patch only', () async {
      final temp = await Directory.systemTemp.createTemp('ai_team_tool_patch_');
      addTearDown(() async => temp.delete(recursive: true));
      final file = File('${temp.path}/lib.txt');
      await file.writeAsString('old\n');
      final state = AppState.seed().copyWith(
        workspaces: [
          ProjectWorkspace(
            id: 'workspace-1',
            name: 'Fixture',
            path: temp.path,
          ),
        ],
      );
      final gateway = ScriptedToolGateway(
        toolCall: const ModelToolCall(
          id: 'call-patch',
          name: 'propose_workspace_patch',
          arguments:
              '{"workspaceId":"workspace-1","relativePath":"lib.txt","proposedContent":"new\\n"}',
        ),
        finalReply: '已创建补丁',
      );

      final updated = await TeamOrchestrator(gateway).dispatchMemberChat(
        state,
        conversationId: 'conv-member-secretary',
        userText: '修改文件',
      );

      expect(updated.patchProposals, hasLength(1));
      expect(updated.patchProposals.single.status, PatchStatus.pending);
      expect(updated.patchProposals.single.diff, contains('+new'));
      expect(await file.readAsString(), 'old\n');
      expect(
        gateway.toolRounds.single.results.single.content,
        contains('"status":"pending"'),
      );
    });

    test('member chat command tool creates policy evaluated request only',
        () async {
      final temp =
          await Directory.systemTemp.createTemp('ai_team_tool_command_');
      addTearDown(() async => temp.delete(recursive: true));
      final gateway = ScriptedToolGateway(
        toolCall: ModelToolCall(
          id: 'call-command',
          name: 'request_command',
          arguments: jsonEncode({
            'memberId': 'member-secretary',
            'command': 'flutter test',
            'workingDirectory': temp.path,
          }),
        ),
        finalReply: '已创建命令请求',
      );

      final updated = await TeamOrchestrator(gateway).dispatchMemberChat(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '运行测试',
      );

      expect(updated.commandRequests, hasLength(1));
      expect(
          updated.commandRequests.single.status, CommandRequestStatus.pending);
      expect(updated.commandRequests.single.decision,
          CommandDecision.requiresConfirmation);
      expect(updated.commandRequests.single.output, isNull);
      expect(
        gateway.toolRounds.single.results.single.content,
        contains('"decision":"requiresConfirmation"'),
      );
    });

    test('member chat command tool allows df through wildcard policy',
        () async {
      final temp =
          await Directory.systemTemp.createTemp('ai_team_tool_command_star_');
      addTearDown(() async => temp.delete(recursive: true));
      final state = AppState.seed().copyWith(
        roles: AppState.seed()
            .roles
            .map(
              (role) => role.id == 'role-secretary'
                  ? role.copyWith(
                      commandPolicy: CommandPolicy(
                        allowedCommands: ['*'],
                        blockedCommands: ['rm'],
                        allowedDirectories: [temp.path],
                        requiresConfirmation: true,
                      ),
                    )
                  : role,
            )
            .toList(),
      );
      final gateway = ScriptedToolGateway(
        toolCall: ModelToolCall(
          id: 'call-df',
          name: 'request_command',
          arguments: jsonEncode({
            'memberId': 'member-secretary',
            'command': 'df -h /',
            'workingDirectory': temp.path,
          }),
        ),
        finalReply: '已创建待审批命令请求',
      );

      final updated = await TeamOrchestrator(gateway).dispatchMemberChat(
        state,
        conversationId: 'conv-member-secretary',
        userText: '秘书看一下磁盘占用',
      );

      expect(gateway.firstSystemPrompt, contains('allowedCommands=["*"]'));
      expect(gateway.firstSystemPrompt, contains('request_command'));
      expect(gateway.firstSystemPrompt, contains('无需确认时可以自动执行'));
      expect(gateway.firstSystemPrompt, isNot(contains('命令只会进入用户确认流程')));
      final requestCommandTool = gateway.firstTools.singleWhere(
        (tool) => tool.name == 'request_command',
      );
      expect(
        requestCommandTool.description,
        contains('默认使用当前成员'),
      );
      expect(
        requestCommandTool.parameters['required'],
        isNot(contains('memberId')),
      );
      expect(updated.commandRequests, hasLength(1));
      expect(updated.commandRequests.single.command, 'df -h /');
      expect(
        updated.commandRequests.single.conversationId,
        'conv-member-secretary',
      );
      expect(updated.commandRequests.single.memberId, 'member-secretary');
      expect(updated.commandRequests.single.toolCallId, 'call-df');
      expect(
          updated.commandRequests.single.status, CommandRequestStatus.pending);
      expect(updated.commandRequests.single.decision,
          CommandDecision.requiresConfirmation);
      expect(updated.commandRequests.single.output, isNull);
      expect(
        gateway.toolRounds.single.results.single.content,
        contains('"status":"pending"'),
      );
      expect(
        gateway.toolRounds.single.results.single.content,
        contains('"requiresUserAction":true'),
      );
    });

    test('member chat command tool auto executes allowed commands', () async {
      final temp =
          await Directory.systemTemp.createTemp('ai_team_tool_command_auto_');
      addTearDown(() async => temp.delete(recursive: true));
      final state = AppState.seed().copyWith(
        roles: AppState.seed()
            .roles
            .map(
              (role) => role.id == 'role-secretary'
                  ? role.copyWith(
                      commandPolicy: CommandPolicy(
                        allowedCommands: ['*'],
                        blockedCommands: ['rm'],
                        allowedDirectories: [temp.path],
                        requiresConfirmation: false,
                      ),
                    )
                  : role,
            )
            .toList(),
      );
      final gateway = ScriptedToolGateway(
        firstReplyBeforeTool: '我先查看一下',
        toolCall: ModelToolCall(
          id: 'call-df-auto',
          name: 'request_command',
          arguments: jsonEncode({
            'memberId': 'member-secretary',
            'command': 'df -h /',
            'workingDirectory': temp.path,
          }),
        ),
        finalReply: '根目录已使用 42G',
      );

      final updated = await TeamOrchestrator(
        gateway,
        commandRunner: (_, __) async => ProcessResult(
          9,
          0,
          'Filesystem Size Used Avail Capacity Mounted on\n'
              '/dev/disk3s1s1 460Gi 42Gi 100Gi 30% /',
          '',
        ),
      ).dispatchMemberChat(
        state,
        conversationId: 'conv-member-secretary',
        userText: '秘书看一下磁盘占用',
      );

      final request = updated.commandRequests.single;
      final result = gateway.toolRounds.single.results.single.content;
      final conversation = updated.conversations.firstWhere(
        (conversation) => conversation.id == 'conv-member-secretary',
      );
      expect(request.decision, CommandDecision.allowed);
      expect(request.status, CommandRequestStatus.executed);
      expect(request.messageId, isNotNull);
      expect(request.output, contains('42Gi'));
      expect(result, contains('"status":"executed"'));
      expect(result, contains('"output"'));
      expect(result, contains('42Gi'));
      expect(result, contains('"exitCode":0'));
      expect(result, contains('"requiresUserAction":false'));
      expect(conversation.messages, hasLength(3));
      expect(conversation.messages.last.authorName, '秘书');
      expect(conversation.messages.last.content, contains('我先查看一下'));
      expect(conversation.messages.last.content, contains('根目录已使用 42G'));
      expect(conversation.messages.last.contentBlocks, hasLength(3));
      expect(conversation.messages.last.contentBlocks.first.text, '我先查看一下');
      expect(
        conversation.messages.last.contentBlocks[1].commandResult?.output,
        contains('42Gi'),
      );
      expect(conversation.messages.last.contentBlocks.last.text, '根目录已使用 42G');
    });

    test('member chat command tool accepts current member display name',
        () async {
      final temp =
          await Directory.systemTemp.createTemp('ai_team_tool_command_name_');
      addTearDown(() async => temp.delete(recursive: true));
      final state = AppState.seed().copyWith(
        roles: AppState.seed()
            .roles
            .map(
              (role) => role.id == 'role-secretary'
                  ? role.copyWith(
                      commandPolicy: CommandPolicy(
                        allowedCommands: ['*'],
                        blockedCommands: [],
                        allowedDirectories: [temp.path],
                        requiresConfirmation: true,
                      ),
                    )
                  : role,
            )
            .toList(),
      );
      final gateway = ScriptedToolGateway(
        toolCall: ModelToolCall(
          id: 'call-df-name',
          name: 'request_command',
          arguments: jsonEncode({
            'memberId': '秘书',
            'command': 'df -h /',
            'workingDirectory': temp.path,
          }),
        ),
        finalReply: '已创建待审批命令请求',
      );

      final updated = await TeamOrchestrator(gateway).dispatchMemberChat(
        state,
        conversationId: 'conv-member-secretary',
        userText: '秘书看一下磁盘占用',
      );

      expect(updated.commandRequests, hasLength(1));
      expect(updated.commandRequests.single.memberName, '秘书');
      expect(updated.commandRequests.single.command, 'df -h /');
      expect(
          updated.commandRequests.single.status, CommandRequestStatus.pending);
      expect(updated.commandRequests.single.decision,
          CommandDecision.requiresConfirmation);
      expect(gateway.toolRounds.single.results.single.content,
          isNot(contains('Bad state: No element')));
    });

    test('member chat command tool defaults to active member when omitted',
        () async {
      final temp = await Directory.systemTemp
          .createTemp('ai_team_tool_command_default_');
      addTearDown(() async => temp.delete(recursive: true));
      final state = AppState.seed().copyWith(
        roles: AppState.seed()
            .roles
            .map(
              (role) => role.id == 'role-secretary'
                  ? role.copyWith(
                      commandPolicy: CommandPolicy(
                        allowedCommands: ['*'],
                        blockedCommands: [],
                        allowedDirectories: [temp.path],
                        requiresConfirmation: true,
                      ),
                    )
                  : role,
            )
            .toList(),
      );
      final gateway = ScriptedToolGateway(
        toolCall: ModelToolCall(
          id: 'call-df-default',
          name: 'request_command',
          arguments: jsonEncode({
            'command': 'df -h /',
            'workingDirectory': temp.path,
          }),
        ),
        finalReply: '已创建待审批命令请求',
      );

      final updated = await TeamOrchestrator(gateway).dispatchMemberChat(
        state,
        conversationId: 'conv-member-secretary',
        userText: '秘书看一下磁盘占用',
      );

      expect(updated.commandRequests, hasLength(1));
      expect(updated.commandRequests.single.memberName, '秘书');
      expect(updated.commandRequests.single.command, 'df -h /');
      expect(
          updated.commandRequests.single.status, CommandRequestStatus.pending);
    });

    test('member chat command tool rejects cross member command requests',
        () async {
      final temp =
          await Directory.systemTemp.createTemp('ai_team_tool_command_cross_');
      addTearDown(() async => temp.delete(recursive: true));
      final gateway = ScriptedToolGateway(
        toolCall: ModelToolCall(
          id: 'call-cross-member',
          name: 'request_command',
          arguments: jsonEncode({
            'memberId': 'member-frontend',
            'command': 'df -h /',
            'workingDirectory': temp.path,
          }),
        ),
        finalReply: '命令请求失败已说明',
      );

      final updated = await TeamOrchestrator(gateway).dispatchMemberChat(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '秘书看一下磁盘占用',
      );

      final result = gateway.toolRounds.single.results.single.content;
      expect(updated.commandRequests, isEmpty);
      expect(result, contains('"ok":false'));
      expect(result, contains('不允许跨成员请求命令'));
      expect(result, isNot(contains('Bad state: No element')));
    });

    test('member chat blocks command execution claims without tool calls',
        () async {
      final gateway = ScriptedToolGateway(
        toolCall: null,
        finalReply: '我已尝试执行 `df -h /` 查看磁盘占用。',
      );

      final updated = await TeamOrchestrator(gateway).dispatchMemberChat(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '执行 df -h / 看磁盘占用',
      );

      final reply = updated.conversations
          .firstWhere(
            (conversation) => conversation.id == 'conv-member-secretary',
          )
          .messages
          .last
          .content;
      expect(updated.commandRequests, isEmpty);
      expect(reply, contains('未创建命令请求'));
      expect(reply, isNot(contains('已尝试执行')));
    });

    test('member chat returns structured tool errors without dropping reply',
        () async {
      final gateway = ScriptedToolGateway(
        toolCall: const ModelToolCall(
          id: 'call-unknown',
          name: 'unknown_tool',
          arguments: '{}',
        ),
        finalReply: '工具失败已说明',
      );

      final updated = await TeamOrchestrator(gateway).dispatchMemberChat(
        AppState.seed(),
        conversationId: 'conv-member-secretary',
        userText: '调用未知工具',
      );

      expect(
        gateway.toolRounds.single.results.single.content,
        contains('"ok":false'),
      );
      expect(
        gateway.toolRounds.single.results.single.content,
        contains('未知工具'),
      );
      expect(
        updated.conversations
            .firstWhere(
              (conversation) => conversation.id == 'conv-member-secretary',
            )
            .messages
            .last
            .content,
        '工具失败已说明',
      );
    });

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
