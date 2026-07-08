# Codex 级图片附件 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 让 Flutter 桌面聊天输入的图片粘贴、预览、提交、队列和失败恢复达到 Codex 级可靠性。

**Architecture:** 以结构化附件为事实来源，分离草稿附件和已提交 `MessageAttachment`。聊天输入使用 `Shortcuts`/`Actions` 自管粘贴，提交采用“保存图片 -> 写入用户消息 -> 回调清空草稿”的事务边界，队列复用入队时创建的用户消息及其附件。

**Tech Stack:** Flutter/Dart、`super_clipboard`、`desktop_drop`、`file_picker`、`image`、`mime`、`flutter_test`。

## Global Constraints

- 现有 `ChatMessage.attachments` JSON 保持兼容。
- 现有 `ModelProfile` 缺少 `supportsImages` 时迁移为 `true`。
- 新建自定义模型默认 `supportsImages=false`。
- `QueuedTask` 不新增图片字段；旧队列数据继续通过 `messageIds` 关联消息。
- 图片能力门禁必须同时存在于添加入口和提交层。
- 不使用文本 `[Image #N]` 作为附件事实来源。
- 不提交或回滚用户未确认的既有工作区改动；每个任务的 commit 步骤只有在用户明确授权提交时执行。

---

## File Structure

- Create: `lib/core/workspace/pending_image_attachment.dart`  
  草稿附件模型、状态、来源枚举和轻量错误类型。
- Create: `lib/core/workspace/image_paste_service.dart`  
  剪贴板图片候选读取、路径解析、普通文本插入辅助。
- Modify: `lib/core/workspace/image_service.dart`  
  保存图片事务、部分失败回滚、删除附件图片、data URL 错误显式化。
- Modify: `lib/core/domain/configuration.dart`  
  `ModelProfile.supportsImages` 字段、序列化、旧配置迁移。
- Modify: `lib/core/domain/app_state.dart`  
  seed 模型图片能力默认值。
- Modify: `lib/ui/dialogs/model_dialog.dart`  
  新建/编辑模型时提供“支持图片输入”开关，新建自定义模型默认关闭。
- Modify: `lib/application/app_controller.dart`  
  暴露图片能力判断、图片提交和队列入口。
- Modify: `lib/application/dispatch_controller.dart`  
  提交事务边界、模型能力二次校验、用户消息写入回调。
- Modify: `lib/application/task_queue_controller.dart`  
  入队图片保存到排队用户消息，运行时复用该消息，不创建重复用户消息。
- Modify: `lib/core/orchestration/team_orchestrator.dart`  
  队列运行时复用排队用户消息及附件。
- Modify: `lib/core/orchestration/member_chat_dispatcher.dart`  
  接收外部生成的用户消息 ID。
- Modify: `lib/core/orchestration/secretary_private_dispatcher.dart`  
  保持私聊转发路径附件不丢失。
- Modify: `lib/ui/chat/chat_pane.dart`  
  草稿附件 controller、paste action、模型能力门禁、提交事务 UI 回调。
- Modify: `lib/ui/chat/image_preview_list.dart`  
  从 `List<File>` 改为 `List<PendingImageAttachment>`，显示 ready/failed 状态。
- Modify: `lib/ui/chat/message_image_grid.dart`  
  缺失图片占位、稳定尺寸、语义标签。
- Modify: `lib/ui/chat/message_bubble.dart`  
  图片复制摘要和渲染接入。
- Test: `test/core/domain/configuration_export_test.dart`
- Test: `test/core/workspace/image_paste_service_test.dart`
- Test: `test/core/workspace/image_service_test.dart`
- Test: `test/application/image_dispatch_test.dart`
- Test: `test/application/task_queue_image_test.dart`
- Test: `test/ui/chat_image_paste_test.dart`
- Test: `test/ui/message_image_grid_test.dart`

---

### Task 1: 模型图片能力字段与管理 UI

**Estimate:** 45-75 分钟。依据：修改 3 个核心/界面文件，补 2-3 个序列化和 widget 行为测试；不涉及异步外部依赖。

**Files:**
- Modify: `lib/core/domain/configuration.dart:15-105`
- Modify: `lib/core/domain/app_state.dart:159-174`
- Modify: `lib/ui/dialogs/model_dialog.dart:1-190`
- Test: `test/core/domain/configuration_export_test.dart`

**Interfaces:**
- Produces: `ModelProfile.supportsImages: bool`
- Produces: `ModelProfile.copyWith({bool? supportsImages})`
- Produces: `ModelProfile.fromJson` 旧配置缺字段时 `supportsImages == true`
- Produces: 新建模型 UI 默认 `supportsImages == false`

- [x] **Step 1: 写失败测试：旧配置默认支持图片，新模型可显式关闭**

Add to `test/core/domain/configuration_export_test.dart`:

```dart
test('model image support defaults preserve legacy configs', () {
  final legacy = ModelProfile.fromJson({
    'id': 'legacy-model',
    'name': 'Legacy Vision Maybe',
    'baseUrl': 'https://example.test/v1',
    'modelName': 'legacy-model',
  });

  expect(legacy.supportsImages, isTrue);
  expect(legacy.toJson(), containsPair('supportsImages', true));

  final disabled = legacy.copyWith(supportsImages: false);
  expect(disabled.supportsImages, isFalse);
  expect(disabled.toJson(), containsPair('supportsImages', false));
});
```

- [x] **Step 2: 运行失败测试**

Run: `flutter test test/core/domain/configuration_export_test.dart`

Expected: FAIL with a compile error similar to `The getter 'supportsImages' isn't defined for the type 'ModelProfile'`.

- [x] **Step 3: 实现 `ModelProfile.supportsImages`**

Modify `lib/core/domain/configuration.dart`:

