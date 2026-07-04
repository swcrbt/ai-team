import 'package:flutter/material.dart';

import '../../core/domain.dart';

class ChatPatchConfirmationCard extends StatefulWidget {
  const ChatPatchConfirmationCard({
    super.key,
    required this.patch,
    required this.onApply,
    required this.onReject,
  });

  final PatchProposal patch;
  final VoidCallback onApply;
  final VoidCallback onReject;

  @override
  State<ChatPatchConfirmationCard> createState() =>
      _ChatPatchConfirmationCardState();
}

class _ChatPatchConfirmationCardState extends State<ChatPatchConfirmationCard> {
  bool expanded = true;

  @override
  Widget build(BuildContext context) {
    final stats = _diffStats(widget.patch.diff);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 18,
          backgroundColor: Color(0xFF8B5CF6),
          child: Icon(
            Icons.difference_rounded,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 760),
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFC7D2FE)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '补丁确认',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text('${widget.patch.memberName} 提议修改'),
                const SizedBox(height: 10),
                _PatchFileTab(filePath: widget.patch.filePath),
                if (expanded)
                  _DiffViewer(diff: widget.patch.diff)
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(
                        left: BorderSide(color: Color(0xFFE2E8F0)),
                        right: BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    child: Text(
                      '${stats.additions} additions · ${stats.deletions} deletions',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: widget.onApply,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('应用修改'),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.onReject,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('拒绝'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => expanded = !expanded),
                      icon: Icon(
                        expanded
                            ? Icons.unfold_less_rounded
                            : Icons.unfold_more_rounded,
                      ),
                      label: Text(expanded ? '收起 Diff' : '展开 Diff'),
                    ),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('+${stats.additions} -${stats.deletions}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PatchFileTab extends StatelessWidget {
  const _PatchFileTab({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        color: Color(0xFFEFF6FF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
        border: Border.fromBorderSide(BorderSide(color: Color(0xFFBFDBFE))),
      ),
      child: Text(
        filePath,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DiffViewer extends StatelessWidget {
  const _DiffViewer({required this.diff});

  final String diff;

  @override
  Widget build(BuildContext context) {
    final lines = diff.split('\n').where((line) => line.isNotEmpty).toList();
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: Color(0xFFE2E8F0)),
          right: BorderSide(color: Color(0xFFE2E8F0)),
          bottom: BorderSide(color: Color(0xFFE2E8F0)),
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            for (final line in lines) _DiffLine(line: line),
          ],
        ),
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final type = line.startsWith('+') && !line.startsWith('+++')
        ? _DiffLineType.added
        : line.startsWith('-') && !line.startsWith('---')
            ? _DiffLineType.deleted
            : _DiffLineType.neutral;
    final background = switch (type) {
      _DiffLineType.added => const Color(0xFFECFDF3),
      _DiffLineType.deleted => const Color(0xFFFFF1F2),
      _DiffLineType.neutral => Colors.white,
    };
    final foreground = switch (type) {
      _DiffLineType.added => const Color(0xFF047857),
      _DiffLineType.deleted => const Color(0xFFBE123C),
      _DiffLineType.neutral => const Color(0xFF475569),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      color: background,
      child: SelectableText(
        line,
        style: TextStyle(
          color: foreground,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }
}

enum _DiffLineType { added, deleted, neutral }

_DiffStats _diffStats(String diff) {
  var additions = 0;
  var deletions = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      additions++;
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      deletions++;
    }
  }
  return _DiffStats(additions: additions, deletions: deletions);
}

class _DiffStats {
  const _DiffStats({required this.additions, required this.deletions});

  final int additions;
  final int deletions;
}

class ChatCommandRequestCard extends StatelessWidget {
  const ChatCommandRequestCard({
    super.key,
    required this.request,
    required this.onApproveExecute,
    required this.onReject,
  });

  final CommandRequest request;
  final VoidCallback onApproveExecute;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final title = switch (request.status) {
      CommandRequestStatus.pending => '命令请求 · 待审批',
      CommandRequestStatus.approved => '命令已允许',
      CommandRequestStatus.executed => '命令已执行',
      CommandRequestStatus.failed => '命令执行失败',
      CommandRequestStatus.denied => '命令已拒绝',
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _commandCardBackground(request.status),
        border: Border.all(color: _commandCardBorder(request.status)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                request.memberName,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            '${request.workingDirectory}\n\$ ${request.command}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          if (request.status == CommandRequestStatus.pending ||
              request.status == CommandRequestStatus.approved) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: onApproveExecute,
                  icon: Icon(
                    request.status == CommandRequestStatus.pending
                        ? Icons.check_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  label: Text(
                    request.status == CommandRequestStatus.pending
                        ? '允许'
                        : '执行',
                  ),
                ),
                if (request.status == CommandRequestStatus.pending)
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('拒绝'),
                  ),
                if (request.status == CommandRequestStatus.approved)
                  OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.article_outlined),
                    label: const Text('日志'),
                  ),
              ],
            ),
          ],
          if (request.output != null && request.output!.isNotEmpty) ...[
            const SizedBox(height: 12),
            SelectableText(
              request.output!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

Color _commandCardBackground(CommandRequestStatus status) {
  return switch (status) {
    CommandRequestStatus.pending => const Color(0xFFFFFBEB),
    CommandRequestStatus.approved => const Color(0xFFEFF6FF),
    CommandRequestStatus.executed => const Color(0xFFECFDF3),
    CommandRequestStatus.failed => const Color(0xFFFFF1F2),
    CommandRequestStatus.denied => const Color(0xFFFFF1F2),
  };
}

Color _commandCardBorder(CommandRequestStatus status) {
  return switch (status) {
    CommandRequestStatus.pending => const Color(0xFFFDE68A),
    CommandRequestStatus.approved => const Color(0xFFBFDBFE),
    CommandRequestStatus.executed => const Color(0xFFA7F3D0),
    CommandRequestStatus.failed => const Color(0xFFFECDD3),
    CommandRequestStatus.denied => const Color(0xFFFECDD3),
  };
}
