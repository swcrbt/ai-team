import 'package:flutter/material.dart';

class ManagementPageFrame extends StatelessWidget {
  const ManagementPageFrame({
    super.key,
    required this.title,
    required this.child,
    this.headerAction,
    this.sectionTitle,
    this.sectionIcon,
    this.fillBody = false,
  });

  final String title;
  final Widget child;
  final Widget? headerAction;
  final String? sectionTitle;
  final IconData? sectionIcon;
  final bool fillBody;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFF5F7F9),
      child: Column(
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFD9DDE2))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (headerAction != null) headerAction!,
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: _ManagementPageBody(
                sectionTitle: sectionTitle,
                sectionIcon: sectionIcon,
                fillBody: fillBody,
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManagementPageBody extends StatelessWidget {
  const _ManagementPageBody({
    required this.sectionTitle,
    required this.sectionIcon,
    required this.fillBody,
    required this.child,
  });

  final String? sectionTitle;
  final IconData? sectionIcon;
  final bool fillBody;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (sectionTitle == null) {
      return fillBody ? child : SingleChildScrollView(child: child);
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD9DDE2)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (sectionIcon != null) ...[
                    Icon(sectionIcon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    sectionTitle!,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class ManagementHeaderActions extends StatelessWidget {
  const ManagementHeaderActions({
    super.key,
    required this.countLabel,
    required this.actionLabel,
    required this.onPressed,
  });

  final String countLabel;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          countLabel,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(onPressed: onPressed, child: Text(actionLabel)),
      ],
    );
  }
}

class ManagementPanel extends StatelessWidget {
  const ManagementPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.action,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final body = SingleChildScrollView(child: child);
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              if (action != null)
                Align(alignment: Alignment.centerRight, child: action!),
              const SizedBox(height: 8),
              if (constraints.hasBoundedHeight)
                Expanded(child: body)
              else
                child,
            ],
          ),
        );
      },
    );
  }
}

class ManagementKeyValueRow extends StatelessWidget {
  const ManagementKeyValueRow({
    super.key,
    required this.label,
    required this.value,
    this.actions = const [],
  });

  final String label;
  final String value;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (actions.isNotEmpty) Wrap(spacing: 2, children: actions),
            ],
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}
