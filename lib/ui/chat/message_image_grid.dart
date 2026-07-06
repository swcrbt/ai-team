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
            Semantics(
              label: '消息图片 ${i + 1}',
              button: true,
              child: GestureDetector(
                onTap: () => _showFullImage(
                  context,
                  images: images,
                  index: i,
                ),
                child: SizedBox(
                  width: images.length == 1 ? 300 : 100,
                  height: images.length == 1 ? 200 : 100,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        imageService.getImageFile(images[i]),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(Icons.broken_image, color: Colors.grey),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
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
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(20),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              child: Image.file(
                imageService.getImageFile(attachments[initialIndex]),
              ),
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