```dart
class ModelProfile {
  const ModelProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.modelName,
    required this.apiKey,
    this.streaming = true,
    this.temperature = 0.4,
    this.maxTokens = 1600,
    this.contextWindowTokens = defaultContextWindowTokens,
    this.reasoningEffort,
    this.protocol = ModelProtocol.chatCompletions,
    this.supportsImages = true,
  });

  final bool supportsImages;

  ModelProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? modelName,
    String? apiKey,
    bool? streaming,
    double? temperature,
    int? maxTokens,
    int? contextWindowTokens,
    String? reasoningEffort,
    ModelProtocol? protocol,
    bool? supportsImages,
  }) =>
      ModelProfile(
        id: id ?? this.id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        modelName: modelName ?? this.modelName,
        apiKey: apiKey ?? this.apiKey,
        streaming: streaming ?? this.streaming,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
        contextWindowTokens: contextWindowTokens ?? this.contextWindowTokens,
        reasoningEffort: reasoningEffort ?? this.reasoningEffort,
        protocol: protocol ?? this.protocol,
        supportsImages: supportsImages ?? this.supportsImages,
      );

  Map<String, Object?> toJson({bool includeSecrets = false}) {
    final json = <String, Object?>{
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'modelName': modelName,
      'streaming': streaming,
      'temperature': temperature,
      'maxTokens': maxTokens,
      if (contextWindowTokens != defaultContextWindowTokens)
        'contextWindowTokens': contextWindowTokens,
      'protocol': protocol.name,
      'supportsImages': supportsImages,
      if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
    };
    if (includeSecrets) {
      json['apiKey'] = apiKey;
    }
    return json;
  }

  factory ModelProfile.fromJson(Map<String, Object?> json) => ModelProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        baseUrl: json['baseUrl'] as String,
        modelName: json['modelName'] as String,
        apiKey: (json['apiKey'] as String?) ?? '',
        streaming: (json['streaming'] as bool?) ?? true,
        temperature: ((json['temperature'] as num?) ?? 0.4).toDouble(),
        maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 1600,
        contextWindowTokens: (json['contextWindowTokens'] as num?)?.toInt() ??
            ModelProfile.defaultContextWindowTokens,
        reasoningEffort: _optionalJsonString(json['reasoningEffort']),
        protocol: _parseProtocol(json['protocol']),
        supportsImages: (json['supportsImages'] as bool?) ?? true,
      );
}
```

- [x] **Step 4: 设置 seed 模型能力**

Modify `lib/core/domain/app_state.dart`:

```dart
const ModelProfile(
  id: 'model-main',
  name: 'OpenAI Compatible',
  baseUrl: 'https://api.openai.com/v1',
  modelName: 'gpt-4.1',
  apiKey: 'sk-local-placeholder',
  supportsImages: true,
),
const ModelProfile(
  id: 'model-local',
  name: 'Local Compatible',
  baseUrl: 'http://localhost:11434/v1',
  modelName: 'qwen2.5-coder',
  apiKey: 'local',
  supportsImages: false,
),
```

- [x] **Step 5: 给模型对话框加开关**

In `lib/ui/dialogs/model_dialog.dart`, add a local `bool supportsImages` initialized as:

```dart
var supportsImages = widget.model?.supportsImages ?? false;
```

Add a `SwitchListTile` near protocol/reasoning fields:

```dart
SwitchListTile(
  value: supportsImages,
  onChanged: (value) => setState(() => supportsImages = value),
  title: const Text('支持图片输入'),
  subtitle: const Text('仅视觉模型开启；未知自定义模型默认关闭'),
),
```

When constructing `ModelProfile`, pass:

```dart
supportsImages: supportsImages,
```

- [x] **Step 6: 运行验证**

Run: `flutter test test/core/domain/configuration_export_test.dart`

Expected: PASS. Existing export tests continue to pass, and new test passes.

- [x] **Step 7: 提交或记录差异**

If the user has explicitly authorized commits, run:

```bash
git add lib/core/domain/configuration.dart lib/core/domain/app_state.dart lib/ui/dialogs/model_dialog.dart test/core/domain/configuration_export_test.dart
git commit -m "feat: 增加模型图片能力配置"
```

If commits are not authorized, do not commit; record the modified files in the task handoff.

---

### Task 2: 草稿图片模型、路径解析和剪贴板候选服务

**Estimate:** 2-3.5 小时。依据：新增 2 个服务文件，路径解析和剪贴板候选需要多平台字符串规则与异步读取测试；`super_clipboard` item 遍历可能需要一次 API 试验。

**Files:**
- Create: `lib/core/workspace/pending_image_attachment.dart`
- Create: `lib/core/workspace/image_paste_service.dart`
- Test: `test/core/workspace/image_paste_service_test.dart`

**Interfaces:**
- Produces: `enum PendingImageSource`
- Produces: `enum PendingImageStatus`
- Produces: `class PendingImageAttachment`
- Produces: `class ImagePasteService`
- Produces: `ImagePasteService.parsePastedImagePath(String text): ImagePathParseResult`
- Produces: `ImagePasteService.insertText(TextEditingValue value, String text): TextEditingValue`

- [x] **Step 1: 写失败测试：路径解析和普通文本插入**

Create `test/core/workspace/image_paste_service_test.dart`:

```dart
import 'dart:io';

import 'package:ai_team/core/workspace/image_paste_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImagePasteService path parsing', () {
    test('parses file urls and quoted paths only when image exists', () async {
      final dir = await Directory.systemTemp.createTemp('ai_team_paste_');
      addTearDown(() async => dir.delete(recursive: true));
      final image = File('${dir.path}/sample.png');
      await image.writeAsBytes(_onePixelPng);
      final service = ImagePasteService();

      final fromFileUrl = await service.parsePastedImagePath(image.uri.toString());
      expect(fromFileUrl.path, image.path);
      expect(fromFileUrl.isImagePath, isTrue);

      final fromQuoted = await service.parsePastedImagePath('"${image.path}"');
      expect(fromQuoted.path, image.path);
      expect(fromQuoted.isImagePath, isTrue);
    });

    test('treats non image text as normal paste text', () async {
      final service = ImagePasteService();

      final result = await service.parsePastedImagePath('hello world');

      expect(result.isImagePath, isFalse);
      expect(result.path, isNull);
    });

    test('insertText replaces selection and clears composing', () {
      final value = const TextEditingValue(
        text: 'hello world',
        selection: TextSelection(baseOffset: 6, extentOffset: 11),
        composing: TextRange(start: 0, end: 5),
      );

      final next = ImagePasteService.insertText(value, 'Dart');

      expect(next.text, 'hello Dart');
      expect(next.selection, const TextSelection.collapsed(offset: 10));
      expect(next.composing, TextRange.empty);
    });
  });
}

const _onePixelPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];
```

