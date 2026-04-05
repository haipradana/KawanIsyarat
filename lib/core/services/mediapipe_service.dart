import 'dart:math';
import 'dart:ui';

/// MediaPipe Holistic keypoint extraction service.
/// 
/// CURRENT: Stub with realistic mock keypoints.
/// TODO: Replace with actual MediaPipe Tasks API via platform channel.
/// 
/// Keypoint format (258 floats total):
///   [0..131]   = pose landmarks (33 × 4: x,y,z,visibility)
///   [132..194] = left hand landmarks (21 × 3: x,y,z)
///   [195..257] = right hand landmarks (21 × 3: x,y,z)
class MediaPipeService {
  static final MediaPipeService _instance = MediaPipeService._internal();
  factory MediaPipeService() => _instance;
  MediaPipeService._internal();

  bool _isActive = false;
  final Random _random = Random();

  void startCapture() => _isActive = true;
  void stopCapture() => _isActive = false;
  bool get isActive => _isActive;

  /// Extract keypoints from a camera frame.
  /// 
  /// Returns List<double> of length 258.
  /// 
  /// CURRENT IMPLEMENTATION: Stub with realistic random values.
  /// The shape is correct so LSTM integration works once MediaPipe is real.
  List<double> extractKeypoints(dynamic frame) {
    if (!_isActive) return List.filled(258, 0.0);

    final keypoints = <double>[];

    // Pose: 33 landmarks × 4 (x, y, z, visibility)
    for (int i = 0; i < 33; i++) {
      keypoints.add(0.3 + _random.nextDouble() * 0.4); // x: 0.3–0.7
      keypoints.add(0.2 + _random.nextDouble() * 0.6); // y: 0.2–0.8
      keypoints.add(_random.nextDouble() * 0.1 - 0.05); // z: small
      keypoints.add(0.8 + _random.nextDouble() * 0.2);  // vis: 0.8–1.0
    }

    // Left hand: 21 landmarks × 3 (x, y, z)
    for (int i = 0; i < 21; i++) {
      keypoints.add(0.2 + _random.nextDouble() * 0.3); // x: left side
      keypoints.add(0.3 + _random.nextDouble() * 0.5); // y
      keypoints.add(_random.nextDouble() * 0.05);       // z
    }

    // Right hand: 21 landmarks × 3 (x, y, z)
    for (int i = 0; i < 21; i++) {
      keypoints.add(0.5 + _random.nextDouble() * 0.3); // x: right side
      keypoints.add(0.3 + _random.nextDouble() * 0.5); // y
      keypoints.add(_random.nextDouble() * 0.05);       // z
    }

    return keypoints;
  }

  /// Get hand landmark screen positions for skeleton overlay.
  /// Returns 21 Offset points for the right hand.
  List<Offset> getHandLandmarkPositions(
    List<double> keypoints,
    Size canvasSize,
  ) {
    final positions = <Offset>[];
    if (keypoints.length < 258) return positions;

    // Right hand landmarks start at index 195, 21 landmarks × 3 values
    for (int i = 0; i < 21; i++) {
      final x = keypoints[195 + i * 3] * canvasSize.width;
      final y = keypoints[195 + i * 3 + 1] * canvasSize.height;
      positions.add(Offset(x, y));
    }

    return positions;
  }
}
