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
    unawaited(serve(server, (request) async {
      requests.add(request);
      final body = jsonDecode(await utf8.decodeStream(request)) as Map;
      expect(body['stream'], isTrue);
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
    expect(requests, hasLength(1));
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
}

Future<void> serve(
  HttpServer server,
  Future<void> Function(HttpRequest request) handler,
) async {
  await for (final request in server) {
    await handler(request);
  }
}