- [x] **Step 2: 运行失败测试**

Run: `flutter test test/core/workspace/image_paste_service_test.dart`

Expected: FAIL because `ImagePasteService` does not exist.

- [x] **Step 3: 创建草稿附件模型**

Create `lib/core/workspace/pending_image_attachment.dart`:

```dart
import 'dart:io';

enum PendingImageSource {
  pickedFile,
  droppedFile,
  clipboardFile,
  clipboardImage,
  pastedPath,
}

enum PendingImageStatus {
  ready,
  invalid,
  failed,
}

class PendingImageAttachment {
  const PendingImageAttachment({
    required this.id,
    required this.source,
    required this.file,
    this.ownedTemporaryFile = false,
    this.mimeType,
    this.fileSize,
    this.width,
    this.height,
    this.status = PendingImageStatus.ready,
    this.errorMessage,
  });

  final String id;
  final PendingImageSource source;
  final File file;
  final bool ownedTemporaryFile;
  final String? mimeType;
  final int? fileSize;
  final int? width;
  final int? height;
  final PendingImageStatus status;
  final String? errorMessage;

  bool get canSubmit => status == PendingImageStatus.ready;

  PendingImageAttachment copyWith({
    PendingImageStatus? status,
    String? errorMessage,
  }) {
    return PendingImageAttachment(
      id: id,
      source: source,
      file: file,
      ownedTemporaryFile: ownedTemporaryFile,
      mimeType: mimeType,
      fileSize: fileSize,
      width: width,
      height: height,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
```

- [x] **Step 4: 创建路径解析和文本插入服务**

Create `lib/core/workspace/image_paste_service.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_team/core/workspace/pending_image_attachment.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:super_clipboard/super_clipboard.dart';

class ImagePathParseResult {
  const ImagePathParseResult.image(this.path)
      : isImagePath = true,
        errorMessage = null;

  const ImagePathParseResult.notImagePath()
      : isImagePath = false,
        path = null,
        errorMessage = null;

  const ImagePathParseResult.error(this.errorMessage)
      : isImagePath = false,
        path = null;

  final bool isImagePath;
  final String? path;
  final String? errorMessage;
}

class ImagePasteException implements Exception {
  const ImagePasteException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ImagePasteService {
  Future<ImagePathParseResult> parsePastedImagePath(String text) async {
    final normalized = _normalizeSinglePath(text);
    if (normalized == null) {
      return const ImagePathParseResult.notImagePath();
    }
    final file = File(normalized);
    if (!file.existsSync()) {
      return const ImagePathParseResult.notImagePath();
    }
    final extension = path.extension(file.path).toLowerCase();
    const imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};
    if (!imageExtensions.contains(extension)) {
      return const ImagePathParseResult.notImagePath();
    }
    try {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        return const ImagePathParseResult.error('图片无法解码');
      }
      return ImagePathParseResult.image(file.path);
    } catch (error) {
      return ImagePathParseResult.error('图片不可读：$error');
    }
  }

  static TextEditingValue insertText(TextEditingValue value, String text) {
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final normalizedStart = start.clamp(0, value.text.length);
    final normalizedEnd = end.clamp(0, value.text.length);
    final replaceStart = normalizedStart < normalizedEnd ? normalizedStart : normalizedEnd;
    final replaceEnd = normalizedStart < normalizedEnd ? normalizedEnd : normalizedStart;
    final nextText = value.text.replaceRange(replaceStart, replaceEnd, text);
    return value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: replaceStart + text.length),
      composing: TextRange.empty,
    );
  }

  Future<PendingImageAttachment> attachmentFromFile(
    File file,
    PendingImageSource source, {
    bool ownedTemporaryFile = false,
  }) async {
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      return failedAttachment(source: source, errorMessage: '图片无法解码');
    }
    return PendingImageAttachment(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      source: source,
      file: file,
      ownedTemporaryFile: ownedTemporaryFile,
      mimeType: lookupMimeType(file.path),
      fileSize: bytes.length,
      width: image.width,
      height: image.height,
    );
  }

  Future<PendingImageAttachment> attachmentFromBytes(
    Uint8List bytes, {
    required String extension,
    required PendingImageSource source,
  }) async {
    final file = File(
      '${Directory.systemTemp.path}/ai_team_clipboard_image_'
      '${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return attachmentFromFile(file, source, ownedTemporaryFile: true);
  }

  PendingImageAttachment failedAttachment({
    required PendingImageSource source,
    required String errorMessage,
  }) {
    return PendingImageAttachment(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      source: source,
      file: File(''),
      status: PendingImageStatus.failed,
      errorMessage: errorMessage,
    );
  }

  String? _normalizeSinglePath(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.contains('\n')) {
      return null;
    }
    var candidate = trimmed;
    if ((candidate.startsWith('"') && candidate.endsWith('"')) ||
        (candidate.startsWith("'") && candidate.endsWith("'"))) {
      candidate = candidate.substring(1, candidate.length - 1);
    }
    final uri = Uri.tryParse(candidate);
    if (uri != null && uri.scheme == 'file') {
      return uri.toFilePath();
    }
    if (candidate.contains(' ') && !File(candidate).existsSync()) {
      return null;
    }
    return candidate.replaceAll('\\ ', ' ');
  }
}
```

- [x] **Step 5: 运行验证**

Run: `flutter test test/core/workspace/image_paste_service_test.dart`

Expected: PASS.

- [x] **Step 6: 实现剪贴板 item 遍历**

Extend `ImagePasteService` with `Future<List<PendingImageAttachment>> readClipboardImageCandidates()` using `SystemClipboard.instance.read()` and `ClipboardReader.items` from `super_clipboard 0.8.24`:

