import 'dart:convert';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/domain.dart';
import '../app_helpers.dart';
import 'management_components.dart';

class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  var selectedFilter = _AuditFilter.all;
  String? selectedEntryId;

  @override
  Widget build(BuildContext context) {
    final entries = widget.controller.state.auditLog.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final filteredEntries = entries
        .where((entry) => _auditMatchesFilter(entry, selectedFilter))
        .toList();
    final selectedEntry = _selectedEntry(filteredEntries);
    return ManagementPageFrame(
      title: '审计日志',
      subtitle: '查看操作记录、命令执行和模型诊断',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 920;
          final list = _AuditListPanel(
            entries: filteredEntries,
            selectedEntryId: selectedEntry?.id,
            selectedFilter: selectedFilter,
            onFilterChanged: (filter) => setState(() {
              selectedFilter = filter;
              selectedEntryId = null;
            }),
            onSelectEntry: (entry) =>
                setState(() => selectedEntryId = entry.id),
          );
          final details = _AuditDetailDrawer(entry: selectedEntry);
          if (!wide) {
            return Column(
              children: [list, const SizedBox(height: 12), details],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: list),
              const SizedBox(width: 14),
              Expanded(flex: 2, child: details),
            ],
          );
        },
      ),
    );
  }

  AuditEntry? _selectedEntry(List<AuditEntry> entries) {
    final selectedEntryId = this.selectedEntryId;
    if (entries.isEmpty || selectedEntryId == null) {
      return null;
    }
    for (final entry in entries) {
      if (entry.id == selectedEntryId) {
        return entry;
      }
    }
    return null;
  }
}

class _AuditListPanel extends StatelessWidget {
  const _AuditListPanel({
    required this.entries,
    required this.selectedEntryId,
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.onSelectEntry,
  });

  final List<AuditEntry> entries;
  final String? selectedEntryId;
  final _AuditFilter selectedFilter;
  final ValueChanged<_AuditFilter> onFilterChanged;
  final ValueChanged<AuditEntry> onSelectEntry;

  @override
  Widget build(BuildContext context) {
    return ManagementPanel(
      title: '操作记录',
      icon: Icons.receipt_long_rounded,
      action: Text(
        '${entries.length} 条',
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w800,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AuditFilterBar(
            selectedFilter: selectedFilter,
            onChanged: onFilterChanged,
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            const _AuditEmptyState()
          else
            for (final entry in entries)
              _AuditLogRow(
                entry: entry,
                selected: entry.id == selectedEntryId,
                onSelect: () => onSelectEntry(entry),
              ),
        ],
      ),
    );
  }
}

class _AuditFilterBar extends StatelessWidget {
  const _AuditFilterBar({
    required this.selectedFilter,
    required this.onChanged,
  });

  final _AuditFilter selectedFilter;
  final ValueChanged<_AuditFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in _AuditFilter.values)
          ChoiceChip(
            label: Text(_auditFilterLabel(filter)),
            selected: filter == selectedFilter,
            onSelected: (_) => onChanged(filter),
          ),
      ],
    );
  }
}

class _AuditEmptyState extends StatelessWidget {
  const _AuditEmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Text(
        '当前过滤条件下暂无审计记录',
        style: TextStyle(color: Color(0xFF64748B)),
      ),
    );
  }
}

class _AuditDetailDrawer extends StatelessWidget {
  const _AuditDetailDrawer({required this.entry});

  final AuditEntry? entry;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    return ManagementPanel(
      title: '审计详情',
      icon: Icons.fact_check_rounded,
      child: entry == null
          ? const Text('选择一条记录查看详情', style: TextStyle(color: Color(0xFF64748B)))
          : _AuditDetailBody(entry: entry),
    );
  }
}

class _AuditDetailBody extends StatelessWidget {
  const _AuditDetailBody({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final metadata = entry.metadata ?? const <String, Object?>{};
    final rawResponse = metadata['rawResponse'] as String?;
    final requestBody = metadata['requestBody'];
    final requestModel = _auditRequestModel(requestBody);
    final structuredEntries = _auditStructuredEntries(metadata, requestModel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AuditDetailSection(
          title: '基础信息',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText('action: ${entry.action}'),
              SelectableText('createdAt: ${auditLogTimeText(entry.createdAt)}'),
            ],
          ),
        ),
        _AuditDetailSection(
          title: '摘要',
          child: SelectableText(_auditDisplayDetail(entry)),
        ),
        if (structuredEntries.isNotEmpty)
          _AuditDetailSection(
            title: '结构化字段',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: structuredEntries
                  .map(
                    (item) => SelectableText(
                      '${item.key}: ${_auditMetadataValueText(item.value)}',
                    ),
                  )
                  .toList(),
            ),
          ),
        if (requestBody != null)
          _AuditDetailSection(
            title: '请求参数',
            child: _AuditCodeBlock(
              text: const JsonEncoder.withIndent('  ').convert(requestBody),
            ),
          ),
        if (rawResponse != null)
          _AuditDetailSection(
            title: '原始返回内容',
            child: _AuditCodeBlock(text: rawResponse),
          ),
      ],
    );
  }
}

