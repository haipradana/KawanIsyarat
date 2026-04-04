import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/constants.dart';

class PushToStartButton extends StatefulWidget {
  final bool isActive;
  final IconData icon;
  final String label;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const PushToStartButton({
    super.key,
    required this.isActive,
    required this.icon,
    required this.label,
    required this.onStart,
    required this.onStop,
  });

  @override
  State<PushToStartButton> createState() => _PushToStartButtonState();
}

class _PushToStartButtonState extends State<PushToStartButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(PushToStartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.isActive && oldWidget.isActive) {
      _pulseController.stop();
      _pulseController.reset();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onLongPressStart: (_) => widget.onStart(),
          onLongPressEnd: (_) => widget.onStop(),
          onTap: () {
            if (widget.isActive) {
              widget.onStop();
            } else {
              widget.onStart();
            }
          },
          child: AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              final scale = widget.isActive ? _pulseAnimation.value : 1.0;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: widget.isActive
                          ? [AppColors.accent, Color(0xFFE8941E)]
                          : [AppColors.primaryDark, AppColors.primaryContainer],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (widget.isActive
                                ? AppColors.accent
                                : AppColors.primary)
                            .withOpacity(0.35),
                        blurRadius: widget.isActive ? 32 : 24,
                        spreadRadius: widget.isActive ? 4 : 0,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    widget.icon,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: 12),
        AnimatedDefaultTextStyle(
          duration: Duration(milliseconds: 200),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: widget.isActive ? AppColors.accent : AppColors.textSecondary,
          ),
          child: Text(widget.isActive ? 'MEREKAM...' : widget.label),
        ),
      ],
    );
  }
}
