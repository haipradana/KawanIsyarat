import 'package:flutter/material.dart';
import '../../../app/constants.dart';

class ReferenceImageCard extends StatelessWidget {
  final String word;

  const ReferenceImageCard({
    super.key,
    required this.word,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // Background pattern
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl - 1),
              child: CustomPaint(
                painter: _PatternPainter(),
              ),
            ),
          ),
          // Center illustration
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '🤟',
                      style: TextStyle(fontSize: 40),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                Text(
                  'Referensi Gerakan',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          // Label
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                '📷 REFERENSI',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withOpacity(0.03)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 8; i++) {
      for (int j = 0; j < 12; j++) {
        if ((i + j) % 3 == 0) {
          canvas.drawCircle(
            Offset(j * (size.width / 12) + 15, i * (size.height / 8) + 15),
            3,
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
