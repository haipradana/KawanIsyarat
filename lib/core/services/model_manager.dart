import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

/// Types of AI models used in the app.
enum ModelType {
  gemmaLLM,
  whisperSTT,
}

/// Manages downloading, caching, and locating model weight files.
class ModelManager {
  static final ModelManager _instance = ModelManager._internal();
  factory ModelManager() => _instance;
  ModelManager._internal();

  // Pre-converted model URLs hosted on HuggingFace
  static const _modelUrls = {
    ModelType.gemmaLLM:
        'https://huggingface.co/haipradana/kawan-isyarat-gemma-c/resolve/main/gemma-4-E2B-it-int4.zip',
    ModelType.whisperSTT:
        'https://huggingface.co/haipradana/kawan-isyarat-gemma-c/resolve/main/whisper-tiny-id-cactus.zip',
  };

  static const _modelDirNames = {
    ModelType.gemmaLLM: 'gemma-4-E2B-it-int4',
    ModelType.whisperSTT: 'whisper-tiny-id-cactus',
  };

  static const _modelDisplayNames = {
    ModelType.gemmaLLM: 'Gemma 4 E2B (AI Bahasa)',
    ModelType.whisperSTT: 'Whisper Tiny ID (Speech-to-Text)',
  };

  String? _modelsBasePath;

  /// Get the base directory for storing models.
  Future<String> get _basePath async {
    if (_modelsBasePath != null) return _modelsBasePath!;
    final appDir = await getApplicationDocumentsDirectory();
    _modelsBasePath = '${appDir.path}/cactus_models';
    return _modelsBasePath!;
  }

  /// Get the display name for a model type.
  String getDisplayName(ModelType type) => _modelDisplayNames[type] ?? 'Unknown';

  /// Get the local directory path for a model.
  Future<String> getModelPath(ModelType type) async {
    final base = await _basePath;
    return '$base/${_modelDirNames[type]}';
  }

  /// Check if a model is already downloaded and ready.
  Future<bool> isModelReady(ModelType type) async {
    final modelPath = await getModelPath(type);
    final dir = Directory(modelPath);
    if (!await dir.exists()) return false;

    // Check if directory has files (not empty)
    final files = await dir.list().toList();
    return files.isNotEmpty;
  }

  /// Get total estimated download size for both models.
  String get estimatedTotalSize => '~5.2 GB';

  /// Download a model with progress callback.
  /// Returns the local path to the extracted model directory.
  Future<String> downloadModel(
    ModelType type, {
    void Function(double progress, String status)? onProgress,
  }) async {
    final url = _modelUrls[type]!;
    final modelPath = await getModelPath(type);
    final modelDir = Directory(modelPath);

    // Check if already downloaded
    if (await modelDir.exists()) {
      final files = await modelDir.list().toList();
      if (files.isNotEmpty) {
        onProgress?.call(1.0, 'Sudah tersedia');
        return modelPath;
      }
    }

    // Create base directory
    final baseDir = Directory(await _basePath);
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final zipPath = '$modelPath.zip';
    final zipFile = File(zipPath);

    try {
      // Download the zip file
      onProgress?.call(0.0, 'Menghubungkan ke server...');

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      var receivedBytes = 0;

      final sink = zipFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final progress = receivedBytes / totalBytes;
          final mbReceived = (receivedBytes / 1024 / 1024).toStringAsFixed(1);
          final mbTotal = (totalBytes / 1024 / 1024).toStringAsFixed(1);
          onProgress?.call(
            progress * 0.9, // 0-90% for download
            'Mengunduh $mbReceived/$mbTotal MB',
          );
        } else {
          final mbReceived = (receivedBytes / 1024 / 1024).toStringAsFixed(1);
          onProgress?.call(0.5, 'Mengunduh $mbReceived MB...');
        }
      }

      await sink.close();
      client.close();

      // Extract the zip file
      onProgress?.call(0.9, 'Mengekstrak model...');
      await _extractZip(zipPath, modelPath);

      // Delete the zip file to save space
      onProgress?.call(0.95, 'Membersihkan...');
      if (await zipFile.exists()) {
        await zipFile.delete();
      }

      onProgress?.call(1.0, 'Selesai!');
      return modelPath;
    } catch (e) {
      // Clean up on failure
      if (await zipFile.exists()) {
        await zipFile.delete();
      }
      rethrow;
    }
  }

  /// Extract a zip file to a directory.
  /// Uses system unzip command for efficiency.
  Future<void> _extractZip(String zipPath, String destPath) async {
    final destDir = Directory(destPath);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }

    // Use system unzip for large files (more efficient than Dart archive lib)
    final result = await Process.run('unzip', ['-o', zipPath, '-d', destPath]);
    if (result.exitCode != 0) {
      throw Exception('Failed to extract zip: ${result.stderr}');
    }
  }

  /// Delete all downloaded models to free space.
  Future<void> clearAllModels() async {
    final base = await _basePath;
    final dir = Directory(base);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Delete a specific model.
  Future<void> clearModel(ModelType type) async {
    final modelPath = await getModelPath(type);
    final dir = Directory(modelPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Get total size of downloaded models in bytes.
  Future<int> getDownloadedSize() async {
    final base = await _basePath;
    final dir = Directory(base);
    if (!await dir.exists()) return 0;

    int totalSize = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }
}
