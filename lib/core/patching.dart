import 'dart:io';

import 'domain.dart';

class PatchProposal {
  const PatchProposal({
    required this.id,
    required this.filePath,
    required this.originalContent,
    required this.proposedContent,
    required this.memberName,
    required this.diff,
    this.status = PatchStatus.pending,
  });

  final String id;
  final String filePath;
  final String originalContent;
  final String proposedContent;
  final String memberName;
  final String diff;
  final PatchStatus status;

  factory PatchProposal.fromFileChange({
    required String id,
    required String filePath,
    required String originalContent,
    required String proposedContent,
    required String memberName,
  }) {
    return PatchProposal(
      id: id,
      filePath: filePath,
      originalContent: originalContent,
      proposedContent: proposedContent,
      memberName: memberName,
      diff: _createUnifiedDiff(filePath, originalContent, proposedContent),
    );
  }

  PatchProposal copyWith({PatchStatus? status}) => PatchProposal(
        id: id,
        filePath: filePath,
        originalContent: originalContent,
        proposedContent: proposedContent,
        memberName: memberName,
        diff: diff,
        status: status ?? this.status,
      );
}

class PatchApplier {
  Future<PatchProposal> apply(PatchProposal proposal) async {
    if (proposal.status != PatchStatus.pending) {
      return proposal;
    }
    final file = File(proposal.filePath);
    final current = await file.exists() ? await file.readAsString() : '';
    if (current != proposal.originalContent) {
      throw StateError('文件内容已变化，拒绝应用补丁: ${proposal.filePath}');
    }
    await file.writeAsString(proposal.proposedContent);
    return proposal.copyWith(status: PatchStatus.applied);
  }
}

String _createUnifiedDiff(
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
