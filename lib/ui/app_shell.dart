part of '../app.dart';

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

const _reasoningEffortOffValue = '';
const _reasoningEffortValues = [
  'none',
  'minimal',
  'low',
  'medium',
  'high',
  'xhigh'
];
const _reasoningEffortLabels = <String, String>{
  _reasoningEffortOffValue: '关闭',
  'none': 'none',
  'minimal': 'minimal',
  'low': 'low',
  'medium': 'medium',
  'high': 'high',
  'xhigh': 'xhigh',
};

class AiTeamApp extends StatelessWidget {
  const AiTeamApp({
    super.key,
    required this.initialState,
    required this.modelGateway,
    this.onStateChanged,
    this.fileDialogs = const SystemFileDialogService(),
    this.chatScrollDiagnostics,
  });

  final AppState initialState;
  final ModelGateway modelGateway;
  final StateChanged? onStateChanged;
  final FileDialogService fileDialogs;
  final ChatScrollDiagnostics? chatScrollDiagnostics;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Team',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
      ),
      home: AiTeamHome(
        initialState: initialState,
        modelGateway: modelGateway,
        onStateChanged: onStateChanged,
        fileDialogs: fileDialogs,
        chatScrollDiagnostics: chatScrollDiagnostics,
      ),
    );
  }
}

class AiTeamHome extends StatefulWidget {
  const AiTeamHome({
    super.key,
    required this.initialState,
    required this.modelGateway,
    this.onStateChanged,
    this.fileDialogs = const SystemFileDialogService(),
    this.chatScrollDiagnostics,
  });

  final AppState initialState;
  final ModelGateway modelGateway;
  final StateChanged? onStateChanged;
  final FileDialogService fileDialogs;
  final ChatScrollDiagnostics? chatScrollDiagnostics;

  @override
  State<AiTeamHome> createState() => _AiTeamHomeState();
}

class _AiTeamHomeState extends State<AiTeamHome> {
  late AppController controller;
  final chatPaneKeys = <String, GlobalKey<_ChatPaneState>>{};
  _MainView mainView = _MainView.chat;

  @override
  void initState() {
    super.initState();
    controller = AppController(
      widget.initialState,
      TeamOrchestrator(widget.modelGateway),
      onStateChanged: widget.onStateChanged,
      fileDialogs: widget.fileDialogs,
      diagnostics: widget.chatScrollDiagnostics,
    );
  }

  @override
  void dispose() {
    unawaited(controller.flushPersistence());
    controller.dispose();
    super.dispose();
  }

  void _showMainView(_MainView view) {
    setState(() => mainView = view);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        widget.chatScrollDiagnostics?.appBuildCount++;
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final conversationListWidth =
                    (constraints.maxWidth * 0.28).clamp(300.0, 360.0);
                return Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: _AppSidebar(
                        selectedView: mainView,
                        onChat: () => _showMainView(_MainView.chat),
                        onTeam: () => _showMainView(_MainView.teams),
                        onModels: () => _showMainView(_MainView.models),
                        onRoles: () => _showMainView(_MainView.roles),
                        onMembers: () => _showMainView(_MainView.members),
                        onHistory: () => _showMainView(_MainView.history),
                        onAudit: () => _showMainView(_MainView.audit),
                        onProject: () => _showMainView(_MainView.project),
                        onSettings: () => _showMainView(_MainView.settings),
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Offstage(
                            offstage: mainView != _MainView.chat,
                            child: _buildChatWorkspace(conversationListWidth),
                          ),
                          if (mainView != _MainView.chat) _buildSecondaryView(),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatWorkspace(double conversationListWidth) {
    final paneConversations = controller.openConversationPanes;
    final visibleConversationIds = paneConversations
        .map(
          (conversation) => conversation.id,
        )
        .toSet();
    chatPaneKeys.removeWhere(
      (conversationId, key) => !visibleConversationIds.contains(conversationId),
    );
    final selectedIndex = paneConversations.indexWhere(
      (conversation) => conversation.id == controller.selectedConversationId,
    );
    return Row(
      children: [
        SizedBox(
          width: conversationListWidth,
          child: _ConversationList(
            controller: controller,
            selectedView: mainView,
            onSelectConversation: (conversationId) {
              controller.selectConversation(conversationId);
              setState(() => mainView = _MainView.chat);
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: IndexedStack(
            index: selectedIndex < 0 ? 0 : selectedIndex,
            children: paneConversations
                .map(
                  (conversation) => _ChatPane(
                    key: chatPaneKeys.putIfAbsent(
                      conversation.id,
                      () => GlobalKey<_ChatPaneState>(
                        debugLabel: 'chat-pane-${conversation.id}',
                      ),
                    ),
                    controller: controller,
                    conversationId: conversation.id,
                    diagnostics: widget.chatScrollDiagnostics,
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSecondaryView() {
    return switch (mainView) {
      _MainView.teams => _TeamManagementPage(
          controller: controller,
          onStartChat: () => _showMainView(_MainView.chat),
        ),
      _MainView.models => _ModelManagementPage(controller: controller),
      _MainView.roles => _RoleManagementPage(controller: controller),
      _MainView.members => _MemberManagementPage(
          controller: controller,
          onStartChat: () => _showMainView(_MainView.chat),
        ),
      _MainView.history => _HistoryPage(controller: controller),
      _MainView.audit => _AuditLogPage(controller: controller),
      _MainView.project => _ProjectPage(controller: controller),
      _MainView.settings => _SettingsPage(controller: controller),
      _MainView.chat => const SizedBox.shrink(),
    };
  }
}

enum _MainView {
  chat,
  teams,
  models,
  roles,
  members,
  history,
  audit,
  project,
  settings,
}
