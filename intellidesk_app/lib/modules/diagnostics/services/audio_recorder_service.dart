import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Recording status lifecycle for UI binding
enum AudioRecorderStatus {
  idle,
  requestingPermission,
  permissionDenied,
  recording,
  recorded,
  error,
}

/// Structured result of an audio recording session
class AudioRecordingResult {
  final Uint8List wavBytes;
  final Duration duration;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final String fileName;
  final DateTime recordedAt;

  const AudioRecordingResult({
    required this.wavBytes,
    required this.duration,
    this.sampleRate = 16000,
    this.channels = 1,
    this.bitsPerSample = 16,
    required this.fileName,
    required this.recordedAt,
  });

  int get byteLength => wavBytes.length;
  double get durationSeconds => duration.inMilliseconds / 1000.0;
}

/// Abstract contract for Audio Recording to facilitate headless test mocking
abstract class AudioRecorderInterface {
  AudioRecorderStatus get status;
  int get remainingSeconds;
  Future<bool> requestMicPermission();
  Future<void> start5SecondRecording({VoidCallback? onComplete});
  Future<AudioRecordingResult?> stopRecording();
  void cancel();
  void dispose();
}

/// Production Audio Recording Service with hardware microphone capture & silence rejection
class AudioRecorderService extends ChangeNotifier implements AudioRecorderInterface {
  AudioRecorderStatus _status = AudioRecorderStatus.idle;
  int _remainingSeconds = 5;
  Timer? _countdownTimer;
  AudioRecordingResult? _lastResult;
  String? _errorMessage;

  // Hardware recorder instance
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentRecordingPath;

  // Injection points for testing
  final Future<PermissionStatus> Function()? permissionCheckOverride;
  final Future<PermissionStatus> Function()? permissionRequestOverride;
  final Future<Uint8List> Function(Duration duration)? customByteGenerator;

  static const int targetSampleRate = 16000;
  static const int targetChannels = 1;
  static const int targetBitsPerSample = 16;
  static const int targetDurationSeconds = 5;

  AudioRecorderService({
    this.permissionCheckOverride,
    this.permissionRequestOverride,
    this.customByteGenerator,
  });

  @override
  AudioRecorderStatus get status => _status;

  @override
  int get remainingSeconds => _remainingSeconds;

  AudioRecordingResult? get lastResult => _lastResult;
  String? get errorMessage => _errorMessage;

  /// Gracefully checks and requests microphone permission across platforms
  @override
  Future<bool> requestMicPermission() async {
    _status = AudioRecorderStatus.requestingPermission;
    _errorMessage = null;
    notifyListeners();

    try {
      // 1. Request via permission_handler
      bool handlerGranted = false;
      if (permissionRequestOverride != null) {
        final status = await permissionRequestOverride!();
        handlerGranted = status.isGranted;
      } else {
        final status = await Permission.microphone.request();
        handlerGranted = status.isGranted;
      }

      // 2. Also check via record plugin native interface
      bool recordPluginGranted = false;
      try {
        recordPluginGranted = await _audioRecorder.hasPermission();
      } catch (recErr) {
        debugPrint('⚠️ [AudioRecorderService] Native record permission check: $recErr');
        recordPluginGranted = handlerGranted;
      }

      if (handlerGranted || recordPluginGranted) {
        _status = AudioRecorderStatus.idle;
        notifyListeners();
        return true;
      } else {
        _status = AudioRecorderStatus.permissionDenied;
        _errorMessage = 'Microphone permission denied. Microphone access is required to analyze cough biomarkers. Please grant microphone permission in device settings.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('⚠️ [AudioRecorderService] Permission request error: $e');
      _status = AudioRecorderStatus.permissionDenied;
      _errorMessage = 'Microphone permission denied. Microphone access is required to analyze cough biomarkers.';
      notifyListeners();
      return false;
    }
  }

  /// Initiates a standardized 5-second clinical acoustic intake from hardware microphone
  @override
  Future<void> start5SecondRecording({VoidCallback? onComplete}) async {
    final hasPermission = await requestMicPermission();
    if (!hasPermission) {
      debugPrint('⛔ [AudioRecorderService] Microphone permission not granted. Cannot record.');
      return;
    }

    _status = AudioRecorderStatus.recording;
    _remainingSeconds = targetDurationSeconds;
    _errorMessage = null;
    _lastResult = null;
    notifyListeners();

    // Start hardware microphone stream recording to temp WAV file
    try {
      if (customByteGenerator == null) {
        final tempDir = await getTemporaryDirectory();
        _currentRecordingPath = '${tempDir.path}/cough_rec_${DateTime.now().millisecondsSinceEpoch}.wav';
        
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: targetSampleRate,
            numChannels: targetChannels,
            bitRate: 256000,
          ),
          path: _currentRecordingPath!,
        );
        debugPrint('🎙️ [AudioRecorderService] Hardware microphone recording started -> $_currentRecordingPath');
      }
    } catch (e) {
      debugPrint('🚨 [AudioRecorderService] Failed to start hardware microphone recording: $e');
      _status = AudioRecorderStatus.error;
      _errorMessage = 'Failed to start microphone recording ($e). Please verify microphone permissions.';
      notifyListeners();
      return;
    }

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _remainingSeconds--;
      notifyListeners();

