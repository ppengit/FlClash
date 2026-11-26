import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/route_scope.dart';

class PageTrailEntry {
  const PageTrailEntry({
    required this.title,
    required this.route,
    required this.context,
  });

  final ValueListenable<String> title;
  final ModalRoute<Object?> route;
  final BuildContext context;
}

class PageTrailScope extends InheritedWidget {
  const PageTrailScope({
    super.key,
    required this.entries,
    required super.child,
  });

  final List<PageTrailEntry> entries;
  static final _titles = Expando<List<PageTrailEntry>>();

  static void register(PageTrailEntry entry) {
    final entries = _titles[entry.route] ??= [];
    if (!entries.contains(entry)) {
      entries.add(entry);
    }
  }

  static void unregister(PageTrailEntry entry) {
    final entries = _titles[entry.route];
    entries?.remove(entry);
    if (entries?.isEmpty == true) {
      _titles[entry.route] = null;
    }
  }

  static PageTrailEntry? _sourceOf(
    BuildContext context,
    List<PageTrailEntry> entries,
  ) {
    PageTrailEntry? nearest;
    int? distance;
    for (final entry in entries) {
      if (!entry.context.mounted) {
        continue;
      }
      var steps = 0;
      var found = identical(entry.context, context);
      if (!found) {
        entry.context.visitAncestorElements((element) {
          steps++;
          found = identical(element, context);
          return !found;
        });
      }
      if (found && (distance == null || steps < distance)) {
        nearest = entry;
        distance = steps;
      } else if (found && steps == distance) {
        nearest = null;
      }
    }
    return nearest ??
        (distance == null &&
                entries.length == 1 &&
                entries.single.context.mounted
            ? entries.single
            : null);
  }

  static List<PageTrailEntry> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageTrailScope>()?.entries ??
      const [];

  static List<PageTrailEntry> capture(BuildContext context) {
    final navigator = Navigator.of(context);
    final route = routeOf(context);
    final entries = of(context);
    PageTrailEntry? current;
    for (final entry in entries) {
      if (identical(entry.route, route)) {
        current = entry;
      }
    }
    // A page's State.context can stand above the scope its scaffold builds.
    current ??= route == null
        ? null
        : _sourceOf(context, _titles[route] ?? const []);
    return [
      for (final entry in entries)
        if (entry.context.mounted &&
            entry.route.isActive &&
            identical(entry.route.navigator, navigator) &&
            !identical(entry.route, route))
          entry,
      if (current != null && current.context.mounted && current.route.isActive)
        current,
    ];
  }

  @override
  bool updateShouldNotify(PageTrailScope oldWidget) =>
      !listEquals(entries, oldWidget.entries);
}
