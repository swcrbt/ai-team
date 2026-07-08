import 'package:flutter/material.dart';
import '../../core/domain.dart';
import '../../core/workspace/image_service.dart';

List<MessageAttachment> messageImageAttachments(
  List<MessageAttachment> attachments,
) {
  return attachments
      .where((attachment) => attachment.type == MessageAttachmentType.image)
      .toList(growable: false);
}

/// 消息中的图片网格
class MessageImageGrid extends StatelessWidget {
  const MessageImageGrid({
    super.key,
    required this.attachments,
    required this.imageService,
  });

  final List<MessageAttachment> attachments;
  final ImageService imageService;

  void _showFullImage(
    BuildContext context, {
    required List<MessageAttachment> images,
    required int index,
  }) {
    showDialog(
      context: context,
      builder: (context) => _ImageDialog(
        attachments: images,
        initialIndex: index,
        imageService: imageService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = messageImageAttachments(attachments);

    if (images.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var i = 0; i < images.length; i++)
            _MessageImageTile(
              attachment: images[i],
              imageService: imageService,
              index: i,
              imageCount: images.length,
              onTap: () => _showFullImage(
                context,
                images: images,
                index: i,
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageImageTile extends StatelessWidget {
  const _MessageImageTile({
    required this.attachment,
    required this.imageService,
    required this.index,
    required this.imageCount,
    required this.onTap,
  });

  final MessageAttachment attachment;
  final ImageService imageService;
  final int index;
  final int imageCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final file = imageService.getImageFile(attachment);

    return Semantics(
      label: '消息图片 ${index + 1}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: imageCount == 1 ? 300 : 100,
          height: imageCount == 1 ? 200 : 100,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: file.existsSync()
                  ? Image.file(
                      file,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const _BrokenImagePlaceholder(),
                    )
                  : const _BrokenImagePlaceholder(),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrokenImagePlaceholder extends StatelessWidget {
  const _BrokenImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.broken_image, color: Colors.grey),
    );
  }
}

/// 全屏图片查看对话框
class _ImageDialog extends StatelessWidget {
  const _ImageDialog({
    required this.attachments,
    required this.initialIndex,
    required this.imageService,
  });

  final List<MessageAttachment> attachments;
  final int initialIndex;
  final ImageService imageService;

  @override
  Widget build(BuildContext context) {
    final file = imageService.getImageFile(attachments[initialIndex]);

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(20),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: file.existsSync()
                  ? Image.file(file)
                  : const _BrokenImagePlaceholder(),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
