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