```dart
Future<List<PendingImageAttachment>> readClipboardImageCandidates() async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) {
    throw const ImagePasteException('剪贴板不可用');
  }
  final reader = await clipboard.read();
  final result = <PendingImageAttachment>[];
  for (final item in reader.items) {
    final fileUri = await item.readValue(Formats.fileUri);
    if (fileUri != null) {
      final parsed = await parsePastedImagePath(fileUri.toString());
      if (parsed.isImagePath && parsed.path != null) {
        result.add(await attachmentFromFile(
          File(parsed.path!),
          PendingImageSource.clipboardFile,
          ownedTemporaryFile: false,
        ));
      } else if (parsed.errorMessage != null) {
        result.add(failedAttachment(
          source: PendingImageSource.clipboardFile,
          errorMessage: parsed.errorMessage!,
        ));
      }
      continue;
    }
    for (final candidate in const [
      (format: Formats.png, extension: '.png'),
      (format: Formats.jpeg, extension: '.jpg'),
      (format: Formats.gif, extension: '.gif'),
      (format: Formats.webp, extension: '.webp'),
      (format: Formats.bmp, extension: '.bmp'),
    ]) {
      final bytes = await _readClipboardFile(item, candidate.format);
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      result.add(await attachmentFromBytes(
        bytes,
        extension: candidate.extension,
        source: PendingImageSource.clipboardImage,
      ));
      break;
    }
  }
  return result;
}

Future<Uint8List?> _readClipboardFile(
  ClipboardDataReader item,
  FileFormat format,
) {
  final completer = Completer<Uint8List?>();
  final progress = item.getFile(
    format,
    (file) async => completer.complete(await file.readAll()),
    onError: (error) => completer.completeError(error),
  );
  if (progress == null) {
    completer.complete(null);
  }
  return completer.future;
}
```

Run: `flutter test test/core/workspace/image_paste_service_test.dart`

Expected: PASS. If a platform returns `Formats.fileUri` and image bytes for the same item, only the file URI branch is used so copied Finder files keep their source file names.

- [x] **Step 7: 提交或记录差异**

If commits are authorized:

```bash
git add lib/core/workspace/pending_image_attachment.dart lib/core/workspace/image_paste_service.dart test/core/workspace/image_paste_service_test.dart
git commit -m "feat: 增加图片粘贴解析服务"
```

---

### Task 3: ImageService 保存事务与显式错误

**Estimate:** 1.5-2.5 小时。依据：已有 `ImageService` 雏形，可在现有方法上补事务和测试；主要风险是部分失败回滚。

**Files:**
- Modify: `lib/core/workspace/image_service.dart`
- Test: `test/core/workspace/image_service_test.dart`
- Test: `test/core/model/model_gateway_test.dart`

**Interfaces:**
- Produces: `Future<List<MessageAttachment>> savePendingImages({required String conversationId, required String messageId, required List<PendingImageAttachment> images})`
- Produces: `Future<void> deleteAttachments(List<MessageAttachment> attachments)`
- Changes: `readImageAsDataUrl` throws `ImageServiceException` on missing/unreadable file

- [x] **Step 1: 写失败测试：部分保存失败回滚**

Create `test/core/workspace/image_service_test.dart`:

```dart
import 'dart:io';

import 'package:ai_team/core/workspace/image_service.dart';
import 'package:ai_team/core/workspace/pending_image_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('savePendingImages rolls back files when a later image fails', () async {
    final root = await Directory.systemTemp.createTemp('ai_team_images_');
    addTearDown(() async => root.delete(recursive: true));
    final valid = File('${root.path}/valid.png')..writeAsBytesSync(_onePixelPng);
    final missing = File('${root.path}/missing.png');
    final service = ImageService(root);

    await expectLater(
      service.savePendingImages(
        conversationId: 'conv-1',
        messageId: 'msg-1',
        images: [
          PendingImageAttachment(
            id: 'pending-1',
            source: PendingImageSource.pickedFile,
            file: valid,
          ),
          PendingImageAttachment(
            id: 'pending-2',
            source: PendingImageSource.pickedFile,
            file: missing,
          ),
        ],
      ),
      throwsA(isA<ImageServiceException>()),
    );

    final imageDir = Directory('${root.path}/images/conv-1');
    expect(imageDir.existsSync(), isFalse);
  });
}

const _onePixelPng = <int>[/* reuse bytes from Task 2 */];
```

- [x] **Step 2: 运行失败测试**

Run: `flutter test test/core/workspace/image_service_test.dart`

Expected: FAIL because `savePendingImages` and `ImageServiceException` are undefined.

- [x] **Step 3: 实现异常和事务保存**

Modify `lib/core/workspace/image_service.dart`:

```dart
class ImageServiceException implements Exception {
  const ImageServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension ImageServicePendingImages on ImageService {
  Future<List<MessageAttachment>> savePendingImages({
    required String conversationId,
    required String messageId,
    required List<PendingImageAttachment> images,
  }) async {
    final attachments = <MessageAttachment>[];
    final created = <File>[];
    try {
      for (var index = 0; index < images.length; index++) {
        final pending = images[index];
        if (!pending.canSubmit) {
          throw ImageServiceException(pending.errorMessage ?? '图片不可提交');
        }
        final attachment = await saveImage(
          conversationId: conversationId,
          messageId: messageId,
          sourceFile: pending.file,
          index: index,
        );
        attachments.add(attachment);
        created.add(getImageFile(attachment));
      }
      return attachments;
    } catch (error) {
      for (final file in created) {
        if (file.existsSync()) {
          await file.delete();
        }
      }
      final imageDir = Directory(path.join(workspaceRoot.path, 'images', conversationId));
      if (imageDir.existsSync() && imageDir.listSync().isEmpty) {
        await imageDir.delete();
      }
      throw ImageServiceException('图片保存失败：$error');
    }
  }
}
```

If Dart extension cannot access private helpers, make `_getImageDirectory` public as `imageDirectoryForConversation` and keep changes in the same file.

- [x] **Step 4: 让 `readImageAsDataUrl` 显式失败**

Modify `readImageAsDataUrl`:

```dart
Future<String> readImageAsDataUrl(MessageAttachment attachment) async {
  final file = getImageFile(attachment);
  if (!file.existsSync()) {
    throw ImageServiceException('图片文件不存在：${attachment.filePath}');
  }
  try {
    final bytes = await file.readAsBytes();
    final base64Data = base64Encode(bytes);
    final mimeType = attachment.mimeType ?? 'image/png';
    return 'data:$mimeType;base64,$base64Data';
  } catch (error) {
    throw ImageServiceException('图片读取失败：$error');
  }
}
```

- [x] **Step 5: 更新 gateway 测试，禁止静默丢图**

Add to `test/core/model/model_gateway_test.dart`:

