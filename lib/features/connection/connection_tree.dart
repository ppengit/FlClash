import 'dart:async';
import 'dart:isolate';

import 'package:fl_clash/models/common.dart';
import 'package:flutter/foundation.dart';

@immutable
class ConnectionTreeGroup {
  final String key;
  final String label;
  final String representativeId;
  final List<String> ids;
  final int upload;
  final int download;
  final int uploadSpeed;
  final int downloadSpeed;
  final int active;
  final DateTime start;

  ConnectionTreeGroup({
    required this.key,
    required this.label,
    required this.representativeId,
    required List<String> ids,
    required this.upload,
    required this.download,
    required this.uploadSpeed,
    required this.downloadSpeed,
    required this.active,
    required this.start,
  }) : ids = List.unmodifiable(ids);
}

typedef ConnectionTreeProjection = ({
  List<ConnectionTreeGroup> groups,
  List<String> ids,
});

typedef _Row = ({
  String id,
  String path,
  String process,
  String text,
  String detail,
  int upload,
  int download,
  int uploadSpeed,
  int downloadSpeed,
  DateTime? start,
  int status,
});

typedef _Input = ({
  List<_Row> rows,
  bool grouped,
  String? column,
  bool descending,
});

typedef _Runner =
    Future<ConnectionTreeProjection> Function(
      ConnectionTreeProjection Function() project,
    );

class ConnectionTree extends ChangeNotifier {
  final _Runner? _projectionRunner;
  List<TrackerInfo> _sources = const [];
  _Input _input = (
    rows: const [],
    grouped: false,
    column: null,
    descending: false,
  );
  List<ConnectionTreeGroup> _groups = const [];
  List<String> _ids = const [];
  ({_Input input, int revision})? _pending;
  var _revision = 0;
  var _running = false;
  var _disposed = false;
  var _loading = false;
  Object? _error;

  ConnectionTree() : _projectionRunner = null;

  @visibleForTesting
  ConnectionTree.withProjectionRunner(
    Future<ConnectionTreeProjection> Function(
      ConnectionTreeProjection Function() project,
    )
    runner,
  ) : _projectionRunner = runner;

  List<ConnectionTreeGroup> get groups => _groups;
  List<String> get ids => _ids;
  bool get loading => _loading;
  Object? get error => _error;

  void update(
    List<TrackerInfo> newestFirst, {
    required bool grouped,
    required String? sortColumn,
    required bool descending,
  }) {
    if (_disposed) {
      return;
    }
    final column = switch (sortColumn) {
      'destination' ||
      'process' ||
      'network' ||
      'rule' ||
      'exit' ||
      'upload' ||
      'download' ||
      'uploadSpeed' ||
      'downloadSpeed' ||
      'start' ||
      'status' => sortColumn,
      _ => null,
    };
    final reversed = column != null && descending;
    final sameOptions =
        grouped == _input.grouped &&
        column == _input.column &&
        reversed == _input.descending;
    var changed = !sameOptions || newestFirst.length != _sources.length;
    final rows = List<_Row>.generate(newestFirst.length, (index) {
      final source = newestFirst[index];
      final previous = index < _sources.length ? _sources[index] : null;
      if (sameOptions && identical(source, previous)) {
        return _input.rows[index];
      }
      final row = _compact(source, grouped, column);
      if (!changed && row != _input.rows[index]) {
        changed = true;
      }
      return row;
    }, growable: false);
    _sources = List.of(newestFirst, growable: false);
    if (!changed && _error == null) {
      return;
    }
    final input = (
      rows: List<_Row>.unmodifiable(rows),
      grouped: grouped,
      column: column,
      descending: reversed,
    );
    _input = input;
    final revision = ++_revision;
    _pending = null;
    if (rows.isEmpty) {
      _publish((groups: const [], ids: const []));
      return;
    }
    if (_projectionRunner == null && rows.length < _isolateThreshold) {
      _publish(_project(input));
      return;
    }
    _pending = (input: input, revision: revision);
    if (!_loading || _error != null) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    if (!_running && !_disposed) {
      unawaited(_drain());
    }
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (!_disposed && _pending != null) {
        final request = _pending!;
        _pending = null;
        try {
          final task = _projectionTask(request.input);
          final result =
              await (_projectionRunner?.call(task) ??
                  Isolate.run(task, debugName: 'ConnectionTree'));
          if (!_disposed && request.revision == _revision) {
            _publish(result);
          }
        } catch (error) {
          if (!_disposed && request.revision == _revision) {
            _loading = false;
            _error = error;
            notifyListeners();
          }
        }
      }
    } finally {
      _running = false;
    }
  }

  void _publish(ConnectionTreeProjection result) {
    _groups = result.groups;
    _ids = result.ids;
    _loading = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _pending = null;
    _sources = const [];
    _input = (rows: const [], grouped: false, column: null, descending: false);
    _groups = const [];
    _ids = const [];
    super.dispose();
  }
}

