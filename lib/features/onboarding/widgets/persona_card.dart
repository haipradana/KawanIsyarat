import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/constants.dart';
import '../../../shared/models/user_persona.dart';

class PersonaCard extends StatefulWidget {
  final UserPersona persona;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color textColor;

  const PersonaCard({
    super.key,
    required this.persona,
    required this.onTap,
    required this.backgroundColor,
    this.textColor = Colors.white,
  });

  @override
  State<PersonaCard> createState() => _PersonaCardState();
}

class _PersonaCardState extends State<PersonaCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isTuli = widget.persona == UserPersona.tuli;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: Duration(milliseconds: 150),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: isTuli
                ? LinearGradient(
                    colors: [AppColors.primaryDark, AppColors.primaryContainer],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: [AppColors.darkSurface, Color(0xFF2A3542)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(AppRadius.xxl),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isTuli ? Icons.sign_language_rounded : Icons.hearing_rounded,
                      color: widget.textColor,
                      size: 26,
                    ),
                  ),
                  SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isTuli ? 'Pengguna Tuli' : 'Pengguna Mendengar',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: widget.textColor,
                            height: 1.3,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          widget.persona.description,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: widget.textColor.withOpacity(0.7),
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: AppSpacing.md),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: widget.textColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
