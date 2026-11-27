import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/connection/connection_connected_buttons.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/connection/requests.dart';
import 'package:fl_clash/views/connection/requests_detail_pane.dart'
    show RequestsDetailPane;
import 'package:fl_clash/views/connection/requests_table.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _previewKey = ValueKey('requestsPreview');
const _fontFamily = 'RequestsPreview';
const _profile = Profile(
  id: 1,
  label: 'Preview',
  autoUpdateDuration: Duration.zero,
);
const _previews = [
  (
    name: 'requests-light-desktop',
    size: Size(1400, 900),
    brightness: Brightness.light,
    split: false,
  ),
  (
    name: 'requests-dark-desktop',
    size: Size(1400, 900),
    brightness: Brightness.dark,
    split: false,
  ),
  (
    name: 'requests-light-split',
    size: Size(1400, 900),
    brightness: Brightness.light,
    split: true,
  ),
  (
    name: 'requests-light-narrow',
    size: Size(390, 844),
    brightness: Brightness.light,
    split: false,
  ),
];

List<TrackerInfo> _connections() => List.generate(24, (index) {
  final start = DateTime.utc(2026, 11, 27, 10, 24, index * 2);
  final process = index.isEven ? 'Editor.exe' : 'Browser.exe';
  final host = index.isEven ? 'example.test' : 'api.test';
  final active = index % 3 == 0;
  final failed = index % 3 == 2;
  return TrackerInfo(
    id: 'preview-$index',
    start: start,
    metadata: Metadata(
      network: index % 4 == 0 ? 'udp' : 'tcp',
      sourceIP: '192.0.2.10',
      sourcePort: '${51000 + index}',
      destinationIP: '198.51.100.${index + 1}',
      destinationPort: '443',
      host: '$index.$host',
      process: process,
      processPath: 'Applications/$process',
    ),
    chains: index % 4 == 0 ? const ['DIRECT'] : const ['Node', 'Proxy'],
    rule: 'DomainSuffix',
    rulePayload: host,
    upload: failed ? 0 : (index + 1) * 2048,
    download: failed ? 0 : (index + 1) * 65536,
    uploadSpeed: active ? 1024 * (index + 1) : null,
    downloadSpeed: active ? 8192 * (index + 1) : null,
    closedAt: active ? null : start.add(const Duration(seconds: 12)),
    failure: failed
        ? const ConnectionFailure(kind: ConnectionFailureKind.timeout)
        : null,
    timing: ConnectionTiming(
      accepted: start,
      dnsStart: 200,
      dnsEnd: 1400,
      routed: 1800,
      dialStart: 2000,
      connected: failed ? null : 18000,
    ),
  );
});

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void _expectUntruncated(WidgetTester tester, Finder controls) {
  final paragraphs = find.descendant(
    of: controls,
    matching: find.byType(RichText),
  );
  expect(paragraphs, findsWidgets);
  for (final element in paragraphs.evaluate()) {
    final paragraph = element.renderObject! as RenderParagraph;
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: paragraph.text.toPlainText(),
    );
    expect(paragraph.text.toPlainText(), isNot(contains('…')));
  }
}

void _expectToolbar(WidgetTester tester) {
  final filters = find.byType(
    ConditionFilterRow<TrackerInfo, ConnectionStatus>,
  );
  final segments = find.byType(ConnectedFilterButtons<RequestsSegment>);
  final status = find.byType(
    ConditionStatusButtons<TrackerInfo, ConnectionStatus>,
  );
  final search = find.descendant(
    of: filters,
    matching: find.byType(SearchField),
  );
  final add = find.descendant(
    of: filters,
    matching: find.byTooltip('Add condition'),
  );
  expect(filters, findsOneWidget);
  expect(segments, findsOneWidget);
  expect(status, findsOneWidget);
  expect(find.descendant(of: filters, matching: segments), findsOneWidget);
  expect(find.text('All(24)'), findsOneWidget);
  expect(find.text('Active(8)'), findsOneWidget);
  expect(find.text('Failed(8)'), findsOneWidget);
  final searchRect = tester.getRect(search);
  final segmentRect = tester.getRect(segments);
  expect(searchRect.width, greaterThanOrEqualTo(120));
  expect(segmentRect.left, greaterThan(searchRect.right));
  expect(segmentRect.center.dy, closeTo(searchRect.center.dy, .01));
  expect(tester.getCenter(add).dy, closeTo(searchRect.center.dy, .01));
  _expectUntruncated(tester, segments);
  _expectUntruncated(tester, status);
}

Future<void> _expandAndCheckTable(WidgetTester tester) async {
  final tableFinder = find.byType(RequestsTable);
  expect(tableFinder, findsOneWidget);
  expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  expect(find.byTooltip('List'), findsOneWidget);
  expect(find.byTooltip('List and details'), findsOneWidget);
  await tester.tap(find.byTooltip('Expand all'));
  await _frames(tester);
  expect(find.byType(RequestsTableRow), findsWidgets);
  expect(
    tester.widgetList<RequestsProcessRow>(find.byType(RequestsProcessRow)),
    everyElement(
      isA<RequestsProcessRow>().having((row) => row.expanded, 'expanded', true),
    ),
  );
  final headers = find.byType(RecordHeaderCell);
  _expectUntruncated(tester, headers);
  final before = [
    for (final element in headers.evaluate())
      tester.getRect(find.byWidget(element.widget)),
  ];
  final table = tester.widget<RequestsTable>(tableFinder);
  expect(table.rows.shownCount, 24);
  expect(table.controller.position.maxScrollExtent, greaterThan(0));
  table.controller.jumpTo(table.controller.position.maxScrollExtent);
  await _frames(tester);
  expect([
    for (final element in headers.evaluate())
      tester.getRect(find.byWidget(element.widget)),
  ], before);
  table.controller.jumpTo(table.controller.position.minScrollExtent);
  await _frames(tester);
  expect(
    tester.getTopLeft(find.byType(PrismListView)).dy,
    greaterThanOrEqualTo(before.first.bottom),
  );
}

