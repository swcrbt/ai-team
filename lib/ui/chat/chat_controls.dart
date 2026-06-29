import 'package:flutter/material.dart';

import '../../core/domain.dart';
import '../app_helpers.dart';

enum SendButtonMenuAction { send, stop }

class SplitSendButton extends StatelessWidget {
  const SplitSendButton({
    super.key,
    required this.isDispatching,
    required this.isConversationDispatching,
    required this.onSend,
    required this.onStop,
  });

  final bool isDispatching;
  final bool isConversationDispatching;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final primaryAction = isConversationDispatching
        ? onStop
        : isDispatching
            ? null
            : onSend;
    final menuAction = isConversationDispatching
        ? SendButtonMenuAction.stop
        : isDispatching
            ? null
            : SendButtonMenuAction.send;
    final enabled = primaryAction != null;
    final backgroundColor =
        enabled ? const Color(0xFF0EA5E9) : const Color(0xFFB8DDF0);
    final foregroundColor =
        enabled ? Colors.white : Colors.white.withValues(alpha: 0.72);

    return ClipRRect(
      key: const ValueKey('chat-send-button'),
      borderRadius: BorderRadius.circular(4),
      child: Material(
        color: backgroundColor,
        child: SizedBox(
          height: 32,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: isConversationDispatching ? '停止生成' : '发送',
                child: InkWell(
                  onTap: primaryAction,
                  child: SizedBox(
                    width: 66,
                    height: 32,
                    child: Center(
                      child: isConversationDispatching
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.stop_rounded,
                                  size: 14,
                                  color: foregroundColor,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '停止',
                                  style: TextStyle(
                                    color: foregroundColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              '发送(S)',
                              style: TextStyle(
                                color: foregroundColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 18, color: Colors.white24),
              MenuAnchor(
                alignmentOffset: const Offset(-70, 4),
                menuChildren: [
                  if (menuAction != null)
                    MenuItemButton(
                      onPressed: () {
                        switch (menuAction) {
                          case SendButtonMenuAction.send:
                            onSend();
                          case SendButtonMenuAction.stop:
                            onStop();
                        }
                      },
                      child: Text(
                        menuAction == SendButtonMenuAction.stop ? '停止生成' : '发送',
                      ),
                    ),
                ],
                builder: (context, controller, child) {
                  return Tooltip(
                    message: '发送选项',
                    child: InkWell(
                      onTap: menuAction == null
                          ? null
                          : () {
                              if (controller.isOpen) {
                                controller.close();
                              } else {
                                controller.open();
                              }
                            },
                      child: SizedBox(
                        width: 26,
                        height: 32,
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: foregroundColor,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key, required this.member});

  final TeamMember member;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: avatarColor(member.name),
          child: Text(
            avatarText(member.name),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${member.name} 正在输入中',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
