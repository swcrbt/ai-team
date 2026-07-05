import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_team/core/domain.dart';
import 'package:ai_team/core/model_gateway.dart';

void main() {
  late HttpServer server;
  late List<HttpRequest> requests;

  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  ModelProfile model() => ModelProfile(
        id: 'model-test',
        name: 'Test Model',
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        modelName: 'test-model',
        apiKey: 'test-secret',
      );

  test('builds the chat completions endpoint without duplicate slashes', () {
    expect(
      openAiCompatibleChatCompletionsEndpoint(
        model().copyWith(baseUrl: 'https://api.openai.com/v1'),
      ).toString(),
      'https://api.openai.com/v1/chat/completions',
    );
    expect(
      openAiCompatibleChatCompletionsEndpoint(
        model().copyWith(baseUrl: 'https://api.openai.com/v1/'),
      ).toString(),
      'https://api.openai.com/v1/chat/completions',
    );
  });

  test('sends OpenAI compatible payload and parses assistant content',
      () async {
    unawaited(serve(server, (request) async {
      requests.add(request);
      final body = jsonDecode(await utf8.decodeStream(request)) as Map;
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer test-secret');
      expect(body['model'], 'test-model');
      expect(body['stream'], isFalse);
      expect(body['messages'].first['role'], 'system');
      expect(body['messages'][1]['content'], '我: hi');
      expect(
          body['messages'][1]['content'], isNot(contains('hidden thinking')));
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'choices': [
            {
              'message': {'content': 'hello from model'}
            }
          ]
        }));
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway();

    final content = await gateway.complete(
      model: model().copyWith(streaming: false),
      systemPrompt: 'system',
      messages: [
        ChatMessage(
          id: 'm1',
          authorName: '我',
          content: 'hi',
          thinkingContent: 'hidden thinking',
          createdAt: DateTime(2026),
          isUser: true,
        ),
      ],
    );

    expect(content, 'hello from model');
    expect(requests, hasLength(1));
  });

  test('sends tool definitions and parses non-streaming tool calls', () async {
    late Map<String, Object?> sentBody;
    unawaited(serve(server, (request) async {
      requests.add(request);
      sentBody =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'choices': [
            {
              'message': {
                'content': null,
                'tool_calls': [
                  {
                    'id': 'call-read',
                    'type': 'function',
                    'function': {
                      'name': 'read_workspace_file',
                      'arguments':
                          '{"workspaceId":"workspace-1","relativePath":"README.md"}',
                    },
                  },
                ],
              },
            },
          ],
        }));
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway();

    final completion = await gateway.completeWithMetadata(
      model: model().copyWith(streaming: false),
      systemPrompt: 'system',
      messages: const [],
      tools: const [
        ModelToolDefinition(
          name: 'read_workspace_file',
          description: 'Read a workspace file.',
          parameters: {
            'type': 'object',
            'properties': {
              'workspaceId': {'type': 'string'},
              'relativePath': {'type': 'string'},
            },
            'required': ['workspaceId', 'relativePath'],
          },
        ),
      ],
    );

    expect(sentBody['tool_choice'], 'auto');
    final tools = sentBody['tools'] as List<Object?>;
    expect(tools, hasLength(1));
    expect(
      tools.single,
      containsPair('type', 'function'),
    );
    expect(jsonEncode(tools), contains('read_workspace_file'));
    expect(completion.content, isEmpty);
    expect(completion.toolCalls, hasLength(1));
    expect(completion.toolCalls.single.id, 'call-read');
    expect(completion.toolCalls.single.name, 'read_workspace_file');
    expect(
      completion.toolCalls.single.arguments,
      '{"workspaceId":"workspace-1","relativePath":"README.md"}',
    );
    expect(completion.diagnostics!.toolCallCount, 1);
    expect(jsonEncode(completion.diagnostics!.toJson()),
        isNot(contains('test-secret')));
  });

  test('sends assistant tool calls and tool result messages', () async {
    late Map<String, Object?> sentBody;
    unawaited(serve(server, (request) async {
      requests.add(request);
      sentBody =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'choices': [
            {
              'message': {'content': 'final'}
            }
          ],
        }));
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway();

    await gateway.completeWithMetadata(
      model: model().copyWith(streaming: false),
      systemPrompt: 'system',
      messages: const [],
      toolRounds: const [
        ModelToolRound(
          calls: [
            ModelToolCall(
              id: 'call-read',
              name: 'read_workspace_file',
              arguments: '{"workspaceId":"workspace-1"}',
            ),
          ],
          results: [
            ModelToolResult(
              toolCallId: 'call-read',
              name: 'read_workspace_file',
              content: '{"ok":true,"content":"hello"}',
            ),
          ],
        ),
      ],
    );

    final messages = sentBody['messages'] as List<Object?>;
    expect(messages[messages.length - 2], containsPair('role', 'assistant'));
    expect(jsonEncode(messages[messages.length - 2]), contains('tool_calls'));
    expect(messages.last, containsPair('role', 'tool'));
    expect(messages.last, containsPair('tool_call_id', 'call-read'));
    expect(messages.last,
        containsPair('content', '{"ok":true,"content":"hello"}'));
  });

  test('parses real reasoning content from non-streaming responses', () async {
    unawaited(serve(server, (request) async {
      requests.add(request);
      await utf8.decodeStream(request);
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'choices': [
            {
              'message': {
                'content': 'final answer',
                'reasoning_content': 'visible reasoning from provider',
              }
            }
          ]
        }));
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway();

    final completion = await gateway.completeWithMetadata(
      model: model().copyWith(streaming: false),
      systemPrompt: 'system',
      messages: const [],
    );

    expect(completion.content, 'final answer');
    expect(completion.thinkingContent, 'visible reasoning from provider');
  });

  test('records raw response text in non-streaming diagnostics', () async {
    final rawResponse = jsonEncode({
      'choices': [
        {
          'message': {
            'content': 'final answer',
            'reasoning_content': 'private reasoning',
          }
        }
      ]
    });
    unawaited(serve(server, (request) async {
      requests.add(request);
      await utf8.decodeStream(request);
      request.response
        ..headers.contentType = ContentType.json
        ..write(rawResponse);
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway();

    final completion = await gateway.completeWithMetadata(
      model: model().copyWith(streaming: false),
      systemPrompt: 'system',
      messages: const [],
    );

    expect(completion.diagnostics, isNotNull);
    expect(completion.diagnostics!.streaming, isFalse);
    expect(completion.diagnostics!.contentLength, 'final answer'.length);
    expect(
      completion.diagnostics!.thinkingContentLength,
      'private reasoning'.length,
    );
    expect(completion.diagnostics!.thinkingFieldKeys, ['reasoning_content']);
    expect(
      completion.diagnostics!.rawResponse,
      rawResponse,
    );
    expect(
      completion.diagnostics!.toJson()['rawResponse'],
      rawResponse,
    );
  });

  test('records token usage and cache hits in response diagnostics', () async {
    unawaited(serve(server, (request) async {
      requests.add(request);
      await utf8.decodeStream(request);
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'choices': [
            {
              'message': {'content': 'usage response'}
            }
          ],
          'usage': {
            'prompt_tokens': 3100,
            'completion_tokens': 700,
            'total_tokens': 3800,
            'prompt_tokens_details': {'cached_tokens': 900},
          },
        }));
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway();

    final completion = await gateway.completeWithMetadata(
      model: model().copyWith(streaming: false),
      systemPrompt: 'system',
      messages: const [],
    );

    expect(completion.inputTokens, 3100);
    expect(completion.outputTokens, 700);
    expect(completion.cachedTokens, 900);
    expect(completion.totalTokens, 3800);
    expect(completion.diagnostics!.toJson()['inputTokens'], 3100);
    expect(completion.diagnostics!.toJson()['cachedTokens'], 900);
  });

  test(
      'records request body diagnostics while preserving max_tokens by default',
      () async {
    late Map<String, Object?> sentBody;
    unawaited(serve(server, (request) async {
      requests.add(request);
      sentBody =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'choices': [
            {
              'message': {'content': 'default response'}
            }
          ]
        }));
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway();

    final completion = await gateway.completeWithMetadata(
      model: model().copyWith(streaming: false, maxTokens: 321),
      systemPrompt: 'system prompt',
      messages: const [],
    );

    expect(sentBody['max_tokens'], 321);
    expect(sentBody, isNot(contains('reasoning_effort')));
    expect(sentBody, isNot(contains('max_completion_tokens')));
    expect(completion.diagnostics!.requestBody, sentBody);
    expect(
      completion.diagnostics!.requestUrl,
      'http://${server.address.host}:${server.port}/v1/chat/completions',
    );
    expect(completion.diagnostics!.toJson()['requestBody'], sentBody);
    expect(
      completion.diagnostics!.toJson()['requestUrl'],
      'http://${server.address.host}:${server.port}/v1/chat/completions',
    );
    expect(jsonEncode(completion.diagnostics!.requestBody),
        isNot(contains('test-secret')));
    expect(jsonEncode(completion.diagnostics!.toJson()),
        isNot(contains('test-secret')));
  });

  test('sends chat reasoning effort with max_completion_tokens when enabled',
      () async {
    late Map<String, Object?> sentBody;
    unawaited(serve(server, (request) async {
      requests.add(request);
      sentBody =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'choices': [
            {
              'message': {'content': 'reasoned response'}
            }
          ]
        }));
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway();

    final completion = await gateway.completeWithMetadata(
      model: model().copyWith(
        streaming: false,
        maxTokens: 654,
        reasoningEffort: 'high',
      ),
      systemPrompt: 'system prompt',
      messages: const [],
    );

    expect(sentBody['reasoning_effort'], 'high');
    expect(sentBody['max_completion_tokens'], 654);
    expect(sentBody, isNot(contains('max_tokens')));
    expect(completion.diagnostics!.requestBody, sentBody);
  });

  test('retries transient server failures before succeeding', () async {
    var attempt = 0;
    unawaited(serve(server, (request) async {
      requests.add(request);
      await utf8.decodeStream(request);
      attempt++;
      if (attempt == 1) {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write('temporary failure');
      } else {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'choices': [
              {
                'message': {'content': 'recovered'}
              }
            ]
          }));
      }
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway(
      maxRetries: 1,
      retryDelay: Duration.zero,
    );

    final content = await gateway.complete(
      model: model().copyWith(streaming: false),
      systemPrompt: 'system',
      messages: const [],
    );

    expect(content, 'recovered');
    expect(requests, hasLength(2));
  });

  test('parses OpenAI compatible streaming deltas', () async {
    unawaited(serve(server, (request) async {
      requests.add(request);
      final body = jsonDecode(await utf8.decodeStream(request)) as Map;
      expect(body['stream'], isTrue);
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response
        ..write('data: {"choices":[{"delta":{"content":"hel"}}]}\n\n')
        ..write('data: {"choices":[{"delta":{"content":"lo"}}]}\n\n')
        ..write('data: [DONE]\n\n');
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway();

    final content = await gateway.complete(
      model: model().copyWith(streaming: true),
      systemPrompt: 'system',
      messages: const [],
    );

    expect(content, 'hello');
    expect(requests, hasLength(1));
  });

  test('parses real reasoning content from streaming deltas', () async {
    const rawReasoning1 =
        'data: {"choices":[{"delta":{"reasoning_content":"think "}}]}';
    const rawReasoning2 =
        'data: {"choices":[{"delta":{"reasoning_content":"step"}}]}';
    const rawContent = 'data: {"choices":[{"delta":{"content":"answer"}}]}';
    late Map<String, Object?> sentBody;
    unawaited(serve(server, (request) async {
      requests.add(request);
      sentBody =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      expect(sentBody['stream'], isTrue);
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response
        ..write('$rawReasoning1\n\n')
        ..write('$rawReasoning2\n\n')
        ..write('$rawContent\n\n')
        ..write('data: [DONE]\n\n');
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway();

    final completion = await gateway.completeWithMetadata(
      model: model().copyWith(streaming: true),
      systemPrompt: 'system',
      messages: const [],
    );

    expect(completion.content, 'answer');
    expect(completion.thinkingContent, 'think step');
    expect(completion.diagnostics!.streaming, isTrue);
    expect(completion.diagnostics!.contentDeltaCount, 1);
    expect(completion.diagnostics!.thinkingDeltaCount, 2);
    expect(completion.diagnostics!.thinkingFieldKeys, ['reasoning_content']);
    expect(completion.diagnostics!.rawResponse, contains(rawReasoning1));
    expect(completion.diagnostics!.rawResponse, contains(rawReasoning2));
    expect(completion.diagnostics!.rawResponse, contains(rawContent));
    expect(completion.diagnostics!.rawResponse, contains('data: [DONE]'));
    expect(completion.diagnostics!.requestBody, sentBody);
    expect(requests, hasLength(1));
  });

  test('parses streaming tool call deltas split across chunks', () async {
    unawaited(serve(server, (request) async {
      requests.add(request);
      await utf8.decodeStream(request);
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response
        ..write(
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-list","type":"function","function":{"name":"list_workspace_files","arguments":"{\\"workspaceId\\":"}}]}}]}\n\n',
        )
        ..write(
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"workspace-1\\"}"}}]}}]}\n\n',
        )
        ..write('data: [DONE]\n\n');
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway();

    final completion = await gateway.completeWithMetadata(
      model: model().copyWith(streaming: true),
      systemPrompt: 'system',
      messages: const [],
    );

    expect(completion.content, isEmpty);
    expect(completion.toolCalls, hasLength(1));
    expect(completion.toolCalls.single.id, 'call-list');
    expect(completion.toolCalls.single.name, 'list_workspace_files');
    expect(
      completion.toolCalls.single.arguments,
      '{"workspaceId":"workspace-1"}',
    );
    expect(completion.diagnostics!.toolCallCount, 1);
  });

  test('reports streaming reasoning and content deltas before completion',
      () async {
    unawaited(serve(server, (request) async {
      requests.add(request);
      await utf8.decodeStream(request);
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.write(
          'data: {"choices":[{"delta":{"reasoning_content":"think"}}]}\n\n');
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      request.response
        ..write('data: {"choices":[{"delta":{"content":"answer"}}]}\n\n')
        ..write('data: [DONE]\n\n');
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway();
    final deltas = <ModelStreamDelta>[];

    final completion = await gateway.completeWithMetadata(
      model: model().copyWith(streaming: true),
      systemPrompt: 'system',
      messages: const [],
      onDelta: deltas.add,
    );

    expect(completion.thinkingContent, 'think');
    expect(completion.content, 'answer');
    expect(deltas.map((delta) => delta.thinkingDelta), contains('think'));
    expect(deltas.map((delta) => delta.contentDelta), contains('answer'));
  });

  test('fails with a gateway exception when request times out', () async {
    unawaited(serve(server, (request) async {
      requests.add(request);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway(
      requestTimeout: const Duration(milliseconds: 20),
      maxRetries: 0,
    );

    await expectLater(
      gateway.complete(
        model: model(),
        systemPrompt: 'system',
        messages: const [],
      ),
      throwsA(isA<ModelGatewayException>()
          .having((error) => error.message, 'message', contains('超时'))),
    );
  });

  test('cancels an in-flight model request', () async {
    unawaited(serve(server, (request) async {
      requests.add(request);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway(
      requestTimeout: const Duration(seconds: 5),
      maxRetries: 0,
    );
    final cancellation = ModelRequestCancellation();
    final future = gateway.complete(
      model: model(),
      systemPrompt: 'system',
      messages: const [],
      cancellation: cancellation,
    );

    cancellation.cancel();

    await expectLater(
      future,
      throwsA(isA<ModelGatewayException>()
          .having((error) => error.message, 'message', contains('已取消'))),
    );
  });

  test('cancels while waiting for the next streaming event', () async {
    final streamOpened = Completer<void>();
    final releaseResponse = Completer<void>();
    addTearDown(() {
      if (!releaseResponse.isCompleted) {
        releaseResponse.complete();
      }
    });
    unawaited(serve(server, (request) async {
      requests.add(request);
      await utf8.decodeStream(request);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType =
            ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.write(
        'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
      );
      await request.response.flush();
      if (!streamOpened.isCompleted) {
        streamOpened.complete();
      }
      await releaseResponse.future;
      await request.response.close();
    }));
    final gateway = OpenAiCompatibleGateway(
      requestTimeout: const Duration(seconds: 5),
      maxRetries: 0,
    );
    final cancellation = ModelRequestCancellation();
    final future = gateway.completeWithMetadata(
      model: model().copyWith(streaming: true),
      systemPrompt: 'system',
      messages: const [],
      cancellation: cancellation,
    );

    await streamOpened.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    cancellation.cancel();

    await expectLater(
      future.timeout(const Duration(milliseconds: 250)),
      throwsA(isA<ModelGatewayException>()
          .having((error) => error.message, 'message', contains('已取消'))),
    );
  });
}

Future<void> serve(
  HttpServer server,
  Future<void> Function(HttpRequest request) handler,
) async {
  await for (final request in server) {
    await handler(request);
  }
}
