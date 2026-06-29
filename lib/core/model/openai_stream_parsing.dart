part of '../model_gateway.dart';

Future<bool> _moveNextStreamingLine(
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

List<ModelToolCall> _parseToolCalls(Object? value) {
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

List<Map<String, Object?>> _rawToolCalls(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}

void _appendStreamingToolCalls(
  Object? value,
  Map<int, _StreamingToolCallBuilder> builders,
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
      () => _StreamingToolCallBuilder(),
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

List<ModelToolCall> _completeStreamingToolCalls(
  Map<int, _StreamingToolCallBuilder> builders,
) {
  final indexes = builders.keys.toList()..sort();
  return [
    for (final index in indexes)
      if (builders[index]!.isComplete) builders[index]!.build(),
  ];
}

class _StreamingToolCallBuilder {
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

String? _firstStringValue(
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
      final normalized = _normalizeOptionalText(value);
      if (normalized != null) {
        return normalized;
      }
    }
  }
  return null;
}

String? _normalizeOptionalText(String value) {
  return value.trim().isEmpty ? null : value;
}
