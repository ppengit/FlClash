import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';

import '../helpers/test_app.dart';

class _Feed extends StatefulWidget {
  const _Feed({required this.source});

  final ValueNotifier<int> source;

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed> with RouteMotionHoldMixin<_Feed> {
  late int _shown = widget.source.value;

  @override
  void initState() {
    super.initState();
    widget.source.addListener(_handleSource);
  }

  @override
  void dispose() {
    widget.source.removeListener(_handleSource);
    super.dispose();
  }

  void _handleSource() {
    updateWhenRouteSettled(() => setState(() => _shown = widget.source.value));
  }

  @override
  Widget build(BuildContext context) => Text('shown $_shown');
}

void main() {
  late ValueNotifier<int> source;
  late GlobalKey<NavigatorState> navigator;

  setUp(() {
    source = ValueNotifier(0);
    navigator = GlobalKey<NavigatorState>();
  });

  tearDown(() => source.dispose());

  Future<void> holdUpdates(WidgetTester tester) async {
    await tester.pumpWidget(
      HostApp(navigatorKey: navigator, home: _Feed(source: source)),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.didStartUserGesture();
    source.value = 1;
    source.value = 2;
    await tester.pumpAndSettle();
    expect(find.text('shown 0'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  }

  void stopAfterFrame() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      navigator.currentState!.didStopUserGesture();
    });
  }

  testWidgets('a post-frame gesture stop schedules the held update', (
    tester,
  ) async {
    await holdUpdates(tester);
    stopAfterFrame();

    await tester.pump();

    expect(find.text('shown 0'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();

    expect(find.text('shown 2'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a post-frame stop still waits for the animation it starts', (
    tester,
  ) async {
    final fade = AnimationController(
      vsync: const TestVSync(),
      duration: const Duration(milliseconds: 100),
    );
    addTearDown(fade.dispose);
    await holdUpdates(tester);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      navigator.currentState!.didStopUserGesture();
      unawaited(fade.forward());
    });

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('shown 0'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('shown 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing a feed before its post-frame settle drops the update', (
    tester,
  ) async {
    await holdUpdates(tester);
    stopAfterFrame();
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(find.byType(_Feed), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
