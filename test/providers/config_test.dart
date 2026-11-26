import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

import '../helpers/preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('AppSetting provider', () {
    test('default value is defaultAppSettingProps', () {
      final value = container.read(appSettingProvider);
      expect(value.onlyStatisticsProxy, false);
      expect(value.autoLaunch, false);
      expect(value.closeConnections, true);
      expect(value.tabAnimation, TabAnimation.fade);
    });

    test('can update state', () {
      container
          .read(appSettingProvider.notifier)
          .update((_) => const AppSettingProps(autoLaunch: true));
      final value = container.read(appSettingProvider);
      expect(value.autoLaunch, true);
    });
  });

  group('WindowSetting provider', () {
    test('default value has zero dimensions', () {
      final value = container.read(windowSettingProvider);
      expect(value.width, 0);
      expect(value.height, 0);
    });

    test('can update state', () {
      container
          .read(windowSettingProvider.notifier)
          .update((_) => const WindowProps(width: 1024, height: 768));
      final value = container.read(windowSettingProvider);
      expect(value.width, 1024);
      expect(value.height, 768);
    });
  });

  group('VpnSetting provider', () {
    test('default value has enable true', () {
      final value = container.read(vpnSettingProvider);
      expect(value.enable, true);
      expect(value.systemProxy, true);
    });

    test('can update state', () {
      container
          .read(vpnSettingProvider.notifier)
          .update((_) => const VpnProps(enable: false));
      expect(container.read(vpnSettingProvider).enable, false);
    });
  });

  group('NetworkSetting provider', () {
    test('default values', () {
      final value = container.read(networkSettingProvider);
      expect(value.systemProxy, true);
      expect(value.bypassDomain, defaultBypassDomain);
    });

    test('can update state', () {
      container
          .read(networkSettingProvider.notifier)
          .update((_) => const NetworkProps(systemProxy: false));
      expect(container.read(networkSettingProvider).systemProxy, false);
    });
  });

  group('ThemeSetting provider', () {
    test('default value is dark mode', () {
      final value = container.read(themeSettingProvider);
      expect(value.primaryColor, null);
    });

    test('can update state', () {
      container
          .read(themeSettingProvider.notifier)
          .update((_) => const ThemeProps(primaryColor: 0xFF123456));
      expect(container.read(themeSettingProvider).primaryColor, 0xFF123456);
    });
  });

  group('CurrentProfileId provider', () {
    test('default is null', () {
      expect(container.read(currentProfileIdProvider), null);
    });

    test('can set profile id', () {
      container.read(currentProfileIdProvider.notifier).update((_) => 42);
      expect(container.read(currentProfileIdProvider), 42);
    });
  });

  group('DavSetting provider', () {
    test('default is null', () {
      expect(container.read(davSettingProvider), null);
    });

    test('can update WebDAV settings', () {
      const davProps = DAVProps(
        uri: 'https://dav.example.com',
        user: 'user',
        password: 'secret',
      );

      container.read(davSettingProvider.notifier).update((_) => davProps);

      expect(container.read(davSettingProvider), davProps);
      expect(container.read(configProvider).davProps?.password, 'secret');
    });
  });

  group('ExcludeSSIDs provider', () {
    test('reorders with final insertion index semantics', () {
      container
          .read(excludeSSIDsProvider.notifier)
          .update((_) => ['Home', 'Office', 'Cafe', 'Hotel']);

      container.read(excludeSSIDsProvider.notifier).update((value) {
        return value.copyAndReorder(1, 3);
      });

      expect(container.read(excludeSSIDsProvider), [
        'Home',
        'Cafe',
        'Hotel',
        'Office',
      ]);
    });
  });

  group('HotKeyActions provider', () {
    test('default is empty list', () {
      expect(container.read(hotKeyActionsProvider), isEmpty);
    });

    test('can update hotkey actions', () {
      const actions = [
        HotKeyAction(
          action: HotAction.start,
          key: 1,
          modifiers: {KeyboardModifier.control},
        ),
      ];

      container.read(hotKeyActionsProvider.notifier).update((_) => actions);

      expect(container.read(hotKeyActionsProvider), actions);
    });
  });

  group('ProxiesStyleSetting provider', () {
    test('default values', () {
      final value = container.read(proxiesStyleSettingProvider);
      expect(value.type, ProxiesType.list);
      expect(value.hideTimeoutProxies, isFalse);
      expect(value.hideErrorProxies, isFalse);
    });

    test(
      'display and filter options persist globally across profile switches',
      () async {
        await mockPreferences();
        container.listen(configProvider, (_, _) {});
        const style = ProxiesStyleProps(
          type: ProxiesType.tab,
          sortType: ProxiesSortType.name,
          layout: ProxiesLayout.loose,
          iconStyle: ProxiesIconStyle.hidden,
          cardType: ProxyCardType.compact,
          hideTimeoutProxies: true,
          hideErrorProxies: true,
        );
        container.read(proxiesStyleSettingProvider.notifier).value = style;
        for (final profileId in [11, 22, null, 11]) {
          container.read(currentProfileIdProvider.notifier).value = profileId;
          expect(container.read(proxiesStyleSettingProvider), style);
          expect(container.read(configProvider).proxiesStyleProps, style);
        }

        expect(
          await preferences.saveConfig(container.read(configProvider)),
          isTrue,
        );
        final restored = await preferences.getConfig();
        expect(restored?.proxiesStyleProps, style);
        final reloaded = ProviderContainer(
          overrides: buildConfigOverrides(restored!),
        );
        addTearDown(reloaded.dispose);
        reloaded.listen(configProvider, (_, _) {});
        for (final profileId in [22, null, 11]) {
          reloaded.read(currentProfileIdProvider.notifier).value = profileId;
          expect(reloaded.read(proxiesStyleSettingProvider), style);
          expect(reloaded.read(configProvider).proxiesStyleProps, style);
        }
      },
    );

    test('can update state', () {
      container
          .read(proxiesStyleSettingProvider.notifier)
          .update(
            (_) => const ProxiesStyleProps(sortType: ProxiesSortType.delay),
          );
      expect(
        container.read(proxiesStyleSettingProvider).sortType,
        ProxiesSortType.delay,
      );
    });
  });

  group('configProvider (composite)', () {
    test('composes all sub-providers with defaults', () {
      final config = container.read(configProvider);
      expect(config.appSettingProps.onlyStatisticsProxy, false);
      expect(config.windowProps.width, 0);
      expect(config.vpnProps.enable, true);
      expect(config.networkProps.systemProxy, true);
      expect(config.currentProfileId, null);
      expect(config.hotKeyActions, isEmpty);
      expect(config.patchClashConfig, const PatchClashConfig());
      expect(config.excludeSSIDs, isEmpty);
    });

    test('reflects updated sub-provider values', () {
      container.read(currentProfileIdProvider.notifier).update((_) => 99);
      container
          .read(patchClashConfigProvider.notifier)
          .update((_) => const PatchClashConfig(mixedPort: 7890));
      container
          .read(excludeSSIDsProvider.notifier)
          .update((_) => ['Office Wi-Fi']);

      final config = container.read(configProvider);
      expect(config.currentProfileId, 99);
      expect(config.patchClashConfig.mixedPort, 7890);
      expect(config.excludeSSIDs, ['Office Wi-Fi']);
    });
  });

  group('PatchClashConfig provider', () {
    test('keeps its mixed port over a 0 and takes the rest', () {
      final notifier = container.read(patchClashConfigProvider.notifier);
      notifier.update((state) => state.copyWith(mixedPort: 7899));

      notifier.update((state) => state.copyWith(mixedPort: 0, allowLan: true));
      notifier.value = notifier.value.copyWith(mixedPort: 0, ipv6: true);

      final config = container.read(patchClashConfigProvider);
      expect(config.mixedPort, 7899);
      expect(config.allowLan, isTrue);
      expect(config.ipv6, isTrue);
    });
  });

  group('writeConfig', () {
    test('never leaves a restored open controller without a secret', () {
      final ref = container.read(Provider<Ref>((ref) => ref));

      writeConfig(
        ref,
        const Config(
          themeProps: ThemeProps(),
          patchClashConfig: PatchClashConfig(
            externalController: ExternalControllerStatus.open,
          ),
        ),
      );

      expect(container.read(patchClashConfigProvider).secret, hasLength(32));
    });
  });

  group('buildConfigOverrides', () {
    test('produces correct overrides', () {
      const config = Config(themeProps: ThemeProps(), currentProfileId: 7);
      final overrides = buildConfigOverrides(config);
      expect(overrides.length, 11);

      final overrideContainer = ProviderContainer(overrides: overrides);
      addTearDown(overrideContainer.dispose);

      expect(overrideContainer.read(currentProfileIdProvider), 7);
      expect(
        overrideContainer.read(patchClashConfigProvider),
        config.patchClashConfig,
      );
      expect(overrideContainer.read(excludeSSIDsProvider), config.excludeSSIDs);
      expect(
        overrideContainer.read(appSettingProvider).onlyStatisticsProxy,
        false,
      );
    });
  });
}
