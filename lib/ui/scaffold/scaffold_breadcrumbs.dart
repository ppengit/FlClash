part of 'scaffold.dart';

class _BreadcrumbTitle extends StatefulWidget {
  const _BreadcrumbTitle({
    required this.ancestors,
    required this.current,
    required this.child,
  });

  final List<PageTrailEntry> ancestors;
  final PageTrailEntry current;
  final Widget child;

  @override
  State<_BreadcrumbTitle> createState() => _BreadcrumbTitleState();
}

class _BreadcrumbTitleState extends State<_BreadcrumbTitle> {
  var _returning = false;

  Future<void> _returnTo(PageTrailEntry target) async {
    final navigator = target.route.navigator;
    if (_returning ||
        navigator == null ||
        !target.context.mounted ||
        !target.route.isActive) {
      return;
    }
    setState(() => _returning = true);
    try {
      for (final entry in [widget.current, ...widget.ancestors.reversed]) {
        if (identical(entry.route, target.route)) {
          return;
        }
        if (!mounted || !target.route.isActive || !navigator.mounted) {
          return;
        }
        if (!entry.route.isCurrent ||
            !identical(entry.route.navigator, navigator)) {
          return;
        }
        while (entry.route.isCurrent) {
          if (!await PopGuard.maybePop(navigator, entry.route)) {
            return;
          }
        }
      }
    } finally {
      if (mounted) {
        setState(() => _returning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = context.colorScheme.onSurfaceVariant;
    return ListenableBuilder(
      listenable: Listenable.merge([
        for (final entry in widget.ancestors) entry.title,
      ]),
      builder: (context, _) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in widget.ancestors) ...[
              Semantics(
                link: true,
                child: PressRegion(
                  onTap: _returning ? null : () => _returnTo(entry),
                  shape: AppShape.sm,
                  mouseCursor: SystemMouseCursors.click,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Text(
                      entry.title.value,
                      style: AppTextStyle.headline
                          .of(context)
                          .copyWith(color: color),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GlyphIcon(Glyphs.chevronForward, size: 14, color: color),
              ),
            ],
            widget.child,
          ],
        ),
      ),
    );
  }
}
