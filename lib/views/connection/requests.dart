import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/connection/tracker_rule.dart';
import 'package:fl_clash/features/connection/connection_connected_buttons.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_poller.dart';
import 'http_capture.dart';
import 'requests_detail_pane.dart';
import 'requests_split.dart';
import 'requests_table.dart';

export 'requests_detail_pane.dart' show RequestsSegment;

/// Every connection of this run, open or closed, newest first, and in a
/// segment of their own the DNS queries. The log the Core's events keep is
/// shown as it changes; polling the open connections adds their speeds and
/// settles what the events missed.
class RequestsView extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  final RequestsSegment segment;
  final ConnectionStatus status;
  final Future<List<TrackerInfo>> Function()? connectionsReader;
  final MitmQuery? httpQuery;

  const RequestsView({
    super.key,
    this.scrollController,
    this.segment = RequestsSegment.connections,
    this.status = ConnectionStatus.all,
    @visibleForTesting this.connectionsReader,
    @visibleForTesting this.httpQuery,
  });

  @override
  ConsumerState<RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends ConsumerState<RequestsView>
    with
        WidgetsBindingObserver,
        ActivePollingMixin<RequestsView>,
        RouteMotionHoldMixin<RequestsView> {
  final _rows = ConnectionRows();
  final _expandedProcesses = <String>{};
  final _tableKey = GlobalKey<RequestsTableState>();
  final _searchController = TextEditingController();
  var _query = '';
  var _rowsQuery = '';
  final _filters = connectionFilters();
  final _selected = ValueNotifier<String?>(null);
  late var _segment = widget.segment;

  /// Each segment shown so far, kept as it was left while another shows.
  final _bodies = <RequestsSegment, Widget>{};
  final _kept = <RequestsSegment, Offstage>{};
  final _scrollControllers = <RequestsSegment, ScrollController>{};

  /// Hidden segments that missed a change, brought up to date when shown.
  final _behind = <RequestsSegment>{};
  final _dnsFeed = DnsQueryFeed();
  final _dnsFilters = dnsFilters();
  final _dnsSelected = ValueNotifier<DnsQuery?>(null);
  List<DnsQuery>? _dnsOffered;
  final _httpFeed = HttpRequestFeed();
  final _httpFilters = httpFilters();
  final _httpSelected = ValueNotifier<int?>(null);
  List<MitmExchangeSummary>? _httpOffered;
  var _httpRuns = 0;

  BuildContext? _sheet;

  /// Whether the detail stands beside the list rather than in a sheet.
  var _split = false;
  var _table = false;
  late final _menuActions = TrackerMenuActions(
    close: _closeConnection,
    onlyApp: _onlyApp,
    hideHost: _hideHost,
    addRule: (trackerInfo) => showTrackerRuleForm(context, ref, trackerInfo),
  );
  final _poller = ConnectionPoller();

  CoreController get _core => ref.read(coreHandlerProvider);

  /// The dashboard's sheet can show over this page, each refreshing its own.
  late final _refreshTag = (FunctionTag.requests, this);
  late final _dnsRefreshTag = (FunctionTag.dnsQueries, this);

  @override
  void initState() {
    super.initState();
    _rows
      ..addListener(_offerCounts)
      ..addListener(_dropGone);
    _dnsFeed.addListener(_offerDns);
    _httpFeed.addListener(_offerHttp);
    _follow();
    _filters
      ..status = widget.status
      ..addListener(_showWhere);
    if (_segment == RequestsSegment.http &&
        !_showsHttp(ref.read(patchClashConfigProvider))) {
      _segment = RequestsSegment.connections;
    }
    ref.listenManual(patchClashConfigProvider.select(_showsHttp), (_, shows) {
      if (!shows && _segment == RequestsSegment.http) {
        _setSegment(RequestsSegment.connections);
      }
    });
    ref.listenManual(requestsProvider.select((state) => state.revision), (
      _,
      _,
    ) {
      _scheduleRefresh();
    });
    ref.listenManual(patchClashConfigProvider.select(httpCapturing), (
      _,
      capturing,
    ) {
      if (!capturing) {
        _httpSelected.value = null;
        _httpFeed.hovered = false;
      }
    });
    ref.listenManual(coreStatusProvider, (previous, next) {
      if (previous == CoreStatus.connected && next != CoreStatus.connected) {
        _httpFeed.reset();
        _httpSelected.value = null;
      }
    });
    _setDnsQueries(ref.read(dnsQueriesProvider).list);
    ref.listenManual(dnsQueriesProvider.select((state) => state.revision), (
      _,
      _,
    ) {
      throttler.call(_dnsRefreshTag, () {
        if (!mounted) {
          return;
        }
        updateWhenRouteSettled(
          () => _setDnsQueries(ref.read(dnsQueriesProvider).list),
        );
      }, duration: renderThrottleDuration);
    });
  }

  void _followDns() {
    _dnsFeed.following = true;
    _setDnsQueries(ref.read(dnsQueriesProvider).list);
  }

  void _setDnsQueries(List<DnsQuery> dnsQueries) {
    if (_segment != RequestsSegment.dns) {
      _behind.add(RequestsSegment.dns);
      return;
    }
    _dnsFeed.offer(dnsQueries);
  }

  void _offerDns() {
    final shown = _dnsFeed.items;
    if (identical(shown, _dnsOffered)) {
      return;
    }
    _dnsOffered = shown;
    _dnsFilters.offer(shown);
    final selected = _dnsSelected.value;
    if (selected != null && !shown.any((query) => identical(query, selected))) {
      _dnsSelected.value = null;
    }
  }

  void _offerHttp() {
    final shown = _httpFeed.items;
    if (identical(shown, _httpOffered)) {
      return;
    }
    _httpOffered = shown;
    _httpFilters.offer(shown);
  }

  @override
  void dispose() {
    throttler.cancel(_refreshTag);
    throttler.cancel(_dnsRefreshTag);
    for (final controller in _scrollControllers.values) {
      if (controller != widget.scrollController) {
        controller.dispose();
      }
    }
    _rows.dispose();
    _filters.dispose();
    _selected.dispose();
    _dnsFeed.dispose();
    _dnsFilters.dispose();
    _dnsSelected.dispose();
    _httpFeed.dispose();
    _httpFilters.dispose();
    _httpSelected.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Duration get pollInterval => const Duration(seconds: 1);

  @override
  Future<void> poll(PollGuard isCurrent) async {
    if (_segment == RequestsSegment.connections &&
        _behind.contains(RequestsSegment.connections)) {
      updateWhenRouteSettled(_refreshConnections);
    }
    await Future.wait([
      _readConnections(),
      if (_segment == RequestsSegment.http) _readHttp(),
    ]);
  }

  Future<void> _readHttp() async {
    final query =
        widget.httpQuery ??
        (ref.read(coreStatusProvider) == CoreStatus.connected
            ? _core.queryMitmExchanges
            : null);
    if (query == null || !httpCapturing(ref.read(patchClashConfigProvider))) {
      return;
    }
    try {
      await _httpFeed.read(query);
    } catch (error) {
      commonPrint.log(
        'queryMitmExchanges error: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
    if (!mounted) {
      return;
    }
    final restarted = _httpFeed.runs != _httpRuns;
    _httpRuns = _httpFeed.runs;
    final selected = _httpSelected.value;
    if (selected != null &&
        (restarted || !_httpFeed.items.any((item) => item.id == selected))) {
      _httpSelected.value = null;
    }
  }

  Future<void> _readConnections() => _poller.read(
    ref,
    reader: widget.connectionsReader,
    mounted: () => mounted,
  );

  void _scheduleRefresh() {
    if (!canPoll || _segment != RequestsSegment.connections) {
      _behind.add(RequestsSegment.connections);
      return;
    }
    throttler.call(_refreshTag, () {
      if (!mounted) {
        return;
      }
      updateWhenRouteSettled(_refreshConnections);
    }, duration: renderThrottleDuration);
  }

  void _refreshConnections() {
    if (!canPoll || _segment != RequestsSegment.connections) {
      _behind.add(RequestsSegment.connections);
      return;
    }
    final log = ref.read(requestsProvider);
    if (_behind.remove(RequestsSegment.connections)) {
      _rows.catchUp(log);
    } else {
      _rows.update(log);
    }
  }

  void _follow() => _rows.follow(ref.read(requestsProvider));

  void _offerCounts() => _filters.offerCounts(_rows.counts, () => _rows.held);

  void _showWhere() {
    _rowsQuery = _query;
    final searched = trackerInfoQueryMatcher(_query);
    final filtered = _filters.shows;
    _rows.showWhere(
      searched == null
          ? filtered
          : filtered == null
          ? searched
          : (trackerInfo) => searched(trackerInfo) && filtered(trackerInfo),
      repeatKeyOf: _filters.mergesRepeats ? trackerRepeatKeyOf : null,
    );
  }

  Future<void> _close(Future<void> Function() close) async {
    await globalState.safeRun(close, title: 'close connections');
    if (mounted) {
      await _readConnections();
    }
    if (mounted) {
      _scheduleRefresh();
    }
  }

  String get _detailTitle => _detailTitleOf(context);

  String _detailTitleOf(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return appLocalizations.details(appLocalizations.connection);
  }

  void _setSegment(RequestsSegment segment) {
    if (segment == _segment) {
      return;
    }
    setState(() => _segment = segment);
    _searchShown();
    final behind = canPoll && _behind.remove(segment);
    switch (segment) {
      case RequestsSegment.connections when behind:
        _rows.catchUp(ref.read(requestsProvider));
      case RequestsSegment.dns when behind:
        _setDnsQueries(ref.read(dnsQueriesProvider).list);
      case RequestsSegment.http:
        unawaited(_readHttp());
      case RequestsSegment.connections || RequestsSegment.dns:
        break;
    }
  }

  void _openConnection(TrackerInfo trackerInfo) {
    _setSegment(RequestsSegment.connections);
    _selected.value = trackerInfo.id;
  }

  void _search(String query) {
    _query = query;
    _searchShown();
  }

  /// A hidden segment takes the search when shown.
  void _searchShown() {
    switch (_segment) {
      case RequestsSegment.connections:
        if (_rowsQuery != _query) {
          _showWhere();
        }
      case RequestsSegment.dns:
        _dnsFeed.search(_query);
      case RequestsSegment.http:
        _httpFeed.search(_query);
    }
  }

  void _selectDns(DnsQuery dnsQuery) {
    if (ViewScope.isMobileOf(context, listen: false)) {
      showDnsQueryDetail(context, dnsQuery);
      return;
    }
    _dnsSelected.value = _split && identical(_dnsSelected.value, dnsQuery)
        ? null
        : dnsQuery;
    _showSelected();
  }

  void _selectHttp(MitmExchangeSummary exchange) {
    if (ViewScope.isMobileOf(context, listen: false)) {
      showNestedSheet<void>(
        context,
        builder: (_) =>
            MitmExchangeView(id: exchange.id, showsConnection: true),
      );
      return;
    }
    _httpSelected.value = _split && _httpSelected.value == exchange.id
        ? null
        : exchange.id;
    _showSelected();
  }

  void _showSelected() {
    if (!_split && _sheet == null) {
      _openSheet();
    }
  }

  Future<void> _clearDnsCache() async {
    final appLocalizations = context.appLocalizations;
    var cleared = false;
    try {
      await _core.clearDnsCache();
      cleared = true;
    } catch (error) {
      commonPrint.log(
        'clearDnsCache error: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
    if (!mounted) {
      return;
    }
    dialogs.showBanner(
      cleared
          ? appLocalizations.dnsCacheCleared
          : appLocalizations.clearDnsCacheFailed,
      level: cleared ? BannerLevel.success : BannerLevel.error,
    );
  }

  /// Beside the list, choosing the selected row again empties the pane.
  void _select(TrackerInfo trackerInfo) {
    if (_split && _selected.value == trackerInfo.id) {
      _selected.value = null;
      return;
    }
    _selected.value = trackerInfo.id;
    _showSelected();
  }

  /// The selection of the segment shown, which closing the sheet drops.
  Future<void> _openSheet() async {
    final segment = _segment;
    final dnsQuery = _dnsSelected.value;
    final httpId = _httpSelected.value;
    await showNestedSheet<void>(
      context,
      builder: (context) {
        _sheet = context;
        return switch (segment) {
          RequestsSegment.connections => TrackerMenuScope(
            actions: _menuActions,
            child: TrackerClock(
              child: TrackerInfoDetailSheet(
                selected: _selected,
                rows: _rows,
                title: _detailTitle,
              ),
            ),
          ),
          RequestsSegment.dns => DnsQueryDetailSheet(dnsQuery: dnsQuery!),
          RequestsSegment.http => MitmExchangeView(
            id: httpId!,
            showsConnection: true,
          ),
        };
      },
    );
    _sheet = null;
    if (mounted && !_split) {
      _dropSelectionsBut(null);
    }
  }

  void _dropSelectionsBut(RequestsSegment? kept) {
    if (kept != RequestsSegment.connections) {
      _selected.value = null;
    }
    if (kept != RequestsSegment.dns) {
      _dnsSelected.value = null;
    }
    if (kept != RequestsSegment.http) {
      _httpSelected.value = null;
    }
  }

  bool get _hasSelection => switch (_segment) {
    RequestsSegment.connections => _selected.value != null,
    RequestsSegment.dns => _dnsSelected.value != null,
    RequestsSegment.http => _httpSelected.value != null,
  };

  void _closeSheet() {
    final sheet = _sheet;
    if (sheet != null && sheet.mounted) {
      SheetProvider.of(sheet)?.nestedNavigatorPop?.call();
    }
  }

  /// A filtered-out connection stays selected, as the log or the rows still
  /// hold it.
  void _dropGone() {
    final id = _selected.value;
    if (id != null && _infoOf(id) == null) {
      _selected.value = null;
      _closeSheet();
    }
  }

  TrackerInfo? _infoOf(String id) =>
      ref.read(requestsProvider)[id] ?? _rows.heldInfoOf(id);

  void _onlyApp(TrackerInfo trackerInfo) {
    _filters.only(RecordFacetKind.app, trackerInfo.metadata.process);
  }

  void _hideHost(TrackerInfo trackerInfo) {
    final host = trackerInfo.metadata.host;
    _filters.addCondition(
      ConnectionCondition(
        ConnectionField.host,
        host.isNotEmpty ? host : trackerInfo.title,
        excludes: true,
      ),
    );
  }

  Future<void> _closeConnection(TrackerInfo trackerInfo) =>
      _close(() => _core.closeConnection(trackerInfo.id));

  Future<void> _closeActiveConnections() async {
    final count = ref.read(requestsProvider).activeCount;
    if (count == 0) {
      return;
    }
    final appLocalizations = context.appLocalizations;
    final confirmed = await dialogs.showMessage(
      title: appLocalizations.closeActiveConnections,
      message: TextSpan(
        text: appLocalizations.closeActiveConnectionsTip(count),
      ),
      confirmText: appLocalizations.close,
      destructive: true,
    );
    if (confirmed == true && mounted) {
      await _close(_core.closeConnections);
    }
  }

  Widget _directButton({
    required Glyph glyph,
    required String label,
    required VoidCallback? onPressed,
  }) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    style: ButtonStyle.from(
      shape: AppShape.sm,
      minimumSize: const Size(36, 36),
      tapTargetSize: TapTargetSize.shrinkWrap,
    ),
    icon: GlyphIcon(glyph, size: 18),
  );

  Widget _pageActions({
    required bool hasActive,
    required bool offersCapture,
    required bool requestsSplitView,
    required double maxWidth,
    required double pageWidth,
  }) {
    final l10n = context.appLocalizations;
    final mobile = ViewScope.isMobileOf(context);
    final table =
        !mobile &&
        !requestsSplitView &&
        pageWidth >= 640 &&
        _segment == RequestsSegment.connections;
    final grouped = ref.watch(
      appSettingProvider.select((state) => state.requestsGroupByProcess),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            if (!mobile)
              ConnectedFilterButtons<bool>(
                values: const [false, true],
                labelOf: (split) => split ? l10n.listAndDetails : l10n.list,
                isSelected: (split) => requestsSplitView == split,
                inMutuallyExclusiveGroup: true,
                childBuilder: (split, selected) => GlyphIcon(
                  split ? AppGlyphs.split : AppGlyphs.appsList,
                  size: 18,
                  color: selected
                      ? context.colorScheme.onPrimary
                      : context.colorScheme.onSurfaceVariant,
                ),
                onSelected: (split) => ref
                    .read(appSettingProvider.notifier)
                    .update(
                      (state) => state.copyWith(requestsSplitView: split),
                    ),
              ),
            if (table) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: grouped,
                    onChanged: (value) => ref
                        .read(appSettingProvider.notifier)
                        .update(
                          (state) => state.copyWith(
                            requestsGroupByProcess: value ?? false,
                          ),
                        ),
                  ),
                  PressRegion(
                    onTap: () => ref
                        .read(appSettingProvider.notifier)
                        .update(
                          (state) => state.copyWith(
                            requestsGroupByProcess:
                                !state.requestsGroupByProcess,
                          ),
                        ),
                    child: Text(
                      l10n.groupByProcess,
                      style: AppTextStyle.footnote.of(context),
                    ),
                  ),
                ],
              ),
              if (grouped) ...[
                _directButton(
                  glyph: AppGlyphs.chevronDown,
                  label: l10n.expandAll,
                  onPressed: () => _tableKey.currentState?.expandAll(true),
                ),
                _directButton(
                  glyph: AppGlyphs.chevronUp,
                  label: l10n.collapseAll,
                  onPressed: () => _tableKey.currentState?.expandAll(false),
                ),
              ],
              PopupAnchor(
                targetBuilder: (open) => _directButton(
                  glyph: AppGlyphs.sliders,
                  label: l10n.visibleColumns,
                  onPressed: open,
                ),
                popupBuilder: (_) =>
                    PopupMenu(items: requestsTableColumnItems(context, ref)),
              ),
            ],
            if (_segment == RequestsSegment.connections)
              _directButton(
                glyph: AppGlyphs.block,
                label: l10n.closeActiveConnections,
                onPressed: hasActive ? _closeActiveConnections : null,
              ),
            if (_segment == RequestsSegment.dns)
              _directButton(
                glyph: AppGlyphs.clearAll,
                label: l10n.clearDnsCache,
                onPressed: _clearDnsCache,
              ),
            if (offersCapture) ..._captureActions(),
          ],
        ),
      ),
    );
  }

  List<Widget> _captureActions() {
    final l10n = context.appLocalizations;
    final mitm = ref.watch(
      patchClashConfigProvider.select((state) => state.mitm),
    );
    final items = httpCaptureMenuItems(
      ref,
      l10n,
      mitm: mitm,
      isAndroid: system.isAndroid,
    );
    return [
      ConnectedFilterButtons<bool>(
        values: const [true, false],
        labelOf: (on) => on ? l10n.turnOn : l10n.turnOff,
        isSelected: (on) => mitm.capture == on,
        onSelected: (on) => items[on ? 0 : 1].onPressed?.call(),
        childBuilder: (on, selected) => GlyphIcon(
          on ? AppGlyphs.camera : AppGlyphs.block,
          size: 18,
          color: selected
              ? context.colorScheme.onPrimary
              : context.colorScheme.onSurfaceVariant,
        ),
        inMutuallyExclusiveGroup: true,
      ),
      PopupAnchor(
        targetBuilder: (open) => _directButton(
          glyph: AppGlyphs.memory,
          label: l10n.httpCaptureLimit,
          onPressed: open,
        ),
        popupBuilder: (_) => PopupMenu(
          items: [
            for (final item in items.last.subItems)
              PopupMenuItem(
                glyph: AppGlyphs.memory,
                label: item.label,
                checked: item.checked,
                onPressed: item.onPressed,
              ),
          ],
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = ref.watch(
      requestsProvider.select((log) => log.activeCount > 0),
    );
    final requestsSplitView = ref.watch(
      appSettingProvider.select((state) => state.requestsSplitView),
    );
    final showsHttp = ref.watch(patchClashConfigProvider.select(_showsHttp));
    final offersCapture = ref.watch(
      patchClashConfigProvider.select(_offersCapture),
    );
    final body = Stack(
      fit: StackFit.passthrough,
      children: [
        for (final segment in RequestsSegment.values)
          if (segment == _segment || _bodies.containsKey(segment))
            _keptSegment(segment),
      ],
    );
    final mobile = ViewScope.isMobileOf(context);
    return TrackerMenuScope(
      actions: _menuActions,
      child: TrackerClock(
        child: WidthBuilder(
          builder: (context, width) {
            final split =
                requestsSplitView && !mobile && width >= _splitMinWidth;
            if (split != _split) {
              _split = split;
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _settleDetail(),
              );
            }
            return _buildPage(
              body,
              split: split,
              hasActive: hasActive,
              showsHttp: showsHttp,
              offersCapture: offersCapture,
              requestsSplitView: requestsSplitView,
              width: width,
            );
          },
        ),
      ),
    );
  }

  /// A hidden segment's list keeps its place and does no work: its clock
  /// stops and the changes it misses wait for it to show.
  Widget _keptSegment(RequestsSegment segment) {
    final shown = segment == _segment;
    if (_kept[segment] case final kept? when kept.offstage != shown) {
      return kept;
    }
    return _kept[segment] = Offstage(
      key: ValueKey(segment),
      offstage: !shown,
      child: ExcludeFocus(
        excluding: !shown,
        child: TickerMode(
          enabled: shown,
          child: _bodies[segment] ??= _buildSegment(segment),
        ),
      ),
    );
  }

  Widget _buildSegment(RequestsSegment segment) {
    final scrollController = _scrollControllers[segment] =
        segment == widget.segment
        ? widget.scrollController ?? sheetScrollController(context)
        : sheetScrollController(context);
    return switch (segment) {
      RequestsSegment.connections => TrackerClock(
        child: RecordFilterScope(
          onFilter: _filters.add,
          child: ListenableBuilder(
            listenable: _rows,
            builder: (context, _) => TrackerRepeats(
              counts: _rows.repeats,
              child: _buildBody(context, scrollController),
            ),
          ),
        ),
      ),
      RequestsSegment.http => _buildHttp(scrollController),
      RequestsSegment.dns => DnsQueryList(
        feed: _dnsFeed,
        filters: _dnsFilters,
        scrollController: scrollController,
        selected: _dnsSelected,
        onSelect: _selectDns,
        onFollow: _followDns,
      ),
    };
  }

  /// The selection moves between the sheet and the pane as the layout changes.
  void _settleDetail() {
    if (!mounted) {
      return;
    }
    if (_split) {
      _closeSheet();
      return;
    }
    _dropSelectionsBut(_segment);
    if (_hasSelection && _sheet == null) {
      _openSheet();
    }
  }

  Widget _buildPage(
    Widget body, {
    required bool split,
    required bool hasActive,
    required bool showsHttp,
    required bool offersCapture,
    required bool requestsSplitView,
    required double width,
  }) {
    final mobile = ViewScope.isMobileOf(context);
    final list = mobile
        ? body
        : TrackerSelection(selected: _selected, onSelect: _select, child: body);
    final header = _buildHeader(showsHttp: showsHttp);
    return Scaffold(
      title: PageLabel.requests.label,
      header: header,
      actions: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (width - (mobile ? 90 : 160)).clamp(160, 1200).toDouble(),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                switch (_segment) {
                  RequestsSegment.connections => ConditionStatusButtons(
                    controller: _filters,
                  ),
                  RequestsSegment.http => ConditionStatusButtons(
                    controller: _httpFilters,
                  ),
                  RequestsSegment.dns => ConditionStatusButtons(
                    controller: _dnsFilters,
                  ),
                },
                _pageActions(
                  hasActive: hasActive,
                  offersCapture: offersCapture,
                  requestsSplitView: requestsSplitView,
                  maxWidth: 720,
                  pageWidth: width,
                ),
              ],
            ),
          ),
        ),
      ],
      body: split ? _buildSplit(list) : list,
    );
  }

  Widget _buildSplit(Widget list) => RequestsSplit(
    minDetailWidth: RequestsDetailPane.minWidth,
    list: list,
    detail: RequestsDetailPane(
      segment: _segment,
      selected: _selected,
      rows: _rows,
      dnsSelected: _dnsSelected,
      httpSelected: _httpSelected,
      detailTitle: _detailTitle,
      top: _headerTop,
      onOpenConnection: _openConnection,
    ),
  );

  Widget _buildHeader({required bool showsHttp}) {
    return Padding(
      padding: const EdgeInsets.only(top: _headerTop, bottom: 4),
      child: switch (_segment) {
        RequestsSegment.connections => ConditionFilterRow(
          controller: _filters,
          searchController: _searchController,
          onSearch: _search,
          leadingFilters: _segmentButtons(showsHttp),
        ),
        RequestsSegment.http => ConditionFilterRow(
          controller: _httpFilters,
          searchController: _searchController,
          onSearch: _search,
          leadingFilters: _segmentButtons(showsHttp),
        ),
        RequestsSegment.dns => ConditionFilterRow(
          controller: _dnsFilters,
          searchController: _searchController,
          onSearch: _search,
          leadingFilters: _segmentButtons(showsHttp),
        ),
      },
    );
  }

  Widget _segmentButtons(bool showsHttp) =>
      ConnectedFilterButtons<RequestsSegment>(
        values: [
          RequestsSegment.connections,
          if (showsHttp) RequestsSegment.http,
          RequestsSegment.dns,
        ],
        labelOf: (segment) => switch (segment) {
          RequestsSegment.connections => context.appLocalizations.connections,
          RequestsSegment.http => 'HTTP',
          RequestsSegment.dns => 'DNS',
        },
        isSelected: (segment) => segment == _segment,
        onSelected: _setSegment,
        inMutuallyExclusiveGroup: true,
      );

  Widget _buildHttp(ScrollController scrollController) {
    return Consumer(
      builder: (context, ref, _) {
        final appLocalizations = context.appLocalizations;
        final hasModule = ref.watch(
          mitmModulesProvider.select(
            (state) => state.value?.any((module) => module.enabled) == true,
          ),
        );
        final noHost = ref.watch(
          patchClashConfigProvider.select(
            (state) => httpCaptureHasNoHost(state, hasModule),
          ),
        );
        return HttpRequestList(
          feed: _httpFeed,
          filters: _httpFilters,
          scrollController: scrollController,
          selected: _httpSelected,
          onSelect: _selectHttp,
          emptyDescription: noHost ? appLocalizations.httpCaptureNoHosts : null,
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, ScrollController scrollController) {
    return Consumer(
      builder: (context, ref, _) {
        final split = ref.watch(
          appSettingProvider.select((state) => state.requestsSplitView),
        );
        return WidthBuilder(
          builder: (context, width) {
            final table =
                !split && !ViewScope.isMobileOf(context) && width >= 640;
            if (_table != table) {
              _table = table;
              if (table) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !_table) {
                    return;
                  }
                  _rows.hovered = false;
                  if (!_rows.following) {
                    _follow();
                  }
                  if (scrollController.hasClients) {
                    scrollController.jumpTo(
                      scrollController.position.minScrollExtent,
                    );
                  }
                });
              }
            }
            if (table) {
              return RequestsTable(
                key: _tableKey,
                rows: _rows,
                controller: scrollController,
                expanded: _expandedProcesses,
                isSearching:
                    SearchQuery(_query).isNotEmpty ||
                    _filters.narrowsPastStatus,
                emptyLabel: _filters.status.emptyLabel(
                  context.appLocalizations,
                ),
                detailTitle: _detailTitleOf(context),
              );
            }
            return _buildCards(context, scrollController);
          },
        );
      },
    );
  }

  Widget _buildCards(BuildContext context, ScrollController scrollController) {
    final appLocalizations = context.appLocalizations;
    return RecordFeedView<String>(
      rows: _rows,
      isEmpty: _rows.shownCount == 0,
      isSearching: SearchQuery(_query).isNotEmpty || _filters.narrowsPastStatus,
      nullStatus: NullStatus(
        label: _filters.status.emptyLabel(appLocalizations),
        illustration: NullStatusIllustration.connections,
      ),
      controller: scrollController,
      timeAt: (fraction) => _rows.atFraction(fraction)?.start,
      following: _rows.following,
      onStopFollowing: () => _rows.following = false,
      onFollow: _follow,
      onHover: (hovered) => _rows.hovered = hovered,
      itemBuilder: trackerInfoRows(
        _rows,
        detailTitle: _detailTitleOf(context),
        onClose: _closeConnection,
      ),
      addAutomaticKeepAlives: false,
    );
  }
}

bool _showsHttp(PatchClashConfig state) => rsFeature && httpCapturing(state);

bool _offersCapture(PatchClashConfig state) => rsFeature && state.mitm.enable;

const _headerTop = 4.0;
final _splitMinWidth =
    RequestsSplit.minListWidth +
    RequestsSplit.handleWidth +
    RequestsDetailPane.minWidth;
