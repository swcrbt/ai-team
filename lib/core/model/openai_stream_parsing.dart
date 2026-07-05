import 'dart:async';

import 'gateway_contracts.dart';
import 'model_gateway_exception.dart';

Future<bool> moveNextStreamingLine(
  StreamIterator<String> iterator,
  ModelRequestCancellation? cancellation,
) {
  if (cancellation == null) {
    return iterator.moveNext();
  }
  return Future.any<bool>([
    iterator.moveNext(),
    cancellation.cancelled.then<bool>(
      (_) => throw const ModelGatewayException('模型请求已取消'),
    ),
  ]);
}

List<ModelToolCall> parseToolCalls(Object? value) {
  if (value is! List) {
    return const [];
  }
  final calls = <ModelToolCall>[];
  for (final item in value) {
    if (item is! Map) {
      continue;
    }
    final json = Map<String, Object?>.from(item);
    final function = json['function'];
    if (function is! Map) {
      continue;
    }
    final functionJson = Map<String, Object?>.from(function);
    final id = json['id'];
    final name = functionJson['name'];
    final arguments = functionJson['arguments'];
    if (id is String && name is String) {
      calls.add(
        ModelToolCall(
          id: id,
          name: name,
          arguments: arguments is String ? arguments : '',
        ),
      );
    }
  }
  return calls;
}

List<Map<String, Object?>> rawToolCalls(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}

void appendStreamingToolCalls(
  Object? value,
  Map<int, StreamingToolCallBuilder> builders,
) {
  if (value is! List) {
    return;
  }
  for (final item in value) {
    if (item is! Map) {
      continue;
    }
    final json = Map<String, Object?>.from(item);
    final indexValue = json['index'];
    if (indexValue is! num) {
      continue;
    }
    final index = indexValue.toInt();
    final builder = builders.putIfAbsent(
      index,
      () => StreamingToolCallBuilder(),
    );
    final id = json['id'];
    if (id is String && id.isNotEmpty) {
      builder.id = id;
    }
    final function = json['function'];
    if (function is Map) {
      final functionJson = Map<String, Object?>.from(function);
      final name = functionJson['name'];
      if (name is String && name.isNotEmpty) {
        builder.name = name;
      }
      final arguments = functionJson['arguments'];
      if (arguments is String) {
        builder.arguments.write(arguments);
      }
    }
  }
}

List<ModelToolCall> completeStreamingToolCalls(
  Map<int, StreamingToolCallBuilder> builders,
) {
  final indexes = builders.keys.toList()..sort();
  return [
    for (final index in indexes)
      if (builders[index]!.isComplete) builders[index]!.build(),
  ];
}

class StreamingToolCallBuilder {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();

  bool get isComplete => id != null && name != null;

  ModelToolCall build() => ModelToolCall(
        id: id!,
        name: name!,
        arguments: arguments.toString(),
      );
}

String? firstStringValue(
  Map<String, Object?>? json,
  List<String> keys, {
  Set<String>? keysSeen,
}) {
  if (json == null) {
    return null;
  }
  for (final key in keys) {
    if (json.containsKey(key)) {
      keysSeen?.add(key);
    }
    final value = json[key];
    if (value is String) {
      final normalized = normalizeOptionalText(value);
      if (normalized != null) {
        return normalized;
      }
    }
  }
  return null;
}

String? normalizeOptionalText(String value) {
  return value.trim().isEmpty ? null : value;
}

ModelTokenUsage parseTokenUsage(Object? value) {
  if (value is! Map) {
    return const ModelTokenUsage();
  }
  final usage = Map<String, Object?>.from(value);
  final inputTokens = _firstInt(usage, const [
    'prompt_tokens',
    'input_tokens',
  ]);
  final outputTokens = _firstInt(usage, const [
    'completion_tokens',
    'output_tokens',
  ]);
  final totalTokens = _firstInt(usage, const ['total_tokens']);
  final cachedTokens = _cachedTokenCount(usage);
  return ModelTokenUsage(
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    cachedTokens: cachedTokens,
    totalTokens: totalTokens,
  );
}

int? _cachedTokenCount(Map<String, Object?> usage) {
  final direct = _firstInt(usage, const [
    'cached_tokens',
    'cache_read_input_tokens',
    'prompt_cache_hit_tokens',
  ]);
  if (direct != null) {
    return direct;
  }
  final promptDetails = usage['prompt_tokens_details'];
  if (promptDetails is Map) {
    return _firstInt(Map<String, Object?>.from(promptDetails), const [
      'cached_tokens',
    ]);
  }
  final inputDetails = usage['input_tokens_details'];
  if (inputDetails is Map) {
    return _firstInt(Map<String, Object?>.from(inputDetails), const [
      'cached_tokens',
      'cache_read',
    ]);
  }
  return null;
}

int? _firstInt(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) {
      return value.toInt();
    }
  }
  return null;
}

class ModelTokenUsage {
  const ModelTokenUsage({
    this.inputTokens,
    this.outputTokens,
    this.cachedTokens,
    this.totalTokens,
  });

  final int? inputTokens;
  final int? outputTokens;
  final int? cachedTokens;
  final int? totalTokens;

  bool get isEmpty =>
      inputTokens == null &&
      outputTokens == null &&
      cachedTokens == null &&
      totalTokens == null;
}
