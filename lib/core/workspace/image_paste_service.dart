import 'dart:async';
import 'dart:io';

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

class ImageClipboardItem {
  const ImageClipboardItem({
    this.fileUri,
    this.imageBytesByExtension = const {},
  });

  final Uri? fileUri;
  final Map<String, Uint8List> imageBytesByExtension;
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
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (error) {
      return ImagePathParseResult.error('图片不可读：$error');
    }
    final image = _decodeImage(bytes);
    if (image == null) {
      return const ImagePathParseResult.error('图片无法解码');
    }
    return ImagePathParseResult.image(file.path);
  }

  static TextEditingValue insertText(TextEditingValue value, String text) {
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final normalizedStart = start.clamp(0, value.text.length);
    final normalizedEnd = end.clamp(0, value.text.length);
    final replaceStart = normalizedStart < normalizedEnd
        ? normalizedStart
        : normalizedEnd;
    final replaceEnd = normalizedStart < normalizedEnd
        ? normalizedEnd
        : normalizedStart;
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
    final image = _decodeImage(bytes);
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
    final image = _decodeImage(bytes);
    if (image == null) {
      return failedAttachment(source: source, errorMessage: '图片无法解码');
    }
    final file = File(
      '${Directory.systemTemp.path}/ai_team_clipboard_image_'
      '${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return PendingImageAttachment(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      source: source,
      file: file,
      ownedTemporaryFile: true,
      mimeType: lookupMimeType(file.path),
      fileSize: bytes.length,
      width: image.width,
      height: image.height,
    );
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

  Future<List<PendingImageAttachment>> readClipboardImageCandidates() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      throw const ImagePasteException('剪贴板不可用');
    }
    final reader = await clipboard.read();
    final items = <ImageClipboardItem>[];
    for (final item in reader.items) {
      final fileUri = await item.readValue(Formats.fileUri);
      if (fileUri != null) {
        items.add(ImageClipboardItem(fileUri: fileUri));
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
        items.add(
          ImageClipboardItem(imageBytesByExtension: {
            candidate.extension: bytes,
          }),
        );
        break;
      }
    }
    return attachmentsFromClipboardItems(items);
  }

  Future<List<PendingImageAttachment>> attachmentsFromClipboardItems(
    Iterable<ImageClipboardItem> items,
  ) async {
    final result = <PendingImageAttachment>[];
    for (final item in items) {
      final fileUri = item.fileUri;
      if (fileUri != null) {
        final parsed = await parsePastedImagePath(fileUri.toString());
        if (parsed.isImagePath && parsed.path != null) {
          result.add(
            await attachmentFromFile(
              File(parsed.path!),
              PendingImageSource.clipboardFile,
              ownedTemporaryFile: false,
            ),
          );
        } else if (parsed.errorMessage != null) {
          result.add(
            failedAttachment(
              source: PendingImageSource.clipboardFile,
              errorMessage: parsed.errorMessage!,
            ),
          );
        }
        continue;
      }
      for (final candidate in const [
        '.png',
        '.jpg',
        '.gif',
        '.webp',
        '.bmp',
      ]) {
        final bytes = item.imageBytesByExtension[candidate];
        if (bytes == null || bytes.isEmpty) {
          continue;
        }
        result.add(
          await attachmentFromBytes(
            bytes,
            extension: candidate,
            source: PendingImageSource.clipboardImage,
          ),
        );
        break;
      }
    }
    return result;
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
    candidate = candidate.replaceAll('\\ ', ' ');
    if (candidate.contains(' ') && !File(candidate).existsSync()) {
      return null;
    }
    return candidate;
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

  img.Image? _decodeImage(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }
}
