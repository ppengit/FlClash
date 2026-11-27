import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/connection/connection_tree.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

List<TableColumn> requestsTableColumns(BuildContext context) {
  final l10n = context.appLocalizations;
  final columns = [
    TableColumn('destination', l10n.destination, width: 280),
    TableColumn('process', l10n.process, width: 160),
    TableColumn('network', l10n.network, width: 76),
    TableColumn('rule', l10n.rule, width: 190),
    TableColumn('exit', l10n.outboundExit, width: 150),
    TableColumn('download', l10n.download, width: 110, end: true),
    TableColumn('upload', l10n.upload, width: 110, end: true),
    TableColumn('downloadSpeed', l10n.downloadSpeed, width: 120, end: true),
    TableColumn('uploadSpeed', l10n.uploadSpeed, width: 120, end: true),
    TableColumn('start', l10n.start, width: 170),
    TableColumn('status', l10n.status, width: 110),
  ];
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  );
  final style = AppTextStyle.footnote.of(context, emphasized: true);
  try {
    final measured = <TableColumn>[];
    for (final column in columns) {
      painter.text = TextSpan(text: column.label, style: style);
      painter.layout();
      measured.add(
        TableColumn(
          column.id,
          column.label,
          width: math.max(column.width!, painter.width.ceilToDouble() + 40),
          end: column.end,
        ),
      );
    }
    return measured;
  } finally {
    painter.dispose();
  }
}

List<PopupMenuItem> requestsTableMenuItems(
  BuildContext context,
  WidgetRef ref,
) {
  final settings = ref.watch(appSettingProvider);
  final l10n = context.appLocalizations;
  return [
    PopupMenuItem(
      label: l10n.visibleColumns,
      section: const PopupMenuSection(),
      subItems: [
        for (final column in requestsTableColumns(context))
          PopupMenuItem(
            label: column.label,
            checked:
                column.id == 'destination' ||
                settings.requestsColumns.contains(column.id),
            keepsOpen: true,
            onPressed: column.id == 'destination'
                ? null
                : () => ref.read(appSettingProvider.notifier).update((state) {
                    final columns = {...state.requestsColumns};
                    if (!columns.remove(column.id)) {
                      columns.add(column.id);
                    }
                    return state.copyWith(
                      requestsColumns: columns.toList(),
                      requestsSortColumn:
                          !columns.contains(state.requestsSortColumn)
                          ? null
                          : state.requestsSortColumn,
                    );
                  }),
          ),
        PopupMenuItem(
          label: l10n.reset,
          section: const PopupMenuSection(),
          onPressed: () => ref
              .read(appSettingProvider.notifier)
              .update(
                (state) => state.copyWith(
                  requestsColumns: const AppSettingProps().requestsColumns,
                  requestsSortColumn: null,
                  requestsSortDescending: false,
                  tableColumnWidths: {...state.tableColumnWidths}
                    ..remove('requests'),
                ),
              ),
        ),
      ],
    ),
  ];
}

class RequestsTable extends ConsumerStatefulWidget {
  const RequestsTable({
    super.key,
    required this.rows,
    required this.controller,
    required this.expanded,
    required this.isSearching,
    required this.emptyLabel,
    required this.detailTitle,
    @visibleForTesting this.treeBuilder,
  });

  final ConnectionTree Function()? treeBuilder;
  final ConnectionRows rows;
  final ScrollController controller;
  final Set<String> expanded;
  final bool isSearching;
  final String emptyLabel;
  final String detailTitle;

  @override
  ConsumerState<RequestsTable> createState() => _RequestsTableState();
}

