import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/constants.dart';
import '../screens/alphabet_practice_screen.dart' show AlphabetMode;

/// Widget pratinjau gambar referensi huruf alfabet isyarat.
///
/// Mencari asset di:
///   `assets/images/alfabet/sibi/<huruf>.webp` (SIBI, 1 tangan)
///   `assets/images/alfabet/bisindo/<huruf>.webp` (BISINDO, 2 tangan)
///
/// Kalau file tidak ada (mis. dataset belum lengkap), fallback ke
/// placeholder ikon — tidak crash. Huruf di-lowercase saat dicari.
class AlphabetReferenceImage extends StatefulWidget {
  final String letter;
  final AlphabetMode mode;
  final double height;

  const AlphabetReferenceImage({
    super.key,
    required this.letter,
    required this.mode,
    this.height = 200,
  });

  @override
  State<AlphabetReferenceImage> createState() =>
      _AlphabetReferenceImageState();
}

class _AlphabetReferenceImageState extends State<AlphabetReferenceImage> {
  bool _loading = true;
  bool _missing = false;
  String? _assetPath;

  @override
  void initState() {
    super.initState();
    _checkAsset();
  }

  @override
  void didUpdateWidget(covariant AlphabetReferenceImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.letter != widget.letter || oldWidget.mode != widget.mode) {
      _checkAsset();
    }
  }

  Future<void> _checkAsset() async {
    final modeFolder =
        widget.mode == AlphabetMode.sibi ? 'sibi' : 'bisindo';
    final path =
        'assets/images/alfabet/$modeFolder/${widget.letter.toLowerCase()}.webp';
    setState(() {
      _loading = true;
      _missing = false;
      _assetPath = path;
    });
    try {
      await rootBundle.load(path);
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _missing = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: _loading
            ? _placeholder(Icons.hourglass_top_rounded, 'Memuat referensi…')
            : (_missing || _assetPath == null)
                ? _placeholder(
                    widget.mode == AlphabetMode.sibi
                        ? Icons.front_hand_rounded
                        : Icons.sign_language_rounded,
                    'Isyarat huruf "${widget.letter}"',
                    sub: widget.mode == AlphabetMode.sibi
                        ? 'Gunakan 1 tangan'
                        : 'Gunakan 2 tangan',
                  )
                : Container(
                    color: AppColors.surfaceContainerHigh,
                    child: Image.asset(
                      _assetPath!,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => _placeholder(
                        Icons.broken_image_rounded,
                        'Gambar tidak bisa dimuat',
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _placeholder(IconData icon, String label, {String? sub}) {
    return Container(
      color: AppColors.surfaceContainerHigh,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: AppColors.outlineVariant),
          SizedBox(height: AppSpacing.sm),
          Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          if (sub != null) ...[
            SizedBox(height: 4),
            Text(
              sub,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                color: AppColors.outlineVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
