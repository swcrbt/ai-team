import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import '../domain.dart';
import 'pending_image_attachment.dart';

/// 图片服务异常
class ImageServiceException implements Exception {
  const ImageServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 图片管理服务
class ImageService {
  ImageService(this.workspaceRoot);

  final Directory workspaceRoot;

  /// 获取图片目录
  Directory _getImageDirectory(String conversationId) {
    return Directory(
      path.join(workspaceRoot.path, 'images', conversationId),
    );
  }

  /// 保存本地文件到 workspace
  Future<MessageAttachment> saveImage({
    required String conversationId,
    required String messageId,
    required File sourceFile,
    required int index,
  }) async {
    final imageDir = _getImageDirectory(conversationId);
    if (!imageDir.existsSync()) {
      imageDir.createSync(recursive: true);
    }

    final extension = path.extension(sourceFile.path);
    final fileName = '$messageId-$index$extension';
    final targetFile = File(path.join(imageDir.path, fileName));

    await sourceFile.copy(targetFile.path);

    final fileSize = await targetFile.length();
    final mimeType = lookupMimeType(targetFile.path);

    int? width;
    int? height;
    try {
      final image = img.decodeImage(await targetFile.readAsBytes());
      if (image != null) {
        width = image.width;
        height = image.height;
      }
    } catch (e) {
      // 图片解码失败，忽略尺寸
    }

    return MessageAttachment(
      id: '$messageId-$index',
      type: MessageAttachmentType.image,
      filePath: path.relative(targetFile.path, from: workspaceRoot.path),
      mimeType: mimeType,
      fileName: path.basename(sourceFile.path),
      fileSize: fileSize,
      width: width,
      height: height,
    );
  }

  /// 从字节数据保存（用于剪贴板）
  Future<MessageAttachment> saveImageFromBytes({
    required String conversationId,
    required String messageId,
    required Uint8List imageData,
    required int index,
    String extension = '.png',
  }) async {
    final imageDir = _getImageDirectory(conversationId);
    if (!imageDir.existsSync()) {
      imageDir.createSync(recursive: true);
    }

    final fileName = '$messageId-$index$extension';
    final targetFile = File(path.join(imageDir.path, fileName));
    await targetFile.writeAsBytes(imageData);

    final fileSize = imageData.length;
    final mimeType = lookupMimeType(targetFile.path);

    int? width;
    int? height;
    try {
      final image = img.decodeImage(imageData);
      if (image != null) {
        width = image.width;
        height = image.height;
      }
    } catch (e) {
      // 忽略
    }

    return MessageAttachment(
      id: '$messageId-$index',
      type: MessageAttachmentType.image,
      filePath: path.relative(targetFile.path, from: workspaceRoot.path),
      mimeType: mimeType,
      fileName: fileName,
      fileSize: fileSize,
      width: width,
      height: height,
    );
  }

  /// 获取图片文件
  File getImageFile(MessageAttachment attachment) {
    return File(path.join(workspaceRoot.path, attachment.filePath));
  }

  /// 读取图片为 base64 data URL
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

  /// 删除消息的所有图片
  Future<void> deleteMessageImages(List<MessageAttachment> attachments) async {
    for (final attachment in attachments) {
      try {
        final file = getImageFile(attachment);
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (e) {
        // 忽略删除错误
      }
    }
  }

  /// 清理对话的所有图片
  Future<void> cleanupConversationImages(String conversationId) async {
    final imageDir = _getImageDirectory(conversationId);
    if (imageDir.existsSync()) {
      try {
        await imageDir.delete(recursive: true);
      } catch (e) {
        // 忽略
      }
    }
  }

  /// 保存待处理图片列表（事务性）
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
      // 回滚已保存的文件
      for (final file in created) {
        if (file.existsSync()) {
          await file.delete();
        }
      }
      // 删除空目录
      final imageDir = _getImageDirectory(conversationId);
      if (imageDir.existsSync() && imageDir.listSync().isEmpty) {
        await imageDir.delete();
      }
      if (error is ImageServiceException) {
        rethrow;
      }
      throw ImageServiceException('图片保存失败：$error');
    }
  }

  /// 删除附件对应的图片文件
  Future<void> deleteAttachments(List<MessageAttachment> attachments) async {
    for (final attachment in attachments) {
      if (attachment.type != MessageAttachmentType.image) {
        continue;
      }
      try {
        final file = getImageFile(attachment);
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (e) {
        // 忽略删除错误
      }
    }
  }
}
