import 'dart:math' as math;

import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RequestsSplit extends ConsumerStatefulWidget {
  static const handleWidth = 10.0;
  static const minListWidth = 320.0;
  static const defaultListWidth = 392.0;

  final Widget list;
  final Widget detail;
  final double _minListWidth;
  final double? _minDetailWidth;
  final double _defaultListWidth;

  const RequestsSplit({
    super.key,
    required this.list,
    required this.detail,
    double minListWidth = RequestsSplit.minListWidth,
    double? minDetailWidth,
    double? defaultListWidth,
  }) : _minListWidth = minListWidth,
       _minDetailWidth = minDetailWidth,
       _defaultListWidth = defaultListWidth ?? RequestsSplit.defaultListWidth;

  @override
  ConsumerState<RequestsSplit> createState() => _RequestsSplitState();
}

class _RequestsSplitState extends ConsumerState<RequestsSplit> {
  late double _width;
  late final FocusNode _handleFocusNode;
  var _dragging = false;
  var _dragChanged = false;
  var _effectiveWidth = RequestsSplit.defaultListWidth;
  var _minWidth = 0.0;
  var _maxWidth = double.infinity;

  @override
  void initState() {
    super.initState();
    _width = _safeWidth(
      ref.read(appSettingProvider).requestsListWidth,
      _safeDefaultWidth(),
    );
    _handleFocusNode = FocusNode(debugLabel: 'RequestsSplitHandle');
    ref.listenManual(
      appSettingProvider.select((state) => state.requestsListWidth),
      (_, value) {
        if (_dragging) {
          return;
        }
        final width = _safeWidth(value, _safeDefaultWidth());
        if (width != _width && mounted) {
          setState(() => _width = width);
        }
      },
    );
  }

  @override
  void dispose() {
    _handleFocusNode.dispose();
    super.dispose();
  }

  double _safeDefaultWidth() {
    final width = widget._defaultListWidth;
    return width.isFinite && width > 0 ? width : RequestsSplit.defaultListWidth;
  }

  static double _safeWidth(double width, double fallback) {
    return width.isFinite && width > 0 ? width : fallback;
  }

  ({double handle, double min, double max, double detail}) _layoutFor(
    double maxWidth,
  ) {
    final handle = math.min(RequestsSplit.handleWidth, maxWidth);
    final available = math.max(0.0, maxWidth - handle);
    final detail = widget._minDetailWidth;
    final safeDetail = detail != null && detail.isFinite && detail > 0
        ? detail
        : 0.0;
    final max = math.max(0.0, available - safeDetail);
    final min = math.min(
      widget._minListWidth.isFinite && widget._minListWidth > 0
          ? widget._minListWidth
          : RequestsSplit.minListWidth,
      max,
    );
    return (handle: handle, min: min, max: max, detail: safeDetail);
  }

  double _clampWidth(double width) =>
      width.clamp(_minWidth, _maxWidth).toDouble();

  void _startDrag() {
    _dragging = true;
    _dragChanged = false;
    _effectiveWidth = _clampWidth(_effectiveWidth);
    _handleFocusNode.requestFocus();
  }

  void _drag(double delta) {
    final direction = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;
    final width = _clampWidth(_effectiveWidth + delta * direction);
    if (width == _effectiveWidth) {
      return;
    }
    _dragChanged = true;
    setState(() {
      _effectiveWidth = width;
      _width = width;
    });
  }

  void _endDrag() {
    if (!_dragging) {
      return;
    }
    _dragging = false;
    if (_dragChanged) {
      _saveWidth();
    }
  }

  bool _keyResize(double delta) {
    final direction = Directionality.of(context) == TextDirection.rtl
        ? -1.0
        : 1.0;
    final width = _clampWidth(_effectiveWidth + delta * direction);
    if (width != _effectiveWidth) {
      setState(() {
        _effectiveWidth = width;
        _width = width;
      });
      _saveWidth();
    }
    return true;
  }

  void _resetWidth() {
    final width = _clampWidth(_safeDefaultWidth());
    setState(() {
      _effectiveWidth = width;
      _width = width;
    });
    _saveWidth();
  }

  void _saveWidth() {
    final width = _safeWidth(_width, _safeDefaultWidth());
    _width = width;
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(requestsListWidth: width));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _safeDefaultWidth() + RequestsSplit.handleWidth;
        final layout = _layoutFor(maxWidth);
        _minWidth = layout.min;
        _maxWidth = layout.max;
        final width = _clampWidth(_width);
        _effectiveWidth = width;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: width, child: widget.list),
            SizedBox(
              width: layout.handle,
              child: _RequestsSplitHandle(
                focusNode: _handleFocusNode,
                onDragStart: _startDrag,
                onDrag: _drag,
                onDragEnd: _endDrag,
                onKeyResize: _keyResize,
                onReset: _resetWidth,
              ),
            ),
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: math.min(
                    layout.detail,
                    math.max(0.0, maxWidth - width - layout.handle),
                  ),
                ),
                child: widget.detail,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RequestsSplitHandle extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDrag;
  final VoidCallback onDragEnd;
  final ValueChanged<double> onKeyResize;
  final VoidCallback onReset;

  const _RequestsSplitHandle({
    required this.focusNode,
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onKeyResize,
    required this.onReset,
  });

  @override
  State<_RequestsSplitHandle> createState() => _RequestsSplitHandleState();
}

class _RequestsSplitHandleState extends State<_RequestsSplitHandle> {
  static const _keyboardStep = 16.0;

  var _hovered = false;
  var _dragging = false;
  var _focused = false;

  void _startDrag() {
    if (_dragging) {
      return;
    }
    setState(() => _dragging = true);
    widget.focusNode.requestFocus();
    widget.onDragStart();
  }

  void _endDrag() {
    if (!_dragging) {
      return;
    }
    setState(() => _dragging = false);
    widget.onDragEnd();
  }

  KeyEventResult _onKeyEvent(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -_keyboardStep,
      LogicalKeyboardKey.arrowRight => _keyboardStep,
      _ => null,
    };
    if (delta == null) {
      return KeyEventResult.ignored;
    }
    widget.onKeyResize(delta);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _dragging || _focused;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => widget.focusNode.requestFocus(),
        onHorizontalDragStart: (_) => _startDrag(),
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        onDoubleTap: widget.onReset,
        child: Focus(
          focusNode: widget.focusNode,
          onFocusChange: (focused) => setState(() => _focused = focused),
          onKeyEvent: _onKeyEvent,
          child: Center(
            child: SizedBox(
              width: active ? 2 : 1,
              height: double.infinity,
              child: ColoredBox(
                color: active
                    ? context.colorScheme.primary
                    : Divider.colorOf(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
