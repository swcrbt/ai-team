import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../domain.dart';
import 'pending_image_attachment.dart';

class ImageServiceException implements Exception {
  const ImageServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ImageService {
  const ImageService(this.workspaceRoot);

  final Directory workspaceRoot;

  Future<MessageAttachment> saveImage({
    required String conversationId,
    required String messageId,
    required File sourceFile,
    required int index,
    String? mimeType,
  }) async {
    if (!sourceFile.existsSync()) {
      throw ImageServiceException('图片文件不存在：${sourceFile.path}');
    }
    final imageDir = imageDirectoryForConversation(conversationId);
    await imageDir.create(recursive: true);
    final safeExtension = _safeExtensionFor(sourceFile);
    final relativePath = _imageRelativePath(
      conversationId: conversationId,
      messageId: messageId,
      index: index,
      extension: safeExtension,
    );
    final destination = File(path.join(workspaceRoot.path, relativePath));
    if (destination.existsSync()) {
      throw ImageServiceException('图片文件已存在：$relativePath');
    }
    await sourceFile.copy(destination.path);
    final stat = await destination.stat();
    return MessageAttachment(
      id: 'image-$messageId-$index',
      type: MessageAttachmentType.image,
      filePath: relativePath,
      mimeType: mimeType ?? _mimeTypeForExtension(safeExtension),
      fileSize: stat.size,
    );
  }

  Future<List<MessageAttachment>> savePendingImages({
    required String conversationId,
    required String messageId,
    required List<PendingImageAttachment> images,
  }) async {
    final attachments = <MessageAttachment>[];
    final created = <File>[];
    final imageDir = imageDirectoryForConversation(conversationId);
    final createdImageDir = !imageDir.existsSync();
    try {
      for (var index = 0; index < images.length; index++) {
        final pending = images[index];
        if (!pending.canSubmit) {
          throw ImageServiceException(pending.errorMessage ?? '图片不可提交');
        }
        final destination = File(path.join(
          workspaceRoot.path,
          _imageRelativePath(
            conversationId: conversationId,
            messageId: messageId,
            index: index,
            extension: _safeExtensionFor(pending.file),
          ),
        ));
        if (destination.existsSync()) {
          throw ImageServiceException('图片文件已存在：${destination.path}');
        }
        created.add(destination);
        final attachment = await saveImage(
          conversationId: conversationId,
          messageId: messageId,
          sourceFile: pending.file,
          index: index,
          mimeType: pending.mimeType,
        );
        attachments.add(attachment);
      }
      return attachments;
    } catch (error) {
      for (final file in created) {
        if (file.existsSync()) {
          await file.delete();
        }
      }
      if (createdImageDir &&
          imageDir.existsSync() &&
          imageDir.listSync().isEmpty) {
        await imageDir.delete();
      }
      throw ImageServiceException('图片保存失败：$error');
    }
  }

  Future<void> deleteAttachments(List<MessageAttachment> attachments) async {
    for (final attachment in attachments) {
      if (attachment.type != MessageAttachmentType.image) {
        continue;
      }
      final file = getImageFile(attachment);
      if (file.existsSync()) {
        await file.delete();
      }
    }
  }

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

  File getImageFile(MessageAttachment attachment) {
    return File(path.join(workspaceRoot.path, attachment.filePath));
  }

  Directory imageDirectoryForConversation(String conversationId) {
    return Directory(path.join(workspaceRoot.path, 'images', conversationId));
  }
}

String _safeExtensionFor(File file) {
  final extension = path.extension(file.path).toLowerCase();
  return extension.isEmpty ? '.png' : extension;
}

String _imageRelativePath({
  required String conversationId,
  required String messageId,
  required int index,
  required String extension,
}) {
  return path.join(
    'images',
    conversationId,
    '$messageId-$index$extension',
  );
}

String _mimeTypeForExtension(String extension) {
  return switch (extension) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.webp' => 'image/webp',
    '.gif' => 'image/gif',
    _ => 'image/png',
  };
}
