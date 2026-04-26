import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/constants.dart';

class GlossChipRow extends StatefulWidget {
  final List<String> glossTokens;

  const GlossChipRow({
    super.key,
    required this.glossTokens,
  });

  @override
  State<GlossChipRow> createState() => _GlossChipRowState();
}

class _GlossChipRowState extends State<GlossChipRow> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant GlossChipRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to end when new tokens are added
    if (widget.glossTokens.length > oldWidget.glossTokens.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.glossTokens.isEmpty) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'Tidak ada isyarat terdeteksi',
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: widget.glossTokens.asMap().entries.map((entry) {
          final index = entry.key;
          final token = entry.value;
          return Padding(
            padding: EdgeInsets.only(right: 8),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Text(
                token,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  letterSpacing: 0.5,
                ),
              ),
            )
                .animate()
                .fadeIn(
                  duration: 300.ms,
                  delay: Duration(milliseconds: index * 100),
                )
                .slideX(
                  begin: 0.3,
                  end: 0,
                  duration: 300.ms,
                  delay: Duration(milliseconds: index * 100),
                  curve: Curves.easeOut,
                ),
          );
        }).toList(),
      ),
    );
  }
}
