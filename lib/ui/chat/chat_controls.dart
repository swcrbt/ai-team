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
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 14,
                                  color: foregroundColor,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '发送',
                                  style: TextStyle(
                                    color: foregroundColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
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

class TokenUsageData {
  const TokenUsageData({
    required this.contextWindowTokens,
    this.inputTokens,
    this.outputTokens,
    this.cachedTokens,
    this.totalTokens,
  });

  final int contextWindowTokens;
  final int? inputTokens;
  final int? outputTokens;
  final int? cachedTokens;
  final int? totalTokens;

  double? get ratio {
    final total = totalTokens;
    if (total == null || contextWindowTokens <= 0) {
      return null;
    }
    return (total / contextWindowTokens).clamp(0, 1);
  }
}

class TokenUsageMeter extends StatefulWidget {
  const TokenUsageMeter({
    super.key,
    required this.data,
  });

  final TokenUsageData data;

  @override
  State<TokenUsageMeter> createState() => _TokenUsageMeterState();
}

class _TokenUsageMeterState extends State<TokenUsageMeter> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final ratio = widget.data.ratio;
    final percent = ratio == null ? '--' : '${(ratio * 100).round()}%';
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: FocusableActionDetector(
        onShowFocusHighlight: (value) => setState(() => hovered = value),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomRight,
          children: [
            Semantics(
              label: 'Token 用量',
              child: Container(
                key: const ValueKey('token-usage-meter'),
                height: 34,
                padding: const EdgeInsets.only(left: 8, right: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomPaint(
                      size: const Size.square(26),
                      painter: _TokenRingPainter(ratio: ratio),
                      child: SizedBox.square(
                        dimension: 26,
                        child: Center(
                          child: Text(
                            percent,
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tokenText(widget.data.totalTokens),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const Text(
                          'tokens',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (hovered)
              Positioned(
                right: 0,
                bottom: 42,
                child: _TokenUsagePopover(data: widget.data),
              ),
          ],
        ),
      ),
    );
  }
}

class _TokenUsagePopover extends StatelessWidget {
  const _TokenUsagePopover({required this.data});

  final TokenUsageData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 232,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TokenRow(
              label: '上下文',
              value:
                  '${_tokenText(data.totalTokens)} / ${_tokenText(data.contextWindowTokens)}',
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              minHeight: 5,
              value: data.ratio,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: const Color(0xFFE5E7EB),
            ),
            const SizedBox(height: 8),
            _TokenRow(label: '输入 tokens', value: _tokenText(data.inputTokens)),
            _TokenRow(label: '输出 tokens', value: _tokenText(data.outputTokens)),
            _TokenRow(label: '命中缓存', value: _tokenText(data.cachedTokens)),
          ],
        ),
      ),
    );
  }
}

class _TokenRow extends StatelessWidget {
  const _TokenRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TokenRingPainter extends CustomPainter {
  const _TokenRingPainter({required this.ratio});

  final double? ratio;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect.deflate(2),
      -1.5708,
      6.28318,
      false,
      stroke..color = const Color(0xFFE2E8F0),
    );
    final value = ratio;
    if (value == null) {
      return;
    }
    canvas.drawArc(
      rect.deflate(2),
      -1.5708,
      6.28318 * value,
      false,
      stroke..color = const Color(0xFF2563EB),
    );
  }

  @override
  bool shouldRepaint(covariant _TokenRingPainter oldDelegate) {
    return oldDelegate.ratio != ratio;
  }
}

String _tokenText(int? value) {
  if (value == null) {
    return '--';
  }
  if (value >= 1000) {
    final rounded = (value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1);
    return '${rounded}k';
  }
  return value.toString();
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
