import 'package:flutter/material.dart';

/// Miee brand logo widgets.
///
/// Two variants:
/// - [MieeWordmark]    — full lowercase "miee" wordmark with the distinctive
///                       crosshair "ee" signature. Use on splash, headers,
///                       desktop sidebar, and anywhere there is enough space.
/// - [MieeCompactIcon] — the isolated "ee" crosshair mark only. Use as a
///                       compact brand mark in collapsed sidebar states or
///                       any tight context.
///
/// Both are pure [CustomPainter] widgets — no image assets required.
/// They inherit color from the [color] parameter (defaults to white on dark).

// ─────────────────────────────────────────────────────────────────────────────

/// Full "miee" typographic wordmark with crosshair-ee signature.
class MieeWordmark extends StatelessWidget {
  /// Rendered width in logical pixels. Height scales automatically to preserve
  /// the wordmark's aspect ratio (approx 3.4 : 1).
  final double width;

  /// Mark color. Defaults to [Colors.white] for use on dark backgrounds.
  final Color color;

  const MieeWordmark({
    super.key,
    this.width = 160,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final height = width / 3.4;
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _MieeWordmarkPainter(color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

/// Compact "ee" crosshair mark — isolated brand icon for tight contexts.
class MieeCompactIcon extends StatelessWidget {
  /// Width = height (square).
  final double size;

  /// Mark color. Defaults to [Colors.white].
  final Color color;

  const MieeCompactIcon({
    super.key,
    this.size = 40,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MieeCompactPainter(color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painters
// ─────────────────────────────────────────────────────────────────────────────

class _MieeWordmarkPainter extends CustomPainter {
  final Color color;
  _MieeWordmarkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Normalize: everything expressed as fractions of [w, h].
    // Reference viewport: 520 × 128 (the SVG viewBox we designed to).
    final sx = w / 520.0;
    final sy = h / 128.0;

    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 14 * sy;

    final barPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10 * sy;

    final stemPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 20 * sy;

    // ── m ──
    // Left stem
    _drawRoundedStem(canvas, Offset(20 * sx, 28 * sy), Offset(20 * sx, 100 * sy), stemPaint);
    // Left arch
    final leftArchRect = Rect.fromLTWH(20 * sx, 28 * sy, 84 * sx, 72 * sy);
    canvas.drawArc(leftArchRect, _deg(180), _deg(-180), false, ringPaint);
    // Center stem
    _drawRoundedStem(canvas, Offset(104 * sx, 28 * sy), Offset(104 * sx, 100 * sy), stemPaint);
    // Right arch
    final rightArchRect = Rect.fromLTWH(104 * sx, 28 * sy, 84 * sx, 72 * sy);
    canvas.drawArc(rightArchRect, _deg(180), _deg(-180), false, ringPaint);
    // Right stem
    _drawRoundedStem(canvas, Offset(188 * sx, 28 * sy), Offset(188 * sx, 100 * sy), stemPaint);

    // ── i ──
    // Dot
    final dotCenter = Offset(258 * sx, 22 * sy);
    canvas.drawCircle(dotCenter, 10 * sy, Paint()..color = color);
    // Stem
    _drawRoundedStem(canvas, Offset(258 * sx, 40 * sy), Offset(258 * sx, 100 * sy), stemPaint);

    // ── e (first) — at x-offset 295 ──
    _drawEWithCrosshair(
      canvas,
      leftX: 295 * sx,
      topY: 28 * sy,
      eWidth: 88 * sx,
      eHeight: 72 * sy,
      ringPaint: ringPaint,
      barPaint: barPaint,
    );

    // ── e (second) — at x-offset 403 ──
    _drawEWithCrosshair(
      canvas,
      leftX: 403 * sx,
      topY: 28 * sy,
      eWidth: 88 * sx,
      eHeight: 72 * sy,
      ringPaint: ringPaint,
      barPaint: barPaint,
    );
  }

  /// Draws a single "e" with the crosshair (horizontal + vertical bar) signature.
  void _drawEWithCrosshair(
    Canvas canvas, {
    required double leftX,
    required double topY,
    required double eWidth,
    required double eHeight,
    required Paint ringPaint,
    required Paint barPaint,
  }) {
    final cx = leftX + eWidth / 2;
    final cy = topY + eHeight / 2;
    final rect = Rect.fromLTWH(leftX, topY, eWidth, eHeight);

    // "e" arc: full circle with a right-side opening (approx 40°–320° sweep)
    canvas.drawArc(rect, _deg(40), _deg(280), false, ringPaint);

    // Horizontal crosshair bar
    canvas.drawLine(Offset(leftX, cy), Offset(leftX + eWidth, cy), barPaint);

    // Vertical crosshair bar
    canvas.drawLine(Offset(cx, topY), Offset(cx, topY + eHeight), barPaint);
  }

  void _drawRoundedStem(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
  }

  double _deg(double degrees) => degrees * (3.141592653589793 / 180.0);

  @override
  bool shouldRepaint(_MieeWordmarkPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────

class _MieeCompactPainter extends CustomPainter {
  final Color color;
  _MieeCompactPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Two "e"s side by side in a square canvas.
    // Each e occupies roughly 44% of width; 4% gap between them.
    final pad = w * 0.06;
    final gap = w * 0.04;
    final eW = (w - 2 * pad - gap) / 2;
    final eH = h * 0.60;
    final topY = (h - eH) / 2;

    final strokeW = w * 0.075;

    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeW;

    final barPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeW * 0.7;

    for (int i = 0; i < 2; i++) {
      final leftX = pad + i * (eW + gap);
      final rect = Rect.fromLTWH(leftX, topY, eW, eH);
      final cx = leftX + eW / 2;
      final cy = topY + eH / 2;

      // "e" arc with right-side opening
      canvas.drawArc(rect, _deg(40), _deg(280), false, ringPaint);

      // Horizontal bar
      canvas.drawLine(Offset(leftX, cy), Offset(leftX + eW, cy), barPaint);

      // Vertical bar
      canvas.drawLine(Offset(cx, topY), Offset(cx, topY + eH), barPaint);
    }
  }

  double _deg(double degrees) => degrees * (3.141592653589793 / 180.0);

  @override
  bool shouldRepaint(_MieeCompactPainter old) => old.color != color;
}
