import 'package:fl_clash/ui/ui.dart';
import 'package:flutter/widgets.dart';

class ConnectedFilterButtons<T extends Object> extends StatelessWidget {
  const ConnectedFilterButtons({
    super.key,
    required this.values,
    required this.labelOf,
    required this.isSelected,
    required this.onSelected,
    this.inMutuallyExclusiveGroup = false,
    this.maxWidth = double.infinity,
    this.childBuilder,
  }) : assert(maxWidth > 0);

  final List<T> values;
  final String Function(T value) labelOf;
  final bool Function(T value) isSelected;
  final ValueChanged<T> onSelected;
  final bool inMutuallyExclusiveGroup;
  final double maxWidth;
  final Widget Function(T value, bool selected)? childBuilder;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return const SizedBox.shrink();
    }
    final colorScheme = context.colorScheme;
    final direction = Directionality.of(context);
    final fill = context.raisedSurfaceLevel.colorOf(colorScheme);
    final style = AppTextStyle.subheadline.of(context).toTabular;
    final separatorWidth = 1 / MediaQuery.devicePixelRatioOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DecoratedBox(
          decoration: ShapeDecoration(color: fill, shape: AppShape.sm),
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, value) in values.indexed) ...[
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: ColoredBox(
                        color: Divider.colorOf(context),
                        child: SizedBox(width: separatorWidth),
                      ),
                    ),
                  Builder(
                    builder: (context) {
                      final selected = isSelected(value);
                      final label = labelOf(value);
                      final shape = AppShape.of(
                        BorderRadiusDirectional.horizontal(
                          start: Radius.circular(
                            index == 0 ? AppCorner.sm : AppCorner.none,
                          ),
                          end: Radius.circular(
                            index == values.length - 1
                                ? AppCorner.sm
                                : AppCorner.none,
                          ),
                        ).resolve(direction),
                      );
                      return MergeSemantics(
                        child: Semantics(
                          label: label,
                          selected: selected,
                          inMutuallyExclusiveGroup: inMutuallyExclusiveGroup,
                          child: Tooltip(
                            message: label,
                            excludeFromSemantics: true,
                            child: PressSurface(
                              fill: selected ? colorScheme.primary : fill,
                              foreground: selected
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurfaceVariant,
                              textStyle: style,
                              iconSize: 20,
                              shape: shape,
                              selected: selected,
                              minimum: BoxConstraints(
                                minWidth: TonalButtonSize.section.button,
                                minHeight: TonalButtonSize.section.button,
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: childBuilder == null ? 12 : 8,
                                vertical: 8,
                              ),
                              onPressed: () => onSelected(value),
                              child: ExcludeSemantics(
                                child: Center(
                                  widthFactor: 1,
                                  heightFactor: 1,
                                  child:
                                      childBuilder?.call(value, selected) ??
                                      Text(label, maxLines: 1, softWrap: false),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
