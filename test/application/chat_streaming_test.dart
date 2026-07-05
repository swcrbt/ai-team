import 'package:ai_team/application/chat_streaming.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streaming text partition commits stable lines and keeps live tail', () {
    final partition = StreamingTextPartition();

    var update = partition.apply('第一行\n第二');

    expect(update.reset, isFalse);
    expect(update.newStableSegments, ['第一行\n']);
    expect(update.tailChanged, isTrue);
    expect(partition.stableSegments, ['第一行\n']);
    expect(partition.liveTail, '第二');

    update = partition.apply('第一行\n第二行\n第三');

    expect(update.reset, isFalse);
    expect(update.newStableSegments, ['第二行\n']);
    expect(update.tailChanged, isTrue);
    expect(partition.stableSegments, ['第一行\n', '第二行\n']);
    expect(partition.liveTail, '第三');
  });

  test('streaming text partition rebuilds on non append updates', () {
    final partition = StreamingTextPartition();

    partition.apply('旧第一行\n旧尾巴');
    final update = partition.apply('新第一行\n新尾巴');

    expect(update.reset, isTrue);
    expect(update.newStableSegments, ['新第一行\n']);
    expect(partition.stableSegments, ['新第一行\n']);
    expect(partition.liveTail, '新尾巴');
  });
}
