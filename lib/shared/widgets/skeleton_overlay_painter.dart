import 'dart:math';
import 'package:flutter/material.dart';

/// Draws MediaPipe skeleton: pose (body) + both hands on camera preview.
/// Expects normalized (0-1) landmark coordinates — scales to actual canvas size.
/// Mirrors X axis for front camera selfie view.
///
/// Landmark order:
///   [0-32]    = pose (33 landmarks: spine, arms, legs, face)
///   [33-53]   = right hand (21 landmarks)
///   [54-74]   = left hand (21 landmarks)
class SkeletonOverlayPainter extends CustomPainter {
  final List<Offset> landmarks;
  final bool isActive;

  /// Pose bone connections (MediaPipe Pose 33 landmarks).
  static const _poseConnections = [
    // Torso/spine
    [11, 12], // shoulders
    [11, 23], [12, 24], // shoulders to hips
    [23, 24], // hips
    // Left arm
    [12, 14], [14, 16], // shoulder-elbow-wrist
    [16, 20], [16, 18], // wrist-pinky, wrist-index
    // Right arm
    [11, 13], [13, 15], // shoulder-elbow-wrist
    [15, 19], [15, 17], // wrist-pinky, wrist-index
    // Left leg
    [24, 26], [26, 28], [28, 30], [30, 32], // hip-knee-ankle-toe
    // Right leg
    [23, 25], [25, 27], [27, 29], [29, 31], // hip-knee-ankle-toe
  ];

  /// Hand bone connections (21 MediaPipe hand landmarks).
  static const _handConnections = [
    [0, 1], [1, 2], [2, 3], [3, 4],           // thumb
    [0, 5], [5, 6], [6, 7], [7, 8],           // index
    [0, 9], [9, 10], [10, 11], [11, 12],      // middle
    [0, 13], [13, 14], [14, 15], [15, 16],    // ring
    [0, 17], [17, 18], [18, 19], [19, 20],    // pinky
    [5, 9], [9, 13], [13, 17],                // palm
  ];

  const SkeletonOverlayPainter({
    required this.landmarks,
    this.isActive = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!isActive || landmarks.isEmpty) return;

    final linePaint = Paint()
      ..color = const Color(0xFF1D9E75).withOpacity(0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = const Color(0xFF1D9E75)
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = const Color(0xFF1D9E75).withOpacity(0.25)
      ..style = PaintingStyle.fill;

    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    // Koordinat sudah di-swap landscape→portrait di provider.
    // Mirror X untuk front camera selfie: (1.0 - x).
    final scaled = landmarks.map((p) => Offset(
      (1.0 - p.dx) * size.width,
      p.dy * size.height,
    )).toList();

    // Draw pose (first 33 points)
    if (scaled.length >= 33) {
      final pose = scaled.sublist(0, 33);
      _drawPose(canvas, pose, linePaint, dotPaint, glowPaint, highlightPaint);
    }

    // Draw right hand (points 33-53, 21 landmarks)
    if (scaled.length > 33 && scaled.length <= 54) {
      final rightHand = scaled.sublist(33);
      _drawHand(canvas, rightHand, linePaint, dotPaint, glowPaint, highlightPaint);
    } else if (scaled.length > 54) {
      final rightHand = scaled.sublist(33, 54);
      _drawHand(canvas, rightHand, linePaint, dotPaint, glowPaint, highlightPaint);
    }

    // Draw left hand (points 54+, 21 landmarks)
    if (scaled.length > 54) {
      final leftHand = scaled.sublist(54, min(75, scaled.length));
      _drawHand(canvas, leftHand, linePaint, dotPaint, glowPaint, highlightPaint);
    }
  }

  void _drawPose(Canvas canvas, List<Offset> points, Paint linePaint, Paint dotPaint, Paint glowPaint, Paint highlightPaint) {
    if (points.length < 33) return;

    // Draw pose connections
    for (final conn in _poseConnections) {
      if (conn[0] < points.length && conn[1] < points.length) {
        final p1 = points[conn[0]];
        final p2 = points[conn[1]];
        // Only draw if both points are visible (not zero)
        if ((p1.dx != 0 || p1.dy != 0) && (p2.dx != 0 || p2.dy != 0)) {
          canvas.drawLine(p1, p2, linePaint);
        }
      }
    }

    // Draw pose dots (lighter than hands)
    final poseDotPaint = Paint()
      ..color = const Color(0xFF1D9E75).withOpacity(0.6)
      ..style = PaintingStyle.fill;
    final poseGlowPaint = Paint()
      ..color = const Color(0xFF1D9E75).withOpacity(0.15)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      // Skip semua face landmarks (0-10: nose, eyes, ears, mouth) — hanya tampil badan
      // LSTM tetap baca face landmarks dari 258 floats, ini hanya visual overlay
      if (i <= 10 || (point.dx == 0 && point.dy == 0)) continue;

      canvas.drawCircle(point, 4, poseGlowPaint);
      canvas.drawCircle(point, 2, poseDotPaint);
    }
  }

  void _drawHand(Canvas canvas, List<Offset> points, Paint linePaint, Paint dotPaint, Paint glowPaint, Paint highlightPaint) {
    if (points.isEmpty) return;

    // Draw hand connections
    for (final conn in _handConnections) {
      if (conn[0] < points.length && conn[1] < points.length) {
        final p1 = points[conn[0]];
        final p2 = points[conn[1]];
        if ((p1.dx != 0 || p1.dy != 0) && (p2.dx != 0 || p2.dy != 0)) {
          canvas.drawLine(p1, p2, linePaint);
        }
      }
    }

    // Draw hand dots (brighter than pose)
    for (final point in points) {
      if (point.dx == 0 && point.dy == 0) continue; // skip invisible
      canvas.drawCircle(point, 6, glowPaint);
      canvas.drawCircle(point, 3.5, dotPaint);
      canvas.drawCircle(point, 1.5, highlightPaint);
    }
  }

  @override
  bool shouldRepaint(SkeletonOverlayPainter old) =>
      old.landmarks != landmarks || old.isActive != isActive;
}
