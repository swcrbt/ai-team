import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'main_view.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.selectedView,
    required this.onChat,
    required this.onTeam,
    required this.onModels,
    required this.onRoles,
    required this.onMembers,
    required this.onAudit,
    required this.onProject,
    required this.onSettings,
  });

  final MainView selectedView;
  final VoidCallback onChat;
  final VoidCallback onTeam;
  final VoidCallback onModels;
  final VoidCallback onRoles;
  final VoidCallback onMembers;
  final VoidCallback onAudit;
  final VoidCallback onProject;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final entries = [
      _SidebarEntry(
        view: MainView.chat,
        label: '消息',
        icon: SidebarIconKind.messages,
        onPressed: onChat,
      ),
      _SidebarEntry(
        view: MainView.teams,
        label: '团队',
        icon: SidebarIconKind.teams,
        onPressed: onTeam,
      ),
      _SidebarEntry(
        view: MainView.models,
        label: '模型',
        icon: SidebarIconKind.models,
        onPressed: onModels,
      ),
      _SidebarEntry(
        view: MainView.roles,
        label: '角色',
        icon: SidebarIconKind.roles,
        onPressed: onRoles,
      ),
      _SidebarEntry(
        view: MainView.members,
        label: '成员',
        icon: SidebarIconKind.members,
        onPressed: onMembers,
      ),
      _SidebarEntry(
        view: MainView.project,
        label: '项目',
        icon: SidebarIconKind.project,
        onPressed: onProject,
      ),
      _SidebarEntry(
        view: MainView.audit,
        label: '审计',
        icon: SidebarIconKind.audit,
        onPressed: onAudit,
      ),
    ];
    return ColoredBox(
      color: const Color(0xFF050505),
      child: Column(
        children: [
          const SizedBox(height: 14),
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF272A31),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFF3A3E48)),
            ),
            child: const Text(
              'ai',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final entry in entries)
                    _SidebarButton(
                      label: entry.label,
                      icon: entry.icon,
                      selected: selectedView == entry.view,
                      onPressed: entry.onPressed,
                    ),
                ],
              ),
            ),
          ),
          _SidebarButton(
            label: '设置',
            icon: SidebarIconKind.settings,
            selected: selectedView == MainView.settings,
            onPressed: onSettings,
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

class _SidebarEntry {
  const _SidebarEntry({
    required this.view,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final MainView view;
  final String label;
  final SidebarIconKind icon;
  final VoidCallback onPressed;
}

class _SidebarButton extends StatefulWidget {
  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final SidebarIconKind icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  State<_SidebarButton> createState() => _SidebarButtonState();
}

class _SidebarButtonState extends State<_SidebarButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final foreground = widget.selected
        ? Colors.white
        : hovered
            ? const Color(0xFFE6E8EC)
            : const Color(0xFFA8AFBD);
    final background = widget.selected
        ? const Color(0xFF282C35)
        : hovered
            ? const Color(0xFF22262E)
            : Colors.transparent;
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              if (widget.selected)
                Positioned(
                  left: -10,
                  child: Container(
                    width: 3,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Color(0xFF3B82F6),
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
              Semantics(
                button: true,
                label: widget.label,
                selected: widget.selected,
                child: InkWell(
                  onTap: widget.onPressed,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: widget.selected || hovered
                            ? const Color(0xFF3A3F4A)
                            : Colors.transparent,
                      ),
                    ),
                    child: Center(
                      child: SidebarLinearIcon(
                        widget.icon,
                        color: foreground,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum SidebarIconKind {
  messages,
  teams,
  models,
  roles,
  members,
  project,
  audit,
  settings,
}

class SidebarLinearIcon extends StatelessWidget {
  const SidebarLinearIcon(
    this.kind, {
    super.key,
    this.color = const Color(0xFFA8AFBD),
  });

  final SidebarIconKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(20),
      painter: _SidebarIconPainter(kind: kind, color: color),
    );
  }
}

class _SidebarIconPainter extends CustomPainter {
  const _SidebarIconPainter({
    required this.kind,
    required this.color,
  });

  final SidebarIconKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    switch (kind) {
      case SidebarIconKind.messages:
        path
          ..addRRect(RRect.fromRectAndRadius(
            const Rect.fromLTWH(3, 4, 14, 10),
            const Radius.circular(4),
          ))
          ..moveTo(8, 14)
          ..lineTo(6, 17)
          ..lineTo(11, 14);
        break;
      case SidebarIconKind.teams:
        canvas.drawCircle(const Offset(6, 7), 2.4, paint);
        canvas.drawCircle(const Offset(14, 7), 2.4, paint);
        canvas.drawCircle(const Offset(10, 14), 2.6, paint);
        path
          ..moveTo(7.8, 8.5)
          ..lineTo(9.2, 11.6)
          ..moveTo(12.2, 8.5)
          ..lineTo(10.8, 11.6);
        break;
      case SidebarIconKind.models:
        path
          ..addRRect(RRect.fromRectAndRadius(
            const Rect.fromLTWH(4, 4, 12, 12),
            const Radius.circular(3),
          ))
          ..moveTo(8, 1.8)
          ..lineTo(8, 4)
          ..moveTo(12, 1.8)
          ..lineTo(12, 4)
          ..moveTo(8, 16)
          ..lineTo(8, 18.2)
          ..moveTo(12, 16)
          ..lineTo(12, 18.2)
          ..moveTo(1.8, 8)
          ..lineTo(4, 8)
          ..moveTo(1.8, 12)
          ..lineTo(4, 12)
          ..moveTo(16, 8)
          ..lineTo(18.2, 8)
          ..moveTo(16, 12)
          ..lineTo(18.2, 12);
        break;
      case SidebarIconKind.roles:
        path
          ..addRRect(RRect.fromRectAndRadius(
            const Rect.fromLTWH(5, 3, 10, 14),
            const Radius.circular(4),
          ))
          ..moveTo(8, 8)
          ..lineTo(12, 8)
          ..moveTo(7.5, 12)
          ..lineTo(12.5, 12);
        break;
      case SidebarIconKind.members:
        canvas.drawCircle(const Offset(10, 7), 3, paint);
        path
          ..moveTo(4.5, 17)
          ..cubicTo(5.4, 13.8, 7.2, 12.3, 10, 12.3)
          ..cubicTo(12.8, 12.3, 14.6, 13.8, 15.5, 17);
        break;
      case SidebarIconKind.project:
        path
          ..moveTo(3, 6)
          ..lineTo(8, 6)
          ..lineTo(9.8, 8)
          ..lineTo(17, 8)
          ..lineTo(17, 16)
          ..lineTo(3, 16)
          ..close();
        break;
      case SidebarIconKind.audit:
        path
          ..addRRect(RRect.fromRectAndRadius(
            const Rect.fromLTWH(5, 3, 10, 14),
            const Radius.circular(2),
          ))
          ..moveTo(8, 7)
          ..lineTo(12, 7)
          ..moveTo(8, 10)
          ..lineTo(12, 10)
          ..moveTo(8, 13)
          ..lineTo(10.5, 13);
        break;
      case SidebarIconKind.settings:
        canvas.drawCircle(const Offset(10, 10), 3, paint);
        for (var i = 0; i < 8; i++) {
          final angle = i * 0.785398;
          final start = Offset(
            10 + 6 * math.cos(angle),
            10 + 6 * math.sin(angle),
          );
          final end = Offset(
            10 + 8 * math.cos(angle),
            10 + 8 * math.sin(angle),
          );
          canvas.drawLine(start, end, paint);
        }
        break;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SidebarIconPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}
