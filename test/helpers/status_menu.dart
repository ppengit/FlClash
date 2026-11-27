import 'package:fl_clash/features/connection/connection_connected_buttons.dart';
import 'package:fl_clash/features/features.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Finder findStatusButtons() => find.byWidgetPredicate(
  (widget) =>
      widget is ConnectedFilterButtons<ConnectionStatus> ||
      widget is ConnectedFilterButtons<DnsStatus> ||
      widget is ConnectedFilterButtons<HttpRequestStatus>,
);

List<String> statusButtonLabels(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(of: findStatusButtons(), matching: find.byType(Text)),
  ))
    text.data!,
];

String selectedStatusText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.descendant(
          of: findStatusButtons(),
          matching: find.byWidgetPredicate(
            (widget) => widget is PressSurface && widget.selected,
          ),
        ),
        matching: find.byType(Text),
      ),
    )
    .data!;

// The dashboard sheet assertions compare a status and count, not its punctuation.
String shownStatusText(WidgetTester tester) => selectedStatusText(
  tester,
).replaceFirstMapped(RegExp(r'\(([^)]+)\)$'), (match) => ' ${match[1]}');

Future<void> pickStatus(WidgetTester tester, String status) async {
  final split = status.lastIndexOf(' ');
  final label = '${status.substring(0, split)}(${status.substring(split + 1)})';
  expect(statusButtonLabels(tester), contains(label));
  final button = find.descendant(
    of: findStatusButtons(),
    matching: find.byTooltip(label),
  );
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}
