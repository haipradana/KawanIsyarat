import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import '../../../app/constants.dart';

/// Widget pratinjau video isyarat BISINDO untuk sebuah kata.
///
/// Mencari asset di `assets/videos/bisindo/<word>.mp4`.
/// Kalau file tidak ada (mis. dataset belum lengkap), akan fallback
/// ke placeholder ikon — tidak crash.
///
/// Auto-play + loop + mute untuk demo flow.
class BisindoVideoPreview extends StatefulWidget {
  final String word;
  final double aspectRatio;
  const BisindoVideoPreview({
    super.key,
    required this.word,
    this.aspectRatio = 16 / 10,
  });

  @override
  State<BisindoVideoPreview> createState() => _BisindoVideoPreviewState();
}

class _BisindoVideoPreviewState extends State<BisindoVideoPreview> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _missing = false;
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    _loadVideo();
  }

  @override
  void didUpdateWidget(covariant BisindoVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.word != widget.word) {
      _disposeController();
      setState(() {
        _loading = true;
        _missing = false;
      });
      _loadVideo();
    }
  }

  Future<void> _loadVideo() async {
    final assetPath =
        'assets/videos/bisindo/${widget.word.toLowerCase()}.mp4';
    // Cek eksistensi asset supaya tidak crash saat file belum ada.
    try {
      await rootBundle.load(assetPath);
    } catch (_) {
      if (mounted) {
        setState(() {
          _missing = true;
          _loading = false;
        });
      }
      return;
    }
    try {
      final controller = VideoPlayerController.asset(assetPath);
      await controller.initialize();
      controller.setLooping(true);
      controller.setVolume(_muted ? 0 : 1);
      await controller.play();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _missing = true;
          _loading = false;
        });
      }
    }
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_loading)
              _placeholder(
                icon: Icons.hourglass_top_rounded,
                label: 'Memuat pratinjau…',
              )
            else if (_missing || _controller == null)
              _placeholder(
                icon: Icons.movie_filter_outlined,
                label: 'Video demo segera hadir',
                sub: 'Kata "${widget.word}" belum punya klip',
              )
            else
              Container(
                color: Colors.black,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              ),
            if (_controller != null && !_missing)
              Positioned(
                right: 8,
                bottom: 8,
                child: Material(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    onTap: _toggleMute,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(
                        _muted
                            ? Icons.volume_off_rounded
                            : Icons.volume_up_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ),
            if (_controller != null && !_missing)
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 5),
                      Text(
                        'DEMO',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(
      {required IconData icon, required String label, String? sub}) {
    return Container(
      color: AppColors.textPrimary.withOpacity(0.06),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: AppColors.primary.withOpacity(0.7)),
          SizedBox(height: 10),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.primary.withOpacity(0.8),
              letterSpacing: 1.1,
            ),
          ),
          if (sub != null) ...[
            SizedBox(height: 2),
            Text(
              sub,
              style: GoogleFonts.beVietnamPro(
                fontSize: 11,
                color: AppColors.textPrimary.withOpacity(0.45),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
