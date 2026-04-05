import 'package:flutter/material.dart';

/// Draws MediaPipe-style hand skeleton dots and connections on camera preview.
/// Used in comm_deaf_to_hearing_screen and learn_alfabet_screen.
class SkeletonOverlayPainter extends CustomPainter {
  final List<Offset> landmarks;
  final bool isActive;

  /// Hand bone connections (21 MediaPipe hand landmarks).
  static const _connections = [
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

    // Draw bone connections
    for (final conn in _connections) {
      if (conn[0] < landmarks.length && conn[1] < landmarks.length) {
        canvas.drawLine(landmarks[conn[0]], landmarks[conn[1]], linePaint);
      }
    }

    // Draw landmark dots with glow effect
    for (final point in landmarks) {
      canvas.drawCircle(point, 6, glowPaint);     // outer glow
      canvas.drawCircle(point, 3.5, dotPaint);     // main dot
      canvas.drawCircle(point, 1.5, highlightPaint); // center highlight
    }
  }

  @override
  bool shouldRepaint(SkeletonOverlayPainter old) =>
      old.landmarks != landmarks || old.isActive != isActive;
}
