library;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/clash_config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'form_page.dart';
import 'form_row.dart';
import 'selection_sheet.dart';

const _ruleRowVerticalPadding = 7.0;

/// Rule lists run to thousands of rows, so a rule row is padded tighter than
/// other list rows.
double get ruleItemHeight =>
    globalState.measure.listTitleHeight() +
    globalState.measure.listSubtitleHeight() +
    2 * _ruleRowVerticalPadding;

class RuleItem extends StatelessWidget {
  static const _targetMaxWidthFactor = 0.5;
  static const _targetMinWidthFactor = 0.3;
  static const _labelTargetGap = 16.0;

  final bool isSelected;
  final bool isEditing;
  final Rule rule;

  /// Without it the row has no selection checkbox.
  final void Function()? onSelected;
  final void Function(Rule rule)? onEdit;
  final String? Function(Rule rule)? invalidMessageOf;

  const RuleItem({
    super.key,
    this.isSelected = false,
    required this.rule,
    this.onSelected,
    this.onEdit,
    this.invalidMessageOf,
    this.isEditing = false,
  });

  ({bool invalid, Color? color, String? message}) _checkInvalid(
    BuildContext context,
  ) {
    final message = invalidMessageOf?.call(rule);
    if (rule.customExit) {
      return (
        invalid: false,
        color: context.colorScheme.tertiary,
        message: null,
      );
    }
    if (message == null && rule.ruleAction != RuleAction.SUB_RULE) {
      final ruleTarget = (rule.ruleTarget ?? '').toUpperCase();
      final color = switch (ruleTarget) {
        'DIRECT' || 'COMPATIBLE' => context.colorScheme.success,
        'REJECT' || 'REJECT-DROP' => context.colorScheme.warning,
        'PASS' || 'PASS-RULE' || 'GLOBAL' => context.colorScheme.tertiary,
        _ => null,
      };
      if (color != null) {
        return (invalid: false, color: color, message: null);
      }
    }
    final invalid = invalidMessageOf == null || message != null;
    return (
      invalid: invalid,
      color: invalid ? context.colorScheme.error : context.colorScheme.tertiary,
      message: message,
    );
  }

