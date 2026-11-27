import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_ui/prism_ui.dart';

import '../helpers/host_scaffold.dart';
import '../helpers/test_app.dart';

void main() {
  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets('a connected bar shares label widths, keeps every segment '
        'pill-shaped, and changes selection in ${direction.name}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final changes = <int>[];
        var selected = 0;
        const labels = ['One', 'Two', 'Three'];
        await tester.pumpWidget(
          HostApp(
            home: HostScaffold(
              body: Directionality(
                textDirection: direction,
                child: SizedBox(
                  width: 303,
                  child: StatefulBuilder(
                    builder: (context, setState) => ConnectedButtonBar<int>(
                      segments: const [(0, 'One'), (1, 'Two'), (2, 'Three')],
                      value: selected,
                      onChanged: (value) {
                        changes.add(value);
                        setState(() => selected = value);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final buttons = find.byType(ConnectedButton);
        expect(buttons, findsNWidgets(3));
        for (final value in [0, 2, 1]) {
          await tester.tap(find.text(labels[value]));
          await tester.pumpAndSettle();
          for (final index in [0, 1, 2]) {
            final button = buttons.at(index);
            final rect = tester.getRect(button);
            expect(rect.height, viewSwitcherHeight);
            expect(rect.width, 99);
            final decoration =
                tester
                        .widget<Container>(
                          find
                              .descendant(
                                of: button,
                                matching: find.byType(Container),
                              )
                              .first,
                        )
                        .decoration!
                    as ShapeDecoration;
            expect(
              (decoration.shape as RoundedSuperellipseBorder).borderRadius,
              BorderRadius.circular(viewSwitcherHeight / 2),
            );
            final node = tester.getSemantics(button);
            expect(node.label, labels[index]);
            expect(node.flagsCollection.isButton, isTrue);
            expect(node.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
            expect(
              node.flagsCollection.isSelected.toBoolOrNull(),
              index == value,
            );
          }
        }
        expect(changes, [2, 1]);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('a screen reader activates a connected button as a press '
      'would', (tester) async {
    final semantics = tester.ensureSemantics();
    final changes = <int>[];
    await tester.pumpWidget(
      HostApp(
        home: HostScaffold(
          body: SizedBox(
            width: 303,
            child: ConnectedButtonBar<int>(
              segments: const [(0, 'One'), (1, 'Two'), (2, 'Three')],
              value: 0,
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.semantics.tap(find.semantics.byLabel('Three'));

    expect(changes, [2]);
    semantics.dispose();
  });
}
