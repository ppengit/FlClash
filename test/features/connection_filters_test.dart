import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/connection/connection_filters.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerInfo _connection(
  String id, {
  bool open = true,
  String network = 'tcp',
  String rule = 'MATCH',
}) => TrackerInfo(
  id: id,
  start: DateTime.utc(2026, 11, 22),
  metadata: Metadata(network: network, process: 'curl'),
  chains: const ['Proxy'],
  rule: rule,
  rulePayload: '',
  closedAt: open ? null : DateTime.utc(2026, 11, 22, 0, 1),
);

enum _TestStatus { all }

void main() {
  test(
    'offering connections counts statuses and offers fixed facet values',
    () {
      final controller = connectionFilters();
      addTearDown(controller.dispose);
      var told = 0;
      controller.counted.addListener(() => told++);

      controller.offer([_connection('a'), _connection('b', open: false)]);
      expect(controller.countOf(ConnectionStatus.all), 2);
      expect(controller.countOf(ConnectionStatus.active), 1);
      expect(told, 1);
      expect(controller.options.value, {
        RecordFacetKind.network: ['tcp'],
        RecordFacetKind.rule: ['MATCH'],
      });

      controller.offer([_connection('a'), _connection('c', open: false)]);
      expect(told, 1);
      controller.offer([_connection('a')]);
      expect(controller.countOf(ConnectionStatus.all), 1);
      expect(told, 2);
    },
  );

  testWidgets(
    'the first records offer their chips without waiting on an empty feed throttle',
    (tester) async {
      final controller = connectionFilters();
      addTearDown(controller.dispose);
      controller.offer(const []);
      await tester.pump(const Duration(milliseconds: 100));
      controller.offer([_connection('a')]);
      expect(controller.options.value, {
        RecordFacetKind.network: ['tcp'],
        RecordFacetKind.rule: ['MATCH'],
      });
    },
  );

  testWidgets('offers changed facet values after the throttle without another '
      'refresh', (tester) async {
    final controller = connectionFilters();
    addTearDown(controller.dispose);

    controller.offer([_connection('a')]);
    controller.offer([_connection('b', network: 'udp', rule: 'REJECT')]);

    expect(controller.options.value, {
      RecordFacetKind.network: ['tcp'],
      RecordFacetKind.rule: ['MATCH'],
    });
    await tester.pump(const Duration(seconds: 2));
    expect(controller.options.value, {
      RecordFacetKind.network: ['udp'],
      RecordFacetKind.rule: ['REJECT'],
    });
  });

  testWidgets('cancels a pending option refresh on dispose', (tester) async {
    final controller = connectionFilters();
    controller.offer([_connection('a')]);
    controller.offer([_connection('b', network: 'udp')]);
    controller.dispose();

    await tester.pump(const Duration(seconds: 2));
  });

  test('clears empty options immediately and retains selected values', () {
    final controller = connectionFilters();
    addTearDown(controller.dispose);

    controller.offer([_connection('a')]);
    controller.offer(const []);
    expect(controller.options.value, isEmpty);

    controller.add(const RecordFilter(RecordFacetKind.network, 'tcp'));
    controller.offer(const []);
    expect(controller.options.value, {
      RecordFacetKind.network: ['tcp'],
    });
  });

  test('does not read items to offer when no facet is offered', () {
    final controller = ConditionFilterController<int, _TestStatus>(
      facets: [
        RecordFacet(RecordFacetKind.network, (_) => ['tcp']),
      ],
      statuses: _TestStatus.values,
      fields: const [],
      labelOf: (_) => '',
      statusHolds: (_, _) => true,
      showsText: (_) => '',
      valuesInText: (_) => '',
      conditionTip: () => '',
    );
    addTearDown(controller.dispose);
    var reads = 0;

    controller.offerCounts({_TestStatus.all: 1}, () {
      reads++;
      return [1];
    });

    expect(reads, 0);
  });

  test('a status alone filters without narrowing past the status', () {
    final controller = connectionFilters();
    addTearDown(controller.dispose);

    controller.status = ConnectionStatus.active;

    expect(controller.isFiltering, isTrue);
    expect(controller.narrowsPastStatus, isFalse);
  });

  test('narrowing a facet to one value drops the conditions that widened its '
      'field and keeps exclusions and other fields', () {
    final controller = connectionFilters();
    addTearDown(controller.dispose);
    final widened = RecordCondition(ConnectionField.exit, 'Proxy');
    final excluded = RecordCondition(
      ConnectionField.exit,
      'DIRECT',
      excludes: true,
    );
    final host = RecordCondition(ConnectionField.host, 'example.com');
    for (final condition in [widened, excluded, host]) {
      controller.addCondition(condition);
    }

    controller.only(RecordFacetKind.proxy, 'Proxy');
    controller.only(RecordFacetKind.proxy, 'Other');

    expect(controller.conditions, [excluded, host]);
    expect(controller.selectedOf(RecordFacetKind.proxy), ['Other']);
    expect(controller.selectedOf(RecordFacetKind.app), isEmpty);
  });

  test('letting one condition alone through its field keeps exclusions', () {
    final controller = connectionFilters();
    addTearDown(controller.dispose);
    final excluded = RecordCondition(
      ConnectionField.app,
      'wget',
      excludes: true,
    );
    final host = RecordCondition(ConnectionField.host, 'example.com');
    for (final condition in [
      RecordCondition(ConnectionField.app, 'curl'),
      excluded,
      host,
    ]) {
      controller.addCondition(condition);
    }
    final only = RecordCondition(ConnectionField.app, 'git');

    controller.onlyCondition(only);

    expect(controller.conditions, [excluded, host, only]);
  });

  test('a facet value or a condition replaced by a condition gives way to '
      'it', () {
    final controller = connectionFilters();
    addTearDown(controller.dispose);
    final first = RecordCondition(ConnectionField.app, 'curl');
    final second = RecordCondition(ConnectionField.host, 'example.com');
    controller.only(RecordFacetKind.network, 'tcp');

    controller.replace(
      const RecordFilter(RecordFacetKind.network, 'tcp'),
      first,
    );
    expect(controller.filters, isEmpty);
    expect(controller.conditions, [first]);

    controller.addCondition(second);
    controller.replace(first, second);
    expect(controller.conditions, [second]);

    final third = RecordCondition(ConnectionField.ip, '1.1.1.1');
    controller.replace(first, third);
    expect(controller.conditions, [second, third]);
  });
}
