import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import 'alphabet_practice_screen.dart';

class LearnAlfabetScreen extends StatefulWidget {
  const LearnAlfabetScreen({super.key});

  @override
  State<LearnAlfabetScreen> createState() => _LearnAlfabetScreenState();
}

class _LearnAlfabetScreenState extends State<LearnAlfabetScreen> {
  String? _selectedLetter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Alfabet BISINDO',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: BouncingScrollPhysics(),
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pilih huruf untuk belajar',
              style: GoogleFonts.beVietnamPro(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ).animate().fadeIn(duration: 400.ms),
            SizedBox(height: AppSpacing.xxl),
            // Alphabet grid
            GridView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.0,
              ),
              itemCount: BisindoData.alfabet.length,
              itemBuilder: (context, index) {
                final letter = BisindoData.alfabet[index];
                final isSelected = _selectedLetter == letter;
                return _LetterTile(
                  letter: letter,
                  isSelected: isSelected,
                  delay: index * 30,
                  onTap: () {
                    setState(() => _selectedLetter = letter);
                  },
                );
              },
            ),
            SizedBox(height: AppSpacing.xxxl),
            // Detail section
            if (_selectedLetter != null) ...[
              _buildLetterDetail(_selectedLetter!)
                  .animate()
                  .fadeIn(duration: 400.ms)
                  .slideY(begin: 0.05, end: 0, duration: 400.ms),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLetterDetail(String letter) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.12),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Large letter
          Text(
            letter,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 64,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          SizedBox(height: AppSpacing.lg),
          // Reference placeholder
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.sign_language_rounded,
                  size: 48,
                  color: AppColors.outlineVariant,
                ),
                SizedBox(height: AppSpacing.md),
                Text(
                  'Isyarat huruf "$letter"',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Referensi visual akan ditampilkan di sini',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 12,
                    color: AppColors.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: AppSpacing.xl),
          // Practice button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AlphabetPracticeScreen(
                      targetLetter: letter,
                    ),
                  ),
                );
              },
              icon: Icon(Icons.videocam_rounded, size: 20),
              label: Text(
                'Praktik dengan Kamera',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LetterTile extends StatefulWidget {
  final String letter;
  final bool isSelected;
  final int delay;
  final VoidCallback onTap;

  const _LetterTile({
    required this.letter,
    required this.isSelected,
    required this.delay,
    required this.onTap,
  });

  @override
  State<_LetterTile> createState() => _LetterTileState();
}

class _LetterTileState extends State<_LetterTile> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? AppColors.primary
              : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: widget.isSelected
                ? AppColors.primary
                : AppColors.outlineVariant.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            widget.letter,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: widget.isSelected
                  ? Colors.white
                  : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    ).animate().fadeIn(
          duration: 300.ms,
          delay: Duration(milliseconds: widget.delay),
        );
  }
}
