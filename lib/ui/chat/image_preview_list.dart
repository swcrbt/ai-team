import 'package:flutter/material.dart';
import '../../core/workspace/pending_image_attachment.dart';

/// 待发送图片预览列表
class ImagePreviewList extends StatelessWidget {
  const ImagePreviewList({
    super.key,
    required this.images,
    required this.onRemove,
  });

  final List<PendingImageAttachment> images;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < images.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _ImagePreviewItem(
                attachment: images[i],
                index: i + 1,
                onRemove: () => onRemove(i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImagePreviewItem extends StatelessWidget {
  const _ImagePreviewItem({
    required this.attachment,
    required this.index,
    required this.onRemove,
  });

  final PendingImageAttachment attachment;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE5E7EB)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Semantics(
              label: '图片 $index',
              child: Image.file(
                attachment.file,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(Icons.broken_image, size: 24, color: Colors.grey),
                  );
                },
              ),
            ),
          ),
        ),
        // 图片序号
        Positioned(
          bottom: 2,
          left: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        // 删除按钮
        Positioned(
          top: 2,
          right: 2,
          child: Tooltip(
            message: '移除图片 $index',
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
        // 错误指示器
        if (attachment.status != PendingImageStatus.ready)
          Positioned(
            bottom: 2,
            right: 2,
            child: Tooltip(
              message: attachment.errorMessage ?? '图片不可用',
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