  Widget _buildInfoWidget(BuildContext context, String? message) {
    return MinIconButtonTheme(
      child: IconButton(
        tooltip: context.appLocalizations.tip,
        onPressed: () {
          dialogs.showAlert(
            message: TextSpan(
              text:
                  message ??
                  rule.targetErrorTip(
                    context.appLocalizations.invalidSubRule(rule.subRule ?? ''),
                    context.appLocalizations.invalidPolicy(
                      rule.ruleTarget ?? '',
                    ),
                  ),
            ),
          );
        },
        icon: GlyphIcon(
          AppGlyphs.info,
          fill: 1,
          size: 16.ap(context),
          color: context.colorScheme.error,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checkResult = _checkInvalid(context);
    final invalid = checkResult.invalid;
    final title = Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelStyle = DefaultTextStyle.of(context).style.toJetBrainsMono;
          final actionWidth = globalState.measure
              .computeTextSize(Text(rule.ruleAction.value, style: labelStyle))
              .width;
          final maxWidth = constraints.maxWidth;
          final targetMaxWidth = (maxWidth - _labelTargetGap - actionWidth)
              .clamp(
                maxWidth * _targetMinWidthFactor,
                maxWidth * _targetMaxWidthFactor,
              );
          return Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _RuleItemLabel(rule: rule, style: labelStyle),
              ),
              const SizedBox(width: _labelTargetGap),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: targetMaxWidth),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (invalid) _buildInfoWidget(context, checkResult.message),
                    if (rule.realTarget != null)
                      Flexible(
                        child: TooltipText(
                          text: Text(
                            rule.realTarget!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.subheadline
                                .of(context)
                                .toJetBrainsMono
                                .copyWith(color: checkResult.color),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
    final onSelected = this.onSelected;
    final onEdit = this.onEdit;
    if (onSelected == null) {
      return DecorationListItem(
        minVerticalPadding: 0,
        horizontalTitleGap: 0,
        invalid: invalid,
        title: title,
        onPressed: onEdit == null ? null : () => onEdit(rule),
      );
    }
    return SelectedDecorationListItem(
      minVerticalPadding: 0,
      isSelected: isSelected,
      isEditing: isEditing,
      horizontalTitleGap: 0,
      invalid: invalid,
      onSelected: () {
        onSelected();
      },
      title: title,
      onPressed: () {
        onEdit?.call(rule);
      },
    );
  }
}

class _RuleItemLabel extends StatelessWidget {
  const _RuleItemLabel({required this.rule, required this.style});

  final Rule rule;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final content = rule.realContent ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rule.ruleAction.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
        if (content.isNotEmpty)
          Flexible(
            child: TooltipText(
              text: Text(
                content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.listSubtitleStyle.toJetBrainsMono.copyWith(
                  color: style.color?.opacity60,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class RuleStatusItem extends StatelessWidget {
  final bool status;
  final Rule rule;
  final void Function(bool) onChange;

  const RuleStatusItem({
    super.key,
    required this.status,
    required this.rule,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    return DecorationListItem(
      title: TooltipText(
        text: Text(
          rule.rawValue,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.subheadline.of(context).toJetBrainsMono,
        ),
      ),
      trailing: Switch(value: status, onChanged: onChange),
      onPressed: () {
        onChange(!status);
      },
    );
  }
}

enum _RuleField { content, target, exit }

typedef _Target = ({String name, bool exit});

const _Target _newExit = (name: '', exit: true);

class RuleForm extends StatefulWidget {
  final Rule? rule;

  /// The custom exits other added rules already go to.
  final Iterable<String> exits;
  final Widget? scope;
  final Map<RuleAction, String> suggestedContents;
  final Iterable<String>? targets;

  const RuleForm({
    super.key,
    this.rule,
    this.exits = const [],
    this.scope,
    this.suggestedContents = const {},
    this.targets,
  });

  @override
  State<RuleForm> createState() => _RuleFormState();
}

class _RuleFormState extends State<RuleForm> {
  late RuleAction _ruleAction;
  late _Target _target;
  late final TextEditingController _contentController;
  late final Map<RuleAction, String> _contents;
  final _exitController = TextEditingController();
  late bool _noResolve;
  late bool _src;
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _contents = Map.of(widget.suggestedContents);
    _ruleAction =
        rule?.ruleAction ??
        _contents.keys.firstOrNull ??
        RuleAction.addedRuleActions.first;
    _target = (
      name:
          rule?.ruleTarget ??
          widget.targets?.firstOrNull ??
          RuleTarget.ruleTargetNames.first,
      exit: rule?.customExit ?? false,
    );
    _contentController = TextEditingController(
      text: rule?.content ?? _contents[_ruleAction],
    );
    _noResolve = rule?.noResolve ?? false;
    _src = rule?.src ?? false;
  }

  @override
  void dispose() {
    _contentController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  ({_RuleField field, String message})? _issue() {
    final appLocalizations = context.appLocalizations;
    final content = _contentController.text;
    if (content.isEmpty) {
      return (
        field: _RuleField.content,
        message: appLocalizations.emptyTip(appLocalizations.content),
      );
    }
    final payloadError = Rule(
      ruleAction: _ruleAction,
      content: content,
    ).payloadError;
    if (payloadError != null) {
      return (
        field: _RuleField.content,
        message: payloadError.getMessage(context),
      );
    }
    if (_target == _newExit) {
      final name = _exitController.text.trim();
      if (name.isEmpty) {
        return (
          field: _RuleField.exit,
          message: appLocalizations.emptyTip(appLocalizations.name),
        );
      }
      if (RuleTarget.ruleTargets.contains(name)) {
        return (
          field: _RuleField.exit,
          message: appLocalizations.existsTip(appLocalizations.name),
        );
      }
    } else if (_target.name.isEmpty) {
      return (
        field: _RuleField.target,
        message: appLocalizations.splitStrategyNotEmpty,
      );
    }
    return null;
  }

  void _handleSubmit() {
    if (_issue() != null) {
      setState(() {
        _attempted = true;
      });
      return;
    }
    final target = _target == _newExit
        ? (name: _exitController.text.trim(), exit: true)
        : _target;
    Navigator.of(context).pop(
      (widget.rule ?? Rule(id: snowflake.id)).copyWith(
        ruleAction: _ruleAction,
        content: _contentController.text,
        ruleTarget: target.name,
        customExit: target.exit,
        noResolve: _noResolve,
        src: _src,
      ),
    );
  }

  String _targetLabel(_Target target) =>
      target == _newExit ? context.appLocalizations.customExit : target.name;

  void _handleTarget(_Target target) {
    setState(() {
      _target = target;
    });
  }

  Future<void> _pickTarget(List<_Target> targets) async {
    final selected = await showNestedSheet<_Target>(
      context,
      builder: (context) => SelectionSheet<_Target>(
        title: context.appLocalizations.splitStrategy,
        sections: [SelectionSection(items: targets)],
        labelBuilder: _targetLabel,
        selectedOf: (_) => _target,
        onSelected: (target) => Navigator.of(context).pop(target),
      ),
    );
    if (selected != null && mounted) {
      _handleTarget(selected);
    }
  }

  Widget _buildSwitchRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return FormRow(
      title: title,
      onPressed: () => onChanged(!value),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final issue = _attempted ? _issue() : null;
    final basic = [
      for (final name in widget.targets ?? RuleTarget.ruleTargetNames)
        (name: name, exit: false),
    ];
    final exits = [
      if (widget.targets == null)
        for (final name in {
          ...widget.exits,
          if (_target.exit && _target != _newExit) _target.name,
        })
          (name: name, exit: true),
    ];
    final targets = [...basic, ...exits, if (widget.targets == null) _newExit];
    return FormPage(
      title: widget.rule != null
          ? appLocalizations.editRule
          : appLocalizations.addRule,
      onSave: _handleSubmit,
      error: issue?.message,
      children: [
        generateSection(
          title: appLocalizations.basicInfo,
          items: [
            ?widget.scope,
            ListItem<RuleAction>.options(
              title: Text(appLocalizations.proxyType),
              options: RuleAction.addedRuleActions,
              value: _ruleAction,
              textBuilder: (action) => action.value,
              onChanged: (action) {
                setState(() {
                  if (widget.suggestedContents.isNotEmpty) {
                    final content = _contentController.text;
                    _contents[_ruleAction] = content;
                    _contentController.text = _contents[action] ?? content;
                  }
                  _ruleAction = action;
                });
              },
            ),
            FormRow(
              title: appLocalizations.content,
              invalid: issue?.field == _RuleField.content,
              trailing: FormRowTextField(
                controller: _contentController,
                hintText: appLocalizations.inputRuleContent,
                autocorrect: false,
                inputFormatters: TextInputLimits.limit(TextInputLimits.rule),
                onChanged: (_) {
                  if (_attempted) {
                    setState(() {});
                  }
                },
                onFieldSubmitted: (_) => _handleSubmit(),
              ),
            ),
            if (widget.targets != null)
              ListItem(
                title: Text(appLocalizations.splitStrategy),
                subtitle: Text(_targetLabel(_target)),
                trailing: const GlyphIcon(AppGlyphs.chevronForward),
                onTap: () => _pickTarget([
                  if (!targets.contains(_target)) _target,
                  ...targets,
                ]),
              )
            else
              ListItem<_Target>.options(
                title: Text(appLocalizations.splitStrategy),
                options: [if (!targets.contains(_target)) _target, ...targets],
                value: _target,
                textBuilder: _targetLabel,
                sectionStarts: {?exits.firstOrNull, _newExit},
                onChanged: _handleTarget,
              ),
            if (_target == _newExit)
              FormRow(
                title: appLocalizations.name,
                invalid: issue?.field == _RuleField.exit,
                trailing: FormRowTextField(
                  controller: _exitController,
                  hintText: appLocalizations.inputExitName,
                  autofocus: true,
                  autocorrect: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.singleLineFormatter,
                    FilteringTextInputFormatter.deny(','),
                    ...TextInputLimits.limit(TextInputLimits.name),
                  ],
                  onChanged: (_) {
                    if (_attempted) {
                      setState(() {});
                    }
                  },
                  onFieldSubmitted: (_) => _handleSubmit(),
                ),
              ),
          ],
        ),
        if (_ruleAction.hasParams)
          generateSection(
            title: appLocalizations.additionalParameters,
            items: [
              _buildSwitchRow(
                title: appLocalizations.noResolveHostname,
                value: _noResolve,
                onChanged: (value) {
                  setState(() {
                    _noResolve = value;
                  });
                },
              ),
              _buildSwitchRow(
                title: appLocalizations.matchSourceIp,
                value: _src,
                onChanged: (value) {
                  setState(() {
                    _src = value;
                  });
                },
              ),
            ],
          ),
      ],
    );
  }
}
