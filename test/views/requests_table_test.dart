import 'package:fl_clash/features/connection/connection_tree.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/connection/requests.dart';
import 'package:fl_clash/views/connection/requests_table.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/glyph_finders.dart';
import '../helpers/test_app.dart';

TrackerInfo _request(
  String id,
  String process, {
  int download = 0,
  String network = 'tcp',
}) => TrackerInfo(
  id: id,
  metadata: Metadata(process: process, host: '$id.test', network: network),
  start: DateTime.utc(2026, 1, 1, 0, 0, int.tryParse(id) ?? 0),
  download: download,
  chains: const ['Node', 'Group'],
  rule: 'Domain-Suffix',
  rulePayload: 'test',
);

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(
            requestsSplitView: false,
            requestsColumns: ['destination', 'download', 'upload', 'status'],
          ),
        ),
      ],
    );
    globalState.container = container;
    container.listen(appSettingProvider, (_, _) {});
    container.listen(requestsProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  void seed(List<TrackerInfo> requests) {
    final notifier = container.read(requestsProvider.notifier);
    notifier.value = ConnectionLog(requests.length + 1);
    for (final request in requests) {
      notifier.addRequest(request);
    }
  }

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1400, 1000),
  }) async {
    container.read(viewSizeProvider.notifier).update((_) => size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: RequestsView(
            connectionsReader: () async => container
                .read(requestsProvider)
                .list
                .where((info) => info.isActive)
                .toList(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  }

  Finder group(String label) => find.byWidgetPredicate(
    (widget) => widget is RequestsProcessRow && widget.group.label == label,
  );
  Finder row(String id) => find.byWidgetPredicate(
    (widget) => widget is RequestsTableRow && widget.id == id,
  );
  List<String> ids(WidgetTester tester) => [
    for (final widget in tester.widgetList<RequestsTableRow>(
      find.byType(RequestsTableRow),
    ))
      widget.id,
  ];
  Finder header(String id) => find.byWidgetPredicate(
    (widget) =>
        widget is RecordHeaderCell &&
        widget.label ==
            switch (id) {
              'download' => 'Download',
              'destination' => 'Destination',
              _ => id,
            },
  );

  testWidgets(
    'process roots aggregate traffic and expand into requests with working menus and details',
    (tester) async {
      seed([
        _request('1', 'Editor.exe', download: 10),
        _request('2', 'Browser.exe', download: 5),
        _request('3', 'Editor.exe', download: 20),
      ]);
      await pump(tester);
      expect(find.byType(RequestsProcessRow), findsNWidgets(2));
      expect(find.byType(RequestsTableRow), findsNothing);
      final editor = tester.widget<RequestsProcessRow>(group('Editor.exe'));
      expect(editor.group.ids, ['3', '1']);
      expect(editor.group.download, 30);
      expect(editor.group.active, 2);

      await tester.tap(group('Editor.exe'));
      await tester.pumpAndSettle();
      expect(ids(tester), ['3', '1']);
      expect(
        tester.widget<RequestsProcessRow>(group('Editor.exe')).expanded,
        isTrue,
      );
      await tester.tap(
        row('3'),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      final menu = find.byType(PopupMenu);
      expect(
        find.descendant(of: menu, matching: find.text('Add rule')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: menu, matching: find.text('Only this app')),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(10, 500));
      await tester.pumpAndSettle();
      await tester.tap(row('3'));
      await tester.pumpAndSettle();
      expect(find.byType(TrackerInfoDetailSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets(
    'column headers sort process totals and children, flip direction, then restore arrival order',
    (tester) async {
      seed([
        _request('1', 'Browser.exe', download: 90),
        _request('2', 'Editor.exe', download: 10),
        _request('3', 'Editor.exe', download: 20),
      ]);
      await pump(tester);
      await tester.tap(find.byTooltip('Expand all'));
      await tester.pumpAndSettle();
      expect(ids(tester), ['3', '2', '1']);
      await tester.tap(header('download'));
      await tester.pumpAndSettle();
      expect(ids(tester), ['1', '3', '2']);
      expect(container.read(appSettingProvider).requestsSortColumn, 'download');
      expect(container.read(appSettingProvider).requestsSortDescending, isTrue);
      await tester.tap(header('download'));
      await tester.pumpAndSettle();
      expect(ids(tester), ['2', '3', '1']);
      await tester.tap(header('download'));
      await tester.pumpAndSettle();
      expect(ids(tester), ['3', '2', '1']);
      expect(container.read(appSettingProvider).requestsSortColumn, isNull);
      await close(tester);
    },
  );

  testWidgets(
    'quick facets filter children before grouping and keep an expanded process expanded',
    (tester) async {
      seed([
        _request('1', 'Editor.exe'),
        _request('2', 'Editor.exe', network: 'udp'),
        _request('3', 'Browser.exe', network: 'udp'),
      ]);
      await pump(tester);
      await tester.tap(group('Editor.exe'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Chip, 'TCP'));
      await tester.pumpAndSettle();
      expect(group('Browser.exe'), findsNothing);
      expect(ids(tester), ['1']);
      expect(tester.widget<RequestsProcessRow>(group('Editor.exe')).group.ids, [
        '1',
      ]);
      await tester.tap(find.widgetWithText(Chip, 'TCP'));
      await tester.pumpAndSettle();
      expect(ids(tester), ['2', '1']);
      expect(group('Browser.exe'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets('ungrouping, columns and sorting survive reopening the page', (
    tester,
  ) async {
    seed([_request('1', 'Editor.exe'), _request('2', 'Browser.exe')]);
    await pump(tester);
    expect(find.byType(Checkbox), findsOneWidget);
    await tester.tap(find.text('Group by process'));
    await tester.pumpAndSettle();
    expect(find.byType(RequestsProcessRow), findsNothing);
    expect(ids(tester), ['2', '1']);

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byGlyph(AppGlyphs.more),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PopupMenu),
        matching: find.text('Columns'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PopupMenu),
        matching: find.text('Upload'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      container.read(appSettingProvider).requestsColumns,
      isNot(contains('upload')),
    );
    await tester.tapAt(const Offset(10, 500));
    await tester.pumpAndSettle();
    await tester.tap(header('destination'));
    await tester.pumpAndSettle();
    expect(ids(tester), ['1', '2']);
    await close(tester);
    await pump(tester);
    expect(find.byType(RequestsProcessRow), findsNothing);
    expect(ids(tester), ['1', '2']);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is RecordHeaderCell && widget.label == 'Upload',
      ),
      findsNothing,
    );
    await close(tester);
  });

  testWidgets(
    'headers remain above scrolled rows and collapse all hides every child',
    (tester) async {
      seed([for (var i = 0; i < 200; i++) _request('$i', 'Editor.exe')]);
      await pump(tester);
      await tester.tap(find.byTooltip('Expand all'));
      await tester.pumpAndSettle();
      final headerRect = tester.getRect(header('destination'));
      await tester.drag(find.byType(PrismListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.getRect(header('destination')), headerRect);
      final first = find.byType(RequestsTableRow).first;
      final viewport = tester.getRect(find.byType(PrismListView));
      expect(viewport.top, greaterThanOrEqualTo(headerRect.bottom));
      expect(tester.getRect(first).bottom, greaterThan(viewport.top));
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('requestsProcessContext')))
            .data,
        contains('Editor.exe'),
      );
      expect(find.byType(RequestsTableRow).evaluate().length, lessThan(50));
      await tester.tap(find.byTooltip('Collapse all'));
      await tester.pumpAndSettle();
      expect(find.byType(RequestsTableRow), findsNothing);
      expect(group('Editor.exe'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets(
    'the active process stays named when identity columns scroll out of view',
    (tester) async {
      container
          .read(appSettingProvider.notifier)
          .update(
            (state) => state.copyWith(
              requestsColumns: const AppSettingProps().requestsColumns,
            ),
          );
      seed([for (var i = 0; i < 100; i++) _request('$i', 'Editor.exe')]);
      await pump(tester, size: const Size(720, 900));
      await tester.tap(find.byTooltip('Expand all'));
      await tester.pumpAndSettle();
      final horizontal = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byType(RequestsTable),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is SingleChildScrollView &&
                widget.scrollDirection == Axis.horizontal,
          ),
        ),
      );
      horizontal.controller!.jumpTo(
        horizontal.controller!.position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
      final visible = tester
          .getRect(find.byType(PrismListView))
          .intersect(const Rect.fromLTWH(0, 0, 720, 900));
      await tester.dragFrom(visible.center, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PrismListView>(find.byType(PrismListView))
            .controller!
            .offset,
        greaterThan(0),
      );
      final context = find.byKey(const ValueKey('requestsProcessContext'));
      expect(tester.widget<Text>(context).data, contains('Editor.exe'));
      expect(tester.getRect(context).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(context).right, lessThanOrEqualTo(720));
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets(
    'new requests and traffic update the correct process without clearing expansion',
    (tester) async {
      seed([_request('1', 'Editor.exe', download: 10)]);
      await pump(tester);
      await tester.tap(group('Editor.exe'));
      await tester.pumpAndSettle();
      final notifier = container.read(requestsProvider.notifier);
      notifier.addRequest(_request('2', 'Editor.exe', download: 20));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(ids(tester), ['2', '1']);
      expect(
        tester.widget<RequestsProcessRow>(group('Editor.exe')).group.download,
        30,
      );
      notifier.updateTraffic({'1': (upload: 3, download: 100)});
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        tester.widget<RequestsProcessRow>(group('Editor.exe')).group.download,
        120,
      );
      expect(ids(tester), ['2', '1']);
      notifier.close(['1']);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(
        tester.widget<RequestsProcessRow>(group('Editor.exe')).group.active,
        1,
      );
      expect(
        tester.widget<RequestsProcessRow>(group('Editor.exe')).expanded,
        isTrue,
      );
      await close(tester);
    },
  );

  testWidgets(
    'column resizing saves the dragged width and restores it on reopening',
    (tester) async {
      seed([_request('1', 'Editor.exe')]);
      await pump(tester);
      final before = tester.getRect(header('destination'));
      final drag = await tester.startGesture(
        Offset(before.right, before.center.dy),
      );
      await drag.moveBy(const Offset(20, 0));
      await tester.pump();
      await drag.moveBy(const Offset(30, 0));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      final after = tester.getRect(header('destination'));
      expect(after.width, greaterThan(before.width));
      expect(
        container
            .read(appSettingProvider)
            .tableColumnWidths['requests']?['destination'],
        after.width,
      );
      await close(tester);
      await pump(tester);
      expect(tester.getRect(header('destination')).width, after.width);
      await close(tester);
    },
  );

  for (final searching in [false, true]) {
    for (final populated in [false, true]) {
      testWidgets(
        'projection failures offer retry with searching=$searching and populated=$populated',
        (tester) async {
          final rows = ConnectionRows();
          final scroll = ScrollController();
          addTearDown(rows.dispose);
          addTearDown(scroll.dispose);
          var fails = !populated;
          final tree = ConnectionTree.withProjectionRunner((project) async {
            if (fails) throw StateError('projection failed');
            return project();
          });
          var log = ConnectionLog(10).open([_request('1', 'Editor.exe')]);
          rows.follow(log);
          container
              .read(viewSizeProvider.notifier)
              .update((_) => const Size(1400, 1000));
          tester.view.physicalSize = const Size(1400, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: TestApp(
                child: RequestsTable(
                  rows: rows,
                  controller: scroll,
                  expanded: <String>{},
                  isSearching: searching,
                  emptyLabel: 'No connections',
                  detailTitle: 'Connection details',
                  treeBuilder: () => tree,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (populated) {
            expect(find.byType(RequestsProcessRow), findsOneWidget);
            fails = true;
            log = log.open([_request('2', 'Browser.exe')]);
            rows.follow(log);
            await tester.pumpAndSettle();
          }
          expect(find.text('Retry'), findsOneWidget);
          expect(find.text('Error'), findsOneWidget);
          expect(find.byType(RequestsProcessRow), findsNothing);
          fails = false;
          await tester.tap(find.text('Retry'));
          await tester.pumpAndSettle();
          expect(find.text('Retry'), findsNothing);
          expect(
            find.byType(RequestsProcessRow),
            findsNWidgets(populated ? 2 : 1),
          );
          expect(tester.takeException(), isNull);
          await close(tester);
        },
      );
    }
  }

  testWidgets(
    'narrow and split layouts keep compact cards instead of squeezing a table',
    (tester) async {
      seed([_request('1', 'Editor.exe')]);
      await pump(tester, size: const Size(400, 900));
      expect(find.byType(RequestsTable), findsNothing);
      expect(find.byType(TrackerInfoItem), findsOneWidget);
      await close(tester);
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(requestsSplitView: true));
      await pump(tester);
      expect(find.byType(RequestsTable), findsNothing);
      expect(find.byType(TrackerInfoItem), findsOneWidget);
      await close(tester);
    },
  );
}
