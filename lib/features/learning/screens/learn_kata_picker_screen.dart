import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/constants.dart';
import '../widgets/bisindo_video_preview.dart';

/// Pre-screen untuk fitur Belajar Kata BISINDO.
///
/// User memilih kata dari dropdown (diisi dari `bisindo_wl_labels.json`),
/// melihat placeholder preview + deskripsi singkat, lalu tekan
/// "Mulai Belajar" untuk masuk ke mode praktik (LSTM + Gemma Coach).
class LearnKataPickerScreen extends StatefulWidget {
  const LearnKataPickerScreen({super.key});

  @override
  State<LearnKataPickerScreen> createState() => _LearnKataPickerScreenState();
}

class _LearnKataPickerScreenState extends State<LearnKataPickerScreen> {
  List<String> _labels = [];
  String? _selected;
  bool _loading = true;

  /// Deskripsi singkat per label — tampil di bawah preview.
  static const _descriptions = {
    'saya'        : 'Isyarat menunjuk ke diri sendiri — kata dasar untuk memperkenalkan diri.',
    'terima_kasih': 'Gerakan tangan dari dagu ke depan — ungkapan rasa syukur yang tulus.',
    'tuli'        : 'Isyarat menunjuk ke telinga — menunjukkan identitas Tuli dengan bangga.',
    'maaf'        : 'Gerakan tangan membentuk permintaan maaf — dipakai saat meminta izin atau melakukan kesalahan.',
    'belajar'     : 'Gerakan tangan yang menggambarkan aktivitas membaca dan menyerap ilmu.',
    'air'         : 'Isyarat yang menggambarkan air mengalir — kata dasar kebutuhan sehari-hari.',
    'hari'        : 'Gerakan yang menunjukkan perputaran waktu — dipakai untuk menyebut hari.',
    'lagi'        : 'Isyarat pengulangan — menunjukkan "sekali lagi" atau "tambah lagi".',
    'makan'       : 'Gerakan tangan menuju mulut — salah satu kata paling sering dipakai sehari-hari.',
  };

  @override
  void initState() {
    super.initState();
    _loadLabels();
  }

  Future<void> _loadLabels() async {
    try {
      final jsonStr =
          await rootBundle.loadString('assets/models/bisindo_wl_labels.json');
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final labels = List<String>.from(data['labels'] as List);
      setState(() {
        _labels = labels;
        _selected = labels.isNotEmpty ? labels.first : null;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  String _pretty(String raw) {
    return raw
        .split('_')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Belajar Kata BISINDO',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              physics: BouncingScrollPhysics(),
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pilih kata yang ingin kamu pelajari',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ).animate().fadeIn(duration: 400.ms),
                  SizedBox(height: 6),
                  Text(
                    'Lihat pratinjau gerakannya, lalu coba praktik di kamera dengan pendamping AI.',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                  SizedBox(height: AppSpacing.xxl),

                  // Dropdown card
                  _dropdownCard()
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 150.ms)
                      .slideY(begin: 0.05, end: 0),

                  SizedBox(height: AppSpacing.xl),

                  // Placeholder preview
                  if (_selected != null)
                    _previewCard(_selected!)
                        .animate(key: ValueKey(_selected))
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.03, end: 0, duration: 400.ms),

                  SizedBox(height: AppSpacing.xl),

                  // Start button
                  _startButton()
                      .animate()
                      .fadeIn(duration: 500.ms, delay: 300.ms),
                ],
              ),
            ),
    );
  }

  Widget _dropdownCard() {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.front_hand_rounded, color: AppColors.primary, size: 22),
          SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selected,
                isExpanded: true,
                icon: Icon(Icons.expand_more_rounded,
                    color: AppColors.textPrimary),
                dropdownColor: AppColors.surfaceContainerHigh,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
                items: _labels
                    .map((label) => DropdownMenuItem(
                          value: label,
                          child: Text(_pretty(label)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selected = v),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewCard(String label) {
    final desc = _descriptions[label] ?? 'Praktikkan gerakan isyarat kata ini di kamera.';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withOpacity(0.12),
            AppColors.accent.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Video pratinjau (auto fallback ke placeholder kalau asset belum ada)
          BisindoVideoPreview(word: label, aspectRatio: 16 / 10),
          SizedBox(height: AppSpacing.lg),

          // Label
          Row(
            children: [
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  'BISINDO · Kata',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            _pretty(label),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            desc,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13.5,
              color: AppColors.textPrimary.withOpacity(0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _startButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _selected == null
            ? null
            : () => context.push('/learn/kata/practice',
                extra: {'word': _selected}),
        icon: Icon(Icons.play_arrow_rounded),
        label: Text(
          'Mulai Belajar',
          style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w800, fontSize: 15),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
        ),
      ),
    );
  }
}
