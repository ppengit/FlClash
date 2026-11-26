import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../form/form_row.dart';
import '../form/rule.dart';

Map<RuleAction, String> trackerRuleContents(Metadata metadata) {
  final host = metadata.host.trim();
  final hostAddress = InternetAddress.tryParse(host);
  final address =
      hostAddress ?? InternetAddress.tryParse(metadata.destinationIP.trim());
  final path = metadata.processPath.trim();
  final process = metadata.process.trim().takeFirstValid([
    path.split(RegExp(r'[/\\]')).last,
  ]);
  return {
    if (host.isNotEmpty && hostAddress == null) ...{
      RuleAction.DOMAIN: host,
      RuleAction.DOMAIN_SUFFIX: host,
    },
    if (address != null)
      if (address.type == InternetAddressType.IPv4)
        RuleAction.IP_CIDR: '${address.address}/32'
      else
        RuleAction.IP_CIDR6: '${address.address}/128',
    if (process.isNotEmpty) RuleAction.PROCESS_NAME: process,
    if (path.isNotEmpty) RuleAction.PROCESS_PATH: path,
  };
}

enum _RuleScope { profile, global }

Future<void> showTrackerRuleForm(
  BuildContext context,
  WidgetRef ref,
  TrackerInfo trackerInfo,
) async {
  final appLocalizations = context.appLocalizations;
  final profile = ref.read(currentProfileProvider);
  if (profile == null) {
    dialogs.showBanner(appLocalizations.requestRuleSelectProfile);
    return;
  }
  final custom = profile.type == ProfileType.custom;
  var scope = _RuleScope.profile;
  final rule = await showFormSheet<Rule>(
    context: context,
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final localRules = ref.watch(profileRulesProvider(profile.id)).value;
        final globalRules = custom
            ? const <Rule>[]
            : ref.watch(globalRulesProvider).value;
        final data = custom
            ? ref.watch(customProfileDataProvider(profile.id))
            : null;
        return RuleForm(
          suggestedContents: trackerRuleContents(trackerInfo.metadata),
          exits: customExitsOf([...?localRules, ...?globalRules]),
          targets: custom
              ? {
                  ...RuleTarget.ruleTargetNames,
                  ...?data?.proxyGroups.map((group) => group.name),
                  ...?data?.namedProxies,
                }.where((name) => !name.contains(','))
              : null,
          scope: custom
              ? FormRow(
                  title: appLocalizations.ruleScope,
                  trailing: Text(appLocalizations.ruleScopeProfile),
                )
              : StatefulBuilder(
                  builder: (context, setState) => ListItem<_RuleScope>.options(
                    title: Text(appLocalizations.ruleScope),
                    subtitle: Text(appLocalizations.advancedAddedRulesDesc),
                    options: _RuleScope.values,
                    value: scope,
                    textBuilder: (value) => switch (value) {
                      _RuleScope.profile => appLocalizations.ruleScopeProfile,
                      _RuleScope.global => appLocalizations.ruleScopeGlobal,
                    },
                    onChanged: (value) => setState(() => scope = value),
                  ),
                ),
        );
      },
    ),
  );
  if (rule == null || !context.mounted) {
    return;
  }
  final destination = ref.read(profilesProvider).getProfile(profile.id);
  if (destination == null || destination.type != profile.type) {
    dialogs.showBanner(
      appLocalizations.requestRuleProfileUnavailable,
      level: BannerLevel.error,
    );
    return;
  }
  await globalState.safeRun(() {
    switch (scope) {
      case _RuleScope.profile:
        ref.read(profileRulesProvider(profile.id).notifier).put(rule);
        if (ref.read(currentProfileIdProvider) == profile.id) {
          ref
              .read(setupActionProvider.notifier)
              .applyProfileDebounce(silence: true);
        }
      case _RuleScope.global:
        ref.read(globalRulesProvider.notifier).put(rule);
    }
  });
}
