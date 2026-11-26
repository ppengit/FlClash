import 'dart:async';

import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/test_database_providers.dart';
import '../helpers/test_profiles.dart';

class _TrailPage extends StatefulWidget {
  const _TrailPage({
    this.depth = 0,
    this.blockIntermediate = false,
    this.titles,
    this.menu = false,
    this.blockLeaf = false,
    this.onLeafPop,
    this.onLeafSuccess,
  });

  final Future<void> Function()? onLeafSuccess;
  final bool blockLeaf;
  final Future<bool> Function()? onLeafPop;
  final int depth;
  final bool blockIntermediate;
  final ValueNotifier<List<String>>? titles;
  final bool menu;

  @override
  State<_TrailPage> createState() => _TrailPageState();
}

class _TrailPageState extends State<_TrailPage> {
  static const _titles = ['Tools', 'Advanced configuration', 'Added rules'];

  @override
  Widget build(BuildContext context) {
    Widget page(List<String> titles) => PopGuard(
      onPop: widget.depth == 2 && widget.onLeafPop != null
          ? (_) => widget.onLeafPop!()
          : widget.blockIntermediate && widget.depth == 1
          ? (_) => false
          : null,
      onPopSuccess: widget.depth == 2 ? widget.onLeafSuccess : null,
      child: Scaffold(
        title: titles[widget.depth],
        titleMenuItems: widget.menu && widget.depth == 2
            ? [PopupMenuItem(label: 'Page action', onPressed: () {})]
            : const [],
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('body ${widget.depth}'),
              if (widget.depth < 2)
                FilledButton(
                  onPressed: () => BaseNavigator.push<void>(
                    context,
                    _TrailPage(
                      depth: widget.depth + 1,
                      blockIntermediate: widget.blockIntermediate,
                      titles: widget.titles,
                      menu: widget.menu,
                      blockLeaf: widget.blockLeaf,
                      onLeafPop: widget.onLeafPop,
                      onLeafSuccess: widget.onLeafSuccess,
                    ),
                  ),
                  child: Text('open ${widget.depth + 1}'),
                ),
            ],
          ),
        ),
      ),
    );

    final titles = widget.titles;
    final content = titles == null
        ? page(_titles)
        : ValueListenableBuilder(
            valueListenable: titles,
            builder: (_, value, _) => page(value),
          );
    return widget.blockLeaf && widget.depth == 2
        ? PopScope(canPop: false, child: content)
        : content;
  }
}