Future<void> _savePreview(WidgetTester tester, String name, Size size) async {
  final directory = Platform.environment['FLCLASH_REQUEST_PREVIEW_DIR'];
  if (directory == null || directory.isEmpty) return;
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_previewKey),
  );
  expect(boundary.size, size);
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(data, isNotNull);
      await Directory(directory).create(recursive: true);
      await File(p.join(directory, '$name.png')).writeAsBytes(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontFile = Platform.environment['FLCLASH_PREVIEW_FONT_FILE'];
  final hasFont = fontFile != null && fontFile.isNotEmpty;
  late ProviderContainer container;
  late Completer<List<TrackerInfo>> frozenConnections;

  setUpAll(() async {
    if (!hasFont) return;
    final loader = FontLoader(_fontFamily)
      ..addFont(File(fontFile).readAsBytes().then(ByteData.sublistView));
    await loader.load();
  });

  setUp(() {
    loadAppLocalizations(const Locale('en'));
    frozenConnections = Completer<List<TrackerInfo>>();
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles([_profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => _profile.id),
        requestsProvider.overrideWithBuild(
          (_, _) => ConnectionLog(100).open(_connections()),
        ),
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(
            locale: 'en',
            requestsSplitView: false,
            requestsColumns: [
              'destination',
              'process',
              'network',
              'rule',
              'exit',
              'download',
              'upload',
              'status',
            ],
          ),
        ),
        packageIconSourceProvider.overrideWithValue(null),
      ],
    );
    globalState.container = container;
    container.listen(profilesProvider, (_, _) {});
    container.listen(currentProfileIdProvider, (_, _) {});
    container.listen(requestsProvider, (_, _) {});
    container.listen(appSettingProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  for (final preview in _previews) {
    testWidgets('${preview.name} renders an aligned, untruncated toolbar', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = preview.size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      container.read(viewSizeProvider.notifier).update((_) => preview.size);
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(requestsSplitView: preview.split));
      final theme = ThemeData(
        colorScheme: seededColorScheme(
          seedColor: const Color(defaultPrimaryColor),
          brightness: preview.brightness,
          style: ColorStyle.vivid,
        ),
        platform: TargetPlatform.linux,
        fontFamily: hasFont ? _fontFamily : null,
      );
      try {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: RepaintBoundary(
              key: _previewKey,
              child: HostApp(
                theme: theme,
                darkTheme: theme,
                themeMode: preview.brightness == Brightness.dark
                    ? ThemeMode.dark
                    : ThemeMode.light,
                locale: const Locale('en'),
                builder: (context, child) => wrapAppScopes(context, child!),
                home: RequestsView(
                  connectionsReader: () => frozenConnections.future,
                ),
              ),
            ),
          ),
        );
        await _frames(tester);
        _expectToolbar(tester);
        expect(
          Theme.of(tester.element(find.byType(RequestsView))).brightness,
          preview.brightness,
        );
        expect(find.byType(CheckedModeBanner), findsNothing);
        if (preview.size.width >= 1000 && !preview.split) {
          await _expandAndCheckTable(tester);
        } else {
          expect(find.byType(RequestsTable), findsNothing);
          expect(find.byType(TrackerInfoItem), findsWidgets);
          if (preview.split) {
            final pane = find.byType(RequestsDetailPane);
            expect(pane, findsOneWidget);
            final filters = tester.getRect(
              find.byType(ConditionFilterRow<TrackerInfo, ConnectionStatus>),
            );
            final list = tester.getRect(find.byType(ScrollToEndBox));
            expect(list.top, greaterThanOrEqualTo(filters.bottom));
            expect(tester.getTopLeft(pane).dy, closeTo(list.top, .01));
            final selected = find.byType(TrackerInfoItem).hitTestable().first;
            final id = tester.widget<TrackerInfoItem>(selected).trackerInfo.id;
            await tester.tap(selected);
            await _frames(tester);
            expect(find.byType(TrackerSelectedDetail), findsOneWidget);
            expect(
              tester
                  .widget<TrackerInfoHeader>(find.byType(TrackerInfoHeader))
                  .trackerInfo
                  .id,
              id,
            );
            expect(find.byType(TrackerInfoDetailSheet), findsNothing);
          } else {
            expect(find.byType(RequestsDetailPane), findsNothing);
          }
        }
        _expectToolbar(tester);
        expect(tester.takeException(), isNull);
        await _savePreview(tester, preview.name, preview.size);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        if (!frozenConnections.isCompleted) {
          frozenConnections.complete(const []);
        }
        await tester.pump(const Duration(seconds: 2));
      }
    });
  }
}
