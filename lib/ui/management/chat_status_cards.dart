import 'package:flutter/material.dart';

import '../../core/domain.dart';
import '../app_helpers.dart';

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
    return _InteractionMessageShell(
      authorName: widget.patch.memberName,
      child: _InteractionCard(
        title: 'Diff review · 补丁确认',
        titleTrailing: const _StatusPill(
          label: '待确认',
          tone: _StatusTone.amber,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: _PatchMetric(
                      value: '+${stats.additions} -${stats.deletions}',
                      label: '变更量',
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: _PatchMetric(value: '1', label: '文件'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PatchMetric(
                      value: stats.hunks.toString(),
                      label: '片段',
                    ),
                  ),
                ],
              ),
            ),
            _PatchFileTab(filePath: widget.patch.filePath),
            if (expanded)
              _DiffViewer(diff: widget.patch.diff)
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: _DiffCollapsedSummary(stats: stats),
              ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => setState(() => expanded = !expanded),
                    icon: Icon(
                      expanded
                          ? Icons.unfold_less_rounded
                          : Icons.unfold_more_rounded,
                    ),
                    label: Text(expanded ? '收起 diff' : '展开 diff'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onReject,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('拒绝'),
                  ),
                  FilledButton.icon(
                    onPressed: widget.onApply,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('确认应用'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InteractionMessageShell extends StatelessWidget {
  const _InteractionMessageShell({
    required this.authorName,
    this.createdAt,
    required this.child,
  });

  final String authorName;
  final DateTime? createdAt;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: avatarColor(authorName),
            child: Text(
              avatarText(authorName),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SpeakerLine(authorName: authorName, createdAt: createdAt),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: child,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeakerLine extends StatelessWidget {
  const _SpeakerLine({required this.authorName, required this.createdAt});

  final String authorName;
  final DateTime? createdAt;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          authorName,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (createdAt != null) ...[
          const SizedBox(width: 8),
          Text(
            messageTimeText(createdAt!),
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontFamily: 'monospace',
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _InteractionCard extends StatelessWidget {
  const _InteractionCard({
    required this.title,
    required this.titleTrailing,
    required this.child,
  });

  final String title;
  final Widget titleTrailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                titleTrailing,
              ],
            ),
          ),
          child,
        ],
      ),
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
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 0),
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
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
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
          children: [for (final line in lines) _DiffLine(line: line)],
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
      constraints: const BoxConstraints(minHeight: 27),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      color: background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              _linePrefix(line),
              style: TextStyle(
                color: foreground,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              _lineContent(line),
              style: TextStyle(
                color: foreground,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DiffLineType { added, deleted, neutral }

String _linePrefix(String line) {
  if (line.startsWith('@@')) {
    return '@@';
  }
  if (line.startsWith('+') && !line.startsWith('+++')) {
    return '+';
  }
  if (line.startsWith('-') && !line.startsWith('---')) {
    return '-';
  }
  return ' ';
}

String _lineContent(String line) {
  if ((line.startsWith('+') && !line.startsWith('+++')) ||
      (line.startsWith('-') && !line.startsWith('---'))) {
    return line.substring(1);
  }
  return line;
}

_DiffStats _diffStats(String diff) {
  var additions = 0;
  var deletions = 0;
  var hunks = 0;
  for (final line in diff.split('\n')) {
    if (line.startsWith('+') && !line.startsWith('+++')) {
      additions++;
    }
    if (line.startsWith('-') && !line.startsWith('---')) {
      deletions++;
    }
    if (line.startsWith('@@')) {
      hunks++;
    }
  }
  return _DiffStats(
    additions: additions,
    deletions: deletions,
    hunks: hunks == 0 ? 1 : hunks,
  );
}

class _DiffStats {
  const _DiffStats({
    required this.additions,
    required this.deletions,
    required this.hunks,
  });

  final int additions;
  final int deletions;
  final int hunks;
}

class _PatchMetric extends StatelessWidget {
  const _PatchMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DiffCollapsedSummary extends StatelessWidget {
  const _DiffCollapsedSummary({required this.stats});

  final _DiffStats stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
      ),
      child: Text(
        '+${stats.additions} -${stats.deletions} · ${stats.hunks} 个片段',
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    );
  }
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
    return _InteractionMessageShell(
      authorName: request.status == CommandRequestStatus.approved
          ? '系统'
          : request.memberName,
      createdAt: request.createdAt,
      child: _InteractionCard(
        title: title,
        titleTrailing: _StatusPill(
          label: _commandStatusLabel(request.status),
          tone: _commandStatusTone(request.status),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: _CommandStateCard(
            request: request,
            onApproveExecute: onApproveExecute,
            onReject: onReject,
          ),
        ),
      ),
    );
  }
}

class _CommandStateCard extends StatelessWidget {
  const _CommandStateCard({
    required this.request,
    required this.onApproveExecute,
    required this.onReject,
  });

  final CommandRequest request;
  final VoidCallback onApproveExecute;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final description = switch (request.status) {
      CommandRequestStatus.pending => '用户需要明确允许或拒绝，默认不执行。',
      CommandRequestStatus.approved => '用户已允许，命令可进入执行流程。',
      CommandRequestStatus.executed => '命令执行完成，摘要进入消息流并写入审计。',
      CommandRequestStatus.denied => '不进入执行流程，记录拒绝原因与操作者。',
      CommandRequestStatus.failed => '命令执行失败，输出摘要已保留。',
    };
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: _commandCardBackground(request.status),
        border: Border.all(color: _commandCardBorder(request.status)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _commandStateTitle(request.status),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _StatusPill(
                label: _commandStatusLabel(request.status),
                tone: _commandStatusTone(request.status),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 8),
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

String _commandStateTitle(CommandRequestStatus status) {
  return switch (status) {
    CommandRequestStatus.pending => '待确认',
    CommandRequestStatus.approved => '允许中',
    CommandRequestStatus.executed => '已执行',
    CommandRequestStatus.denied => '已拒绝',
    CommandRequestStatus.failed => '执行失败',
  };
}

String _commandStatusLabel(CommandRequestStatus status) {
  return switch (status) {
    CommandRequestStatus.pending => '待审批',
    CommandRequestStatus.approved => '允许中',
    CommandRequestStatus.executed => '已执行',
    CommandRequestStatus.denied => '已拒绝',
    CommandRequestStatus.failed => '失败',
  };
}

_StatusTone _commandStatusTone(CommandRequestStatus status) {
  return switch (status) {
    CommandRequestStatus.pending => _StatusTone.amber,
    CommandRequestStatus.approved => _StatusTone.blue,
    CommandRequestStatus.executed => _StatusTone.green,
    CommandRequestStatus.denied => _StatusTone.red,
    CommandRequestStatus.failed => _StatusTone.red,
  };
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.tone});

  final String label;
  final _StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      _StatusTone.green => const Color(0xFF047857),
      _StatusTone.amber => const Color(0xFFB45309),
      _StatusTone.blue => const Color(0xFF2563EB),
      _StatusTone.red => const Color(0xFFBE123C),
    };
    final background = switch (tone) {
      _StatusTone.green => const Color(0xFFECFDF3),
      _StatusTone.amber => const Color(0xFFFFFBEB),
      _StatusTone.blue => const Color(0xFFEFF6FF),
      _StatusTone.red => const Color(0xFFFFF1F2),
    };
    final border = switch (tone) {
      _StatusTone.green => const Color(0xFFA7F3D0),
      _StatusTone.amber => const Color(0xFFFDE68A),
      _StatusTone.blue => const Color(0xFFBFDBFE),
      _StatusTone.red => const Color(0xFFFECDD3),
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

enum _StatusTone { green, amber, blue, red }

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
