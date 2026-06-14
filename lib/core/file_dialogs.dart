import 'package:file_picker/file_picker.dart';

abstract class FileDialogService {
  Future<String?> pickDirectory();

  Future<String?> pickOpenFile({
    required List<String> allowedExtensions,
  });

  Future<String?> pickSaveFile({
    required String fileName,
    required List<String> allowedExtensions,
  });
}

class SystemFileDialogService implements FileDialogService {
  const SystemFileDialogService();

  @override
  Future<String?> pickDirectory() {
    return FilePicker.getDirectoryPath();
  }

  @override
  Future<String?> pickOpenFile({
    required List<String> allowedExtensions,
  }) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      allowMultiple: false,
    );
    return result?.files.single.path;
  }

  @override
  Future<String?> pickSaveFile({
    required String fileName,
    required List<String> allowedExtensions,
  }) {
    return FilePicker.saveFile(
      dialogTitle: '保存配置',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
  }
}

class FakeFileDialogService implements FileDialogService {
  const FakeFileDialogService({
    this.directoryPath,
    this.openPath,
    this.savePath,
  });

  final String? directoryPath;
  final String? openPath;
  final String? savePath;

  @override
  Future<String?> pickDirectory() async => directoryPath;

  @override
  Future<String?> pickOpenFile({
    required List<String> allowedExtensions,
  }) async =>
      openPath;

  @override
  Future<String?> pickSaveFile({
    required String fileName,
    required List<String> allowedExtensions,
  }) async =>
      savePath;
}
