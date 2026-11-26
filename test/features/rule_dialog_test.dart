import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/connection/tracker_rule.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

Finder _banner(String text) =>
    find.descendant(of: find.byType(ErrorBanner), matching: find.text(text));

void main() {
  test(
    'request rule suggestions use recorded domains, addresses and processes',
    () {
      final suggestions = trackerRuleContents(
        const Metadata(
          host: ' example.com ',
          destinationIP: '192.0.2.10',
          processPath: r'C:\Tools\curl.exe',
        ),
      );

      expect(suggestions[RuleAction.DOMAIN], 'example.com');
      expect(suggestions[RuleAction.DOMAIN_SUFFIX], 'example.com');
      expect(suggestions[RuleAction.IP_CIDR], '192.0.2.10/32');
      expect(suggestions[RuleAction.PROCESS_NAME], 'curl.exe');
      expect(suggestions[RuleAction.PROCESS_PATH], r'C:\Tools\curl.exe');
      expect(trackerRuleContents(const Metadata(host: '2001:db8::1')), {
        RuleAction.IP_CIDR6: '2001:db8::1/128',
      });
      expect(trackerRuleContents(const Metadata()), isEmpty);
    },
  );

  testWidgets('request suggestions follow the type without losing edits', (
    tester,
  ) async {
    Rule? result;
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(1200, 800)),
        ],
        child: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showFormSheet<Rule>(
                context: context,
                builder: (_) => const RuleForm(
                  suggestedContents: {
                    RuleAction.DOMAIN: 'rule.test',
                    RuleAction.IP_CIDR: '192.0.2.10/32',
                    RuleAction.PROCESS_NAME: 'curl.exe',
                  },
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = currentAppLocalizations;
    final content = find.byType(TextFormField);
    expect(tester.widget<TextFormField>(content).controller!.text, 'rule.test');
    expect(
      find.descendant(
        of: find.byType(ListFooter),
        matching: find.text(l10n.ruleContentExample('example.com')),
      ),
      findsOneWidget,
    );
    await tester.enterText(content, 'edited.test');

    Future<void> selectType(RuleAction action) async {
      await tester.tap(find.text(l10n.proxyType));
      await tester.pumpAndSettle();
      final label =
          '${action.value} (${action.getDesc(tester.element(find.byType(RuleForm)))})';
      await tester.ensureVisible(find.text(label).last);
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    await selectType(RuleAction.IP_CIDR);
    expect(
      tester.widget<TextFormField>(content).controller!.text,
      '192.0.2.10/32',
    );
    expect(
      find.descendant(
        of: find.byType(ListFooter),
        matching: find.text(l10n.ruleContentExample('192.0.2.0/24')),
      ),
      findsOneWidget,
    );
    await selectType(RuleAction.DOMAIN);
    expect(
      tester.widget<TextFormField>(content).controller!.text,
      'edited.test',
    );
    await selectType(RuleAction.PROCESS_NAME);
    expect(tester.widget<TextFormField>(content).controller!.text, 'curl.exe');
    await tester.tap(find.widgetWithText(TextButton, l10n.save));
    await tester.pumpAndSettle();

    expect(result!.ruleAction, RuleAction.PROCESS_NAME);
    expect(result!.content, 'curl.exe');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Chinese rule help updates without changing content or wire values',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Rule? result;
      await tester.pumpWidget(
        TestApp(
          locale: const Locale('zh'),
          wrapInProviderScope: true,
          overrides: [
            viewSizeProvider.overrideWithBuild(
              (_, _) => const Size(1200, 1000),
            ),
          ],
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showFormSheet<Rule>(
                  context: context,
                  builder: (_) => const RuleForm(
                    suggestedContents: {RuleAction.DOMAIN: 'already.test'},
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final l = currentAppLocalizations;
      final content = find.byType(TextFormField);
      expect(l.ruleScopeProfile, '当前配置');
      expect(l.ruleScopeGlobal, '所有配置');
      expect(find.text('DIRECT (直连)'), findsOneWidget);

      Future<void> selectType(RuleAction action) async {
        await tester.tap(find.text(l.proxyType));
        await tester.pumpAndSettle();
        final label =
            '${action.value} (${action.getDesc(tester.element(find.byType(RuleForm)))})';
        await tester.ensureVisible(find.text(label).last);
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      Finder example(String value) => find.descendant(
        of: find.byType(ListFooter),
        matching: find.text(l.ruleContentExample(value)),
      );

      await selectType(RuleAction.PROCESS_NAME_REGEX);
      expect(example(r'^app(?:\.exe)?$'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(content).controller!.text,
        'already.test',
      );
      await selectType(RuleAction.DOMAIN_SUFFIX);
      expect(find.text('DOMAIN-SUFFIX (域名后缀)'), findsOneWidget);
      expect(example('example.com'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(content).controller!.text,
        'already.test',
      );
      await tester.tap(find.text(l.splitStrategy));
      await tester.pumpAndSettle();
      await tester.tap(find.text('REJECT (拒绝连接)').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l.save));
      await tester.pumpAndSettle();

      expect(result!.ruleAction, RuleAction.DOMAIN_SUFFIX);
      expect(result!.content, 'already.test');
      expect(result!.ruleTarget, 'REJECT');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a large explicit target list builds only its visible choices', (
    tester,
  ) async {
    final targets = [
      'DIRECT',
      for (var index = 0; index < 2000; index++) 'Proxy $index',
    ];
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(1200, 800)),
        ],
        child: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showFormSheet<Rule>(
              context: context,
              builder: (_) => RuleForm(targets: targets),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(currentAppLocalizations.splitStrategy));
    await tester.pumpAndSettle();

    expect(find.text('Proxy 1999'), findsNothing);
    expect(find.textContaining('Proxy ').evaluate().length, lessThan(50));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('add rule validates content and returns the entered rule', (
    tester,
  ) async {
    Rule? result;
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(1200, 800)),
        ],
        child: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () async {
                result = await showFormSheet<Rule>(
                  context: context,
                  builder: (_) => const RuleForm(),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = currentAppLocalizations;

    await tester.tap(find.widgetWithText(TextButton, l10n.save));
    await tester.pumpAndSettle();
    expect(_banner(l10n.emptyTip(l10n.content)), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(find.byType(TextFormField), 'example.com');
    await tester.pumpAndSettle();
    expect(find.byType(ErrorBanner), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, l10n.save));
    await tester.pumpAndSettle();

    expect(find.byType(RuleForm), findsNothing);
    expect(result, isNotNull);
    expect(result!.ruleAction, RuleAction.DOMAIN);
    expect(result!.content, 'example.com');
    expect(result!.ruleTarget, isNotEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('every built-in target is a valid rule target', (tester) async {
    for (final target in RuleTarget.baseTargetNames) {
      await tester.pumpWidget(
        TestApp(
          child: Surface(
            child: RuleItem(
              isSelected: false,
              rule: Rule(content: 'example.com', ruleTarget: target),
              onSelected: () {},
              onEdit: (_) {},
            ),
          ),
        ),
      );

      expect(find.text(target), findsOneWidget);
      expect(find.byType(IconButton), findsNothing, reason: target);
    }

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a rule without content centers its action', (tester) async {
    await tester.pumpWidget(
      TestApp(
        child: Surface(
          child: Center(
            child: SizedBox(
              width: 600,
              height: 64,
              child: RuleItem(
                isSelected: false,
                rule: const Rule(
                  ruleAction: RuleAction.MATCH,
                  ruleTarget: 'DIRECT',
                ),
                onSelected: () {},
                onEdit: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getCenter(find.text(RuleAction.MATCH.name)).dy,
      moreOrLessEquals(tester.getCenter(find.byType(RuleItem)).dy, epsilon: 1),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a long target yields width to the action on one line', (
    tester,
  ) async {
    await tester.pumpWidget(
      TestApp(
        child: Surface(
          child: Center(
            child: SizedBox(
              width: 480,
              height: 64,
              child: RuleItem(
                isSelected: false,
                rule: const Rule(
                  ruleAction: RuleAction.DOMAIN_KEYWORD,
                  content: 'example',
                  ruleTarget: 'Singapore-Auto-Select',
                ),
                onSelected: () {},
                onEdit: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final action = tester.renderObject<RenderParagraph>(
      find.text(RuleAction.DOMAIN_KEYWORD.value),
    );
    expect(action.didExceedMaxLines, isFalse);
    expect(action.size.height, action.getMinIntrinsicHeight(double.infinity));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a custom exit is named once and marked on the rule', (
    tester,
  ) async {
    Rule? result;
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(1200, 800)),
        ],
        child: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () async {
                result = await showFormSheet<Rule>(
                  context: context,
                  builder: (_) => const RuleForm(exits: ['Media']),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = currentAppLocalizations;

    await tester.enterText(find.byType(TextFormField), 'example.com');
    await tester.tap(find.text(l10n.splitStrategy));
    await tester.pumpAndSettle();
    expect(find.text('Media'), findsOneWidget);
    await tester.ensureVisible(find.text(l10n.customExit).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.customExit).last);
    await tester.pumpAndSettle();
    expect(find.byType(InputDialog), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text(l10n.inputExitName), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, l10n.save));
    await tester.pumpAndSettle();
    expect(_banner(l10n.emptyTip(l10n.name)), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(find.byType(TextFormField).last, 'DIRECT');
    await tester.tap(find.widgetWithText(TextButton, l10n.save));
    await tester.pumpAndSettle();
    expect(_banner(l10n.existsTip(l10n.name)), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(find.byType(TextFormField).last, ' AI ');
    await tester.tap(find.widgetWithText(TextButton, l10n.save));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.ruleTarget, 'AI');
    expect(result!.customExit, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('picking an existing exit hides the name row', (tester) async {
    Rule? result;
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(1200, 800)),
        ],
        child: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () async {
                result = await showFormSheet<Rule>(
                  context: context,
                  builder: (_) => const RuleForm(exits: ['Media']),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = currentAppLocalizations;

    await tester.enterText(find.byType(TextFormField), 'example.com');
    await tester.tap(find.text(l10n.splitStrategy));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(l10n.customExit).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.customExit).last);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));

    await tester.tap(find.text(l10n.splitStrategy));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Media').last);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, l10n.save));
    await tester.pumpAndSettle();
    expect(result?.ruleTarget, 'Media');
    expect(result?.customExit, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('edit rule keeps the id and order and prefills the fields', (
    tester,
  ) async {
    Rule? result;
    const rule = Rule(
      id: 42,
      ruleAction: RuleAction.GEOIP,
      content: 'CN',
      ruleTarget: 'GEOIP',
      noResolve: true,
      order: 'a5',
    );
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(1200, 800)),
        ],
        child: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () async {
                result = await showFormSheet<Rule>(
                  context: context,
                  builder: (_) => const RuleForm(rule: rule),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('CN'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'US');
    await tester.tap(
      find.widgetWithText(TextButton, currentAppLocalizations.save),
    );
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.id, 42);
    expect(result!.order, 'a5');
    expect(result!.content, 'US');
    expect(result!.ruleAction, RuleAction.GEOIP);
    expect(result!.noResolve, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a payload the core would refuse is held at the field', (
    tester,
  ) async {
    Rule? result;
    const rule = Rule(
      id: 7,
      ruleAction: RuleAction.DST_PORT,
      content: '443',
      ruleTarget: 'DIRECT',
    );
    await tester.pumpWidget(
      TestApp(
        wrapInProviderScope: true,
        overrides: [
          viewSizeProvider.overrideWithBuild((_, _) => const Size(1200, 800)),
        ],
        child: Builder(
          builder: (context) {
            return FilledButton(
              onPressed: () async {
                result = await showFormSheet<Rule>(
                  context: context,
                  builder: (_) => const RuleForm(rule: rule),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = currentAppLocalizations;

    await tester.enterText(find.byType(TextFormField), 'https');
    await tester.tap(find.widgetWithText(TextButton, l10n.save));
    await tester.pumpAndSettle();
    expect(_banner(l10n.invalidRangeContent), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(find.byType(TextFormField), '80/443');
    await tester.tap(find.widgetWithText(TextButton, l10n.save));
    await tester.pumpAndSettle();
    expect(result?.content, '80/443');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
