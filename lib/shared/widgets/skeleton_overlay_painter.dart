import 'dart:math';
import 'package:flutter/material.dart';

/// Draws the 100-dim model input: 2 hands (21 landmarks each) + 7 pose anchors + 2 hand-presence.
/// All coordinates are nose-centered (origin = nose).
///
/// Feature layout (100 floats):
///   [0:42]   = Right hand 21×(x,y)
///   [42:84]  = Left hand 21×(x,y)
///   [84:86]  = Nose (always ~0,0)
///   [86:88]  = Left shoulder
///   [88:90]  = Right shoulder
///   [90:92]  = Left ear
///   [92:94]  = Right ear
///   [94:96]  = Left elbow
///   [96:98]  = Right elbow
///   [98]     = has_right_hand
///   [99]     = has_left_hand
class ModelInputPainter extends CustomPainter {
  /// 100-dim nose-centered features from GestureService.
  final List<double> features;
  final bool isActive;

  /// Hand bone connections (21 MediaPipe hand landmarks).
  static const _handConnections = [
    [0, 1], [1, 2], [2, 3], [3, 4],           // thumb
    [0, 5], [5, 6], [6, 7], [7, 8],           // index
    [0, 9], [9, 10], [10, 11], [11, 12],      // middle
    [0, 13], [13, 14], [14, 15], [15, 16],    // ring
    [0, 17], [17, 18], [18, 19], [19, 20],    // pinky
    [5, 9], [9, 13], [13, 17],                // palm
  ];

  /// Pose anchor indices → conceptual connections.
  /// Anchors: nose(0), L_shoulder(1), R_shoulder(2), L_ear(3), R_ear(4), L_elbow(5), R_elbow(6)
  static const _anchorConnections = [
    [0, 3], [0, 4],   // nose → ears
    [1, 2],            // shoulders
    [1, 5], [2, 6],   // shoulders → elbows
  ];