class _AuditCodeBlock extends StatelessWidget {
  const _AuditCodeBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 260),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    );
  }
}

class _AuditLogRow extends StatelessWidget {
  const _AuditLogRow({
    required this.entry,
    required this.selected,
    required this.onSelect,
  });

  final AuditEntry entry;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFEFF6FF) : const Color(0xFFF9FAFB),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: selected ? const Color(0xFFBFDBFE) : Colors.transparent,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.action,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _auditDisplayDetail(entry),
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 4),
                Text(
                  '创建时间：${auditLogTimeText(entry.createdAt)}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _auditDisplayDetail(AuditEntry entry) {
  final requestModel = _auditRequestModel(entry.metadata?['requestBody']);
  final tokens = entry.detail.split(' ');
  final sanitizedTokens = <String>[];
  for (final token in tokens) {
    if (token.startsWith('model=') || token.startsWith('targetModel=')) {
      final separator = token.indexOf('=');
      final key = token.substring(0, separator);
      final value = token.substring(separator + 1);
      if (_isInternalModelProfileId(value)) {
        if (key == 'model' && requestModel != null) {
          sanitizedTokens.add('$key=$requestModel');
        }
        continue;
      }
    }
    sanitizedTokens.add(token);
  }
  return sanitizedTokens.join(' ');
}

enum _AuditFilter { all, command, patch, model, config }

String _auditFilterLabel(_AuditFilter filter) {
  return switch (filter) {
    _AuditFilter.all => '全部',
    _AuditFilter.command => '命令',
    _AuditFilter.patch => '补丁',
    _AuditFilter.model => '模型',
    _AuditFilter.config => '配置',
  };
}

bool _auditMatchesFilter(AuditEntry entry, _AuditFilter filter) {
  if (filter == _AuditFilter.all) {
    return true;
  }
  final haystack = [
    entry.action,
    entry.detail,
    ...?entry.metadata?.keys,
  ].join(' ').toLowerCase();
  return switch (filter) {
    _AuditFilter.all => true,
    _AuditFilter.command => haystack.contains('command') ||
        haystack.contains('tool') ||
        haystack.contains('exec') ||
        haystack.contains('命令'),
    _AuditFilter.patch => haystack.contains('patch') ||
        haystack.contains('diff') ||
        haystack.contains('补丁'),
    _AuditFilter.model => haystack.contains('model') ||
        haystack.contains('request') ||
        haystack.contains('response') ||
        haystack.contains('diagnostic') ||
        haystack.contains('stream'),
    _AuditFilter.config => haystack.contains('config') ||
        haystack.contains('setting') ||
        haystack.contains('storage') ||
        haystack.contains('import') ||
        haystack.contains('export') ||
        haystack.contains('配置'),
  };
}

List<MapEntry<String, Object?>> _auditStructuredEntries(
  Map<String, Object?> metadata,
  String? requestModel,
) {
  final entries = <MapEntry<String, Object?>>[];
  var addedRequestModel = false;
  for (final item in metadata.entries) {
    if (item.key == 'rawResponse' || item.key == 'requestBody') {
      continue;
    }
    if (item.key == 'model') {
      if (requestModel != null) {
        entries.add(MapEntry(item.key, requestModel));
        addedRequestModel = true;
      } else if (!_isInternalModelProfileId(item.value)) {
        entries.add(item);
      }
      continue;
    }
    if (item.key == 'modelName') {
      entries.add(MapEntry('modelProfileName', item.value));
      continue;
    }
    if (item.key.toLowerCase().contains('model') &&
        _isInternalModelProfileId(item.value)) {
      continue;
    }
    entries.add(item);
  }
  if (!addedRequestModel &&
      requestModel != null &&
      !metadata.containsKey('model')) {
    entries.add(MapEntry('model', requestModel));
  }
  return entries;
}

String? _auditRequestModel(Object? requestBody) {
  if (requestBody is Map) {
    final model = requestBody['model'];
    if (model is String && model.trim().isNotEmpty) {
      return model;
    }
  }
  return null;
}

bool _isInternalModelProfileId(Object? value) {
  if (value is! String) {
    return false;
  }
  return value == 'model-main' ||
      value == 'model-local' ||
      RegExp(r'^model-\d{10,}$').hasMatch(value);
}

class _AuditDetailSection extends StatelessWidget {
  const _AuditDetailSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

String _auditMetadataValueText(Object? value) {
  if (value is Iterable) {
    return value.join(',');
  }
  return value.toString();
}
