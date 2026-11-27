import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/connection/requests_split.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

class _Probe extends StatefulWidget {
  final String label;

  const _Probe({required this.label, super.key});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF808080),
    child: Center(child: Text(widget.label)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late GlobalKey<_ProbeState> listKey;
  late GlobalKey<_ProbeState> detailKey;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        appSettingProvider.overrideWithBuild(
          (_, _) => const AppSettingProps(requestsListWidth: 392),
        ),
      ],
    );
    container.listen(appSettingProvider, (_, _) {});
    globalState.container = container;
    listKey = GlobalKey<_ProbeState>();
    detailKey = GlobalKey<_ProbeState>();
  });

  tearDown(() => container.dispose());

  Finder handle() => find.descendant(
    of: find.byType(RequestsSplit),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is MouseRegion &&
          widget.cursor == SystemMouseCursors.resizeColumn,
    ),
  );

  Future<void> pumpSplit(
    WidgetTester tester, {
    Size size = const Size(1000, 700),
    bool rtl = false,
    double minDetailWidth = 300,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: RequestsSplit(
              list: _Probe(key: listKey, label: 'list'),
              detail: _Probe(key: detailKey, label: 'detail'),
              minDetailWidth: minDetailWidth,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('drag changes locally and saves once at drag end', (
    tester,
  ) async {
    await pumpSplit(tester);
    final listState = listKey.currentState;
    final before = tester.getRect(find.byKey(listKey));
    final gesture = await tester.startGesture(tester.getCenter(handle()));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();

    expect(container.read(appSettingProvider).requestsListWidth, 392);
    expect(tester.getRect(find.byKey(listKey)).width, closeTo(472, 0.1));
    expect(listKey.currentState, same(listState));
    expect(detailKey.currentState, isNotNull);
    expect(before.width, closeTo(392, 0.1));

    await gesture.up();
    await tester.pump();
    expect(
      container.read(appSettingProvider).requestsListWidth,
      closeTo(472, 0.1),
    );
    await close(tester);
  });

  testWidgets('drag end and cancellation persist bounded widths', (
    tester,
  ) async {
    await pumpSplit(tester);
    var gesture = await tester.startGesture(tester.getCenter(handle()));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(1000, 0));
    await gesture.up();
    await tester.pump();
    expect(tester.getRect(find.byKey(listKey)).width, closeTo(690, 0.1));
    expect(
      container.read(appSettingProvider).requestsListWidth,
      closeTo(690, 0.1),
    );

    gesture = await tester.startGesture(tester.getCenter(handle()));
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-1000, 0));
    await tester.pump();
    expect(
      container.read(appSettingProvider).requestsListWidth,
      closeTo(690, 0.1),
    );
    await gesture.cancel();
    await tester.pump();
    expect(
      container.read(appSettingProvider).requestsListWidth,
      closeTo(320, 0.1),
    );
    await close(tester);
  });

  testWidgets('responsive shrink clamps without replacing the saved width', (
    tester,
  ) async {
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(requestsListWidth: 600));
    await pumpSplit(tester, size: const Size(1000, 700));
    expect(tester.getRect(find.byKey(listKey)).width, closeTo(600, 0.1));

    tester.view.physicalSize = const Size(700, 700);
    await tester.pump();
    expect(tester.getRect(find.byKey(listKey)).width, closeTo(390, 0.1));
    expect(container.read(appSettingProvider).requestsListWidth, 600);

    tester.view.physicalSize = const Size(1000, 700);
    await tester.pump();
    expect(tester.getRect(find.byKey(listKey)).width, closeTo(600, 0.1));
    await close(tester);
  });

  testWidgets('a reopened split restores the persisted width', (tester) async {
    await pumpSplit(tester);
    final gesture = await tester.startGesture(tester.getCenter(handle()));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(55, 0));
    await gesture.up();
    await tester.pump();
    final saved = container.read(appSettingProvider).requestsListWidth;

    await close(tester);
    listKey = GlobalKey<_ProbeState>();
    detailKey = GlobalKey<_ProbeState>();
    await pumpSplit(tester);
    expect(tester.getRect(find.byKey(listKey)).width, closeTo(saved, 0.1));
    await close(tester);
  });

  testWidgets('RTL drag and keyboard arrows resize toward the visual side', (
    tester,
  ) async {
    await pumpSplit(tester, rtl: true);
    final gesture = await tester.startGesture(tester.getCenter(handle()));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(50, 0));
    await gesture.up();
    await tester.pump();
    expect(
      container.read(appSettingProvider).requestsListWidth,
      closeTo(342, 0.1),
    );

    await tester.tap(handle());
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(
      container.read(appSettingProvider).requestsListWidth,
      closeTo(358, 0.1),
    );
    await close(tester);
  });

  testWidgets('double tap resets the width to the configured default', (
    tester,
  ) async {
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(requestsListWidth: 600));
    await pumpSplit(tester);
    final center = tester.getCenter(handle());
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await tester.pump();
    expect(container.read(appSettingProvider).requestsListWidth, 392);
    expect(tester.getRect(find.byKey(listKey)).width, closeTo(392, 0.1));
    await close(tester);
  });
}