```dart
test('fails instead of silently dropping unreadable image attachments', () async {
  final gateway = OpenAiCompatibleGateway(
    imageDataUrlResolver: (_) async => throw const ImageServiceException('图片文件不存在'),
  );

  await expectLater(
    gateway.complete(
      model: model().copyWith(streaming: false),
      systemPrompt: 'system',
      messages: [
        ChatMessage(
          id: 'm1',
          authorName: '我',
          content: '看图',
          createdAt: DateTime(2026),
          isUser: true,
          attachments: const [
            MessageAttachment(
              id: 'attachment-1',
              type: MessageAttachmentType.image,
              filePath: 'missing.png',
              mimeType: 'image/png',
            ),
          ],
        ),
      ],
    ),
    throwsA(isA<ModelGatewayException>()),
  );
});
```

- [x] **Step 6: 修改 `OpenAiCompatibleGateway._resolveImageDataUrls`**

In `lib/core/model/openai_gateway.dart`, replace the silent catch with:

```dart
try {
  dataUrls[attachment.id] = await resolver(attachment);
} catch (error) {
  throw ModelGatewayException('图片读取失败：$error', isRetryable: false);
}
```

- [x] **Step 7: 运行验证**

Run: `flutter test test/core/workspace/image_service_test.dart test/core/model/model_gateway_test.dart`

Expected: PASS.

- [x] **Step 8: 提交或记录差异**

If commits are authorized:

```bash
git add lib/core/workspace/image_service.dart lib/core/model/openai_gateway.dart test/core/workspace/image_service_test.dart test/core/model/model_gateway_test.dart
git commit -m "feat: 增强图片保存事务"
```

---

### Task 4: 提交事务、模型能力门禁和用户消息写入回调

**Estimate:** 2-4 小时。依据：跨 `ChatPane`、`AppController`、`DispatchController` 和 orchestrator，状态边界复杂；需写应用层回归测试。

**Files:**
- Modify: `lib/application/app_controller.dart`
- Modify: `lib/application/dispatch_controller.dart`
- Modify: `lib/core/orchestration/member_chat_dispatcher.dart`
- Modify: `lib/core/orchestration/team_orchestrator.dart`
- Test: `test/application/image_dispatch_test.dart`

**Interfaces:**
- Produces: `AppController.modelSupportsImagesForConversation(String conversationId): bool`
- Produces: `DispatchController.dispatchConversation(..., String? userMessageId, List<MessageAttachment> attachments, VoidCallback? onUserMessageCommitted)`
- Consumes: `ImageService.savePendingImages`

- [x] **Step 1: 写失败测试：不支持图片模型阻止提交并不写消息**

Create `test/application/image_dispatch_test.dart` with a controller fixture based on existing application tests. Test shape:

```dart
test('dispatch rejects image attachments when current model does not support images', () async {
  final controller = await createControllerForTest();
  final conversation = controller.currentConversation;
  final disabledModel = controller.state.models.first.copyWith(supportsImages: false);
  controller.updateModel(disabledModel);

  await expectLater(
    controller.dispatchConversation(
      conversation.id,
      '看图',
      images: [File('/tmp/missing.png')],
    ),
    throwsA(isA<StateError>()),
  );

  expect(controller.conversationById(conversation.id).messages, conversation.messages);
});
```

Use the existing test helper patterns from `test/application/controller_components_test.dart`. If no helper exists, create a local fake gateway that returns deterministic text.

- [x] **Step 2: 运行失败测试**

Run: `flutter test test/application/image_dispatch_test.dart`

Expected: FAIL because model image capability check is missing.

- [x] **Step 3: 增加会话模型能力判断**

In `lib/application/app_controller.dart`:

```dart
bool modelSupportsImagesForConversation(String conversationId) {
  final conversation = conversationById(conversationId);
  final model = _modelForConversation(conversation);
  return model.supportsImages;
}
```

If `_modelForConversation` is private to `ChatPane`, implement equivalent lookup in `AppController` using current team/member state.

- [x] **Step 4: 提交层二次校验**

In `lib/application/dispatch_controller.dart`, before setting `isDispatching = true`:

```dart
if ((images != null && images.isNotEmpty) && !_conversationModelSupportsImages(conversationId)) {
  throw StateError('当前模型不支持图片输入');
}
```

Add private helper in `DispatchController`:

```dart
bool _conversationModelSupportsImages(String conversationId) {
  final conversation = conversationByIdOrThrow(state, conversationId);
  if (conversation.memberId != null) {
    final member = state.members.firstWhere((item) => item.id == conversation.memberId);
    final model = state.models.firstWhere((item) => item.id == member.modelId);
    return model.supportsImages;
  }
  final team = state.teams.firstWhere((item) => item.id == conversation.teamId);
  final secretary = state.members.firstWhere((item) => item.id == team.secretaryMemberId);
  final model = state.models.firstWhere((item) => item.id == secretary.modelId);
  return model.supportsImages;
}
```

- [x] **Step 5: 支持外部用户消息 ID 和提交回调**

Change dispatcher signatures:

```dart
Future<void> dispatchConversation(
  String conversationId,
  String text, {
  List<File>? images,
  String? userMessageId,
  List<MessageAttachment>? preparedAttachments,
  VoidCallback? onUserMessageCommitted,
}) async
```

Pass `userMessageId` into `dispatchTeamTask`, `dispatchMemberChat`, and secretary private dispatch. In each orchestrator, use:

```dart
ChatMessage(
  id: userMessageId ?? orchestrationId('msg'),
  authorName: '我',
  content: userText,
  createdAt: now,
  isUser: true,
  attachments: attachments ?? const [],
)
```

Call `onUserMessageCommitted?.call()` immediately after `onProgress?.call(workingState)` that includes the user message.

- [x] **Step 6: Run tests**

Run: `flutter test test/application/image_dispatch_test.dart test/core/domain/secretary_orchestration_test.dart`

Expected: PASS. Existing secretary attachment persistence tests remain passing.

- [x] **Step 7: 提交或记录差异**

If commits are authorized:

```bash
git add lib/application/app_controller.dart lib/application/dispatch_controller.dart lib/core/orchestration/member_chat_dispatcher.dart lib/core/orchestration/team_orchestrator.dart test/application/image_dispatch_test.dart test/core/domain/secretary_orchestration_test.dart
git commit -m "feat: 增加图片提交事务门禁"
```

---

