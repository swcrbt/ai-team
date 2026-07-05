import 'dart:async';

import '../core/domain.dart';

typedef StateChanged = FutureOr<void> Function(AppState state);

class ChatScrollDiagnostics {
  var contentUpdateCount = 0;
  var scrollScheduleCount = 0;
  var actualJumpCount = 0;
  var nearBottomFlipCount = 0;
  var streamingBodyBuildCount = 0;
  var streamingThinkingBuildCount = 0;
  var streamingStableSegmentCommitCount = 0;
  var streamingTailUpdateCount = 0;
  var markdownBodyBuildCount = 0;
  var globalCommitCount = 0;
  var globalNotifyCount = 0;
  var persistenceWriteCount = 0;
  var appBuildCount = 0;
  var chatPaneBuildCount = 0;
  var streamingDraftUpdateCount = 0;
  final messageBubbleBuildCounts = <String, int>{};
  final jumpSamples = <ChatScrollJumpSample>[];

  void reset() {
    contentUpdateCount = 0;
    scrollScheduleCount = 0;
    actualJumpCount = 0;
    nearBottomFlipCount = 0;
    streamingBodyBuildCount = 0;
    streamingThinkingBuildCount = 0;
    streamingStableSegmentCommitCount = 0;
    streamingTailUpdateCount = 0;
    markdownBodyBuildCount = 0;
    globalCommitCount = 0;
    globalNotifyCount = 0;
    persistenceWriteCount = 0;
    appBuildCount = 0;
    chatPaneBuildCount = 0;
    streamingDraftUpdateCount = 0;
    messageBubbleBuildCounts.clear();
    jumpSamples.clear();
  }
}

class ChatScrollJumpSample {
  const ChatScrollJumpSample({
    required this.beforePixels,
    required this.beforeMaxScrollExtent,
    required this.target,
    required this.afterPixels,
    required this.afterMaxScrollExtent,
  });

  final double beforePixels;
  final double beforeMaxScrollExtent;
  final double target;
  final double afterPixels;
  final double afterMaxScrollExtent;
}

class StreamingTextPartitionUpdate {
  const StreamingTextPartitionUpdate({
    required this.reset,
    required this.newStableSegments,
    required this.tailChanged,
  });

  final bool reset;
  final List<String> newStableSegments;
  final bool tailChanged;
}

class StreamingTextPartition {
  final stableSegments = <String>[];
  var lastContent = '';
  var stableCommittedLength = 0;
  var liveTail = '';

  StreamingTextPartitionUpdate apply(String content, {bool reset = false}) {
    var didReset = false;
    if (reset || !content.startsWith(lastContent)) {
      _reset();
      didReset = true;
    }
    if (content.length < stableCommittedLength) {
      _reset();
      didReset = true;
    }

    final newStableSegments = <String>[];
    final stableBoundary = content.lastIndexOf('\n') + 1;
    if (stableBoundary < stableCommittedLength) {
      _reset();
      didReset = true;
    }
    if (stableBoundary > stableCommittedLength) {
      final stableText = content.substring(
        stableCommittedLength,
        stableBoundary,
      );
      stableSegments.add(stableText);
      newStableSegments.add(stableText);
      stableCommittedLength = stableBoundary;
    }

    final nextTail = content.substring(stableCommittedLength);
    final tailChanged = nextTail != liveTail;
    if (tailChanged) {
      liveTail = nextTail;
    }
    lastContent = content;

    return StreamingTextPartitionUpdate(
      reset: didReset,
      newStableSegments: newStableSegments,
      tailChanged: tailChanged,
    );
  }

  void _reset() {
    stableSegments.clear();
    stableCommittedLength = 0;
    liveTail = '';
    lastContent = '';
  }
}

class ChatStreamingDraft {
  const ChatStreamingDraft({
    required this.conversationId,
    required this.message,
  });

  final String conversationId;
  final ChatMessage message;
}
