import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/connection/connection_tree.dart';
import 'package:fl_clash/models/common.dart';
import 'package:flutter_test/flutter_test.dart';

final _start = DateTime.utc(2026, 11, 26);

TrackerInfo _connection(
  String id, {
  String process = '',
  String path = '',
  String host = '',
  String ip = '',
  String port = '',
  String network = '',
  String rule = '',
  String payload = '',
  List<String> chains = const [],
  int upload = 0,
  int download = 0,
  int? uploadSpeed,
  int? downloadSpeed,
  int second = 0,
  bool closed = false,
  bool failed = false,
  int uid = 0,
}) => TrackerInfo(
  id: id,
  start: _start.add(Duration(seconds: second)),
  metadata: Metadata(
    process: process,
    processPath: path,
    host: host,
    destinationIP: ip,
    destinationPort: port,
    network: network,
    uid: uid,
  ),
  rule: rule,
  rulePayload: payload,
  chains: chains,
  upload: upload,
  download: download,
  uploadSpeed: uploadSpeed,
  downloadSpeed: downloadSpeed,
  closedAt: closed || failed ? _start : null,
  failure: failed
      ? const ConnectionFailure(kind: ConnectionFailureKind.refused)
      : null,
);

void _update(
  ConnectionTree tree,
  List<TrackerInfo> rows, {
  bool grouped = true,
  String? column,
  bool descending = false,
}) => tree.update(
  rows,
  grouped: grouped,
  sortColumn: column,
  descending: descending,
);

class _ProjectionRunner {
  final tasks = <ConnectionTreeProjection Function()>[];
  final completions = <Completer<ConnectionTreeProjection>>[];

  Future<ConnectionTreeProjection> run(
    ConnectionTreeProjection Function() project,
  ) {
    tasks.add(project);
    final completer = Completer<ConnectionTreeProjection>();
    completions.add(completer);
    return completer.future;
  }

  Future<void> finish(int index) async {
    completions[index].complete(tasks[index]());
    await Future<void>.value();
  }

  Future<void> fail(int index) async {
    completions[index].completeError(StateError('projection failed'));
    await Future<void>.value();
  }
}