### Task 5: 队列图片归属和运行时复用排队用户消息

**Estimate:** 2-3 小时。依据：当前队列已经使用 `messageIds`，但运行时会创建重复用户消息；要改 orchestrator 请求上下文并补删除清理。

**Files:**
- Modify: `lib/application/task_queue_controller.dart`
- Modify: `lib/application/app_controller.dart`
- Modify: `lib/core/orchestration/team_orchestrator.dart`
- Test: `test/application/task_queue_image_test.dart`

**Interfaces:**
- Consumes: `ImageService.savePendingImages`
- Produces: Queue enqueue path creates user `ChatMessage(attachments: ...)`
- Produces: `dispatchQueuedTask` reuses the queued user message in request history

- [x] **Step 1: 写失败测试：运行队列不创建重复用户消息**

Create `test/application/task_queue_image_test.dart`:

```dart
test('queued task reuses queued user message with attachments', () async {
  final controller = await createControllerForTest();
  final conversation = controller.currentConversation;
  final image = await createTempPng();

  await controller.enqueueCurrentConversationTask('分析这张图', images: [image]);
  final queuedConversation = controller.conversationById(conversation.id);
  final queuedUserMessages = queuedConversation.messages.where((message) => message.isUser).toList();
  expect(queuedUserMessages, hasLength(1));
  expect(queuedUserMessages.single.attachments, hasLength(1));

  await controller.runNextQueuedTask();
  final completedConversation = controller.conversationById(conversation.id);
  final userMessages = completedConversation.messages.where((message) => message.isUser).toList();
  expect(userMessages, hasLength(1));
  expect(userMessages.single.attachments, hasLength(1));
});
```

- [x] **Step 2: 运行失败测试**

Run: `flutter test test/application/task_queue_image_test.dart`

Expected: FAIL because enqueue does not accept images and/or run creates duplicate user messages.

- [x] **Step 3: 扩展 enqueue 接口**

In `AppController.enqueueCurrentConversationTask`:

```dart
Future<void> enqueueCurrentConversationTask(
  String text, {
  int priority = 0,
  List<File>? images,
}) async {
  await _taskQueue.enqueueConversationTask(
    currentConversation.id,
    text,
    priority: priority,
    images: images,
    imageService: imageService,
  );
}
```

In `TaskQueueController.enqueueConversationTask`, add parameters:

```dart
List<File>? images,
ImageService? imageService,
```

Generate `userMessageId` before saving images, save attachments, and only then create `userMessage` and `QueuedTask`.

- [x] **Step 4: 复用排队用户消息**

In `TeamOrchestrator.dispatchQueuedTask`, find queued user message:

```dart
ChatMessage? queuedUserMessageForTask(
  Conversation conversation,
  QueuedTask task,
) {
  for (final message in conversation.messages) {
    if (message.isUser && task.messageIds.contains(message.id)) {
      return message;
    }
  }
  return null;
}

final queuedUserMessage = queuedUserMessageForTask(conversation, task);
```

Build `userText` with notes for model request, but do not append a new user message if `queuedUserMessage != null`. Instead pass request messages containing:

```dart
final requestMessages = [
  ...conversation.messages,
  if (task.notes.isNotEmpty)
    ChatMessage(
      id: orchestrationId('task-notes-${task.id}'),
      authorName: '系统',
      content: ['备注:', ...task.notes.map((note) => '- $note')].join('\n'),
      createdAt: DateTime.now(),
    ),
];
```

If no queued user message exists, keep current fallback behavior for legacy queued tasks.

- [x] **Step 5: 删除任务清理图片**

In `TaskQueueController`, inject `ImageService` through the constructor:

```dart
class TaskQueueController {
  const TaskQueueController({
    required this.readState,
    required this.commit,
    required this.gateway,
    required this.imageService,
  });

  final ImageService imageService;
}
```

In `deleteTask`, before removing messages, collect attachments from messages owned by the task and delete them asynchronously:

```dart
final conversation = conversationByIdOrThrow(state, task.conversationId);
final removedAttachments = conversation.messages
    .where(
      (message) =>
          message.taskIds.contains(taskId) ||
          task.messageIds.contains(message.id),
    )
    .expand((message) => message.attachments)
    .toList();
unawaited(imageService.deleteMessageImages(removedAttachments));
```

- [x] **Step 6: 运行验证**

Run: `flutter test test/application/task_queue_image_test.dart test/application/controller_components_test.dart`

Expected: PASS.

- [x] **Step 7: 提交或记录差异**

If commits are authorized:

```bash
git add lib/application/task_queue_controller.dart lib/application/app_controller.dart lib/core/orchestration/team_orchestrator.dart test/application/task_queue_image_test.dart
git commit -m "feat: 队列任务复用图片用户消息"
```

---

### Task 6: ChatPane 自管粘贴、草稿预览和添加入口门禁

**Estimate:** 3-5 小时。依据：UI 状态、剪贴板异步、TextEditingValue 更新和 widget 测试都在此任务，交互风险最高。

**Files:**
- Modify: `lib/ui/chat/chat_pane.dart`
- Modify: `lib/ui/chat/image_preview_list.dart`
- Modify: `lib/ui/chat/image_picker_button.dart`
- Test: `test/ui/chat_image_paste_test.dart`

**Interfaces:**
- Consumes: `ImagePasteService`
- Consumes: `PendingImageAttachment`
- Consumes: `AppController.modelSupportsImagesForConversation`
- Produces: paste action matrix behavior from spec

- [x] **Step 1: 写失败 widget 测试：普通文本粘贴和图片路径粘贴**

Create `test/ui/chat_image_paste_test.dart` with a testable `ChatPane` harness. Include tests:

```dart
testWidgets('paste inserts normal text through controlled paste action', (tester) async {
  final controller = fakeAppController(supportsImages: true);
  await tester.pumpWidget(buildChatPane(controller));
  await tester.enterText(find.byType(TextField), 'hello ');

  await invokePasteAction(tester, clipboardText: 'world');

  expect(find.textContaining('hello world'), findsOneWidget);
});

testWidgets('paste image path adds attachment instead of text', (tester) async {
  final image = await createTempPng();
  final controller = fakeAppController(supportsImages: true);
  await tester.pumpWidget(buildChatPane(controller));

  await invokePasteAction(tester, clipboardText: image.path);

  expect(find.text(image.path), findsNothing);
  expect(find.byTooltip('移除图片 1'), findsOneWidget);
});
```

