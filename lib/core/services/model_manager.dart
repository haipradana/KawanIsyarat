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

  // Model URLs — both Cactus SDK format (zip with weights)
  static const _modelUrls = {
    ModelType.gemmaLLM:
        'https://huggingface.co/Cactus-Compute/gemma-4-E2B-it/resolve/main/weights/gemma-4-e2b-it-int4.zip',
    ModelType.whisperSTT:
        'https://huggingface.co/Cactus-Compute/whisper-base/resolve/main/weights/whisper-base-int8.zip',
  };

  static const _modelDirNames = {
    // Both are dir-based (Cactus zip extraction)
    ModelType.gemmaLLM: 'gemma-4-e2b-it-int4',
    ModelType.whisperSTT: 'whisper-base-int8',
  };

  static const _modelDisplayNames = {
    ModelType.gemmaLLM: 'Gemma 4 E2B Cactus INT4 (AI Bahasa)',
    ModelType.whisperSTT: 'Whisper Base INT8 (Speech-to-Text)',
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

  /// Get the local path for a model.
  /// Gemma → single .task file path
  /// Whisper → directory path
  Future<String> getModelPath(ModelType type) async {
    final base = await _basePath;
    return '$base/${_modelDirNames[type]}';
  }

  /// Check if a model is already downloaded and ready.
  /// Both models are directory-based (Cactus zip extraction).
  Future<bool> isModelReady(ModelType type) async {
    final modelPath = await getModelPath(type);
    final dir = Directory(modelPath);
    if (!await dir.exists()) return false;
    final files = await dir.list().toList();
    return files.isNotEmpty;
  }

  /// Get total estimated download size for both models.
  String get estimatedTotalSize => '~4.2 GB';

  /// Download a model with progress callback.
  /// Supports resume — if a partial .zip exists, it continues from where it left off.
  /// Returns the local path to the extracted model directory.
  Future<String> downloadModel(
    ModelType type, {
    void Function(double progress, String status)? onProgress,
  }) async {
    final url = _modelUrls[type]!;
    final modelPath = await getModelPath(type);

    // Both models: zip-based Cactus download + extract
    final modelDir = Directory(modelPath);

    // Check if already downloaded and extracted
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
      // Check for existing partial download
      int existingBytes = 0;
      if (await zipFile.exists()) {
        existingBytes = await zipFile.length();
        onProgress?.call(0.0, 'Melanjutkan download (${(existingBytes / 1024 / 1024).toStringAsFixed(1)} MB sudah ada)...');
      } else {
        onProgress?.call(0.0, 'Menghubungkan ke server...');
      }

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));

      // Add Range header for resume
      if (existingBytes > 0) {
        request.headers['Range'] = 'bytes=$existingBytes-';
      }

      final response = await client.send(request);

      // Check if server supports resume
      final bool isResume = response.statusCode == 206 && existingBytes > 0;
      final bool isFull = response.statusCode == 200;

      if (!isResume && !isFull) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      // If server doesn't support Range (returns 200 instead of 206),
      // restart from scratch
      if (isFull && existingBytes > 0) {
        existingBytes = 0;
        // Truncate the file
        if (await zipFile.exists()) {
          await zipFile.delete();
        }
      }

      // Calculate total size
      int totalBytes;
      if (isResume) {
        // Content-Range: bytes 12345-67890/67891
        final contentRange = response.headers['content-range'] ?? '';
        final match = RegExp(r'/(\d+)').firstMatch(contentRange);
        totalBytes = match != null ? int.parse(match.group(1)!) : (existingBytes + (response.contentLength ?? 0));
      } else {
        totalBytes = response.contentLength ?? 0;
      }

      var receivedBytes = existingBytes;

      // Open file for append (resume) or write (new)
      final sink = zipFile.openWrite(mode: isResume ? FileMode.append : FileMode.write);

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final progress = receivedBytes / totalBytes;
          final mbReceived = (receivedBytes / 1024 / 1024).toStringAsFixed(1);
          final mbTotal = (totalBytes / 1024 / 1024).toStringAsFixed(1);
          onProgress?.call(
            progress * 0.9, // 0-90% for download
            '${isResume ? "Melanjutkan" : "Mengunduh"} $mbReceived/$mbTotal MB',
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
      // DON'T delete partial zip — keep it for resume on retry!
      // Only delete if extraction failed (zip is likely corrupt)
      rethrow;
    }
  }

  /// Download a single file directly (no zip extraction).
  /// Supports resume — if a partial file exists, continues from where it left off.
  /// Returns the local path to the downloaded file.
  // ignore: unused_element
  Future<String> _downloadFile(
    String url,
    String destPath, {
    void Function(double progress, String status)? onProgress,
  }) async {
    // Create base directory if needed
    final baseDir = Directory(await _basePath);
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }

    final destFile = File(destPath);

    // Check for existing partial download
    int existingBytes = 0;
    if (await destFile.exists()) {
      existingBytes = await destFile.length();
      if (existingBytes > 1024 * 1024) {
        onProgress?.call(0.0, 'Melanjutkan download (${(existingBytes / 1024 / 1024).toStringAsFixed(0)} MB sudah ada)...');
      }
    } else {
      onProgress?.call(0.0, 'Menghubungkan ke server...');
    }

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));

      // Add Range header for resume
      if (existingBytes > 0) {
        request.headers['Range'] = 'bytes=$existingBytes-';
      }

      final response = await client.send(request);

      final bool isResume = response.statusCode == 206 && existingBytes > 0;
      final bool isFull = response.statusCode == 200;

      if (!isResume && !isFull) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      // If server returned 200 instead of 206, restart from scratch
      if (isFull && existingBytes > 0) {
        existingBytes = 0;
        await destFile.delete();
      }

      // Calculate total size
      int totalBytes;
      if (isResume) {
        final contentRange = response.headers['content-range'] ?? '';
        final match = RegExp(r'/(\d+)').firstMatch(contentRange);
        totalBytes = match != null
            ? int.parse(match.group(1)!)
            : (existingBytes + (response.contentLength ?? 0));
      } else {
        totalBytes = response.contentLength ?? 0;
      }

      var receivedBytes = existingBytes;
      final sink = destFile.openWrite(mode: isResume ? FileMode.append : FileMode.write);

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final progress = receivedBytes / totalBytes;
          final mbReceived = (receivedBytes / 1024 / 1024).toStringAsFixed(0);
          final mbTotal = (totalBytes / 1024 / 1024).toStringAsFixed(0);
          onProgress?.call(
            progress,
            '${isResume ? "Melanjutkan" : "Mengunduh"} $mbReceived/$mbTotal MB',
          );
        } else {
          final mbReceived = (receivedBytes / 1024 / 1024).toStringAsFixed(0);
          onProgress?.call(0.5, 'Mengunduh $mbReceived MB...');
        }
      }

      await sink.close();
      onProgress?.call(1.0, 'Selesai!');
      return destPath;
    } finally {
      client.close();
    }
  }

  /// Extract a zip file to a directory.
  /// Uses system unzip command for efficiency.
  /// Handles nested directories: if zip extracts a single subfolder, moves contents up.
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

    // Check if config.txt is directly in destPath
    final configDirect = File('$destPath/config.txt');
    if (await configDirect.exists()) return; // Good, flat extraction

    // If not, check for a single subfolder containing config.txt
    // (some zips extract as folder/config.txt instead of config.txt)
    final entries = await destDir.list().toList();
    if (entries.length == 1 && entries.first is Directory) {
      final subDir = entries.first as Directory;
      final subConfig = File('${subDir.path}/config.txt');
      if (await subConfig.exists()) {
        // Move all files from subfolder up to destPath
        await for (final entity in subDir.list()) {
          final name = entity.path.split('/').last;
          if (entity is File) {
            await entity.rename('$destPath/$name');
          } else if (entity is Directory) {
            await Process.run('mv', [entity.path, '$destPath/$name']);
          }
        }
        // Remove now-empty subfolder
        await subDir.delete(recursive: true);
      }
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
