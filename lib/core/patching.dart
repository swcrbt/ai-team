import 'dart:io';

import 'domain.dart';

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
