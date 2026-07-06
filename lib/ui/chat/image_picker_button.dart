import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

/// 图片选择按钮
class ImagePickerButton extends StatelessWidget {
  const ImagePickerButton({
    super.key,
    required this.onImagesPicked,
    this.enabled = true,
  });

  final void Function(List<File> files) onImagesPicked;
  final bool enabled;

  Future<void> _pickImages() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      dialogTitle: '选择图片',
    );

    if (result != null && result.files.isNotEmpty) {
      final files = result.files
          .where((file) => file.path != null)
          .map((file) => File(file.path!))
          .toList();

      if (files.isNotEmpty) {
        onImagesPicked(files);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.image_outlined, size: 20),
      tooltip: '添加图片',
      onPressed: enabled ? _pickImages : null,
      splashRadius: 20,
    );
  }
}