const _isolateThreshold = 2048;

_Row _compact(TrackerInfo source, bool grouped, String? column) {
  final metadata = source.metadata;
  final (text, detail) = switch (column) {
    'destination' => (
      metadata.host.isEmpty ? metadata.destinationIP : metadata.host,
      metadata.destinationPort,
    ),
    'network' => (metadata.network, ''),
    'rule' => (source.rule, source.rulePayload),
    'exit' => (source.chains.firstOrNull ?? '', ''),
    _ => ('', ''),
  };
  return (
    id: source.id,
    path: grouped || column == 'process' ? metadata.processPath : '',
    process: grouped || column == 'process' ? metadata.process : '',
    text: text,
    detail: detail,
    upload: grouped || column == 'upload' ? source.upload : 0,
    download: grouped || column == 'download' ? source.download : 0,
    uploadSpeed: grouped || column == 'uploadSpeed'
        ? source.uploadSpeed ?? 0
        : 0,
    downloadSpeed: grouped || column == 'downloadSpeed'
        ? source.downloadSpeed ?? 0
        : 0,
    start: grouped || column == 'start' ? source.start : null,
    status: grouped || column == 'status'
        ? source.failure != null
              ? 2
              : source.closedAt != null
              ? 1
              : 0
        : 0,
  );
}

typedef _PackedInput = ({
  List<String> strings,
  Int64List numbers,
  bool grouped,
  String? column,
  bool descending,
});

ConnectionTreeProjection Function() _projectionTask(_Input input) {
  final strings = List<String>.filled(input.rows.length * 5, '');
  final numbers = Int64List(input.rows.length * 6);
  for (var index = 0; index < input.rows.length; index++) {
    final row = input.rows[index];
    final text = index * 5;
    strings[text] = row.id;
    strings[text + 1] = row.path;
    strings[text + 2] = row.process;
    strings[text + 3] = row.text;
    strings[text + 4] = row.detail;
    final value = index * 6;
    numbers[value] = row.upload;
    numbers[value + 1] = row.download;
    numbers[value + 2] = row.uploadSpeed;
    numbers[value + 3] = row.downloadSpeed;
    numbers[value + 4] = row.start?.microsecondsSinceEpoch ?? 0;
    numbers[value + 5] =
        row.status |
        (row.start?.isUtc == true ? 4 : 0) |
        (row.start == null ? 0 : 8);
  }
  return _packedTask((
    strings: List<String>.unmodifiable(strings),
    numbers: numbers.asUnmodifiableView(),
    grouped: input.grouped,
    column: input.column,
    descending: input.descending,
  ));
}

// A separate closure scope keeps the source cache out of the isolate message.
ConnectionTreeProjection Function() _packedTask(_PackedInput input) => () {
  final strings = input.strings;
  final numbers = input.numbers;
  final rows = List<_Row>.generate(numbers.length ~/ 6, (index) {
    final text = index * 5;
    final value = index * 6;
    final flags = numbers[value + 5];
    return (
      id: strings[text],
      path: strings[text + 1],
      process: strings[text + 2],
      text: strings[text + 3],
      detail: strings[text + 4],
      upload: numbers[value],
      download: numbers[value + 1],
      uploadSpeed: numbers[value + 2],
      downloadSpeed: numbers[value + 3],
      start: flags & 8 == 0
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(
              numbers[value + 4],
              isUtc: flags & 4 != 0,
            ),
      status: flags & 3,
    );
  }, growable: false);
  return _project((
    rows: rows,
    grouped: input.grouped,
    column: input.column,
    descending: input.descending,
  ));
};

({String key, String label}) _processOf(_Row row) {
  final path = row.path;
  final process = row.process.trim();
  if (path.trim().isEmpty) {
    return (key: process.isEmpty ? '' : 'process:$process', label: process);
  }
  final windows =
      (path.contains('\\') && !path.startsWith('/')) ||
      path.startsWith('//') ||
      (path.length > 1 && path[1] == ':');
  final normalized = windows ? path.replaceAll('\\', '/').toLowerCase() : path;
  final slash = path.lastIndexOf('/');
  final backslash = windows ? path.lastIndexOf('\\') : -1;
  final basename = path.substring((slash > backslash ? slash : backslash) + 1);
  return (key: 'path:$normalized', label: process.isEmpty ? basename : process);
}

