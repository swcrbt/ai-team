part of '../app.dart';

class _ConversationList extends StatefulWidget {
  const _ConversationList({
    required this.controller,
    required this.selectedView,
    required this.onSelectConversation,
  });

  final AppController controller;
  final _MainView selectedView;
  final ValueChanged<String> onSelectConversation;

  @override
  State<_ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<_ConversationList> {
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
    return ColoredBox(
      color: const Color(0xFFF7F8FB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        hintText: '搜索',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: '新增',
                  onPressed: () =>
                      _showMemberDialog(context, widget.controller),
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleConversationListScrollNotification,
              child: ListView.separated(
                key: const ValueKey('conversation-list'),
                controller: conversationScrollController,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: visibleConversations.length,
                separatorBuilder: (context, index) => const Divider(
                  height: 1,
                  indent: 72,
                  color: Color(0xFFE5E7EB),
                ),
                itemBuilder: (context, index) {
                  final conversation = visibleConversations[index];
                  return _RailTile(
                    key: ValueKey('conversation-row-${conversation.id}'),
                    icon: _conversationListIcon(
                      widget.controller,
                      conversation,
                    ),
                    title: _conversationListTitle(
                      widget.controller,
                      conversation,
                    ),
                    subtitle: _conversationListSubtitle(
                      widget.controller,
                      conversation,
                    ),
                    badge: _conversationListBadge(
                      widget.controller,
                      conversation,
                    ),
                    selected: widget.selectedView == _MainView.chat &&
                        widget.controller.selectedConversationId ==
                            conversation.id,
                    pinned:
                        widget.controller.isConversationPinned(conversation.id),
                    onTap: () => widget.onSelectConversation(conversation.id),
                    onContextMenu: (position) => _showConversationContextMenu(
                      context,
                      position,
                      widget.controller,
                      conversation.id,
                    ),
                  );
                },
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
      PopupMenuItem(
        value: 'pin',
        child: Text(isPinned ? '取消置顶' : '置顶'),
      ),
      const PopupMenuItem(
        value: 'delete',
        child: Text('删除'),
      ),
    ],
  );
  if (action == 'pin') {
    controller.togglePinnedConversation(conversationId);
  } else if (action == 'delete') {
    controller.closeConversation(conversationId);
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
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
  final bool selected;
  final bool pinned;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final titleColor = selected ? Colors.white : const Color(0xFF111827);
    final subtitleColor = selected
        ? Colors.white.withValues(alpha: 0.82)
        : const Color(0xFF4B5563);
    final iconColor = selected ? Colors.white : const Color(0xFF2563EB);
    final avatarColor = selected
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFEFF6FF);
    final backgroundColor = selected
        ? const Color(0xFF2F80ED)
        : pinned
            ? const Color(0xFFE9EDF3)
            : Colors.transparent;
    return Padding(
      padding: EdgeInsets.zero,
      child: GestureDetector(
        onSecondaryTapDown: (details) {
          onContextMenu?.call(details.globalPosition);
        },
        child: Material(
          color: backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListTile(
            dense: true,
            minLeadingWidth: 38,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            onTap: onTap,
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: avatarColor,
              child: Icon(icon, size: 18, color: iconColor),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: titleColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Color(0xFFD97706),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: subtitleColor),
            ),
          ),
        ),
      ),
    );
  }
}
