import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

import 'support/fake_dsh.dart';

void main() {
  test('large snapshot and following event stay in order through worker decoding', () async {
    final host = await FakeDsh.start();
    addTearDown(host.close);
    final requests = <Map<Object?, Object?>>[];
    host.onOpen = (socket, id, endpoint, payload) {
      if (endpoint != 'session/follow') return;
      requests.add((payload['args'] as Map<Object?, Object?>)['request'] as Map<Object?, Object?>);
      final records = [
        for (var i = 0; i < 120; i++)
          {
            'type': 'event',
            'event': {
              'type': 'permission/preset',
              'seq': i,
              'time': i,
              'data': {'preset': 'workspace-write', 'padding': 'x' * 900},
            },
          },
      ];
      socket.item(id, {
        'type': 'snapshot',
        'header': {'version': 4, 'id': 's', 'createdAt': 0, 'isSeeded': false},
        'cursor': 119,
        'records': records,
        'hasMore': true,
        'projections': {'asOfSeq': 119, 'values': {}},
      });
      socket.item(id, {
        'type': 'event',
        'event': {
          'type': 'permission/preset',
          'seq': 120,
          'time': 120,
          'data': {'preset': 'workspace-write'},
        },
      });
    };
    final client = await DshClient.connect(
      baseUri: host.baseUri,
      token: FakeDsh.token,
      backgroundMuxDecode: true,
      backgroundLists: true,
    );
    addTearDown(client.close);
    final events = await client
        .watch(
          's',
          options: const WatchOptions(turnWindow: TurnWindow(10, 1), maxMessages: 50, backgroundSnapshotParsing: true),
        )
        .where((e) => e is SessionSnapshotEvent || e is SessionLogEvent)
        .take(2)
        .toList()
        .timeout(const Duration(seconds: 10));
    expect(requests.single['maxMessages'], 50);
    expect(requests.single['turnWindow'], {'minMessages': 10, 'minTurns': 1});
    final snapshot = events.first as SessionSnapshotEvent;
    expect(snapshot.events.length, 120);
    expect(snapshot.hasMore, isTrue);
    expect(snapshot.cursor, 119);
    expect((events.last as SessionLogEvent).seq, 120);
  });
}
