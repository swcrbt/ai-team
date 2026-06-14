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
          createdAt: DateTime(2026),
          isUser: true,
        ),
      ],
    );

    expect(content, 'hello from model');
    expect(requests, hasLength(1));
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
