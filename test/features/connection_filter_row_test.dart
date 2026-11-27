import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/connection/connection_conditions.dart';
import 'package:fl_clash/features/connection/connection_connected_buttons.dart';
import 'package:fl_clash/features/connection/connection_filter_row.dart';
import 'package:fl_clash/features/connection/connection_filters.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

typedef _Record = ({String network, String rule});

enum _Status { all, active, failed }

const _records = <_Record>[
  (network: 'tcp', rule: 'MATCH'),
  (network: 'udp', rule: 'MATCH'),
  (network: 'tcp', rule: 'REJECT'),
  (network: 'icmp', rule: 'MATCH'),
];

ConditionFilterController<_Record, _Status> _controller({
  bool offered = true,
}) => ConditionFilterController(
  facets: [
    RecordFacet(
      RecordFacetKind.network,
      (item) => [item.network],
      offered: offered,
    ),
    RecordFacet(RecordFacetKind.rule, (item) => [item.rule], offered: offered),
  ],
  statuses: _Status.values,
  fields: const [],
  labelOf: (status) => switch (status) {
    _Status.all => 'All',
    _Status.active => 'Active',
    _Status.failed => 'Failed',
  },
  statusHolds: (status, item) => switch (status) {
    _Status.all => true,
    _Status.active => item.rule != 'REJECT',
    _Status.failed => item.rule == 'REJECT',
  },
  showsText: (count) => count,
  valuesInText: (field) => field,
  conditionTip: () => '',
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 1200,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    TestApp(
      locale: const Locale('en'),
      child: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          devicePixelRatio: 1,
          textScaler: TextScaler.linear(scale),
        ),
        child: Directionality(
          textDirection: direction,
          child: Align(alignment: Alignment.topCenter, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _facet(String label) => find.descendant(
  of: find.byType(ConnectedFilterButtons<String>),
  matching: find.text(label),
);

void main() {
  testWidgets('uses the parent search controller and forwards text changes', (
    tester,
  ) async {
    final controller = _controller();
    final search = TextEditingController(text: 'initial');
    final searches = <String>[];
    addTearDown(controller.dispose);
    addTearDown(search.dispose);
    await _pump(
      tester,
      ConditionFilterRow(
        controller: controller,
        searchController: search,
        onSearch: searches.add,
      ),
    );

    expect(
      tester.widget<SearchField>(find.byType(SearchField)).controller,
      search,
    );
    expect(find.text('initial'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'example.com');
    expect(search.text, 'example.com');
    expect(searches, ['example.com']);
    search.text = 'external';
    await tester.pump();
    expect(find.text('external'), findsOneWidget);
    expect(searches, ['example.com']);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(search.text, isEmpty);
    expect(searches, ['example.com', '']);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(() => search.text = 'still owned by parent', returnsNormally);
  });

  testWidgets('quick buttons widen a facet and narrow across facets', (
    tester,
  ) async {
    final controller = _controller()..offer(_records);
    final search = TextEditingController();
    addTearDown(controller.dispose);
    addTearDown(search.dispose);
    await _pump(
      tester,
      ConditionFilterRow(
        controller: controller,
        searchController: search,
        onSearch: (_) {},
      ),
    );

    expect(find.byType(ConditionBlock<_Record>), findsNothing);
    await tester.tap(_facet('tcp'));
    await tester.pump();
    expect(controller.isValueSelected(RecordFacetKind.network, 'tcp'), isTrue);
    expect(controller.apply(_records), [_records[0], _records[2]]);
    expect(find.byType(ConditionBlock<_Record>), findsOneWidget);
    await tester.tap(_facet('udp'));
    await tester.pump();
    expect(controller.apply(_records), _records.take(3));
    await tester.tap(_facet('MATCH'));
    await tester.pump();
    expect(controller.apply(_records), _records.take(2));
    await tester.tap(_facet('tcp'));
    await tester.pump();
    expect(controller.isValueSelected(RecordFacetKind.network, 'tcp'), isFalse);
    expect(controller.isValueSelected(RecordFacetKind.network, 'udp'), isTrue);
    expect(controller.apply(_records), [_records[1]]);
  });

  testWidgets('short facet groups sit together on the toolbar right edge', (
    tester,
  ) async {
    final controller = _controller()..offer(_records);
    final search = TextEditingController();
    addTearDown(controller.dispose);
    addTearDown(search.dispose);
    await _pump(
      tester,
      ConditionFilterRow(
        controller: controller,
        searchController: search,
        onSearch: (_) {},
      ),
    );

    final field = tester.getRect(find.byType(SearchField));
    final groups = find.byType(ConnectedFilterButtons<String>);
    final first = tester.getRect(groups.first);
    final last = tester.getRect(groups.last);
    final add = tester.getRect(find.byType(AppBarActionButton));
    expect(field.width, greaterThan(120));
    expect(first.left, greaterThan(field.right));
    expect(last.right + 8, closeTo(add.left, .01));
    expect(first.center.dy, closeTo(field.center.dy, .01));
    expect(last.center.dy, closeTo(add.center.dy, .01));
    expect(find.byType(Chip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leading filters share the facet row and scroll viewport', (
    tester,
  ) async {
    final controller = _controller()..offer(_records);
    final search = TextEditingController();
    addTearDown(controller.dispose);
    addTearDown(search.dispose);
    await _pump(
      tester,
      ConditionFilterRow(
        controller: controller,
        searchController: search,
        onSearch: (_) {},
        leadingFilters: ConnectedFilterButtons<int>(
          values: const [0, 1],
          labelOf: (value) => value == 0 ? 'Connections' : 'DNS',
          isSelected: (value) => value == 0,
          onSelected: (_) {},
          inMutuallyExclusiveGroup: true,
        ),
      ),
    );

    final leading = find.byType(ConnectedFilterButtons<int>);
    final facets = find.byType(ConnectedFilterButtons<String>);
    final sharedScroll = find
        .ancestor(of: leading, matching: find.byType(SingleChildScrollView))
        .first;
    expect(
      find.descendant(of: sharedScroll, matching: facets),
      findsNWidgets(2),
    );
    expect(
      tester.getRect(leading).right,
      lessThan(tester.getRect(facets.first).left),
    );
    expect(tester.getCenter(leading).dy, tester.getCenter(facets.first).dy);
  });

  for (final width in [360.0, 392.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final direction in TextDirection.values) {
        testWidgets('toolbar keeps search readable at $width dp, scale $scale, '
            '$direction and scrolls facets', (tester) async {
          final controller = _controller();
          final search = TextEditingController(text: 'example.com');
          addTearDown(controller.dispose);
          addTearDown(search.dispose);
          controller.options.value = {
            RecordFacetKind.network: [
              for (var index = 0; index < 12; index++) 'network-$index',
            ],
            RecordFacetKind.rule: ['MATCH', 'REJECT'],
          };
          await _pump(
            tester,
            ConditionFilterRow(
              controller: controller,
              searchController: search,
              onSearch: (_) {},
            ),
            width: width,
            scale: scale,
            direction: direction,
          );

          final field = tester.getRect(find.byType(SearchField));
          final add = tester.getRect(find.byType(AppBarActionButton));
          expect(field.width, greaterThanOrEqualTo(120));
          expect(field.center.dy, closeTo(add.center.dy, .01));
          expect(tester.takeException(), isNull);
          final scrollable = tester.state<ScrollableState>(
            find
                .ancestor(
                  of: find.byType(ConnectedFilterButtons<String>).first,
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(scrollable.position.maxScrollExtent, greaterThan(0));
          scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
          await tester.pump();
          expect(_facet('REJECT').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
    'quick buttons keep exactly the offered options, including selected '
    'values outside the frequent set',
    (tester) async {
      final controller = _controller()
        ..toggleValue(RecordFacetKind.network, 'selected');
      final search = TextEditingController();
      addTearDown(controller.dispose);
      addTearDown(search.dispose);
      controller.options.value = {
        RecordFacetKind.network: [
          for (var index = 0; index < 12; index++) 'network-$index',
          'selected',
        ],
      };
      await _pump(
        tester,
        ConditionFilterRow(
          controller: controller,
          searchController: search,
          onSearch: (_) {},
        ),
      );
      final group = tester.widget<ConnectedFilterButtons<String>>(
        find.byType(ConnectedFilterButtons<String>),
      );
      expect(group.values, controller.options.value[RecordFacetKind.network]);
      expect(group.values.last, 'selected');
      expect(group.isSelected('selected'), isTrue);
      expect(_facet('network-12'), findsNothing);
    },
  );

  testWidgets('status counts refresh locally without reading records', (
    tester,
  ) async {
    final controller = _controller(offered: false)
      ..toggleValue(RecordFacetKind.network, 'tcp');
    final search = TextEditingController();
    addTearDown(controller.dispose);
    addTearDown(search.dispose);
    var reads = 0;
    void counts(int count) => controller.offerCounts(
      {_Status.all: count, _Status.active: 9, _Status.failed: 2},
      () {
        reads++;
        return _records;
      },
    );
    counts(1234);
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConditionStatusButtons(controller: controller, maxWidth: 600),
          ConditionFilterRow(
            controller: controller,
            searchController: search,
            onSearch: (_) {},
          ),
        ],
      ),
    );
    final block = tester.widget<ConditionBlock<_Record>>(
      find.byType(ConditionBlock<_Record>),
    );
    var blockBuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is ConditionBlock<_Record>) {
        blockBuilds++;
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    expect(find.text('All(1,234)'), findsOneWidget);
    expect(find.text('Active(9)'), findsOneWidget);
    expect(find.text('Failed(2)'), findsOneWidget);
    counts(2345);
    await tester.pump();
    expect(find.text('All(2,345)'), findsOneWidget);
    expect(blockBuilds, 0);
    controller.status = _Status.active;
    await tester.pump();
    expect(blockBuilds, 0);
    expect(
      tester.widget<ConditionBlock<_Record>>(
        find.byType(ConditionBlock<_Record>),
      ),
      same(block),
    );
    expect(reads, 0);
  });

  testWidgets('status toggles preserve selected semantics and keyboard focus', (
    tester,
  ) async {
    final controller = _controller(offered: false);
    addTearDown(controller.dispose);
    controller.offerCounts({
      _Status.all: 11,
      _Status.active: 9,
      _Status.failed: 2,
    }, () => _records);
    await _pump(
      tester,
      ConditionStatusButtons(controller: controller, maxWidth: 600),
    );
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    final active = find.text('Active(9)');
    final focus = Focus.of(tester.element(active));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.status, _Status.active);
    expect(focus.hasPrimaryFocus, isTrue);
    final activeSemantics = tester.getSemantics(
      find.bySemanticsLabel('Active(9)'),
    );
    expect(activeSemantics.flagsCollection.isButton, isTrue);
    expect(activeSemantics.flagsCollection.isSelected.toBoolOrNull(), isTrue);
    expect(activeSemantics.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(controller.status, _Status.failed);
    expect(tester.takeException(), isNull);
  });

  testWidgets('connected buttons adjoin with square inner corners', (
    tester,
  ) async {
    await _pump(
      tester,
      ConnectedFilterButtons<int>(
        values: const [0, 1, 2],
        labelOf: (value) => 'Option $value',
        isSelected: (value) => value == 1,
        onSelected: (_) {},
      ),
    );
    final buttons = find.byType(PressSurface);
    final shapes = tester
        .widgetList<PressSurface>(buttons)
        .map(
          (button) => (button.shape as RoundedSuperellipseBorder).borderRadius
              .resolve(TextDirection.ltr),
        )
        .toList();
    expect(shapes[0].topLeft.x, AppCorner.sm);
    expect(shapes[0].topRight, Radius.zero);
    expect(shapes[1], BorderRadius.zero);
    expect(shapes[2].topLeft, Radius.zero);
    expect(shapes[2].topRight.x, AppCorner.sm);
    expect(
      tester.getRect(buttons.at(1)).left - tester.getRect(buttons.first).right,
      closeTo(1, .01),
    );
    expect(
      tester
          .widgetList<PressSurface>(buttons)
          .every((button) => button.side == BorderSide.none),
      isTrue,
    );
  });

  testWidgets('icon children keep accessible labels in a bounded group', (
    tester,
  ) async {
    await _pump(
      tester,
      ConnectedFilterButtons<bool>(
        values: const [true, false],
        labelOf: (value) => value ? 'List' : 'Table',
        isSelected: (value) => value,
        onSelected: (_) {},
        maxWidth: 60,
        childBuilder: (value, selected) =>
            const SizedBox(width: 20, height: 20),
      ),
    );
    final semantics = tester.ensureSemantics();
    addTearDown(semantics.dispose);
    expect(find.byTooltip('List'), findsOneWidget);
    expect(find.bySemanticsLabel('List'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ConnectedFilterButtons<bool>)).width,
      lessThanOrEqualTo(60),
    );
    expect(tester.takeException(), isNull);
  });
}
