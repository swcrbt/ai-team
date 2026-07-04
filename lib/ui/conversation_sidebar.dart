import 'package:flutter/material.dart';

import '../application/app_controller.dart';
import '../core/domain.dart';
import 'app_helpers.dart';
import 'dialogs/config_dialogs.dart';
import 'main_view.dart';

class ConversationList extends StatefulWidget {
  const ConversationList({
    super.key,
    required this.controller,
    required this.selectedView,
    required this.onSelectConversation,
  });

  final AppController controller;
  final MainView selectedView;
  final ValueChanged<String> onSelectConversation;

  @override
  State<ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<ConversationList> {
  late final ScrollController conversationScrollController;

  @override
  void initState() {
    super.initState();
    conversationScrollController = ScrollController(
      initialScrollOffset: widget.controller.conversationListScrollOffset,
      keepScrollOffset: false,
    );
  }

  @override
  void dispose() {
    _saveConversationListScrollOffset();
    conversationScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleConversations = widget.controller.visibleConversations;
    final groupConversations = visibleConversations
        .where((conversation) => conversation.memberId == null)
        .toList();
    final privateConversations = visibleConversations
        .where((conversation) => conversation.memberId != null)
        .toList();
    return ColoredBox(
      color: const Color(0xFFF4F5F7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '消息',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '新增成员',
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(30),
                    minimumSize: const Size.square(30),
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                      side: const BorderSide(color: Color(0xFFE1E5EA)),
                    ),
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF5D6673),
                  ),
                  onPressed: () => showMemberDialog(context, widget.controller),
                  icon: const Icon(Icons.add_rounded, size: 18),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: SizedBox(
              height: 30,
              child: TextField(
                enabled: false,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 17),
                  hintText: '搜索会话、成员、文件',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFE1E5EA)),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFE1E5EA)),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleConversationListScrollNotification,
              child: ListView(
                key: const ValueKey('conversation-list'),
                controller: conversationScrollController,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _ConversationSection(
                    title: '群聊',
                    conversations: groupConversations,
                    controller: widget.controller,
                    selectedView: widget.selectedView,
                    onSelectConversation: widget.onSelectConversation,
                    onContextMenu: (position, conversationId) =>
                        _showConversationContextMenu(
                      context,
                      position,
                      widget.controller,
                      conversationId,
                    ),
                  ),
                  _ConversationSection(
                    title: '私聊',
                    conversations: privateConversations,
                    controller: widget.controller,
                    selectedView: widget.selectedView,
                    onSelectConversation: widget.onSelectConversation,
                    onContextMenu: (position, conversationId) =>
                        _showConversationContextMenu(
                      context,
                      position,
                      widget.controller,
                      conversationId,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _handleConversationListScrollNotification(
    ScrollNotification notification,
  ) {
    if (notification.metrics.axis == Axis.vertical) {
      widget.controller.recordConversationListScrollOffset(
        notification.metrics.pixels,
      );
    }
    return false;
  }

  void _saveConversationListScrollOffset() {
    if (!conversationScrollController.hasClients) {
      return;
    }
    final position = conversationScrollController.position;
    final offset = position.pixels
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    widget.controller.recordConversationListScrollOffset(offset);
  }
}

class _ConversationSection extends StatelessWidget {
  const _ConversationSection({
    required this.title,
    required this.conversations,
    required this.controller,
    required this.selectedView,
    required this.onSelectConversation,
    required this.onContextMenu,
  });

  final String title;
  final List<Conversation> conversations;
  final AppController controller;
  final MainView selectedView;
  final ValueChanged<String> onSelectConversation;
  final void Function(Offset position, String conversationId) onContextMenu;

  @override
  Widget build(BuildContext context) {
    if (conversations.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final conversation in conversations)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _ConversationTile(
                key: ValueKey('conversation-row-${conversation.id}'),
                icon: conversationListIcon(controller, conversation),
                title: conversationListTitle(controller, conversation),
                subtitle: conversationListSubtitle(controller, conversation),
                badge: conversationListBadge(controller, conversation),
                statusLabel: conversationStatusPill(controller, conversation),
                selected: selectedView == MainView.chat &&
                    controller.selectedConversationId == conversation.id,
                pinned: controller.isConversationPinned(conversation.id),
                onTap: () => onSelectConversation(conversation.id),
                onContextMenu: (position) =>
                    onContextMenu(position, conversation.id),
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> _showConversationContextMenu(
  BuildContext context,
  Offset position,
  AppController controller,
  String conversationId,
) async {
  final isPinned = controller.isConversationPinned(conversationId);
  final action = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: [
      PopupMenuItem(value: 'pin', child: Text(isPinned ? '取消置顶' : '置顶')),
      const PopupMenuItem(value: 'delete', child: Text('删除')),
    ],
  );
  if (action == 'pin') {
    controller.togglePinnedConversation(conversationId);
  } else if (action == 'delete') {
    controller.closeConversation(conversationId);
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.statusLabel,
    this.selected = false,
    this.pinned = false,
    this.onTap,
    this.onContextMenu,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final String? statusLabel;
  final bool selected;
  final bool pinned;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final titleColor = selected ? Colors.white : const Color(0xFF111827);
    final subtitleColor = selected
        ? Colors.white.withValues(alpha: 0.82)
        : const Color(0xFF667085);
    final iconColor = selected ? Colors.white : const Color(0xFF2563EB);
    final avatarColor = selected
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFEFF6FF);
    final backgroundColor = selected
        ? const Color(0xFF2F80ED)
        : pinned
            ? const Color(0xFFE8EBF0)
            : Colors.transparent;
    return GestureDetector(
      onSecondaryTapDown: (details) {
        onContextMenu?.call(details.globalPosition);
      },
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected ? const Color(0xFF2563EB) : Colors.transparent,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: avatarColor,
                  child: Icon(icon, size: 17, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: titleColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (badge != null) _SmallBadge(label: badge!),
                          if (statusLabel != null) ...[
                            const SizedBox(width: 6),
                            _ConversationStatusPill(label: statusLabel!),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: subtitleColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFD97706),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ConversationStatusPill extends StatelessWidget {
  const _ConversationStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = switch (label) {
      '执行中' => const Color(0xFF2563EB),
      '待审批' => const Color(0xFFB45309),
      '允许中' => const Color(0xFF0F766E),
      '有补丁' => const Color(0xFF6D28D9),
      _ => const Color(0xFF64748B),
    };
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
