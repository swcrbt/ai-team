import 'dart:convert';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/domain.dart';
import '../app_helpers.dart';
import 'management_components.dart';

class AuditLogPage extends StatelessWidget {
  const AuditLogPage({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.state.auditLog.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ManagementPageFrame(
      title: '审计日志',
      subtitle: '查看本机操作记录和命令执行审计',
      child: ManagementPanel(
        title: '操作记录',
        icon: Icons.receipt_long_rounded,
        child: Column(
          children: entries.isEmpty
              ? [const Text('暂无操作记录')]
              : entries
                  .map(
                    (entry) => _AuditLogRow(entry: entry),
                  )
                  .toList(),
        ),
      ),
    );
  }
}

class _AuditLogRow extends StatelessWidget {
  const _AuditLogRow({required this.entry});

  final AuditEntry entry;

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
                  entry.action,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: entry.metadata == null ? '无详情' : '查看详情',
                onPressed: entry.metadata == null
                    ? null
                    : () => _showAuditLogDetails(context, entry),
                icon: const Icon(Icons.info_outline_rounded),
              ),
            ],
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
    );
  }
}

void _showAuditLogDetails(BuildContext context, AuditEntry entry) {
  final metadata = entry.metadata ?? const <String, Object?>{};
  final rawResponse = metadata['rawResponse'] as String?;
  final requestBody = metadata['requestBody'];
  final requestModel = _auditRequestModel(requestBody);
  final structuredEntries = _auditStructuredEntries(metadata, requestModel);
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('审计详情'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AuditDetailSection(
                title: '基础信息',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText('action: ${entry.action}'),
                    SelectableText(
                      'createdAt: ${auditLogTimeText(entry.createdAt)}',
                    ),
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
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(requestBody),
                    ),
                  ),
                ),
              if (rawResponse != null)
                _AuditDetailSection(
                  title: '原始返回内容',
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SelectableText(rawResponse),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
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
  const _AuditDetailSection({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
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
