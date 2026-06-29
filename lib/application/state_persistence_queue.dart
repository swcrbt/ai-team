part of '../app.dart';

class StatePersistenceQueue {
  Future<void> _queue = Future<void>.value();

  Future<void> get idle => _queue;

  void enqueue({
    required AppState snapshot,
    required StateChanged? handler,
    required void Function(String message) onError,
  }) {
    if (handler == null) {
      return;
    }
    final save = _queue.then(
      (_) => Future<void>.sync(() => handler(snapshot)),
    );
    _queue = save.catchError((Object error, StackTrace stackTrace) {
      onError('状态保存失败：$error');
    });
    unawaited(_queue);
  }
}
