import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/constants.dart';

class LiveCameraPip extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onRecord;

  const LiveCameraPip({
    super.key,
    required this.isRecording,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        color: Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Stack(
        children: [
          // Simulated camera feed
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              gradient: RadialGradient(
                colors: [
                  Color(0xFF2A2A4A),
                  Color(0xFF1A1A2E),
                ],
                center: Alignment.center,
                radius: 0.8,
              ),
            ),
          ),
          // Center camera icon
          Center(
            child: Icon(
              Icons.person_outline_rounded,
              color: Colors.white.withOpacity(0.2),
              size: 64,
            ),
          ),
          // LIVE AI badge
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.9),
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'LIVE AI',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Record button
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: onRecord,
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(
                    horizontal: isRecording ? 24 : 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isRecording
                        ? AppColors.error
                        : Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isRecording
                            ? Icons.stop_rounded
                            : Icons.fiber_manual_record,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        isRecording ? 'BERHENTI' : 'REKAM',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