Use a small fake `ImagePasteService` injected into `ChatPane` if direct system clipboard testing is brittle.

- [x] **Step 2: 运行失败测试**

Run: `flutter test test/ui/chat_image_paste_test.dart`

Expected: FAIL because `ChatPane` does not expose injectable paste service or controlled paste action.

- [x] **Step 3: 注入服务并替换 `_pendingImages`**

In `ChatPane`, add optional constructor parameter:

```dart
final ImagePasteService? imagePasteService;
```

In state:

```dart
late final ImagePasteService imagePasteService =
    widget.imagePasteService ?? ImagePasteService();
final List<PendingImageAttachment> _pendingImages = [];
```

- [x] **Step 4: 用 Shortcuts/Actions 接管 paste**

Wrap the `TextField` with:

```dart
Shortcuts(
  shortcuts: const <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.keyV, meta: true): PasteTextIntent(SelectionChangedCause.keyboard),
    SingleActivator(LogicalKeyboardKey.keyV, control: true): PasteTextIntent(SelectionChangedCause.keyboard),
  },
  child: Actions(
    actions: <Type, Action<Intent>>{
      PasteTextIntent: CallbackAction<PasteTextIntent>(
        onInvoke: (_) {
          unawaited(_handleControlledPaste());
          return null;
        },
      ),
    },
    child: TextField(...),
  ),
)
```

Implement:

```dart
Future<void> _handleControlledPaste() async {
  final textBefore = textController.value;
  final supportsImages = widget.controller.modelSupportsImagesForConversation(widget.conversationId);
  final imageCandidates = supportsImages
      ? await imagePasteService.readClipboardImageCandidates()
      : const <PendingImageAttachment>[];
  if (imageCandidates.isNotEmpty) {
    setState(() => _pendingImages.addAll(imageCandidates));
    return;
  }
  final clipboardText = await Clipboard.getData(Clipboard.kTextPlain);
  final text = clipboardText?.text ?? '';
  if (text.isEmpty) {
    return;
  }
  if (supportsImages) {
    final pathResult = await imagePasteService.parsePastedImagePath(text);
    if (pathResult.isImagePath && pathResult.path != null) {
      await _addPendingImageFile(File(pathResult.path!), PendingImageSource.pastedPath);
      return;
    }
    if (pathResult.errorMessage != null) {
      _showInputError(pathResult.errorMessage!);
      return;
    }
  } else if (await imagePasteService.parsePastedImagePath(text).then((r) => r.isImagePath)) {
    _showInputError('当前模型不支持图片输入');
    return;
  }
  textController.value = ImagePasteService.insertText(textBefore, text);
}
```

- [x] **Step 5: 更新预览列表**

`ImagePreviewList` takes `List<PendingImageAttachment>` and renders:

```dart
Semantics(
  label: '图片 $index',
  child: Image.file(attachment.file, fit: BoxFit.cover, ...),
)
IconButton(
  tooltip: '移除图片 $index',
  icon: const Icon(Icons.close, size: 12),
  onPressed: onRemove,
)
if (attachment.status != PendingImageStatus.ready)
  Tooltip(message: attachment.errorMessage ?? '图片不可用', child: const Icon(Icons.error_outline))
```

- [x] **Step 6: 添加入口门禁**

Before file picker/drop/paste image attachment:

```dart
bool _canAddImages() {
  final allowed = widget.controller.modelSupportsImagesForConversation(widget.conversationId);
  if (!allowed) {
    _showInputError('当前模型不支持图片输入');
  }
  return allowed;
}
```

Use it in picker, drop, and paste image branches.

- [x] **Step 7: 提交事务 UI 回调**

In `_submit`, do not clear text/images immediately. Generate `messageId`, call `imageService.savePendingImages`, then call dispatch with `onUserMessageCommitted`:

```dart
var committed = false;
await widget.controller.dispatchConversation(
  widget.conversationId,
  text,
  userMessageId: messageId,
  preparedAttachments: attachments,
  onUserMessageCommitted: () {
    committed = true;
    if (!mounted) return;
    setState(() {
      textController.clear();
      _pendingImages.clear();
    });
  },
);
if (!committed) {
  await widget.controller.imageService.deleteMessageImages(attachments);
}
```

- [x] **Step 8: 运行验证**

Run: `flutter test test/ui/chat_image_paste_test.dart test/ui/message_image_grid_test.dart`

Expected: PASS.

- [x] **Step 9: 提交或记录差异**

If commits are authorized:

```bash
git add lib/ui/chat/chat_pane.dart lib/ui/chat/image_preview_list.dart lib/ui/chat/image_picker_button.dart test/ui/chat_image_paste_test.dart
git commit -m "feat: 接管聊天图片粘贴体验"
```

---

### Task 7: 消息图片渲染、删除清理和完整回归

**Estimate:** 1.5-2.5 小时。依据：已有 `MessageImageGrid` 和会话删除逻辑；主要补缺失占位、会话清理和全量验证。

**Files:**
- Modify: `lib/ui/chat/message_image_grid.dart`
- Modify: `lib/ui/chat/message_bubble.dart`
- Modify: `lib/application/conversation_controller.dart`
- Modify: `lib/application/app_controller.dart`
- Test: `test/ui/message_image_grid_test.dart`
- Test: `test/application/image_dispatch_test.dart`

**Interfaces:**
- Consumes: `ImageService.deleteMessageImages`
- Consumes: `ImageService.cleanupConversationImages`
- Produces: missing image placeholder and semantic labels

- [x] **Step 1: 写失败测试：缺失图片稳定占位**

Extend `test/ui/message_image_grid_test.dart`:

```dart
testWidgets('message image grid shows placeholder for missing file', (tester) async {
  final root = await Directory.systemTemp.createTemp('ai_team_missing_image_');
  addTearDown(() async => root.delete(recursive: true));
  final service = ImageService(root);

  await tester.pumpWidget(MaterialApp(
    home: MessageImageGrid(
      imageService: service,
      attachments: const [
        MessageAttachment(
          id: 'image-1',
          type: MessageAttachmentType.image,
          filePath: 'images/conv/missing.png',
          fileName: 'missing.png',
        ),
      ],
    ),
  ));

  expect(find.byIcon(Icons.broken_image), findsOneWidget);
});
```

