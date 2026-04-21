import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/constants.dart';
import '../../../core/services/gemma_service.dart';
import '../../../core/services/persistence_service.dart';

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
  final _scrollController = ScrollController();
  final _gemma = GemmaService();
  final _persist = PersistenceService.instance;
  List<VocabularyExplanation> _history = [];

  bool _isLoading = false;
  String? _error;

  static const _quickSuggestions = [
    'asuransi',
    'polis',
    'formulir',
    'administrasi',
    'rujukan',
    'kuitansi',
    'tagihan',
    'aplikasi',
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    final raw = _persist.loadVocabHistory();
    setState(() {
      _history = raw.map((m) => VocabularyExplanation(
            word: m['word'] as String? ?? '',
            meaning: m['meaning'] as String? ?? '',
            example: m['example'] as String?,
          )).toList();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _explain(String input) async {
    final q = input.trim();
    if (q.isEmpty) return;
    if (_isLoading) return;

    if (!_gemma.isLoaded) {
      setState(() => _error = 'Model Gemma belum siap. Tunggu sebentar atau buka Pengaturan → Model AI Lokal.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _controller.clear();
    });

    // Scroll ke atas agar loading card terlihat
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    final result = await _gemma.explainVocabulary(q);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result != null) {
        // Dedupe: hapus entry lama untuk kata yang sama (jika ada)
        _history.removeWhere(
            (e) => e.word.toLowerCase() == result.word.toLowerCase());
        _history.insert(0, result);
      } else {
        _error = 'Gagal menjelaskan kata ini. Coba lagi.';
      }
    });

    // Simpan ke Hive
    if (result != null) {
      await _persist.saveVocabEntry(result.word, {
        'word': result.word,
        'meaning': result.meaning,
        'example': result.example,
        'savedAt': DateTime.now().toIso8601String(),
      });
    }
  }

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
          'Kamus Pintar',
          style: GoogleFonts.plusJakartaSans(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Sticky input area ───────────────────────────────────────
          _buildInputArea(),
          // ── Scrollable content ──────────────────────────────────────
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  // ── Input area (pinned di atas) ─────────────────────────────────────────

  Widget _buildInputArea() {
    return Container(
      color: AppColors.background,
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
                fillColor: AppColors.surfaceContainerLow,
                prefixIcon: Icon(Icons.search_rounded, color: AppColors.primary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              ),
            ),
          ),
          SizedBox(width: 10),
          SizedBox(
            height: 48,
            width: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : () => _explain(_controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
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
          ),
        ],
      ),
    );
  }

  // ── Scrollable content list ─────────────────────────────────────────────

  Widget _buildContent() {
    return ListView(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        // Hero banner
        _buildHero(),
        SizedBox(height: 12),

        // Error banner
        if (_error != null) _buildError(),

        // Loading card
        if (_isLoading) _loadingCard(),

        // Quick chip suggestions (saat belum ada history)
        if (_history.isEmpty && !_isLoading) ...[
          SizedBox(height: 4),
          _buildChips(),
          SizedBox(height: 16),
          _buildEmptyHint(),
        ],

        // Result cards
        if (_history.isNotEmpty && !_isLoading) ...[
          _buildHistoryHeader(),
          SizedBox(height: 8),
        ],
        for (final exp in _history) ...[
          _vocabCard(exp),
          SizedBox(height: 12),
        ],
      ],
    );
  }

  // ── Widgets ─────────────────────────────────────────────────────────────

  Widget _buildHero() {
    return Container(
      margin: EdgeInsets.only(top: 8),
      padding: EdgeInsets.all(14),
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
              mainAxisSize: MainAxisSize.min,
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
    );
  }

  Widget _buildError() {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.error.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: AppColors.error),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: GoogleFonts.beVietnamPro(
                  fontSize: 12.5, color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryHeader() {
    return Row(
      children: [
        Icon(Icons.history_rounded, size: 14, color: AppColors.textSecondary),
        SizedBox(width: 6),
        Text(
          'Terakhir dicari',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
        Spacer(),
        GestureDetector(
          onTap: _confirmClearHistory,
          child: Text(
            'Hapus semua',
            style: GoogleFonts.beVietnamPro(
              fontSize: 12,
              color: AppColors.error.withOpacity(0.7),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmClearHistory() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xxl)),
        title: Text('Hapus riwayat kamus?',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, fontSize: 16)),
        content: Text('Semua kata yang pernah dicari akan dihapus.',
            style: GoogleFonts.beVietnamPro(
                fontSize: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal',
                style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _persist.clearVocabHistory();
              if (mounted) setState(() => _history.clear());
            },
            child: Text('Hapus',
                style: GoogleFonts.plusJakartaSans(
                    color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _quickSuggestions.map((w) {
        return GestureDetector(
          onTap: _isLoading ? null : () => _explain(w),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Text(
              w,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12.5,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyHint() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 32),
          Icon(Icons.auto_stories_rounded,
              size: 56, color: AppColors.textPrimary.withOpacity(0.15)),
          SizedBox(height: 14),
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
    );
  }

  Widget _loadingCard() {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
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
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
            'ARTI',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary.withOpacity(0.45),
              letterSpacing: 1.0,
            ),
          ),
          SizedBox(height: 4),
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
              'CONTOH',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary.withOpacity(0.45),
                letterSpacing: 1.0,
              ),
            ),
            SizedBox(height: 4),
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
    );
  }
}
