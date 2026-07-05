String createUnifiedDiff(
  String filePath,
  String originalContent,
  String proposedContent,
) {
  final originalLines = originalContent.split('\n');
  final proposedLines = proposedContent.split('\n');
  final buffer = StringBuffer()
    ..writeln('--- $filePath')
    ..writeln('+++ $filePath')
    ..writeln('@@');
  final maxLength = originalLines.length > proposedLines.length
      ? originalLines.length
      : proposedLines.length;
  for (var index = 0; index < maxLength; index++) {
    final oldLine = index < originalLines.length ? originalLines[index] : null;
    final newLine = index < proposedLines.length ? proposedLines[index] : null;
    if (oldLine == newLine) {
      if (oldLine != null && oldLine.isNotEmpty) {
        buffer.writeln(' $oldLine');
      }
      continue;
    }
    if (oldLine != null && oldLine.isNotEmpty) {
      buffer.writeln('-$oldLine');
    }
    if (newLine != null && newLine.isNotEmpty) {
      buffer.writeln('+$newLine');
    }
  }
  return buffer.toString();
}
