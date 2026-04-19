import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/constants.dart';
import '../../../core/services/gemma_service.dart';

/// Deaf Vocabulary Helper — fitur untuk membantu teman Tuli memahami
/// kosakata atau istilah yang sulit (asuransi, polis, formulir, dll).
///
/// Flow: user input kata/frasa → Gemma 4 jelaskan dengan bahasa sederhana.
/// Penjelasan disimpan in-memory sebagai "Riwayat" supaya bisa discroll kembali.
class VocabularyHelperScreen extends StatefulWidget {
  const VocabularyHelperScreen({super.key});

  @override
  State<VocabularyHelperScreen> createState() => _VocabularyHelperScreenState();
}

class _VocabularyHelperScreenState extends State<VocabularyHelperScreen> {
  final _controller = TextEditingController();
  final _gemma = GemmaService();
  final List<VocabularyExplanation> _history = [];

  bool _isLoading = false;
  String? _error;

  static const _quickSuggestions = [
    'asuransi',
    'polis',
    'formulir',
    'administrasi',
    'rujukan',
    'kuitansi',
    'aplikasi',
    'tagihan',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _explain(String input) async {
    final q = input.trim();
    if (q.isEmpty) return;
    if (_isLoading) return;

    if (!_gemma.isLoaded) {
      setState(() => _error = 'Model Gemma belum siap. Coba lagi sebentar.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _controller.clear();
    });

    final result = await _gemma.explainVocabulary(q);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result != null) {
        _history.insert(0, result);
      } else {
        _error = 'Gagal menjelaskan kata ini. Coba lagi.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Kamus Pintar',
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Hero / intro
            Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
              child: Container(
                padding: EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.15),
                      AppColors.primary.withOpacity(0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.menu_book_rounded,
                          color: AppColors.primary, size: 22),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tanya apa saja',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Gemma 4 menjelaskan kata atau istilah dengan bahasa yang mudah dipahami.',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              color: AppColors.textPrimary.withOpacity(0.65),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Input row
            Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_isLoading,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _explain,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ketik kata atau frasa...',
                        hintStyle: GoogleFonts.beVietnamPro(
                          fontSize: 14,
                          color: AppColors.textPrimary.withOpacity(0.4),
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        prefixIcon:
                            Icon(Icons.search_rounded, color: AppColors.primary),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      ),
                    ),
                  ),
                  SizedBox(width: 10),
                  ElevatedButton(
                    onPressed:
                        _isLoading ? null : () => _explain(_controller.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),

            // Quick suggestions chip row
            if (_history.isEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg, 4, AppSpacing.lg, AppSpacing.sm),
                child: SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _quickSuggestions.length,
                    separatorBuilder: (_, __) => SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final w = _quickSuggestions[i];
                      return ActionChip(
                        label: Text(w,
                            style: GoogleFonts.beVietnamPro(fontSize: 12.5)),
                        backgroundColor: AppColors.surface,
                        labelStyle:
                            TextStyle(color: AppColors.textPrimary),
                        side: BorderSide(
                            color: AppColors.primary.withOpacity(0.3)),
                        onPressed: _isLoading ? null : () => _explain(w),
                      );
                    },
                  ),
                ),
              ),

            if (_error != null)
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: AppColors.error),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(_error!,
                          style: GoogleFonts.beVietnamPro(
                              fontSize: 12, color: AppColors.error)),
                    ),
                  ],
                ),
              ),

            // History / result list
            Expanded(
              child: _history.isEmpty && !_isLoading
                  ? _emptyState()
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(AppSpacing.lg,
                          AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
                      itemCount: _history.length + (_isLoading ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (_isLoading && i == 0) return _loadingCard();
                        final idx = _isLoading ? i - 1 : i;
                        return _vocabCard(_history[idx]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_rounded,
                size: 64, color: AppColors.textPrimary.withOpacity(0.15)),
            SizedBox(height: 16),
            Text(
              'Belum ada kata yang dicari',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary.withOpacity(0.6),
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Ketik kata di atas atau pilih saran cepat.',
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: AppColors.textPrimary.withOpacity(0.45),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingCard() {
    return Container(
      margin: EdgeInsets.only(bottom: AppSpacing.md),
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Gemma 4 sedang menjelaskan...',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13.5,
                color: AppColors.textPrimary.withOpacity(0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vocabCard(VocabularyExplanation exp) {
    return Container(
      margin: EdgeInsets.only(bottom: AppSpacing.md),
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  exp.word,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Spacer(),
              Icon(Icons.auto_awesome_rounded,
                  size: 14, color: AppColors.primary.withOpacity(0.6)),
            ],
          ),
          SizedBox(height: 12),
          Text(
            'Arti',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary.withOpacity(0.5),
              letterSpacing: 0.8,
            ),
          ),
          SizedBox(height: 3),
          Text(
            exp.meaning,
            style: GoogleFonts.beVietnamPro(
              fontSize: 14,
              color: AppColors.textPrimary,
              height: 1.5,
            ),
          ),
          if (exp.example != null && exp.example!.isNotEmpty) ...[
            SizedBox(height: 10),
            Text(
              'Contoh',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary.withOpacity(0.5),
                letterSpacing: 0.8,
              ),
            ),
            SizedBox(height: 3),
            Text(
              '"${exp.example!}"',
              style: GoogleFonts.beVietnamPro(
                fontSize: 13.5,
                color: AppColors.textPrimary.withOpacity(0.75),
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0);
  }
}
