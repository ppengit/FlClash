import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show NumberFormat;

import 'connection_condition_form.dart';
import 'connection_conditions.dart';
import 'connection_connected_buttons.dart';
import 'connection_filters.dart';

final _grouped = NumberFormat.decimalPattern('en');

class ConditionFilterRow<T extends Object, S extends Enum>
    extends StatelessWidget {
  final ConditionFilterController<T, S> controller;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;
  final Widget? leadingFilters;

  const ConditionFilterRow({
    super.key,
    required this.controller,
    required this.searchController,
    required this.onSearch,
    this.leadingFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.listInsets.margin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: Listenable.merge([controller, controller.options]),
            child: SearchField(
              controller: searchController,
              onChanged: onSearch,
              height: math.max(
                TonalButtonSize.section.button,
                MediaQuery.textScalerOf(context).scale(AppTextStyle.body.size) *
                        AppTextStyle.body.leading /
                        AppTextStyle.body.size +
                    8,
              ),
              fill: context.raisedSurfaceLevel.colorOf(context.colorScheme),
            ),
            builder: (context, search) => LayoutBuilder(
              builder: (context, constraints) {
                final facetWidth = math.max(
                  0.0,
                  math.min(
                    constraints.maxWidth * .65,
                    constraints.maxWidth - 120 - 48 - 16,
                  ),
                );
                final options = controller.options.value;
                final groups = <Widget>[
                  ?leadingFilters,
                  for (final facet in controller.facets)
                    if (options[facet.kind]?.isNotEmpty ?? false)
                      ConnectedFilterButtons<String>(
                        values: options[facet.kind]!,
                        labelOf: facet.label,
                        isSelected: (value) =>
                            controller.isValueSelected(facet.kind, value),
                        onSelected: (value) =>
                            controller.toggleValue(facet.kind, value),
                      ),
                ];
                return Row(
                  spacing: 8,
                  children: [
                    Expanded(child: search!),
                    if (groups.isNotEmpty)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: facetWidth),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            spacing: 8,
                            children: groups,
                          ),
                        ),
                      ),
                    TonalButtonTheme(
                      size: TonalButtonSize.section,
                      child: AppBarActionButton(
                        data: IconButtonData(
                          glyph: AppGlyphs.add,
                          tooltip: context.appLocalizations.addCondition,
                          onPressed: () => showConditionDialog<T>(
                            context,
                            controller: controller,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => MemoBuilder(
              inputs: [controller, controller.conditions, controller.filters],
              builder: (context) => ConditionBlock.showsFor(controller)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ConditionBlock<T>(controller: controller),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

class ConditionStatusButtons<T extends Object, S extends Enum>
    extends StatelessWidget {
  const ConditionStatusButtons({
    super.key,
    required this.controller,
    this.maxWidth = 360,
  }) : assert(maxWidth > 0);

  final ConditionFilterController<T, S> controller;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.counted]),
      builder: (context, _) => ConnectedFilterButtons<S>(
        values: controller.statuses,
        maxWidth: maxWidth,
        labelOf: (status) =>
            '${controller.labelOf(status)}(${_grouped.format(controller.countOf(status))})',
        isSelected: (status) => status == controller.status,
        onSelected: (status) => controller.status = status,
        inMutuallyExclusiveGroup: true,
      ),
    );
  }
}
