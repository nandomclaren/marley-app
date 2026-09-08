import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// A YNAB-style toast: rises from the bottom of the screen, shows a
/// category's "Disponível" going from its old to its new value, then
/// disappears on its own. Fire-and-forget — [show] inserts itself into the
/// app's root [Overlay] and removes itself when the sequence finishes, so
/// it survives the caller (typically a bottom sheet) closing.
class CategoryImpactPill {
  CategoryImpactPill._();

  static void show(
    BuildContext context, {
    required String category,
    required double before,
    required double after,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _PillView(
        category: category,
        before: before,
        after: after,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _PillView extends StatefulWidget {
  final String category;
  final double before;
  final double after;
  final VoidCallback onDone;

  const _PillView({
    required this.category,
    required this.before,
    required this.after,
    required this.onDone,
  });

  @override
  State<_PillView> createState() => _PillViewState();
}

class _PillViewState extends State<_PillView> with TickerProviderStateMixin {
  // Rise/fall the pill itself, and separately count the value from old to
  // new — each phase waits for the previous one to fully finish, matching
  // the mocked-up storyboard: rise -> hold old -> count -> hold new -> fall.
  static const _rise = Duration(milliseconds: 400);
  static const _holdOld = Duration(milliseconds: 300);
  static const _count = Duration(milliseconds: 550);
  static const _holdNew = Duration(milliseconds: 400);
  static const _fall = Duration(milliseconds: 350);

  late final AnimationController _slide;
  late final CurvedAnimation _slideCurve;
  late final AnimationController _countCtrl;
  late double _displayedValue;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _displayedValue = widget.before;
    _slide = AnimationController(vsync: this, duration: _rise, reverseDuration: _fall);
    _slideCurve = CurvedAnimation(
      parent: _slide,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _countCtrl = AnimationController(vsync: this, duration: _count)
      ..addListener(() {
        setState(() {
          _displayedValue = widget.before +
              (widget.after - widget.before) *
                  Curves.easeOut.transform(_countCtrl.value);
        });
      });
    _run();
  }

  Future<void> _run() async {
    await _slide.forward();
    if (_disposed) return;
    await Future.delayed(_holdOld);
    if (_disposed) return;
    await _countCtrl.forward();
    if (_disposed) return;
    await Future.delayed(_holdNew);
    if (_disposed) return;
    await _slide.reverse();
    if (_disposed) return;
    widget.onDone();
  }

  @override
  void dispose() {
    _disposed = true;
    _slide.dispose();
    _countCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final isDown = widget.after < widget.before - 0.005;
    final isUp = widget.after > widget.before + 0.005;
    final valueColor = isDown
        ? MarleyColors.red(brightness)
        : isUp
            ? MarleyColors.green(brightness)
            : scheme.onInverseSurface;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 78 + MediaQuery.of(context).padding.bottom,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _slideCurve,
          builder: (context, child) {
            final t = _slideCurve.value;
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 70),
                child: child,
              ),
            );
          },
          child: Material(
            color: scheme.inverseSurface,
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onInverseSurface.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        'Disponível',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onInverseSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        formatEur(_displayedValue),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: valueColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