final class _Group {
  final String key;
  String label;
  String sortLabel;
  int representative;
  final ids = <String>[];
  var upload = 0;
  var download = 0;
  var uploadSpeed = 0;
  var downloadSpeed = 0;
  var active = 0;
  DateTime start;

  _Group(this.key, this.label, this.representative, this.start)
    : sortLabel = label.toLowerCase();

  ConnectionTreeGroup finish(List<_Row> rows) => ConnectionTreeGroup(
    key: key,
    label: label,
    representativeId: rows[representative].id,
    ids: ids,
    upload: upload,
    download: download,
    uploadSpeed: uploadSpeed,
    downloadSpeed: downloadSpeed,
    active: active,
    start: start,
  );
}

ConnectionTreeProjection _project(_Input input) {
  final rows = input.rows;
  final column = input.column;
  final textColumn = switch (column) {
    'destination' || 'process' || 'network' || 'rule' || 'exit' => true,
    _ => false,
  };
  final identities = <(String, String), ({String key, String label})>{};
  ({String key, String label}) processOf(_Row row) =>
      identities.putIfAbsent((row.path, row.process), () => _processOf(row));
  final texts = textColumn
      ? List<String>.generate(rows.length, (index) {
          final row = rows[index];
          return (column == 'process'
                  ? processOf(row).label
                  : row.detail.isEmpty
                  ? row.text
                  : '${row.text}\u0000${row.detail}')
              .toLowerCase();
        }, growable: false)
      : const <String>[];
  int compareRows(int a, int b) => switch (column) {
    'upload' => rows[a].upload.compareTo(rows[b].upload),
    'download' => rows[a].download.compareTo(rows[b].download),
    'uploadSpeed' => rows[a].uploadSpeed.compareTo(rows[b].uploadSpeed),
    'downloadSpeed' => rows[a].downloadSpeed.compareTo(rows[b].downloadSpeed),
    'start' => rows[a].start!.compareTo(rows[b].start!),
    'status' => rows[a].status.compareTo(rows[b].status),
    _ => textColumn ? texts[a].compareTo(texts[b]) : 0,
  };
  int ordered(int comparison, int a, int b) => comparison == 0
      ? a.compareTo(b)
      : input.descending
      ? -comparison
      : comparison;
  final order = List<int>.generate(rows.length, (index) => index);
  if (column != null) {
    order.sort((a, b) => ordered(compareRows(a, b), a, b));
  }
  final ids = List<String>.unmodifiable(order.map((index) => rows[index].id));
  if (!input.grouped) {
    return (groups: const [], ids: ids);
  }
  final grouped = <String, _Group>{};
  for (final index in order) {
    final row = rows[index];
    final process = processOf(row);
    final group = grouped.putIfAbsent(
      process.key,
      () => _Group(process.key, process.label, index, row.start!),
    );
    if (index < group.representative) {
      group.representative = index;
      group.label = process.label;
      group.sortLabel = process.label.toLowerCase();
    }
    group.ids.add(row.id);
    group.upload += row.upload;
    group.download += row.download;
    group.uploadSpeed += row.uploadSpeed;
    group.downloadSpeed += row.downloadSpeed;
    group.active += row.status == 0 ? 1 : 0;
    if (row.start!.isAfter(group.start)) {
      group.start = row.start!;
    }
  }
  int compareGroups(_Group a, _Group b) => switch (column) {
    'upload' => a.upload.compareTo(b.upload),
    'download' => a.download.compareTo(b.download),
    'uploadSpeed' => a.uploadSpeed.compareTo(b.uploadSpeed),
    'downloadSpeed' => a.downloadSpeed.compareTo(b.downloadSpeed),
    'start' => a.start.compareTo(b.start),
    'status' => a.active.compareTo(b.active),
    'destination' || 'process' => a.sortLabel.compareTo(b.sortLabel),
    _ => 0,
  };
  final groups = grouped.values.toList()
    ..sort(
      (a, b) =>
          ordered(compareGroups(a, b), a.representative, b.representative),
    );
  return (
    groups: List<ConnectionTreeGroup>.unmodifiable(
      groups.map((group) => group.finish(rows)),
    ),
    ids: ids,
  );
}