void main() {
  for (final width in [400.0, 1400.0]) {
    testWidgets('Tools to added rules keeps the complete chain at $width dp', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        TestApp(
          wrapInProviderScope: true,
          overrides: [
            viewSizeProvider.overrideWithBuild((_, _) => Size(width, 1100)),
            profilesProvider.overrideWith(TestProfiles.new),
            globalRulesProvider.overrideWith(TestGlobalRules.new),
          ],
          child: Navigator(
            key: navigator,
            pages: const [RootPage<void>(child: ToolsView())],
            onDidRemovePage: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = currentAppLocalizations;
      await tester.ensureVisible(find.text(l.advancedConfig));
      await tester.tap(find.text(l.advancedConfig));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.addedRules));
      await tester.pumpAndSettle();

      expect(find.text(l.tools), findsOneWidget);
      expect(find.text(l.advancedConfig), findsOneWidget);
      expect(find.text(l.addedRules), findsOneWidget);
      await tester.ensureVisible(find.text(l.tools));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.tools));
      await tester.pumpAndSettle();
      expect(find.byType(ToolsView), findsOneWidget);
      expect(navigator.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  Future<GlobalKey<NavigatorState>> pumpTrail(
    WidgetTester tester, {
    double width = 1400,
    bool blocked = false,
    bool menu = false,
    bool blockLeaf = false,
    Future<bool> Function()? onLeafPop,
    Future<void> Function()? onLeafSuccess,
    ValueNotifier<List<String>>? titles,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => Size(width, 900)),
        ],
        child: Row(
          children: [
            const SizedBox(width: 80, child: Text('navigation rail')),
            Expanded(
              child: Navigator(
                key: navigator,
                pages: [
                  RootPage<void>(
                    child: _TrailPage(
                      blockIntermediate: blocked,
                      titles: titles,
                      menu: menu,
                      blockLeaf: blockLeaf,
                      onLeafPop: onLeafPop,
                      onLeafSuccess: onLeafSuccess,
                    ),
                  ),
                ],
                onDidRemovePage: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    return navigator;
  }

  Future<void> openRules(WidgetTester tester) async {
    await tester.tap(find.text('open 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open 2'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'full breadcrumbs return to any ancestor in the nested navigator',
    (tester) async {
      final navigator = await pumpTrail(tester);
      await openRules(tester);

      expect(find.text('Tools'), findsOneWidget);
      expect(find.text('Advanced configuration'), findsOneWidget);
      expect(find.text('Added rules'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Tools')).dx,
        lessThan(tester.getTopLeft(find.text('Advanced configuration')).dx),
      );
      await tester.tap(find.text('Advanced configuration'));
      await tester.pumpAndSettle();
      expect(find.text('body 1'), findsOneWidget);
      expect(find.text('Added rules'), findsNothing);

      await tester.tap(find.text('open 2'));
      await tester.pumpAndSettle();
      expect(find.text('Tools').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();
      expect(find.text('body 0'), findsOneWidget);
      expect(find.text('Advanced configuration'), findsNothing);
      expect(navigator.currentState!.canPop(), isFalse);
      expect(find.text('navigation rail'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('breadcrumb navigation closes local history before leaving', (
    tester,
  ) async {
    await pumpTrail(tester);
    await openRules(tester);
    var removed = 0;
    final route = ModalRoute.of(tester.element(find.text('body 2')))!;
    for (var entry = 0; entry < 2; entry++) {
      route.addLocalHistoryEntry(LocalHistoryEntry(onRemove: () => removed++));
    }
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    expect(removed, 2);
    expect(find.text('body 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final allowed in [false, true]) {
    testWidgets('breadcrumb jump awaits an asynchronous $allowed guard', (
      tester,
    ) async {
      final decision = Completer<bool>();
      await pumpTrail(tester, onLeafPop: () => decision.future);
      await openRules(tester);
      await tester.tap(find.text('Tools'));
      await tester.pump();
      expect(find.text('body 2'), findsOneWidget);

      decision.complete(allowed);
      await tester.pumpAndSettle();
      expect(find.text(allowed ? 'body 0' : 'body 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('an approved jump does not wait for post-pop cleanup', (
    tester,
  ) async {
    final cleanup = Completer<void>();
    var cleanupCalls = 0;
    await pumpTrail(
      tester,
      onLeafPop: () async => true,
      onLeafSuccess: () {
        cleanupCalls++;
        return cleanup.future;
      },
    );
    await openRules(tester);
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();

    expect(find.text('body 0'), findsOneWidget);
    expect(cleanupCalls, 1);
    expect(cleanup.isCompleted, isFalse);
    cleanup.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'local history with a pop veto never spins or discards the page',
    (tester) async {
      await pumpTrail(tester, blockLeaf: true);
      await openRules(tester);
      var removed = 0;
      final route = ModalRoute.of(tester.element(find.text('body 2')))!;
      route.addLocalHistoryEntry(LocalHistoryEntry(onRemove: () => removed++));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tools'));
      await tester.pumpAndSettle();
      expect(find.text('body 2'), findsOneWidget);
      expect(removed, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('breadcrumb navigation respects an intermediate pop guard', (
    tester,
  ) async {
    await pumpTrail(tester, blocked: true);
    await openRules(tester);
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();

    expect(find.text('body 1'), findsOneWidget);
    expect(find.text('body 0'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a kept page can push from above its scaffold without mixing titles',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        TestApp(
          wrapInProviderScope: true,
          overrides: [
            viewSizeProvider.overrideWithBuild((_, _) => const Size(400, 900)),
          ],
          child: const IndexedStack(
            index: 0,
            children: [
              _TrailPage(),
              Scaffold(title: 'Other destination', body: SizedBox.shrink()),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await openRules(tester);

      expect(find.text('Tools'), findsOneWidget);
      expect(find.text('Other destination'), findsNothing);
      expect(find.text('Added rules'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('kept pages sharing a root route keep their own breadcrumb', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(400, 900)),
        ],
        child: IndexedStack(
          index: 0,
          children: [
            Scaffold(
              title: 'First destination',
              body: Center(
                child: Builder(
                  builder: (context) => FilledButton(
                    onPressed: () => BaseNavigator.push<void>(
                      context,
                      const _TrailPage(depth: 2),
                    ),
                    child: const Text('push from first'),
                  ),
                ),
              ),
            ),
            const Scaffold(
              title: 'Second destination',
              body: SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('push from first'));
    await tester.pumpAndSettle();

    expect(find.text('First destination'), findsOneWidget);
    expect(find.text('Second destination'), findsNothing);
    expect(find.text('Added rules'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('ancestor title changes update the visible path', (tester) async {
    final titles = ValueNotifier([
      'Tools',
      'Advanced configuration',
      'Added rules',
    ]);
    addTearDown(titles.dispose);
    await pumpTrail(tester, titles: titles);
    await openRules(tester);

    titles.value = ['工具', '进阶配置', '附加规则'];
    await tester.pumpAndSettle();
    expect(find.text('工具'), findsOneWidget);
    expect(find.text('进阶配置'), findsOneWidget);
    expect(find.text('附加规则'), findsOneWidget);
    expect(find.text('Tools'), findsNothing);
    await tester.tap(find.text('工具'));
    await tester.pumpAndSettle();
    expect(find.text('body 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a narrow path scrolls without dropping ancestors', (
    tester,
  ) async {
    await pumpTrail(tester, width: 400);
    await openRules(tester);
    expect(find.text('Added rules'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    expect(find.text('body 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the current breadcrumb retains its title menu', (tester) async {
    await pumpTrail(tester, menu: true);
    await openRules(tester);
    await tester.tap(find.text('Added rules'));
    await tester.pumpAndSettle();

    expect(find.text('Page action'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
