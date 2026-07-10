import 'dart:async';

import 'package:flutter/material.dart';

import '../application/app_controller.dart';
import '../application/chat_streaming.dart';
import '../core/domain.dart';
import '../core/file_dialogs.dart';
import '../core/model_gateway.dart';
import '../core/orchestrator.dart';
import '../core/storage_directories.dart';
import '../core/workspace/image_paste_service.dart';
import 'chat/chat_pane.dart';
import 'conversation_sidebar.dart';
import 'main_view.dart';
import 'management/management_pages.dart';
import 'sidebar.dart';

class AiTeamApp extends StatelessWidget {
  const AiTeamApp({
    super.key,
    required this.initialState,
    required this.modelGateway,
    this.onStateChanged,
    this.fileDialogs = const SystemFileDialogService(),
    this.chatScrollDiagnostics,
    this.storageDirectories,
    this.storageDirectoryConfigStore,
    this.imagePasteServiceFactory,
  });

  final AppState initialState;
  final ModelGateway modelGateway;
  final StateChanged? onStateChanged;
  final FileDialogService fileDialogs;
  final ChatScrollDiagnostics? chatScrollDiagnostics;
  final StorageDirectories? storageDirectories;
  final StorageDirectoryConfigStore? storageDirectoryConfigStore;
  final ImagePasteService Function(String conversationId)?
      imagePasteServiceFactory;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1779E1),
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF1779E1),
      surface: Colors.white,
      onSurface: const Color(0xFF202328),
      outline: const Color(0xFFD9DDE2),
      outlineVariant: const Color(0xFFE6E9EC),
    );
    final baseTextTheme = ThemeData.light().textTheme;
    return MaterialApp(
      title: 'AI Team',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF5F7F9),
        dividerColor: const Color(0xFFD9DDE2),
        textTheme: baseTextTheme.copyWith(
          bodyLarge:
              baseTextTheme.bodyLarge?.copyWith(fontSize: 13, height: 1.45),
          bodyMedium:
              baseTextTheme.bodyMedium?.copyWith(fontSize: 13, height: 1.45),
          bodySmall:
              baseTextTheme.bodySmall?.copyWith(fontSize: 12, height: 1.4),
          titleMedium: baseTextTheme.titleMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          labelLarge: baseTextTheme.labelLarge?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
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
        storageDirectories: storageDirectories,
        storageDirectoryConfigStore: storageDirectoryConfigStore,
        imagePasteServiceFactory: imagePasteServiceFactory,
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
    this.storageDirectories,
    this.storageDirectoryConfigStore,
    this.imagePasteServiceFactory,
  });

  final AppState initialState;
  final ModelGateway modelGateway;
  final StateChanged? onStateChanged;
  final FileDialogService fileDialogs;
  final ChatScrollDiagnostics? chatScrollDiagnostics;
  final StorageDirectories? storageDirectories;
  final StorageDirectoryConfigStore? storageDirectoryConfigStore;
  final ImagePasteService Function(String conversationId)?
      imagePasteServiceFactory;

  @override
  State<AiTeamHome> createState() => _AiTeamHomeState();
}

class _AiTeamHomeState extends State<AiTeamHome> {
  late AppController controller;
  final chatPaneKeys = <String, GlobalKey<ChatPaneState>>{};
  MainView mainView = MainView.chat;

  @override
  void initState() {
    super.initState();
    controller = AppController(
      widget.initialState,
      TeamOrchestrator(widget.modelGateway),
      onStateChanged: widget.onStateChanged,
      fileDialogs: widget.fileDialogs,
      diagnostics: widget.chatScrollDiagnostics,
      storageDirectories: widget.storageDirectories,
      storageDirectoryConfigStore: widget.storageDirectoryConfigStore,
    );
  }

  @override
  void dispose() {
    unawaited(controller.flushPersistence());
    controller.dispose();
    super.dispose();
  }

  void _showMainView(MainView view) {
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
                    constraints.maxWidth < 900 ? 260.0 : 282.0;
                final expandedSidebar = constraints.maxWidth >= 1100 &&
                    _usesExpandedSidebar(mainView);
                return Row(
                  children: [
                    SizedBox(
                      key: const ValueKey('primary-sidebar-width'),
                      width: expandedSidebar ? 216 : 64,
                      child: AppSidebar(
                        selectedView: mainView,
                        expanded: expandedSidebar,
                        onChat: () => _showMainView(MainView.chat),
                        onTeam: () => _showMainView(MainView.teams),
                        onModels: () => _showMainView(MainView.models),
                        onRoles: () => _showMainView(MainView.roles),
                        onMembers: () => _showMainView(MainView.members),
                        onAudit: () => _showMainView(MainView.audit),
                        onProject: () => _showMainView(MainView.project),
                        onSettings: () => _showMainView(MainView.settings),
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Offstage(
                            offstage: mainView != MainView.chat,
                            child: _buildChatWorkspace(conversationListWidth),
                          ),
                          if (mainView != MainView.chat) _buildSecondaryView(),
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

  bool _usesExpandedSidebar(MainView view) {
    return switch (view) {
      MainView.chat || MainView.project => false,
      MainView.teams ||
      MainView.models ||
      MainView.roles ||
      MainView.members ||
      MainView.audit ||
      MainView.settings =>
        true,
    };
  }

  Widget _buildChatWorkspace(double conversationListWidth) {
    final paneConversations = controller.openConversationPanes;
    final visibleConversationIds =
        paneConversations.map((conversation) => conversation.id).toSet();
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
          child: ConversationList(
            controller: controller,
            selectedView: mainView,
            onSelectConversation: (conversationId) {
              controller.selectConversation(conversationId);
              setState(() => mainView = MainView.chat);
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: IndexedStack(
            index: selectedIndex < 0 ? 0 : selectedIndex,
            children: paneConversations
                .map(
                  (conversation) => ChatPane(
                    key: chatPaneKeys.putIfAbsent(
                      conversation.id,
                      () => GlobalKey<ChatPaneState>(
                        debugLabel: 'chat-pane-${conversation.id}',
                      ),
                    ),
                    controller: controller,
                    conversationId: conversation.id,
                    diagnostics: widget.chatScrollDiagnostics,
                    imagePasteService:
                        widget.imagePasteServiceFactory?.call(conversation.id),
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
      MainView.teams => TeamManagementPage(
          controller: controller,
          onStartChat: () => _showMainView(MainView.chat),
        ),
      MainView.models => ModelManagementPage(controller: controller),
      MainView.roles => RoleManagementPage(controller: controller),
      MainView.members => MemberManagementPage(
          controller: controller,
          onStartChat: () => _showMainView(MainView.chat),
        ),
      MainView.audit => AuditLogPage(controller: controller),
      MainView.project => ProjectPage(controller: controller),
      MainView.settings => SettingsPage(controller: controller),
      MainView.chat => const SizedBox.shrink(),
    };
  }
}