      if (_remainingSeconds <= 0) {
        timer.cancel();
        await _finalizeRecording();
        if (onComplete != null) onComplete();
      }
    });
  }

  Future<void> _finalizeRecording() async {
    try {
      Uint8List wavBytes;

      if (customByteGenerator != null) {
        wavBytes = await customByteGenerator!(const Duration(seconds: targetDurationSeconds));
      } else {
        String? targetPath;
        try {
          final isRec = await _audioRecorder.isRecording();
          if (isRec) {
            targetPath = await _audioRecorder.stop();
          }
        } catch (stopErr) {
          debugPrint('⚠️ [AudioRecorderService] Error stopping recorder: $stopErr');
        }

        final filePath = targetPath ?? _currentRecordingPath;
        if (filePath == null) {
          throw Exception('No recorded audio file path returned by microphone stream.');
        }

        final file = File(filePath);
        if (!await file.exists()) {
          throw Exception('Recorded audio file not found on disk ($filePath).');
        }

        final bytes = await file.readAsBytes();
        if (bytes.length <= 44) {
          throw Exception('Microphone recorded 0 audio samples (empty WAV buffer).');
        }

        wavBytes = bytes;
      }

      // Root Mean Square (RMS) volume validation to guard against silent / unpopulated audio
      final numSamples = (wavBytes.length - 44) ~/ 2;
      if (numSamples < 4000) {
        throw Exception('Audio sample too short. Please speak or cough directly into the microphone for at least 2-3 seconds.');
      }

      final byteData = ByteData.sublistView(wavBytes, 44);
      double sumSq = 0.0;
      for (int i = 0; i < numSamples; i++) {
        final sample = byteData.getInt16(i * 2, Endian.little) / 32768.0;
        sumSq += sample * sample;
      }
      final rms = math.sqrt(sumSq / numSamples);
      debugPrint('🎙️ [AudioRecorderService] Captured $numSamples samples (${wavBytes.length} bytes), RMS Volume: ${rms.toStringAsFixed(4)}');

      if (rms < 0.01) {
        _status = AudioRecorderStatus.error;
        _errorMessage = 'No cough sound detected. Please speak or cough directly into the microphone.';
        _lastResult = null;
        notifyListeners();
        return;
      }

      final fileName = 'cough_recording_${DateTime.now().millisecondsSinceEpoch}.wav';
      _lastResult = AudioRecordingResult(
        wavBytes: wavBytes,
        duration: const Duration(seconds: targetDurationSeconds),
        sampleRate: targetSampleRate,
        channels: targetChannels,
        bitsPerSample: targetBitsPerSample,
        fileName: fileName,
        recordedAt: DateTime.now(),
      );

      _status = AudioRecorderStatus.recorded;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      debugPrint('🚨 [AudioRecorderService] Audio recording error: $e');
      _status = AudioRecorderStatus.error;
      _errorMessage = '$e'.replaceAll('Exception: ', '');
      _lastResult = null;
      notifyListeners();
    }
  }

  @override
  Future<AudioRecordingResult?> stopRecording() async {
    _countdownTimer?.cancel();
    if (_status == AudioRecorderStatus.recording) {
      await _finalizeRecording();
    }
    return _lastResult;
  }

  @override
  void cancel() {
    _countdownTimer?.cancel();
    try {
      _audioRecorder.stop();
    } catch (_) {}
    _status = AudioRecorderStatus.idle;
    _remainingSeconds = targetDurationSeconds;
    notifyListeners();
  }

  void reset() {
    _countdownTimer?.cancel();
    try {
      _audioRecorder.stop();
    } catch (_) {}
    _status = AudioRecorderStatus.idle;
    _remainingSeconds = targetDurationSeconds;
    _lastResult = null;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    try {
      _audioRecorder.dispose();
    } catch (_) {}
    super.dispose();
  }

  /// Utility to pack raw 16-bit PCM bytes into a valid RIFF/WAVE container (used in tests)
  static Uint8List encodePcmToWav(
    Uint8List pcmBytes, {
    int sampleRate = 16000,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcmBytes.length;
    final chunkSize = 36 + dataSize;

    final header = ByteData(44);
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57);  // 'W'
    header.setUint8(9, 0x41);  // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataSize, Endian.little);

    final wav = Uint8List(44 + dataSize);
    wav.setRange(0, 44, header.buffer.asUint8List());
    wav.setRange(44, 44 + dataSize, pcmBytes);
    return wav;
  }

  /// Synthesizes acoustic PCM audio for offline unit testing
  static Uint8List generateSyntheticRespiratoryWav({
    Duration duration = const Duration(seconds: 5),
    int sampleRate = 16000,
    double fundamentalFreq = 220.0,
  }) {
    final totalSamples = (sampleRate * (duration.inMilliseconds / 1000.0)).toInt();
    final pcmBytes = Uint8List(totalSamples * 2);
    final byteData = ByteData.view(pcmBytes.buffer);

    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate.toDouble();
      final env = math.exp(-2.5 * (t % 1.25));
      final raw = math.sin(2 * math.pi * fundamentalFreq * t) * 0.6 +
          math.sin(2 * math.pi * (fundamentalFreq * 2.1) * t) * 0.25 +
          ((math.Random(i).nextDouble() * 2.0 - 1.0) * 0.15);
      final sample = (raw * env * 32767.0).clamp(-32768.0, 32767.0).toInt();
      byteData.setInt16(i * 2, sample, Endian.little);
    }

    return encodePcmToWav(pcmBytes, sampleRate: sampleRate, channels: 1, bitsPerSample: 16);
  }
}