- [x] **Step 2: 运行失败测试**

Run: `flutter test test/ui/message_image_grid_test.dart`

Expected: FAIL if widget does not provide stable placeholder or missing imports.

- [x] **Step 3: 改进 `MessageImageGrid`**

Use fixed constraints and semantics:

```dart
Semantics(
  label: '消息图片 ${i + 1}',
  button: true,
  child: GestureDetector(
    onTap: () => _showFullImage(context, images: images, index: i),
    child: SizedBox(
      width: images.length == 1 ? 300 : 100,
      height: images.length == 1 ? 200 : 100,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          imageService.getImageFile(images[i]),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.broken_image, color: Colors.grey),
          ),
        ),
      ),
    ),
  ),
)
```

- [x] **Step 4: 会话删除清理图片**

Inject `ImageService` into `ConversationController` or let `AppController.deleteConversationSession` call cleanup after state deletion:

```dart
void deleteConversationSession(String conversationId) {
  _conversations.deleteConversationSession(conversationId);
  unawaited(imageService.cleanupConversationImages(conversationId));
}
```

If `AppController` lacks `dart:async`, import it.

- [x] **Step 5: 测试会话删除清理**

Add to `test/application/image_dispatch_test.dart`:

```dart
test('delete conversation cleans conversation image directory', () async {
  final controller = await createControllerForTest();
  final conversationId = controller.currentConversation.id;
  final dir = Directory('${controller.imageService.workspaceRoot.path}/images/$conversationId');
  dir.createSync(recursive: true);
  File('${dir.path}/orphan.png').writeAsBytesSync(_onePixelPng);

  controller.deleteConversationSession(conversationId);
  await Future<void>.delayed(Duration.zero);

  expect(dir.existsSync(), isFalse);
});
```

- [x] **Step 6: 运行完整相关验证**

Run: `flutter test test/core/domain/configuration_export_test.dart test/core/workspace/image_paste_service_test.dart test/core/workspace/image_service_test.dart test/core/model/model_gateway_test.dart test/application/image_dispatch_test.dart test/application/task_queue_image_test.dart test/ui/chat_image_paste_test.dart test/ui/message_image_grid_test.dart`

Expected: PASS.

Run: `flutter analyze`

Expected: `No issues found!` or only pre-existing unrelated warnings documented in the handoff.

- [x] **Step 7: 提交或记录差异**

If commits are authorized:

```bash
git add lib/ui/chat/message_image_grid.dart lib/ui/chat/message_bubble.dart lib/application/conversation_controller.dart lib/application/app_controller.dart test/ui/message_image_grid_test.dart test/application/image_dispatch_test.dart
git commit -m "feat: 完善消息图片预览和清理"
```

---

## Final Verification

Run these commands after all tasks are implemented:

```bash
flutter test
flutter analyze
```

Expected:
- `flutter test`: all tests pass.
- `flutter analyze`: no new issues. Any pre-existing issue must be listed with file and line.

Manual desktop checks on macOS:
- Copy a screenshot and paste into chat input: a thumbnail appears, no text inserted.
- Copy an image file in Finder and paste: a thumbnail appears.
- Paste a normal text sentence: text inserts at the cursor.
- Paste a local image path: thumbnail appears, path text is not inserted.
- Switch to a model with `supportsImages=false`: image paste is rejected, normal text paste still works.
- Queue a task with an image: one queued user message exists; running the queue does not create a duplicate user message.

---

## Time Estimate

- Task 1: 45-75 分钟。字段、序列化和 UI 开关，低外部依赖。
- Task 2: 2-3.5 小时。路径解析和 `super_clipboard` item 遍历不确定性较高。
- Task 3: 1.5-2.5 小时。事务保存和 gateway 错误路径，主要风险是回滚测试。
- Task 4: 2-4 小时。跨应用层和 orchestrator，状态边界复杂。
- Task 5: 2-3 小时。队列已有 `messageIds`，但运行时复用需要谨慎改请求历史。
- Task 6: 3-5 小时。UI paste action 和 widget 测试最复杂。
- Task 7: 1.5-2.5 小时。渲染和清理收尾，风险中等。
- Total: 13-23.5 小时，不包含用户等待、代码审查、CI 排队、平台剪贴板手工验证时间。

## Plan Self-Review

### 检查项

- 覆盖 spec 的目标、非目标、粘贴服务、可控粘贴、提交事务、模型能力、队列、UI、错误处理、测试、迁移和验收标准。
- 检查所有任务是否有文件路径、接口、测试命令和预期结果。
- 检查是否存在占位词、未完成标记、含糊处理语句或引用前文替代完整步骤的不可执行表述。
- 检查类型名和方法名是否在前后任务中一致。
- 检查估时是否按文件数量、改动范围、验证成本和未知项给出。

### 发现

- 计划覆盖全部 spec 关键要求。
- Task 2 已按本机 `super_clipboard 0.8.24` 源码写明 `ClipboardReader.items`、`readValue(Formats.fileUri)` 和 `getFile(Formats.png/jpeg/gif/webp/bmp)` 的使用方式。
- 队列运行时复用排队用户消息会触及现有 orchestrator 行为，是 Task 5 的主要风险。

### 修改

- 已把提交步骤改为“仅用户授权时提交”，避免违反当前 Git 约束。
- 已把队列附件设计改为复用 `QueuedTask.messageIds`，不新增队列图片字段。
- 已加入 unsupported model paste 交叉测试和普通文本 selection/composing 测试。

### 剩余风险

- `super_clipboard` 桌面文件列表在 macOS/Windows/Linux 的实际格式需要实现时验证。
- 当前工作区已有图片功能原型改动，执行计划时必须先区分已有改动来源，不能误删用户工作。
- 队列运行复用用户消息可能需要调整模型请求历史，必须通过任务队列回归测试确认没有重复上下文。

### 时间评估

- 总估时 13-23.5 小时来自 7 个任务估时汇总。
- 最不可靠估时是 Task 2 和 Task 6，因为剪贴板插件行为和 widget paste action 测试可能需要试验。
- 估时不包含用户等待、CI 排队、权限审批、外部服务响应和手工跨平台验证。

### 结论

通过。