  const ModelInputPainter({
    required this.features,
    this.isActive = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isActive || features.length < 100) return;

    // Check if any hand data exists
    bool hasAnyData = false;
    for (int i = 0; i < 84; i++) {
      if (features[i].abs() > 1e-6) {
        hasAnyData = true;
        break;
      }
    }
    // Also check anchors
    if (!hasAnyData) {
      for (int i = 84; i < 98; i++) {
        if (features[i].abs() > 1e-6) {
          hasAnyData = true;
          break;
        }
      }
    }
    if (!hasAnyData) return;

    // ── Collect all visible points to compute bounding box ──────────────
    final allPoints = <Offset>[];

    // Right hand [0:42]
    final rightHandPoints = _extractHandPoints(0);
    allPoints.addAll(rightHandPoints.where((p) => p != Offset.zero));

    // Left hand [42:84]
    final leftHandPoints = _extractHandPoints(42);
    allPoints.addAll(leftHandPoints.where((p) => p != Offset.zero));

    // Anchors [84:98] — 7 points
    final anchorPoints = <Offset>[];
    for (int i = 0; i < 7; i++) {
      final x = features[84 + i * 2];
      final y = features[84 + i * 2 + 1];
      anchorPoints.add(Offset(x, y));
      if (x.abs() > 1e-6 || y.abs() > 1e-6) {
        allPoints.add(Offset(x, y));
      }
    }

    if (allPoints.length < 2) return;

    // ── Compute fit-to-bounds transform ─────────────────────────────────
    double minX = allPoints.first.dx, maxX = allPoints.first.dx;
    double minY = allPoints.first.dy, maxY = allPoints.first.dy;
    for (final p in allPoints) {
      minX = min(minX, p.dx);
      maxX = max(maxX, p.dx);
      minY = min(minY, p.dy);
      maxY = max(maxY, p.dy);
    }

    final contentW = max(maxX - minX, 0.001);
    final contentH = max(maxY - minY, 0.001);
    final padX = size.width * 0.10;
    final padY = size.height * 0.10;
    final targetW = max(size.width - padX * 2, 1.0);
    final targetH = max(size.height - padY * 2, 1.0);
    final scale = min(targetW / contentW, targetH / contentH);
    final offX = (size.width - contentW * scale) / 2;
    final offY = (size.height - contentH * scale) / 2;

    Offset transform(Offset p) {
      return Offset(
        (p.dx - minX) * scale + offX,
        (p.dy - minY) * scale + offY,
      );
    }

    // ── draw anchors ────────────────────────────────────────────────────
    final anchorLinePaint = Paint()
      ..color = const Color(0xFF1D9E75).withOpacity(0.35)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final anchorDotPaint = Paint()
      ..color = const Color(0xFF1D9E75).withOpacity(0.5)
      ..style = PaintingStyle.fill;

    // Anchor connections
    for (final conn in _anchorConnections) {
      final a = anchorPoints[conn[0]];
      final b = anchorPoints[conn[1]];
      if ((a.dx.abs() > 1e-6 || a.dy.abs() > 1e-6) &&
          (b.dx.abs() > 1e-6 || b.dy.abs() > 1e-6)) {
        canvas.drawLine(transform(a), transform(b), anchorLinePaint);
      }
    }

    // Anchor dots (small, dim)
    for (final p in anchorPoints) {
      if (p.dx.abs() > 1e-6 || p.dy.abs() > 1e-6) {
        final tp = transform(p);
        canvas.drawCircle(tp, 3, anchorDotPaint);
      }
    }

    // Nose marker (special — center of feature space)
    final noseP = anchorPoints[0];
    if (noseP.dx.abs() < 0.01 && noseP.dy.abs() < 0.01) {
      // Nose is at origin (success)
      final tp = transform(noseP);
      canvas.drawCircle(
        tp,
        4,
        Paint()
          ..color = const Color(0xFFFFFFFF).withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }

    // ── Draw hands ──────────────────────────────────────────────────────
    _drawHand(canvas, rightHandPoints, transform,
      color: const Color(0xFF1D9E75), label: 'R');
    _drawHand(canvas, leftHandPoints, transform,
      color: const Color(0xFF4FC3F7), label: 'L');
  }

  List<Offset> _extractHandPoints(int startIdx) {
    final points = <Offset>[];
    for (int i = 0; i < 21; i++) {
      final x = features[startIdx + i * 2];
      final y = features[startIdx + i * 2 + 1];
      points.add(Offset(x, y));
    }
    return points;
  }

  void _drawHand(
    Canvas canvas,
    List<Offset> points,
    Offset Function(Offset) transform, {
    required Color color,
    required String label,
  }) {
    // Check if hand has data
    bool hasData = false;
    for (final p in points) {
      if (p.dx.abs() > 1e-6 || p.dy.abs() > 1e-6) {
        hasData = true;
        break;
      }
    }
    if (!hasData) return;

    final linePaint = Paint()
      ..color = color.withOpacity(0.65)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    // Draw connections
    for (final conn in _handConnections) {
      if (conn[0] < points.length && conn[1] < points.length) {
        final a = points[conn[0]];
        final b = points[conn[1]];
        if ((a.dx.abs() > 1e-6 || a.dy.abs() > 1e-6) &&
            (b.dx.abs() > 1e-6 || b.dy.abs() > 1e-6)) {
          canvas.drawLine(transform(a), transform(b), linePaint);
        }
      }
    }

    // Draw dots
    for (final p in points) {
      if (p.dx.abs() < 1e-6 && p.dy.abs() < 1e-6) continue;
      final tp = transform(p);
      canvas.drawCircle(tp, 5, glowPaint);
      canvas.drawCircle(tp, 3, dotPaint);
      canvas.drawCircle(tp, 1.2, highlightPaint);
    }

    // Draw hand label near wrist (landmark 0)
    final wrist = points[0];
    if (wrist.dx.abs() > 1e-6 || wrist.dy.abs() > 1e-6) {
      final tp = transform(wrist);
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color.withOpacity(0.6),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, tp + const Offset(-12, 6));
    }
  }

  @override
  bool shouldRepaint(ModelInputPainter old) =>
      old.features != features || old.isActive != isActive;
}
