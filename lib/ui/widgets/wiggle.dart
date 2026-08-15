import 'dart:math';

import 'package:flutter/material.dart';

/// Wraps [child] in a looping iOS-style "jiggle" (tilt + subtle bob) while
/// [enabled] is true. Each instance uses a random phase so a group of wiggling
/// widgets doesn't move in lockstep.
class Wiggle extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const Wiggle({super.key, required this.child, this.enabled = true});

  @override
  State<Wiggle> createState() => _WiggleState();
}

class _WiggleState extends State<Wiggle> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  // Random phase + slight per-instance amplitude variation for a natural look.
  final double _phase = Random().nextDouble();
  final double _amplitude = 0.015 + Random().nextDouble() * 0.015;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    if (widget.enabled) _controller.repeat();
  }

  @override
  void didUpdateWidget(Wiggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = (_controller.value + _phase) * 2 * pi;
        final angle = sin(t) * _amplitude;
        final dy = cos(t) * 0.2;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(angle: angle, child: child),
        );
      },
    );
  }
}