class _RequestsTableState extends ConsumerState<RequestsTable>
    with
        TableColumnWidthsMixin<RequestsTable>,
        ArrivalCacheExtentMixin<RequestsTable> {
  late final _tree = widget.treeBuilder?.call() ?? ConnectionTree();
  final _horizontal = ScrollController();
  final _ranges = <({ConnectionTreeGroup group, int start, int end})>[];
  Map<Key, int>? _indexes;
  var _builtIndexes = <Key, int>{};
  var _previousBuiltIndexes = <Key, int>{};
  ValueListenable<String?>? _selected;
  String? _revealedSelection;
  Object? _labels;
  List<String> _columnIds = const [];
  List<TableColumn> _columns = const [];
  List<double> _widths = const [];
  var _count = 0;
  var _updatePending = false;

  @override
  String get tableId => 'requests';

  @override
  void initState() {
    super.initState();
    widget.rows.addListener(_scheduleUpdate);
    widget.rows.traffic.addListener(_scheduleUpdate);
    _tree.addListener(_changed);
    ref.listenManual(
      appSettingProvider.select((state) => state.tableColumnWidths['requests']),
      (_, widths) {
        if (mounted) setState(() => columnWidths = widths ?? const {});
      },
    );
    ref.listenManual(
      appSettingProvider.select(
        (state) => (
          state.requestsGroupByProcess,
          state.requestsSortColumn,
          state.requestsSortDescending,
        ),
      ),
      (_, _) => _scheduleUpdate(),
    );
    _update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final selected = TrackerSelection.maybeOf(context)?.selected;
    if (selected != _selected) {
      _selected?.removeListener(_selectionChanged);
      _selected = selected?..addListener(_selectionChanged);
      _indexRanges();
    }
  }

  void _selectionChanged() {
    if (mounted) setState(_indexRanges);
  }

  @override
  void didUpdateWidget(RequestsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rows != widget.rows) {
      oldWidget.rows.removeListener(_scheduleUpdate);
      oldWidget.rows.traffic.removeListener(_scheduleUpdate);
      widget.rows.addListener(_scheduleUpdate);
      widget.rows.traffic.addListener(_scheduleUpdate);
    }
    _scheduleUpdate();
  }

  void _scheduleUpdate() {
    if (_updatePending) return;
    _updatePending = true;
    scheduleMicrotask(() {
      _updatePending = false;
      if (mounted) _update();
    });
  }

  void _update() {
    final settings = ref.read(appSettingProvider);
    _tree.update(
      widget.rows.shown.toList(growable: false),
      grouped: settings.requestsGroupByProcess,
      sortColumn: settings.requestsSortColumn,
      descending: settings.requestsSortDescending,
    );
  }

  void _indexRanges() {
    _indexes = null;
    if (_builtIndexes.isNotEmpty) _previousBuiltIndexes = _builtIndexes;
    _builtIndexes = {};
    final selected = _selected?.value;
    if (selected == null) {
      _revealedSelection = null;
    } else if (selected != _revealedSelection) {
      for (final group in _tree.groups) {
        if (group.ids.contains(selected)) {
          widget.expanded.add(group.key);
          _revealedSelection = selected;
          break;
        }
      }
    }
    _ranges.clear();
    var at = 0;
    for (final group in _tree.groups) {
      final end =
          at + 1 + (widget.expanded.contains(group.key) ? group.ids.length : 0);
      _ranges.add((group: group, start: at, end: end));
      at = end;
    }
    _count = _tree.groups.isEmpty ? _tree.ids.length : at;
  }

  void _changed() {
    if (mounted) setState(_indexRanges);
  }

  void _toggle(String key) {
    setState(() {
      if (!widget.expanded.remove(key)) widget.expanded.add(key);
      _indexRanges();
    });
  }

  void _expandAll(bool expand) {
    setState(() {
      for (final group in _tree.groups) {
        expand
            ? widget.expanded.add(group.key)
            : widget.expanded.remove(group.key);
      }
      _indexRanges();
    });
  }

  ({ConnectionTreeGroup? group, String? id}) _rowAt(int index) {
    if (_ranges.isEmpty) return (group: null, id: _tree.ids[index]);
    var low = 0;
    var high = _ranges.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_ranges[mid].end <= index) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final range = _ranges[low];
    return index == range.start
        ? (group: range.group, id: null)
        : (group: null, id: range.group.ids[index - range.start - 1]);
  }

  Key _keyAt(int index) {
    final row = _rowAt(index);
    return row.group == null
        ? ValueKey(('request', row.id))
        : ValueKey(('process', row.group!.key));
  }

  int? _indexOf(Key key) {
    final built = _builtIndexes[key] ?? _previousBuiltIndexes[key];
    if (built != null && built < _count && _keyAt(built) == key) return built;
    return (_indexes ??= _makeIndexes())[key];
  }

  Map<Key, int> _makeIndexes() {
    final indexes = HashMap<Key, int>(
      hashCode: (key) => key is ValueKey ? key.value.hashCode : key.hashCode,
    );
    if (_ranges.isEmpty) {
      for (final (index, id) in _tree.ids.indexed) {
        indexes[ValueKey(('request', id))] = index;
      }
    } else {
      for (final range in _ranges) {
        indexes[ValueKey(('process', range.group.key))] = range.start;
        if (range.end > range.start + 1) {
          for (final (index, id) in range.group.ids.indexed) {
            indexes[ValueKey(('request', id))] = range.start + index + 1;
          }
        }
      }
    }
    return indexes;
  }

  void _sort(TableColumn column) {
    ref.read(appSettingProvider.notifier).update((state) {
      final first = column.end || column.id == 'start';
      final same = state.requestsSortColumn == column.id;
      final clear = same && state.requestsSortDescending != first;
      return state.copyWith(
        requestsSortColumn: clear ? null : column.id,
        requestsSortDescending: same ? !state.requestsSortDescending : first,
      );
    });
  }

  @override
  void dispose() {
    widget.rows.removeListener(_scheduleUpdate);
    widget.rows.traffic.removeListener(_scheduleUpdate);
    _selected?.removeListener(_selectionChanged);
    _tree.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(
      appSettingProvider.select(
        (state) => (
          columns: state.requestsColumns,
          grouped: state.requestsGroupByProcess,
          sortColumn: state.requestsSortColumn,
          descending: state.requestsSortDescending,
          widths: state.tableColumnWidths['requests'],
        ),
      ),
    );
    final l10n = context.appLocalizations;
    final labels = (
      l10n,
      AppTextStyle.footnote.of(context, emphasized: true),
      MediaQuery.textScalerOf(context),
    );
    if (_labels != labels ||
        !const ListEquality<String>().equals(_columnIds, prefs.columns)) {
      _labels = labels;
      _columnIds = prefs.columns;
      _columns = [
        for (final column in requestsTableColumns(context))
          if (column.id == 'destination' || prefs.columns.contains(column.id))
            column,
      ];
    }
    final columns = _columns;
    final style = AppTextStyle.footnote.of(context).toTabular;
    final rowHeight = math.max(
      40.0,
      16 +
          MediaQuery.textScalerOf(context).scale(style.fontSize!) *
              (style.height ?? 1),
    );
    return Padding(
      padding: context.listInsets.page(top: context.contentTopPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Checkbox(
                    value: prefs.grouped,
                    onChanged: (value) => ref
                        .read(appSettingProvider.notifier)
                        .update(
                          (state) => state.copyWith(
                            requestsGroupByProcess: value ?? false,
                          ),
                        ),
                  ),
                  PressRegion(
                    shape: AppShape.none,
                    onTap: () => ref
                        .read(appSettingProvider.notifier)
                        .update(
                          (state) => state.copyWith(
                            requestsGroupByProcess:
                                !state.requestsGroupByProcess,
                          ),
                        ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        l10n.groupByProcess,
                        style: AppTextStyle.footnote.of(context),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    final count =
                        '${l10n.connections}: ${widget.rows.shownCount}';
                    ConnectionTreeGroup? group;
                    if (_ranges.isNotEmpty) {
                      final offset = widget.controller.hasClients
                          ? widget.controller.offset
                          : 0.0;
                      final index = ((offset - 4) / rowHeight).floor().clamp(
                        0,
                        _count - 1,
                      );
                      var low = 0;
                      var high = _ranges.length;
                      while (low < high) {
                        final mid = (low + high) >> 1;
                        if (_ranges[mid].end <= index) {
                          low = mid + 1;
                        } else {
                          high = mid;
                        }
                      }
                      group = _ranges[low].group;
                    }
                    final name = group == null
                        ? null
                        : group.label.isEmpty
                        ? l10n.unknown
                        : group.label;
                    final path = group == null
                        ? ''
                        : widget.rows
                                  .heldInfoOf(group.representativeId)
                                  ?.metadata
                                  .processPath ??
                              '';
                    return Tooltip(
                      message: path.isEmpty ? name ?? count : path,
                      child: Text(
                        key: const ValueKey('requestsProcessContext'),
                        name == null ? count : '$count · $name',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: style.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (prefs.grouped) ...[
                IconButton(
                  tooltip: l10n.expandAll,
                  icon: const GlyphIcon(AppGlyphs.chevronDown, size: 18),
                  onPressed: () => _expandAll(true),
                ),
                IconButton(
                  tooltip: l10n.collapseAll,
                  icon: const GlyphIcon(AppGlyphs.chevronUp, size: 18),
                  onPressed: () => _expandAll(false),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: WidthBuilder(
              builder: (context, width) {
                final natural = columns.fold<double>(
                  0,
                  (sum, col) => sum + (columnWidths[col.id] ?? col.width!),
                );
                final tableWidth = math.max(width, natural);
                final nextWidths = [
                  for (final column in columns)
                    columnWidths[column.id] ?? column.width!,
                ];
                nextWidths[0] += tableWidth - natural;
                if (!const ListEquality<double>().equals(_widths, nextWidths)) {
                  _widths = nextWidths;
                }
                final widths = _widths;
                return Scrollbar(
                  controller: _horizontal,
                  thumbVisibility: tableWidth > width,
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TableColumnResizer(
                            columns: columns,
                            widths: widths,
                            onResize: (boundary, delta) =>
                                resizeColumn(columns, widths, boundary, delta),
                            onResizeEnd: saveColumnWidths,
                            onReset: resetColumnWidths,
                            child: TableCells(
                              columns: columns,
                              widths: widths,
                              height: rowHeight,
                              inset: 0,
                              cells: [
                                for (final column in columns)
                                  RecordHeaderCell(
                                    label: column.label,
                                    end: column.end,
                                    style: AppTextStyle.footnote.of(
                                      context,
                                      emphasized: true,
                                    ),
                                    inset: 10,
                                    descending: prefs.sortColumn == column.id
                                        ? prefs.descending
                                        : null,
                                    onTap: () => _sort(column),
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: _tree.error != null
                                ? NullStatus(
                                    label: l10n.error,
                                    action: TextButton(
                                      onPressed: _update,
                                      child: Text(l10n.retry),
                                    ),
                                    illustration:
                                        NullStatusIllustration.connections,
                                  )
                                : NullStatusSwitcher(
                                    isLoading: _tree.loading && _count == 0,
                                    isEmpty: _count == 0,
                                    isSearching: widget.isSearching,
                                    nullStatus: NullStatus(
                                      label: widget.emptyLabel,
                                      illustration:
                                          NullStatusIllustration.connections,
                                    ),
                                    child: MouseRegion(
                                      onEnter: (_) =>
                                          widget.rows.hovered = true,
                                      onExit: (_) =>
                                          widget.rows.hovered = false,
                                      child: Scrollbar(
                                        controller: widget.controller,
                                        child: PrismListView(
                                          controller: widget.controller,
                                          padding: EdgeInsets.only(
                                            top: 4,
                                            bottom: 16 + context.bottomInset,
                                          ),
                                          scrollCacheExtent: arrivalCacheExtent,
                                          itemExtent: rowHeight,
                                          itemCount: _count,
                                          findChildIndexCallback: _indexOf,
                                          itemBuilder: (context, index) {
                                            final row = _rowAt(index);
                                            final group = row.group;
                                            final key = _keyAt(index);
                                            _builtIndexes[key] = index;
                                            return KeyedSubtree(
                                              key: key,
                                              child: group == null
                                                  ? RequestsTableRow(
                                                      id: row.id!,
                                                      rows: widget.rows,
                                                      columns: columns,
                                                      widths: widths,
                                                      height: rowHeight,
                                                      grouped: _tree
                                                          .groups
                                                          .isNotEmpty,
                                                      striped: index.isOdd,
                                                      detailTitle:
                                                          widget.detailTitle,
                                                    )
                                                  : RequestsProcessRow(
                                                      group: group,
                                                      info: widget.rows
                                                          .heldInfoOf(
                                                            group
                                                                .representativeId,
                                                          ),
                                                      columns: columns,
                                                      widths: widths,
                                                      height: rowHeight,
                                                      expanded: widget.expanded
                                                          .contains(group.key),
                                                      onPressed: () =>
                                                          _toggle(group.key),
                                                    ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class RequestsTableRow extends StatelessWidget {
  const RequestsTableRow({
    super.key,
    required this.id,
    required this.rows,
    required this.columns,
    required this.widths,
    required this.height,
    required this.grouped,
    required this.striped,
    required this.detailTitle,
  });

  final String id;
  final ConnectionRows rows;
  final List<TableColumn> columns;
  final List<double> widths;
  final double height;
  final bool grouped;
  final bool striped;
  final String detailTitle;

  @override
  Widget build(BuildContext context) => TrackerSelected(
    id: id,
    builder: (context, selected) => ListenableBuilder(
      listenable: rows.traffic,
      builder: (context, _) {
        final info = rows.heldInfoOf(id);
        if (info == null) return const SizedBox.shrink();
        return MemoBuilder(
          inputs: [
            info,
            selected,
            columns,
            widths,
            height,
            grouped,
            striped,
            detailTitle,
          ],
          builder: (context) {
            final row = PressSurface(
              fill: striped
                  ? SurfaceLevel.inset.colorOf(context.colorScheme)
                  : Colors.transparent,
              shape: AppShape.none,
              selected: selected,
              onPressed: () => openTrackerInfo(
                context,
                rows.heldInfoOf(id) ?? info,
                detailTitle,
              ),
              child: DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote.of(context).toTabular,
                child: TableCells(
                  columns: columns,
                  widths: widths,
                  height: height,
                  inset: 10,
                  cells: [
                    for (final column in columns)
                      _cell(context, info, column.id),
                  ],
                ),
              ),
            );
            return ContextMenuRegion(
              menuBuilder: (context) =>
                  trackerInfoMenuItems(context, rows.heldInfoOf(id) ?? info),
              child: selected ? RecordSelectedRow(child: row) : row,
            );
          },
        );
      },
    ),
  );

  Widget _cell(BuildContext context, TrackerInfo info, String column) =>
      switch (column) {
        'destination' => Padding(
          padding: EdgeInsetsDirectional.only(start: grouped ? 28 : 0),
          child: TrackerTargetText(info),
        ),
        'process' => Text(
          info.metadata.process.isEmpty ? '—' : info.metadata.process,
        ),
        'network' => Text(info.metadata.network.toUpperCase()),
        'rule' => TrackerRuleText(info),
        'exit' => Text(info.chains.reversed.join(' → ')),
        'download' => Text(info.download.traffic.show),
        'upload' => Text(info.upload.traffic.show),
        'downloadSpeed' => Text(
          info.isActive ? '${(info.downloadSpeed ?? 0).traffic.show}/s' : '—',
        ),
        'uploadSpeed' => Text(
          info.isActive ? '${(info.uploadSpeed ?? 0).traffic.show}/s' : '—',
        ),
        'start' => Text(info.start.showFull),
        'status' => Text(
          info.failure != null
              ? context.appLocalizations.connectionsFailed
              : info.isActive
              ? context.appLocalizations.connectionsActive
              : context.appLocalizations.connectionClosed,
          style: TextStyle(
            color: info.failure != null
                ? context.colorScheme.error
                : context.colorScheme.onSurfaceVariant,
          ),
        ),
        _ => const SizedBox.shrink(),
      };
}

class RequestsProcessRow extends StatelessWidget {
  const RequestsProcessRow({
    super.key,
    required this.group,
    required this.info,
    required this.columns,
    required this.widths,
    required this.height,
    required this.expanded,
    required this.onPressed,
  });

  final ConnectionTreeGroup group;
  final TrackerInfo? info;
  final List<TableColumn> columns;
  final List<double> widths;
  final double height;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    expanded: expanded,
    child: PressSurface(
      fill: context.raisedSurfaceLevel.colorOf(context.colorScheme),
      shape: AppShape.none,
      onPressed: onPressed,
      child: DefaultTextStyle.merge(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyle.footnote.of(context, emphasized: true).toTabular,
        child: TableCells(
          columns: columns,
          widths: widths,
          height: height,
          inset: 10,
          cells: [for (final column in columns) _cell(context, column.id)],
        ),
      ),
    ),
  );

  Widget _cell(BuildContext context, String column) => switch (column) {
    'destination' => Row(
      spacing: 8,
      children: [
        GlyphIcon(
          expanded ? AppGlyphs.chevronDown : AppGlyphs.chevronForward,
          size: 16,
        ),
        if (info case final info?) TrackerAppWell(trackerInfo: info, size: 22),
        Expanded(
          child: Text(
            group.label.isEmpty
                ? context.appLocalizations.unknown
                : group.label,
          ),
        ),
        Text(
          '${group.ids.length}',
          style: TextStyle(color: context.colorScheme.onSurfaceVariant),
        ),
      ],
    ),
    'process' => Text(
      group.label.isEmpty ? context.appLocalizations.unknown : group.label,
    ),
    'download' => Text(group.download.traffic.show),
    'upload' => Text(group.upload.traffic.show),
    'downloadSpeed' => Text('${group.downloadSpeed.traffic.show}/s'),
    'uploadSpeed' => Text('${group.uploadSpeed.traffic.show}/s'),
    'start' => Text(group.start.showFull),
    'status' => Text(
      '${context.appLocalizations.connectionsActive}: ${group.active}',
    ),
    _ => const Text('—'),
  };
}
