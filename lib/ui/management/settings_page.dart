import 'dart:io';

import 'package:flutter/material.dart';

import '../../application/app_controller.dart';
import '../../core/storage_directories.dart';
import '../dialogs/config_dialogs.dart';
import 'management_components.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.controller,
  });

  final AppController controller;

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  late StorageDirectories draftDirectories;
  bool saving = false;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    draftDirectories = controller.storageDirectories;
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.storageDirectories !=
        widget.controller.storageDirectories) {
      draftDirectories = widget.controller.storageDirectories;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ManagementPageFrame(
      title: '设置',
      subtitle: '持久化存储、导入导出和应用级配置',
      child: Column(
        children: [
          _StorageDirectoryPanel(
            directories: draftDirectories,
            onPick: _pickDirectory,
            onOpen: _openDirectory,
            onClear: _clearDirectory,
            onDefaults: _restoreDefaults,
            onSave: saving ? null : _saveDirectories,
          ),
          const SizedBox(height: 14),
          _ImportExportPanel(controller: controller),
        ],
      ),
    );
  }

  Future<void> _pickDirectory(_StorageDirectoryKind kind) async {
    final path = await controller.fileDialogs.pickDirectory();
    if (path == null || path.trim().isEmpty) {
      return;
    }
    setState(() {
      draftDirectories = _applyPath(
        draftDirectories,
        kind,
        Directory(path).absolute.path,
      );
    });
  }

  Future<void> _openDirectory(_StorageDirectoryKind kind) async {
    final path = _pathFor(draftDirectories, kind);
    if (path.trim().isEmpty) {
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
    }
  }

  void _clearDirectory(_StorageDirectoryKind kind) {
    setState(() {
      draftDirectories = _applyPath(draftDirectories, kind, '');
    });
  }

  void _restoreDefaults() {
    setState(() {
      draftDirectories = controller.storageDirectoryConfigStore?.defaults ??
          controller.storageDirectories;
    });
  }

  Future<void> _saveDirectories() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存持久化目录？'),
        content: const Text('保存前会复制现有状态、审计、会话和缓存目录。当前运行中的保存路径会在下次启动时完全生效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认保存'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() => saving = true);
    try {
      await controller.updateStorageDirectories(
        draftDirectories,
        migrate: true,
      );
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }
}

class _StorageDirectoryPanel extends StatelessWidget {
  const _StorageDirectoryPanel({
    required this.directories,
    required this.onPick,
    required this.onOpen,
    required this.onClear,
    required this.onDefaults,
    required this.onSave,
  });

  final StorageDirectories directories;
  final ValueChanged<_StorageDirectoryKind> onPick;
  final ValueChanged<_StorageDirectoryKind> onOpen;
  final ValueChanged<_StorageDirectoryKind> onClear;
  final VoidCallback onDefaults;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return _SettingsPanel(
      title: '持久化存储目录',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '用于 state、审计、会话与缓存；保存前会确认迁移。',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 10),
          _StorageDirectoryRow(
            label: '状态目录',
            description: 'state.json 和模型配置',
            path: directories.stateDirectory,
            kind: _StorageDirectoryKind.state,
            onPick: onPick,
            onOpen: onOpen,
            onClear: onClear,
          ),
          _StorageDirectoryRow(
            label: '审计目录',
            description: '命令、模型调用和补丁审计',
            path: directories.auditDirectory,
            kind: _StorageDirectoryKind.audit,
            onPick: onPick,
            onOpen: onOpen,
            onClear: onClear,
          ),
          _StorageDirectoryRow(
            label: '会话目录',
            description: '长期会话与私聊缓存',
            path: directories.conversationDirectory,
            kind: _StorageDirectoryKind.conversations,
            onPick: onPick,
            onOpen: onOpen,
            onClear: onClear,
          ),
          _StorageDirectoryRow(
            label: '缓存目录',
            description: '临时响应和缓存',
            path: directories.cacheDirectory,
            kind: _StorageDirectoryKind.cache,
            onPick: onPick,
            onOpen: onOpen,
            onClear: onClear,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onDefaults,
                  icon: const Icon(Icons.restore_rounded, size: 17),
                  label: const Text('恢复默认'),
                ),
                FilledButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.save_outlined, size: 17),
                  label: const Text('保存目录'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageDirectoryRow extends StatelessWidget {
  const _StorageDirectoryRow({
    required this.label,
    required this.description,
    required this.path,
    required this.kind,
    required this.onPick,
    required this.onOpen,
    required this.onClear,
  });

  final String label;
  final String description;
  final String path;
  final _StorageDirectoryKind kind;
  final ValueChanged<_StorageDirectoryKind> onPick;
  final ValueChanged<_StorageDirectoryKind> onOpen;
  final ValueChanged<_StorageDirectoryKind> onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 118,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SelectableText(
              path.isEmpty ? '未配置' : path,
              maxLines: 1,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          _DirectoryActionButton(
            tooltip: '选择目录',
            onPressed: () => onPick(kind),
            icon: Icons.folder_open_rounded,
            label: '选择',
          ),
          _DirectoryActionButton(
            tooltip: '打开目录',
            onPressed: path.isEmpty ? null : () => onOpen(kind),
            icon: Icons.open_in_new_rounded,
            label: '打开',
          ),
          _DirectoryActionButton(
            tooltip: '清空目录',
            onPressed: () => onClear(kind),
            icon: Icons.backspace_outlined,
            label: '清空',
          ),
        ],
      ),
    );
  }
}

