import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BRIEF GAMBAR (drop file ke assets/images/ lalu uncommit baris di bawah):
//
//  1. assets/images/comm_deaf.jpg
//     Cari: foto close-up tangan seseorang yang sedang membuat isyarat tangan
//     (bukan huruf, tapi gestur percakapan). Angle sedikit miring dari atas,
//     latar buram/bokeh, tone gelap kehijau-hijauan. Tidak perlu watermark.
//     Keyword pencarian: "sign language hands close-up dark", "deaf communication
//     hands gesture photo" di Unsplash / Pexels (gratis, no attribution required).
//
//  2. assets/images/comm_hearing.jpg
//     Cari: foto wajah seseorang yang sedang berbicara — profil ¾, mulut sedikit
//     terbuka, ekspresif. Atau: gelombang suara/audio yang artistic (bisa abstrak).
//     Tone gelap navy-biru. Keyword: "person talking side profile dark background",
//     "sound wave abstract dark" di Unsplash / Pexels.
//
//  Ukuran rekomendasi: landscape 800×500px, compress WebP q=80 (~30-60KB).
//  Kalau belum ada gambar → card tetap tampil dengan gradient placeholder.
// ─────────────────────────────────────────────────────────────────────────────

class CommDirectionPickerScreen extends StatelessWidget {
  const CommDirectionPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Custom mini header (bukan AppBar supaya bisa kontrol padding) ──
            Padding(
              padding: EdgeInsets.only(
                top: topPad + 10,
                left: 4,
                right: AppSpacing.xxl,
                bottom: 0,
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_rounded,
                        color: AppColors.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Komunikasi',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                            height: 1.2,
                          ),
                        ),
                        Text(
                          'Pilih arah percakapan',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: AppSpacing.lg),

            // ── Dua kartu full-height, masing-masing Expanded ──
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  children: [
                    // Card 1: Deaf → Hearing
                    Expanded(
                      child: _FullCard(
                        imagePath: 'assets/images/comm_deaf.jpg',
                        gradientColors: const [
                          Color(0xFF004D4D),
                          Color(0xFF006D6D),
                        ],
                        direction: 'TULI  →  DENGAR',
                        title: 'Isyarat ke\nTeks & Suara',
                        description:
                            'Kamera menangkap gerakan BISINDO —\nAI terjemahkan & bacakan ke sekitar',
                        cta: 'Mulai isyarat',
                        iconBg: AppColors.primary,
                        icon: Icons.sign_language_rounded,
                        onTap: () => context.push('/comm-deaf'),
                        delay: 150,
                      ),
                    ),

                    SizedBox(height: AppSpacing.md),

                    // Card 2: Hearing → Deaf
                    Expanded(
                      child: _FullCard(
                        imagePath: 'assets/images/comm_hearing.jpg',
                        gradientColors: const [
                          Color(0xFF101C28),
                          Color(0xFF1F2E40),
                        ],
                        direction: 'DENGAR  →  TULI',
                        title: 'Suara ke\nTeks Ringkas',
                        description:
                            'Bicara ke mikrofon — AI ringkas jadi\nteks singkat yang mudah dibaca',
                        cta: 'Mulai bicara',
                        iconBg: Color(0xFF2A3F55),
                        icon: Icons.mic_rounded,
                        onTap: () => context.push('/comm-hearing'),
                        delay: 280,
                      ),
                    ),

                    SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _FullCard extends StatefulWidget {
  final String imagePath;
  final List<Color> gradientColors;
  final String direction;
  final String title;
  final String description;
  final String cta;
  final Color iconBg;
  final IconData icon;
  final VoidCallback onTap;
  final int delay;

  const _FullCard({
    required this.imagePath,
    required this.gradientColors,
    required this.direction,
    required this.title,
    required this.description,
    required this.cta,
    required this.iconBg,
    required this.icon,
    required this.onTap,
    required this.delay,
  });

  @override
  State<_FullCard> createState() => _FullCardState();
}

class _FullCardState extends State<_FullCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Layer 1: Foto / gradient fallback ──────────────────────
              _buildBackground(),

              // ── Layer 2: Gradient overlay bawah (teks readable) ────────
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.25, 0.65, 1.0],
                      colors: [
                        Colors.transparent,
                        widget.gradientColors[0].withOpacity(0.72),
                        widget.gradientColors[0].withOpacity(0.97),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Layer 3: Arah chip (top-left) ──────────────────────────
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.18), width: 1),
                  ),
                  child: Text(
                    widget.direction,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withOpacity(0.85),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),

              // ── Layer 4: Konten bawah ──────────────────────────────────
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Teks kiri
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.description,
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.7),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // CTA button bulat kanan
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.cta,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: widget.gradientColors[0],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 14,
                            color: widget.gradientColors[0],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      )
          .animate()
          .fadeIn(duration: 450.ms, delay: Duration(milliseconds: widget.delay))
          .slideY(
            begin: 0.06,
            end: 0,
            duration: 450.ms,
            delay: Duration(milliseconds: widget.delay),
            curve: Curves.easeOut,
          ),
    );
  }

  Widget _buildBackground() {
    return FutureBuilder<bool>(
      future: _assetExists(widget.imagePath),
      builder: (context, snap) {
        if (snap.data == true) {
          return Image.asset(
            widget.imagePath,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _gradientBox(),
          );
        }
        return _gradientBox();
      },
    );
  }

  Widget _gradientBox() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Future<bool> _assetExists(String path) async {
    try {
      await rootBundle.load(path);
      return true;
    } catch (_) {
      return false;
    }
  }
}