void main() {
  test('groups by real path without folding POSIX case or using uid', () {
    final tree = ConnectionTree();
    addTearDown(tree.dispose);
    _update(tree, [
      _connection(
        'windows-new',
        path: r'C:\Apps\Browser.exe',
        process: 'Browser',
        uid: 1,
      ),
      _connection(
        'windows-old',
        path: 'c:/apps/BROWSER.EXE',
        process: 'renamed',
        uid: 2,
      ),
      _connection(
        'other-path',
        path: r'D:\Apps\Browser.exe',
        process: 'Browser',
      ),
      _connection('posix-upper', path: '/opt/Browser', process: 'Browser'),
      _connection('posix-lower', path: '/opt/browser', process: 'Browser'),
    ]);

    expect(tree.groups.map((group) => group.ids), [
      ['windows-new', 'windows-old'],
      ['other-path'],
      ['posix-upper'],
      ['posix-lower'],
    ]);
    expect(tree.groups.first.key, 'path:c:/apps/browser.exe');
    expect(tree.groups.first.label, 'Browser');
    expect(tree.groups.first.representativeId, 'windows-new');
  });

  test('preserves significant POSIX path whitespace and backslashes', () {
    final tree = ConnectionTree();
    addTearDown(tree.dispose);
    _update(tree, [
      _connection('plain', path: '/opt/worker'),
      _connection('space', path: '/opt/worker '),
      _connection('upper', path: r'/opt/A\worker'),
      _connection('lower', path: r'/opt/a\worker'),
    ]);
    expect(tree.groups.map((group) => group.ids), [
      ['plain'],
      ['space'],
      ['upper'],
      ['lower'],
    ]);
    expect(tree.groups[2].label, r'A\worker');
  });

  test(
    'handles UNC paths process fallback basename and unknown separately',
    () {
      final tree = ConnectionTree();
      addTearDown(tree.dispose);
      _update(tree, [
        _connection('unc-a', path: r'\\Server\Apps\worker.exe'),
        _connection('unc-b', path: '//server/apps/WORKER.exe'),
        _connection('named-a', process: 'worker.exe', uid: 1),
        _connection('named-b', process: 'worker.exe', uid: 2),
        _connection('basename', path: '/usr/bin/worker.exe'),
        _connection('unknown-a'),
        _connection('unknown-b', process: '  ', path: ' '),
        _connection('path-like-label', process: '/usr/bin/worker.exe'),
      ]);

      expect(tree.groups.map((group) => group.ids), [
        ['unc-a', 'unc-b'],
        ['named-a', 'named-b'],
        ['basename'],
        ['unknown-a', 'unknown-b'],
        ['path-like-label'],
      ]);
      expect(tree.groups.map((group) => group.label), [
        'worker.exe',
        'worker.exe',
        'worker.exe',
        '',
        '/usr/bin/worker.exe',
      ]);
      expect(tree.groups[3].key, isEmpty);
    },
  );

  test('aggregates shown children and uses the latest actual start', () {
    final tree = ConnectionTree();
    addTearDown(tree.dispose);
    _update(tree, [
      _connection(
        'first',
        process: 'worker',
        upload: 10,
        download: 100,
        uploadSpeed: 5,
        downloadSpeed: 6,
        second: 1,
      ),
      _connection(
        'closed',
        process: 'worker',
        upload: 20,
        download: 200,
        second: 3,
        closed: true,
      ),
      _connection(
        'failed',
        process: 'worker',
        upload: 30,
        download: 300,
        failed: true,
      ),
      _connection(
        'other-active',
        process: 'worker',
        uploadSpeed: 7,
        downloadSpeed: 8,
      ),
    ]);

    final group = tree.groups.single;
    expect(group.upload, 60);
    expect(group.download, 600);
    expect(group.uploadSpeed, 12);
    expect(group.downloadSpeed, 14);
    expect(group.active, 2);
    expect(group.start, _start.add(const Duration(seconds: 3)));
    expect(group.representativeId, 'first');
    expect(tree.loading, isFalse);
    expect(tree.error, isNull);
    expect(() => group.ids.clear(), throwsUnsupportedError);
    expect(() => tree.groups.clear(), throwsUnsupportedError);
    expect(() => tree.ids.clear(), throwsUnsupportedError);
  });

  test('flat ids keep newest input order and only supplied filtered rows', () {
    final tree = ConnectionTree();
    addTearDown(tree.dispose);
    final rows = [
      _connection('new', process: 'a'),
      _connection('old', process: 'b', second: 10),
    ];
    _update(tree, rows, grouped: false, descending: true);
    expect(tree.groups, isEmpty);
    expect(tree.ids, ['new', 'old']);
    _update(tree, [rows.last]);
    expect(tree.groups.single.ids, ['old']);
    expect(tree.ids, ['old']);
    _update(tree, []);
    expect(tree.groups, isEmpty);
    expect(tree.ids, isEmpty);
    expect(tree.loading, isFalse);
  });

  final textCases = <String, List<TrackerInfo>>{
    'destination': [
      _connection('high', host: 'z.test', ip: '0.0.0.0'),
      _connection('low', ip: 'a.test', port: '80'),
      _connection('tie', host: 'A.TEST', port: '80'),
    ],
    'process': [
      _connection('high', process: 'z-worker'),
      _connection('low', path: r'C:\Apps\a-worker'),
      _connection('tie', process: 'A-worker'),
    ],
    'network': [
      _connection('high', network: 'udp'),
      _connection('low', network: 'tcp'),
      _connection('tie', network: 'TCP'),
    ],
    'rule': [
      _connection('high', rule: 'RULE-SET', payload: 'z'),
      _connection('low', rule: 'RULE-SET', payload: 'a'),
      _connection('tie', rule: 'rule-set', payload: 'A'),
    ],
    'exit': [
      _connection('high', chains: ['Zulu', 'A group']),
      _connection('low', chains: ['Alpha', 'Z group']),
      _connection('tie', chains: ['ALPHA', 'B group']),
    ],
  };
  for (final MapEntry(key: column, value: rows) in textCases.entries) {
    test('$column sorts both directions with stable case-insensitive ties', () {
      final tree = ConnectionTree();
      addTearDown(tree.dispose);
      _update(tree, rows, grouped: false, column: column);
      expect(tree.ids, ['low', 'tie', 'high']);
      _update(tree, rows, grouped: false, column: column, descending: true);
      expect(tree.ids, ['high', 'low', 'tie']);
    });
  }

  test('packed async projections preserve text column keys', () async {
    final runner = _ProjectionRunner();
    final tree = ConnectionTree.withProjectionRunner(runner.run);
    addTearDown(tree.dispose);
    for (final MapEntry(key: column, value: rows) in textCases.entries) {
      _update(tree, rows, grouped: false, column: column);
      await runner.finish(runner.tasks.length - 1);
      expect(tree.ids, ['low', 'tie', 'high'], reason: column);
    }
  });

  final numericCases = <String, List<TrackerInfo>>{
    'upload': [
      _connection('high', upload: 20),
      _connection('low', upload: 10),
      _connection('tie', upload: 10),
    ],
    'download': [
      _connection('high', download: 20),
      _connection('low', download: 10),
      _connection('tie', download: 10),
    ],
    'uploadSpeed': [
      _connection('high', uploadSpeed: 20),
      _connection('low'),
      _connection('tie', uploadSpeed: 0),
    ],
    'downloadSpeed': [
      _connection('high', downloadSpeed: 20),
      _connection('low'),
      _connection('tie', downloadSpeed: 0),
    ],
    'start': [
      _connection('high', second: 20),
      _connection('low', second: 10),
      _connection('tie', second: 10),
    ],
    'status': [
      _connection('high', failed: true),
      _connection('low'),
      _connection('tie'),
    ],
  };
  for (final MapEntry(key: column, value: rows) in numericCases.entries) {
    test('$column sorts flat and grouped children with stable ties', () {
      final tree = ConnectionTree();
      addTearDown(tree.dispose);
      for (final grouped in [false, true]) {
        _update(tree, rows, grouped: grouped, column: column);
        expect(tree.ids, ['low', 'tie', 'high']);
        if (grouped) {
          expect(tree.groups.single.ids, tree.ids);
          expect(tree.groups.single.representativeId, 'high');
        }
        _update(tree, rows, grouped: grouped, column: column, descending: true);
        expect(tree.ids, ['high', 'low', 'tie']);
      }
    });
  }

  test(
    'packed values retain integer precision statuses and date zones',
    () async {
      final runner = _ProjectionRunner();
      final tree = ConnectionTree.withProjectionRunner(runner.run);
      addTearDown(tree.dispose);
      final local = _start.toLocal().add(const Duration(hours: 1));
      final rows = [
        _connection('utc', upload: 9007199254740993, closed: true),
        _connection('local', failed: true).copyWith(start: local),
        _connection('active', upload: 2),
      ];
      _update(tree, rows, column: 'status');
      await runner.finish(0);
      expect(tree.ids, ['active', 'utc', 'local']);
      expect(tree.groups.single.active, 1);
      expect(tree.groups.single.upload, 9007199254740995);
      expect(tree.groups.single.start, local);
      expect(tree.groups.single.start.isUtc, isFalse);
      _update(tree, [rows.first], column: 'start');
      await runner.finish(1);
      expect(tree.groups.single.start, _start);
      expect(tree.groups.single.start.isUtc, isTrue);
    },
  );

  test('status distinguishes active closed and failed connections', () {
    final tree = ConnectionTree();
    addTearDown(tree.dispose);
    _update(tree, [
      _connection('failed', failed: true),
      _connection('closed', closed: true),
      _connection('active'),
    ], column: 'status');
    expect(tree.ids, ['active', 'closed', 'failed']);
    expect(tree.groups.single.active, 1);
  });

  for (final column in ['upload', 'download', 'uploadSpeed', 'downloadSpeed']) {
    test('$column sorts groups by total instead of their largest child', () {
      final tree = ConnectionTree();
      addTearDown(tree.dispose);
      TrackerInfo row(String id, String process, int value) => _connection(
        id,
        process: process,
        upload: value,
        download: value,
        uploadSpeed: value,
        downloadSpeed: value,
      );
      final rows = [
        row('a-new', 'a', 6),
        row('b', 'b', 10),
        row('c', 'c', 12),
        row('a-old', 'a', 6),
      ];
      _update(tree, rows, column: column);
      expect(tree.groups.map((group) => group.label), ['b', 'a', 'c']);
      _update(tree, rows, column: column, descending: true);
      expect(tree.groups.map((group) => group.label), ['a', 'c', 'b']);
      expect(tree.groups.first.ids, ['a-new', 'a-old']);
    });
  }

  test('group start uses latest and status uses the active total', () {
    final tree = ConnectionTree();
    addTearDown(tree.dispose);
    final rows = [
      _connection('a-new', process: 'a', second: 1),
      _connection('b', process: 'b', second: 2),
      _connection('a-old', process: 'a', second: 3),
      _connection('closed', process: 'closed', closed: true),
    ];
    _update(tree, rows, column: 'start', descending: true);
    expect(tree.groups.map((group) => group.label), ['a', 'b', 'closed']);
    expect(tree.groups.first.ids, ['a-old', 'a-new']);
    expect(tree.groups.first.representativeId, 'a-new');
    _update(tree, rows, column: 'status', descending: true);
    expect(tree.groups.map((group) => group.label), ['a', 'b', 'closed']);
  });

  for (final column in ['destination', 'network', 'rule', 'exit']) {
    test('$column sorts leaves without using hidden root values', () {
      final tree = ConnectionTree();
      addTearDown(tree.dispose);
      TrackerInfo row(String id, String process, String text) => _connection(
        id,
        process: process,
        host: text,
        network: text,
        rule: text,
        chains: [text],
      );
      final rows = [
        row('a-new', 'z', 'z'),
        row('b', 'a', 'm'),
        row('a-old', 'z', 'a'),
      ];
      _update(tree, rows, column: column);
      expect(
        tree.groups.map((group) => group.label),
        column == 'destination' ? ['a', 'z'] : ['z', 'a'],
      );
      final group = tree.groups.singleWhere((group) => group.label == 'z');
      expect(group.ids, ['a-old', 'a-new']);
      expect(group.representativeId, 'a-new');
      _update(tree, rows, column: column, descending: true);
      expect(tree.groups.map((group) => group.label), ['z', 'a']);
      expect(tree.groups.first.ids, ['a-new', 'a-old']);
    });
  }

  test('null and unknown columns restore newest group and child order', () {
    final tree = ConnectionTree();
    addTearDown(tree.dispose);
    final rows = [
      _connection('z', process: 'z'),
      _connection('a', process: 'a'),
      _connection('z-old', process: 'z'),
    ];
    _update(tree, rows, column: 'process');
    expect(tree.groups.map((group) => group.label), ['a', 'z']);
    for (final column in [null, 'unrecognized']) {
      _update(tree, rows, column: column, descending: true);
      expect(tree.ids, ['z', 'a', 'z-old']);
      expect(tree.groups.map((group) => group.label), ['z', 'a']);
      expect(tree.groups.first.ids, ['z', 'z-old']);
    }
  });

  test(
    'coalesces in flight updates and never publishes stale options',
    () async {
      final runner = _ProjectionRunner();
      final tree = ConnectionTree.withProjectionRunner(runner.run);
      addTearDown(tree.dispose);
      final rows = [
        _connection('a', process: 'a', upload: 1),
        _connection('b', process: 'b', upload: 2),
      ];
      _update(tree, rows);
      expect(tree.loading, isTrue);
      _update(tree, rows, column: 'process');
      _update(tree, rows, grouped: false, column: 'upload', descending: true);
      expect(runner.tasks, hasLength(1));

      await runner.finish(0);
      expect(tree.ids, isEmpty);
      expect(tree.loading, isTrue);
      expect(runner.tasks, hasLength(2));
      await runner.finish(1);
      expect(tree.groups, isEmpty);
      expect(tree.ids, ['b', 'a']);
      expect(tree.loading, isFalse);
    },
  );

  test(
    'clears a filtered empty input immediately and drops its old task',
    () async {
      final runner = _ProjectionRunner();
      final tree = ConnectionTree.withProjectionRunner(runner.run);
      addTearDown(tree.dispose);
      _update(tree, [_connection('visible')]);
      await runner.finish(0);
      expect(tree.ids, ['visible']);
      _update(tree, [_connection('pending')]);
      _update(tree, []);
      expect(tree.ids, isEmpty);
      expect(tree.groups, isEmpty);
      expect(tree.loading, isFalse);
      await runner.finish(1);
      expect(tree.ids, isEmpty);
      expect(runner.tasks, hasLength(2));
    },
  );

  test(
    'latest traffic wins and task inputs survive caller list mutation',
    () async {
      final runner = _ProjectionRunner();
      final tree = ConnectionTree.withProjectionRunner(runner.run);
      addTearDown(tree.dispose);
      final rows = [_connection('a', process: 'a', upload: 1)];
      _update(tree, rows);
      rows[0] = rows[0].copyWith(upload: 2);
      _update(tree, rows);
      rows[0] = rows[0].copyWith(upload: 3);
      _update(tree, rows);
      rows.clear();
      await runner.finish(0);
      expect(tree.ids, isEmpty);
      expect(runner.tasks[0]().groups.single.upload, 1);
      await runner.finish(1);
      expect(tree.groups.single.upload, 3);
    },
  );

  test(
    'unchanged relevant refs and copies do not launch another task',
    () async {
      final runner = _ProjectionRunner();
      final tree = ConnectionTree.withProjectionRunner(runner.run);
      addTearDown(tree.dispose);
      final row = _connection('a', process: 'a', upload: 1);
      _update(tree, [row]);
      _update(tree, [row]);
      _update(tree, [
        row.copyWith(rule: 'irrelevant when grouped without sort'),
      ]);
      expect(runner.tasks, hasLength(1));
      await runner.finish(0);
      expect(runner.tasks, hasLength(1));
      _update(tree, [row]);
      expect(runner.tasks, hasLength(1));
      _update(tree, [row.copyWith(upload: 2)]);
      expect(runner.tasks, hasLength(2));
      await runner.finish(1);
      expect(tree.groups.single.upload, 2);
    },
  );

  test(
    'flat newest ordering ignores traffic changes and null sort direction',
    () async {
      final runner = _ProjectionRunner();
      final tree = ConnectionTree.withProjectionRunner(runner.run);
      addTearDown(tree.dispose);
      final row = _connection('a');
      _update(tree, [row], grouped: false);
      await runner.finish(0);
      _update(
        tree,
        [row.copyWith(upload: 4)],
        grouped: false,
        descending: true,
      );
      expect(runner.tasks, hasLength(1));
    },
  );

  test(
    'reports current errors retries and ignores superseded failures',
    () async {
      final runner = _ProjectionRunner();
      final tree = ConnectionTree.withProjectionRunner(runner.run);
      addTearDown(tree.dispose);
      final rows = [_connection('a')];
      _update(tree, rows);
      await runner.fail(0);
      expect(tree.error, isStateError);
      expect(tree.loading, isFalse);
      _update(tree, rows);
      expect(tree.error, isNull);
      _update(tree, [_connection('new')]);
      await runner.fail(1);
      expect(tree.error, isNull);
      expect(tree.loading, isTrue);
      await runner.finish(2);
      expect(tree.ids, ['new']);
      expect(tree.error, isNull);
    },
  );

  test(
    'disposing ignores both pending work and late results or errors',
    () async {
      for (final fails in [false, true]) {
        final runner = _ProjectionRunner();
        final tree = ConnectionTree.withProjectionRunner(runner.run);
        var notifications = 0;
        tree.addListener(() => notifications++);
        _update(tree, [_connection('a')]);
        _update(tree, [_connection('b')]);
        tree.dispose();
        if (fails) {
          await runner.fail(0);
        } else {
          await runner.finish(0);
        }
        _update(tree, [_connection('after-dispose')]);
        expect(notifications, 1);
        expect(runner.tasks, hasLength(1));
        expect(tree.ids, isEmpty);
      }
    },
  );

  test(
    'large projections use a real isolate without native initialization',
    () async {
      final tree = ConnectionTree();
      addTearDown(tree.dispose);
      final rows = [
        for (var index = 0; index < 20000; index++)
          _connection(
            '$index',
            process: 'p${index % 40}',
            upload: index,
            uploadSpeed: index % 10,
          ),
      ];
      final done = Completer<void>();
      tree.addListener(() {
        if (!tree.loading && !done.isCompleted) {
          done.complete();
        }
      });
      _update(tree, rows, column: 'upload', descending: true);
      expect(tree.loading, isTrue);
      expect(tree.ids, isEmpty);
      await done.future;
      expect(tree.error, isNull);
      expect(tree.ids, hasLength(20000));
      expect(tree.ids.first, '19999');
      expect(tree.ids.last, '0');
      expect(tree.groups, hasLength(40));
      expect(
        tree.groups.fold(0, (sum, group) => sum + group.ids.length),
        20000,
      );
      expect(
        tree.groups.fold(0, (sum, group) => sum + group.upload),
        199990000,
      );
    },
  );
}
