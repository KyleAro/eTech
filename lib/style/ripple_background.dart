import 'package:flutter/material.dart';
import 'package:etech/style/mainpage_style.dart';

/// Concentric ripple pattern for the pond background.
/// Drop this behind your page content using a Stack.
///
/// Usage:
///   Stack(
///     children: [
///       Positioned.fill(child: RippleBackground()),
///       YourContent(),
///     ],
///   )
///
/// Pass [centerAlignment] to control where the ripples emanate from
/// (e.g. align to the record button on the record screen).
class RippleBackground extends StatelessWidget {
  final Alignment centerAlignment;
  final double opacity;
  final int ringCount;

  const RippleBackground({
    super.key,
    this.centerAlignment = Alignment.center,
    this.opacity = 0.12,
    this.ringCount = 5,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _RipplePainter(
          alignment: centerAlignment,
          opacity: opacity,
          ringCount: ringCount,
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final Alignment alignment;
  final double opacity;
  final int ringCount;

  _RipplePainter({
    required this.alignment,
    required this.opacity,
    required this.ringCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Resolve the alignment into an actual pixel center.
    final center = Offset(
      size.width / 2 + (alignment.x * size.width / 2),
      size.height / 2 + (alignment.y * size.height / 2),
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = textcolor.withOpacity(opacity);

    // Draw evenly-spaced concentric rings out to a generous max radius.
    // Using ~80px spacing matches the mockup spacing.
    const ringSpacing = 70.0;
    final startRadius = 80.0;

    for (var i = 0; i < ringCount; i++) {
      final radius = startRadius + (i * ringSpacing);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RipplePainter oldDelegate) =>
      oldDelegate.alignment != alignment ||
      oldDelegate.opacity != opacity ||
      oldDelegate.ringCount != ringCount;
}