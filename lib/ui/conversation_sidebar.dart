import 'package:flutter/material.dart';

import '../application/app_controller.dart';
import '../core/domain.dart';
import 'app_helpers.dart';
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
  late final TextEditingController searchController;
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    conversationScrollController = ScrollController(
      initialScrollOffset: widget.controller.conversationListScrollOffset,
      keepScrollOffset: false,
    );
    searchController = TextEditingController();
  }

  @override
  void dispose() {
    _saveConversationListScrollOffset();
    conversationScrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleConversations = widget.controller.visibleConversations;

    // 应用搜索过滤
    final filteredConversations = searchQuery.isEmpty
        ? visibleConversations
        : visibleConversations.where((conversation) {
            final titleLower =
                conversationListTitle(widget.controller, conversation)
                    .toLowerCase();
            final subtitleLower =
                conversationListSubtitle(widget.controller, conversation)
                    .toLowerCase();
            final searchLower = searchQuery.toLowerCase();

            // 搜索会话标题和副标题
            if (titleLower.contains(searchLower) ||
                subtitleLower.contains(searchLower)) {
              return true;
            }

            // 搜索成员名称（如果是私聊）
            if (conversation.memberId != null) {
              final member = widget.controller.state.members
                  .where((m) => m.id == conversation.memberId)
                  .firstOrNull;
              if (member != null &&
                  member.name.toLowerCase().contains(searchLower)) {
                return true;
              }
            }

            // 搜索团队名称
            final team = widget.controller.state.teams
                .where((t) => t.id == conversation.teamId)
                .firstOrNull;
            if (team != null && team.name.toLowerCase().contains(searchLower)) {
              return true;
            }

            return false;
          }).toList();

    final groupConversations = filteredConversations
        .where((conversation) => conversation.memberId == null)
        .toList();
    final privateConversations = filteredConversations
        .where((conversation) => conversation.memberId != null)
        .toList();
    return ColoredBox(
      color: const Color(0xFFEBEDEF),
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
                Builder(
                  builder: (buttonContext) => IconButton(
                    tooltip: '新增会话',
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
                    onPressed: () => _showStartConversationMenu(buttonContext),
                    icon: const Icon(Icons.add_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: SizedBox(
              height: 30,
              child: TextField(
                controller: searchController,
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
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFE1E5EA)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                  ),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () {
                            searchController.clear();
                            setState(() {
                              searchQuery = '';
                            });
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: '清除搜索',
                        )
                      : null,
                ),
                onChanged: (value) {
                  setState(() {
                    searchQuery = value;
                  });
                },
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

  Future<void> _showStartConversationMenu(BuildContext buttonContext) async {
    final buttonBox = buttonContext.findRenderObject() as RenderBox;
    final overlayBox = Navigator.of(buttonContext)
        .overlay!
        .context
        .findRenderObject() as RenderBox;
    final buttonRect = Rect.fromPoints(
      buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox),
      buttonBox.localToGlobal(
        buttonBox.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      ),
    );
    final action = await showMenu<String>(
      context: buttonContext,
      position: RelativeRect.fromRect(
        buttonRect,
        Offset.zero & overlayBox.size,
      ),
      items: [
        const PopupMenuItem<String>(enabled: false, child: Text('群聊')),
        for (final team in widget.controller.state.teams)
          PopupMenuItem<String>(
            value: 'team:${team.id}',
            child: Row(
              children: [
                const Icon(Icons.forum_rounded, size: 18),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    team.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(enabled: false, child: Text('私聊')),
        for (final member in widget.controller.currentMembers)
          PopupMenuItem<String>(
            value: 'member:${member.id}',
            child: Row(
              children: [
                Icon(
                  member.isSecretary
                      ? Icons.assignment_ind_rounded
                      : Icons.person_rounded,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    member.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (!mounted || action == null) {
      return;
    }
    if (action.startsWith('team:')) {
      widget.controller.startTeamChat(action.substring('team:'.length));
    } else if (action.startsWith('member:')) {
      widget.controller.startMemberChat(action.substring('member:'.length));
    }
    widget.onSelectConversation(widget.controller.selectedConversationId);
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
    const titleColor = Color(0xFF202328);
    const subtitleColor = Color(0xFF6B7280);
    final backgroundColor = selected
        ? Colors.white
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
            color: selected ? const Color(0xFFD9DDE2) : Colors.transparent,
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
                              style: const TextStyle(
                                color: titleColor,
                                fontWeight: FontWeight.w700,
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
                        style:
                            const TextStyle(color: subtitleColor, fontSize: 12),
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
