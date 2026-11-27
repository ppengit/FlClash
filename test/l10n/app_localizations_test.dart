import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('load resolves accessors for every supported locale', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final appLocalizations = loadAppLocalizations(locale);

      expect(currentAppLocalizations.localeName, appLocalizations.localeName);
      expect(appLocalizations.dashboard, isNotEmpty);
      expect(appLocalizations.proxies, isNotEmpty);
      expect(appLocalizations.settings, isNotEmpty);
      expect(appLocalizations.secondsCount(30), contains('30'));
      expect(appLocalizations.geoUpdated('geoip'), contains('geoip'));
    }
  });

  test('Chinese management actions use subscription terminology', () {
    final appLocalizations = lookupAppLocalizations(const Locale('zh'));

    expect(appLocalizations.profiles, '订阅');
    expect(appLocalizations.profilesSort, '订阅排序');
    expect(appLocalizations.addProfile, '添加订阅');
    expect(appLocalizations.switchProfile, '切换订阅');
    expect(appLocalizations.actionUpdateProfiles, '更新全部订阅');
    expect(appLocalizations.profileUrlNullValidationDesc, '请输入订阅链接');
    expect(appLocalizations.profileUrlInvalidValidationDesc, '请输入有效的订阅链接');
    expect(
      appLocalizations.createProfileFromUrlTip('https://example.com/sub'),
      '是否要添加订阅 https://example.com/sub？',
    );
    expect(appLocalizations.invalidProfileQrcode, '该二维码不包含订阅或代理分享链接');
  });

  test(
    'Chinese file, custom and rule scopes stay distinct from subscriptions',
    () {
      final appLocalizations = lookupAppLocalizations(const Locale('zh', 'CN'));

      expect(appLocalizations.profile, '配置文件');
      expect(appLocalizations.customProfile, '自定义配置');
      expect(appLocalizations.runtimeConfig, '运行时配置');
      expect(appLocalizations.ruleScopeProfile, '当前配置');
      expect(appLocalizations.ruleScopeGlobal, '所有配置');
      expect(appLocalizations.nullProfileDesc, '添加订阅、导入配置文件或创建自定义配置后即可开始使用');
    },
  );

  test('delegate recognizes only supported locales', () {
    expect(AppLocalizations.delegate.isSupported(const Locale('en')), isTrue);
    expect(AppLocalizations.delegate.isSupported(const Locale('de')), isFalse);
    expect(
      AppLocalizations.delegate.shouldReload(AppLocalizations.delegate),
      isFalse,
    );
  });
}
