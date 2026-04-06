import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import '../../../app/constants.dart';
import '../../../core/services/yolo_alphabet_service.dart';

/// Alphabet practice screen — YOLO11n one-shot detector.
///
/// Pipeline: Camera → takePicture → decode JPEG → YOLO → letter + bbox
/// No palm detection or hand crop needed — YOLO handles it directly.
class AlphabetPracticeScreen extends StatefulWidget {
  final String targetLetter;

  const AlphabetPracticeScreen({super.key, required this.targetLetter});

  @override
  State<AlphabetPracticeScreen> createState() => _AlphabetPracticeScreenState();
}

enum _Phase { preparing, countdown, analyzing, result }

class _AlphabetPracticeScreenState extends State<AlphabetPracticeScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  final YoloAlphabetService _yolo = YoloAlphabetService();

  bool _isInitialized = false;
  String? _error;
  bool _disposed = false;

  _Phase _phase = _Phase.preparing;
  YoloDetectionResult? _lastResult;
  bool _isCorrect = false;
  int _correctCount = 0;
  int _totalCount = 0;
  String _debugInfo = '';
  bool _isFrontCamera = false;

  late AnimationController _countdownController;
  Timer? _phaseTimer;

  static const _countdownDuration = Duration(milliseconds: 2500);
  static const _resultDuration = Duration(milliseconds: 2000);

  @override
  void initState() {
    super.initState();
    _countdownController = AnimationController(
      vsync: this,
      duration: _countdownDuration,
    );
    _init();
  }

  Future<void> _init() async {
    try {
      // Camera permission
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() => _error = 'Izin kamera diperlukan untuk fitur ini');
        return;
      }

      // Camera
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'Tidak ada kamera tersedia');
        return;
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _isFrontCamera = camera.lensDirection == CameraLensDirection.front;

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      // Load YOLO model
      await _yolo.initialize();
      debugPrint('[Practice] YOLO loaded');

      if (mounted && !_disposed) {
        setState(() {
          _isInitialized = true;
          _phase = _Phase.countdown;
        });
        _startCountdown();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Gagal memulai: ${e.toString()}');
      }
    }
  }

  void _startCountdown() {
    if (_disposed) return;
    _countdownController.reset();
    _countdownController.forward();

    _phaseTimer?.cancel();
    _phaseTimer = Timer(_countdownDuration, () {
      if (!_disposed && mounted) _captureAndAnalyze();
    });
  }

  Future<void> _captureAndAnalyze() async {
    if (_disposed || !mounted) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    setState(() => _phase = _Phase.analyzing);

    try {
      // Step 1: Capture image
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();

      // Step 2: Decode JPEG → RGBA
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        _showResult(null, 'Decode JPEG gagal');
        return;
      }

      final rgba = Uint8List(decoded.width * decoded.height * 4);
      int idx = 0;
      for (int y = 0; y < decoded.height; y++) {
        for (int x = 0; x < decoded.width; x++) {
          final pixel = decoded.getPixel(x, y);
          rgba[idx++] = pixel.r.toInt();
          rgba[idx++] = pixel.g.toInt();
          rgba[idx++] = pixel.b.toInt();
          rgba[idx++] = 255;
        }
      }

      debugPrint('[Practice] Image: ${decoded.width}×${decoded.height}');

      // Step 3: YOLO detection — one shot, no crop needed
      final result = _yolo.detect(
        rgbaBytes: rgba,
        imageWidth: decoded.width,
        imageHeight: decoded.height,
      );

      final info = result != null
          ? 'YOLO: ${result.letter} ${(result.confidence * 100).toInt()}% | ${decoded.width}×${decoded.height}'
          : 'Img: ${decoded.width}×${decoded.height} | Tidak terdeteksi';

      _showResult(result, info);
    } catch (e) {
      debugPrint('[Practice] Error: $e');
      _showResult(null, 'Error: $e');
    }
  }

  void _showResult(YoloDetectionResult? result, String debug) {
    if (_disposed || !mounted) return;

    _totalCount++;
    final correct = result != null && result.letter == widget.targetLetter;
    if (correct) _correctCount++;

    setState(() {
      _phase = _Phase.result;
      _lastResult = result;
      _isCorrect = correct;
      _debugInfo = debug;
    });

    // Auto-retry
    _phaseTimer?.cancel();
    _phaseTimer = Timer(_resultDuration, () {
      if (!_disposed && mounted) {
        setState(() => _phase = _Phase.countdown);
        _startCountdown();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _phaseTimer?.cancel();
    _countdownController.dispose();
    _cameraController?.dispose();
    _yolo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Camera preview
            if (_isInitialized && _cameraController != null)
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _cameraController!.value.previewSize?.height ?? 1,
                    height: _cameraController!.value.previewSize?.width ?? 1,
                    child: CameraPreview(_cameraController!),
                  ),
                ),
              ),

            // Bounding box overlay from YOLO result
            if (_isInitialized && _lastResult != null && _phase == _Phase.result)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return CustomPaint(
                      painter: _YoloBboxPainter(
                        bbox: _lastResult!.bbox,
                        label: '${_lastResult!.letter} ${(_lastResult!.confidence * 100).toInt()}%',
                        canvasWidth: constraints.maxWidth,
                        canvasHeight: constraints.maxHeight,
                        isCorrect: _isCorrect,
                        isFrontCamera: _isFrontCamera,
                      ),
                    );
                  },
                ),
              ),

            // Countdown indicator
            if (_isInitialized && _phase == _Phase.countdown)
              Center(child: _buildCountdown()),

            // Analyzing indicator
            if (_isInitialized && _phase == _Phase.analyzing)
              Center(
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black38,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),

            // Loading
            if (!_isInitialized && _error == null)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppColors.primary),
                    SizedBox(height: 16),
                    Text(
                      'Memuat model AI...',
                      style: GoogleFonts.beVietnamPro(
                        color: Colors.white70, fontSize: 14),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'YOLO11n Alphabet Detector',
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),

            // Error
            if (_error != null)
              Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded,
                          color: AppColors.error, size: 48),
                      SizedBox(height: 16),
                      Text(
                        _error!,
                        style: GoogleFonts.beVietnamPro(
                          color: Colors.white, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => context.pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white),
                        child: Text('Kembali'),
                      ),
                    ],
                  ),
                ),
              ),

            // Top bar
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () => context.pop(),
                    ),
                    Spacer(),
                    _targetBadge(),
                    Spacer(),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_correctCount/$_totalCount',
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom panel
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.9),
                      Colors.black.withOpacity(0.5),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildResultPanel(),
                    if (_debugInfo.isNotEmpty) ...[
                      SizedBox(height: 6),
                      Text(
                        _debugInfo,
                        style: GoogleFonts.jetBrainsMono(
                          color: Colors.white38, fontSize: 10),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Success flash
            if (_phase == _Phase.result && _isCorrect)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(color: AppColors.success.withOpacity(0.12))
                      .animate()
                      .fadeIn(duration: 200.ms)
                      .then()
                      .fadeOut(duration: 600.ms, delay: 800.ms),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdown() {
    return AnimatedBuilder(
      animation: _countdownController,
      builder: (_, __) => SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: _countdownController.value,
              strokeWidth: 3,
              color: Colors.white.withOpacity(0.6),
              backgroundColor: Colors.white.withOpacity(0.12),
            ),
            Icon(Icons.camera_alt_rounded,
              color: Colors.white.withOpacity(0.4), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _targetBadge() {
    final isOk = _isCorrect && _phase == _Phase.result;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isOk
            ? AppColors.success.withOpacity(0.3)
            : Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
          color: isOk
              ? AppColors.success.withOpacity(0.6)
              : Colors.white30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Target: ',
            style: GoogleFonts.beVietnamPro(
              color: Colors.white70, fontSize: 13)),
          Text(widget.targetLetter,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800)),
          if (isOk) ...[
            SizedBox(width: 4),
            Icon(Icons.check_circle, color: AppColors.success, size: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildResultPanel() {
    switch (_phase) {
      case _Phase.preparing:
        return _pill(Icons.hourglass_top_rounded, 'Mempersiapkan...',
            Colors.white60);
      case _Phase.countdown:
        return _pill(Icons.front_hand_rounded,
            'Tunjukkan isyarat "${widget.targetLetter}" ke kamera',
            Colors.white60);
      case _Phase.analyzing:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white54)),
            SizedBox(width: 10),
            Text('Menganalisis...',
              style: GoogleFonts.beVietnamPro(
                color: Colors.white60, fontSize: 14)),
          ],
        );
      case _Phase.result:
        if (_lastResult == null) {
          return _resultCard(
            Icons.search_off_rounded,
            Colors.white54,
            'Tangan tidak terdeteksi',
            'Pastikan tangan terlihat jelas di kamera',
          );
        }
        if (_isCorrect) {
          return _resultCard(
            Icons.check_circle_rounded,
            AppColors.success,
            'Benar! "${_lastResult!.letter}" ✨',
            '${(_lastResult!.confidence * 100).toStringAsFixed(1)}% confidence',
          );
        }
        return _resultCard(
          Icons.close_rounded,
          AppColors.error,
          'Terdeteksi: "${_lastResult!.letter}"',
          'Target "${widget.targetLetter}" — ${(_lastResult!.confidence * 100).toStringAsFixed(1)}%',
        );
    }
  }

  Widget _pill(IconData icon, String text, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(width: 10),
          Flexible(
            child: Text(text,
              style: GoogleFonts.beVietnamPro(color: color, fontSize: 14),
              textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(IconData icon, Color c, String title, String sub) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: c.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: c, size: 28),
          SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                  style: GoogleFonts.plusJakartaSans(
                    color: c == Colors.white54 ? Colors.white : c,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
                Text(sub,
                  style: GoogleFonts.beVietnamPro(
                    color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).scale(
      begin: Offset(0.97, 0.97), duration: 250.ms);
  }
}

/// Draws YOLO bounding box on the camera preview.
class _YoloBboxPainter extends CustomPainter {
  final YoloBBox bbox;
  final String label;
  final double canvasWidth, canvasHeight;
  final bool isCorrect;
  final bool isFrontCamera;

  const _YoloBboxPainter({
    required this.bbox,
    required this.label,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.isCorrect,
    this.isFrontCamera = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final color = isCorrect ? const Color(0xFF4CAF50) : const Color(0xFFFF9800);

    // Front camera: mirror X coords for display
    final double displayXMin;
    final double displayXMax;
    if (isFrontCamera) {
      displayXMin = (1.0 - bbox.xMax) * canvasWidth;
      displayXMax = (1.0 - bbox.xMin) * canvasWidth;
    } else {
      displayXMin = bbox.xMin * canvasWidth;
      displayXMax = bbox.xMax * canvasWidth;
    }

    final rect = Rect.fromLTRB(
      displayXMin,
      bbox.yMin * canvasHeight,
      displayXMax,
      bbox.yMax * canvasHeight,
    );

    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(8)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // Fill
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(8)),
      Paint()
        ..color = color.withOpacity(0.08)
        ..style = PaintingStyle.fill,
    );

    // Label
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(rect.left + 6, rect.top - 18));
  }

  @override
  bool shouldRepaint(covariant _YoloBboxPainter old) =>
      bbox != old.bbox || isCorrect != old.isCorrect || label != old.label;
}
