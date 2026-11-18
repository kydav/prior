import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The map screen's tour: search, Find water, Saved, Profile.
const kSearchTour = 'search_v1';

/// One step of a spotlight tour: the widget under [target] is lit up and
/// the rest of the screen dims, with a card explaining it.
class CoachMark {
  const CoachMark({
    required this.target,
    required this.title,
    required this.body,
    this.icon,
  });

  final GlobalKey target;
  final String title;
  final String body;
  final IconData? icon;
}

/// Spotlight tours, each shown once per install unless replayed.
class CoachMarks {
  CoachMarks._();

  static String _key(String id) => 'coach_marks_seen_$id';

  /// Shows [steps] unless the tour [id] was already seen.
  static Future<void> showOnce(
    BuildContext context,
    String id,
    List<CoachMark> steps,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_key(id)) ?? false) return;
    if (!context.mounted) return;
    await show(context, steps);
    await prefs.setBool(_key(id), true);
  }

  /// Lets a tour show again (from Profile).
  static Future<void> reset(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(id));
  }

  /// Shows [steps] now. Completes when the tour is finished or skipped.
  /// Steps whose target isn't on screen are skipped.
  static Future<void> show(BuildContext context, List<CoachMark> steps) {
    final visible = steps
        .where((s) => s.target.currentContext?.findRenderObject() is RenderBox)
        .toList();
    if (visible.isEmpty) return Future.value();
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, _, _) => _Tour(steps: visible),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }
}

class _Tour extends StatefulWidget {
  const _Tour({required this.steps});

  final List<CoachMark> steps;

  @override
  State<_Tour> createState() => _TourState();
}

class _TourState extends State<_Tour> {
  int _i = 0;

  bool get _last => _i == widget.steps.length - 1;

  void _next() {
    if (_last) {
      Navigator.of(context).pop();
    } else {
      setState(() => _i++);
    }
  }

  Rect? _targetRect() {
    final box =
        widget.steps[_i].target.currentContext?.findRenderObject()
            as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return (origin & box.size).inflate(6);
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_i];
    final rect = _targetRect();
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    // Card goes on whichever side of the target has more room.
    final below = rect == null || rect.center.dy < size.height / 2;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _next,
              child: TweenAnimationBuilder<Rect?>(
                tween: RectTween(end: rect),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                builder: (_, r, _) =>
                    CustomPaint(painter: _SpotlightPainter(r)),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            left: 16,
            right: 16,
            top: below ? (rect?.bottom ?? size.height * .3) + 16 : null,
            bottom: below ? null : size.height - rect.top + 16,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: size.height - pad.vertical - 32,
              ),
              child: _Card(
                step: step,
                index: _i,
                count: widget.steps.length,
                last: _last,
                onNext: _next,
                onSkip: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.step,
    required this.index,
    required this.count,
    required this.last,
    required this.onNext,
    required this.onSkip,
  });

  final CoachMark step;
  final int index;
  final int count;
  final bool last;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (step.icon != null) ...[
                  Icon(step.icon, color: cs.primary),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    step.title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(step.body, style: text.bodyMedium),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Semantics(
                  label: 'Step ${index + 1} of $count',
                  child: Row(
                    children: [
                      for (var i = 0; i < count; i++)
                        Container(
                          margin: const EdgeInsets.only(right: 5),
                          width: i == index ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: i == index ? cs.primary : cs.outlineVariant,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                if (!last)
                  TextButton(onPressed: onSkip, child: const Text('Skip')),
                FilledButton(
                  onPressed: onNext,
                  child: Text(last ? 'Got it' : 'Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.hole);

  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Path()..addRect(Offset.zero & size);
    final h = hole;
    final path = h == null
        ? dim
        : Path.combine(
            PathOperation.difference,
            dim,
            Path()
              ..addRRect(RRect.fromRectAndRadius(h, const Radius.circular(14))),
          );
    canvas.drawPath(path, Paint()..color = Colors.black.withAlpha(170));
    if (h != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(h, const Radius.circular(14)),
        Paint()
          ..color = Colors.white.withAlpha(200)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole;
}