class _DirectoryActionButton extends StatelessWidget {
  const _DirectoryActionButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: const Color(0xFF475569),
          disabledForegroundColor: const Color(0xFF94A3B8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}

class _ImportExportPanel extends StatelessWidget {
  const _ImportExportPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    void openImportExport() => showExportDialog(context, controller);

    return _SettingsPanel(
      title: '导入导出',
      action: Tooltip(
        message: '导入 / 导出配置',
        child: FilledButton.icon(
          onPressed: openImportExport,
          icon: const Icon(Icons.open_in_new_rounded, size: 17),
          label: const Text('打开'),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '配置文件、脱敏导出和密钥导出选项集中在这里管理。',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 10),
          _SettingsActionRow(
            label: '导入配置',
            description: '读取 JSON 配置文件并恢复团队、模型、角色和成员。',
            value: 'JSON',
            icon: Icons.file_upload_outlined,
            onPressed: openImportExport,
          ),
          _SettingsActionRow(
            label: '脱敏导出',
            description: '默认导出不包含 API Key，适合备份和审阅。',
            value: '默认',
            icon: Icons.file_download_outlined,
            onPressed: openImportExport,
          ),
          _SettingsActionRow(
            label: '密钥导出',
            description: '包含密钥时必须在弹窗中显式确认。',
            value: '需确认',
            icon: Icons.key_outlined,
            onPressed: openImportExport,
          ),
        ],
      ),
    );
  }
}

class _SettingsActionRow extends StatelessWidget {
  const _SettingsActionRow({
    required this.label,
    required this.description,
    required this.value,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String description;
  final String value;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF475569)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: '$label入口',
            child: IconButton(
              onPressed: onPressed,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.title,
    required this.child,
    this.action,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (action != null) action!,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

enum _StorageDirectoryKind { state, audit, conversations, cache }

String _pathFor(StorageDirectories directories, _StorageDirectoryKind kind) {
  return switch (kind) {
    _StorageDirectoryKind.state => directories.stateDirectory,
    _StorageDirectoryKind.audit => directories.auditDirectory,
    _StorageDirectoryKind.conversations => directories.conversationDirectory,
    _StorageDirectoryKind.cache => directories.cacheDirectory,
  };
}

StorageDirectories _applyPath(
  StorageDirectories directories,
  _StorageDirectoryKind kind,
  String path,
) {
  return switch (kind) {
    _StorageDirectoryKind.state => directories.copyWith(stateDirectory: path),
    _StorageDirectoryKind.audit => directories.copyWith(auditDirectory: path),
    _StorageDirectoryKind.conversations =>
      directories.copyWith(conversationDirectory: path),
    _StorageDirectoryKind.cache => directories.copyWith(cacheDirectory: path),
  };
}
