import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:intellidesk_app/modules/diagnostics/models/diagnostic_payload.dart';
import 'package:intellidesk_app/modules/diagnostics/providers/diagnostics_provider.dart';
import 'package:intellidesk_app/modules/diagnostics/services/audio_recorder_service.dart';
import 'package:intellidesk_app/modules/diagnostics/ui/diagnostic_intake_screen.dart';

void main() {
  group('1. Mandatory 16 kHz Mono Resampling & WAV Encoding Tests', () {
    test('Encodes raw 16-bit PCM bytes into canonical 44-byte WAV header', () {
      // 100 samples = 200 bytes PCM
      final pcmBytes = Uint8List(200);
      for (int i = 0; i < 100; i++) {
        pcmBytes[i * 2] = i;
        pcmBytes[i * 2 + 1] = 0;
      }

      final wavBytes = AudioRecorderService.encodePcmToWav(
        pcmBytes,
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
      );

      // Verify total size: 44 header + 200 PCM = 244 bytes
      expect(wavBytes.length, 244);

      // Verify RIFF magic
      expect(String.fromCharCodes(wavBytes.sublist(0, 4)), 'RIFF');
      // Verify WAVE format
      expect(String.fromCharCodes(wavBytes.sublist(8, 12)), 'WAVE');
      // Verify "fmt " chunk
      expect(String.fromCharCodes(wavBytes.sublist(12, 16)), 'fmt ');

      final byteData = ByteData.view(wavBytes.buffer);
      // Subchunk1Size = 16
      expect(byteData.getUint32(16, Endian.little), 16);
      // AudioFormat = 1 (PCM)
      expect(byteData.getUint16(20, Endian.little), 1);
      // NumChannels = 1 (Mono)
      expect(byteData.getUint16(22, Endian.little), 1);
      // SampleRate = 16000
      expect(byteData.getUint32(24, Endian.little), 16000);
      // ByteRate = 16000 * 1 * 2 = 32000
      expect(byteData.getUint32(28, Endian.little), 32000);
      // BlockAlign = 2
      expect(byteData.getUint16(32, Endian.little), 2);
      // BitsPerSample = 16
      expect(byteData.getUint16(34, Endian.little), 16);

      // "data" chunk
      expect(String.fromCharCodes(wavBytes.sublist(36, 40)), 'data');
      // Data length = 200
      expect(byteData.getUint32(40, Endian.little), 200);
    });

    test('Generates synthetic 5s respiratory WAV with calibrated acoustics', () {
      final wav = AudioRecorderService.generateSyntheticRespiratoryWav(
        duration: const Duration(seconds: 5),
        sampleRate: 16000,
      );

      // 5 seconds @ 16 kHz = 80,000 samples = 160,000 PCM bytes
      // Total WAV file size = 44 + 160,000 = 160,044 bytes
      expect(wav.length, 160044);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
    });
  });

  group('2. Graceful Microphone Permission Handling Tests', () {
    test('Transitions to permissionDenied state when user denies mic permission', () async {
      final service = AudioRecorderService(
        permissionCheckOverride: () async => PermissionStatus.denied,
        permissionRequestOverride: () async => PermissionStatus.denied,
      );

      final hasPermission = await service.requestMicPermission();

      expect(hasPermission, isFalse);
      expect(service.status, AudioRecorderStatus.permissionDenied);
      expect(service.errorMessage, contains('Microphone permission denied'));
    });

    test('Transitions to idle/granted state when permission is approved', () async {
      final service = AudioRecorderService(
        permissionCheckOverride: () async => PermissionStatus.granted,
      );

      final hasPermission = await service.requestMicPermission();

      expect(hasPermission, isTrue);
      expect(service.status, AudioRecorderStatus.idle);
      expect(service.errorMessage, isNull);
    });
  });

  group('3. Headless Automated Widget Testing & Mock AudioRecorder Byte Generation', () {
    testWidgets('Renders 5-second acoustic recording button on intake screen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockRecorder = AudioRecorderService(
        permissionCheckOverride: () async => PermissionStatus.granted,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider(
            create: (_) => DiagnosticsProvider(),
            child: DiagnosticIntakeScreen(audioRecorderService: mockRecorder),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the 5s record button is visible
      expect(find.byKey(const Key('recordCoughSoundButton')), findsOneWidget);
      expect(find.text('5. Respiratory Acoustic Intake'), findsOneWidget);
      expect(find.text('Record Cough / Breathing Sound (5s)'), findsOneWidget);
    });

    testWidgets('Executes 5-second countdown and captures mock WAV bytes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Mock synthetic 16kHz WAV byte generation
      final mockWavBytes = AudioRecorderService.generateSyntheticRespiratoryWav(
        duration: const Duration(seconds: 5),
        sampleRate: 16000,
      );

      final mockRecorder = AudioRecorderService(
        permissionCheckOverride: () async => PermissionStatus.granted,
        customByteGenerator: (d) async => mockWavBytes,
      );

      final diagnosticsProvider = DiagnosticsProvider();

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<DiagnosticsProvider>.value(
            value: diagnosticsProvider,
            child: DiagnosticIntakeScreen(audioRecorderService: mockRecorder),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the Record button
      await tester.tap(find.byKey(const Key('recordCoughSoundButton')));
      await tester.pump(); // Trigger setState

      // Verify recording in-progress status with countdown
      expect(mockRecorder.status, AudioRecorderStatus.recording);
      expect(find.textContaining('Recording Cough...'), findsOneWidget);

      // Advance clock through the 5-second recording period
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pumpAndSettle();

      // Verify recording finalized
      expect(mockRecorder.status, AudioRecorderStatus.recorded);
      expect(find.text('Acoustic Sample Captured'), findsOneWidget);
      expect(find.text('16,000 Hz Mono PCM WAV (5.0s)'), findsOneWidget);
      expect(find.byKey(const Key('retakeCoughSoundButton')), findsOneWidget);

      // Verify bytes were stored in DiagnosticsProvider
      expect(diagnosticsProvider.hasAudio, isTrue);
      expect(diagnosticsProvider.capturedAudioBytes, isNotNull);
      expect(diagnosticsProvider.capturedAudioBytes!.length, 160044);
    });

    testWidgets('Displays graceful permission denied warning with retry button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool permissionApproved = false;

      final mockRecorder = AudioRecorderService(
        permissionCheckOverride: () async =>
            permissionApproved ? PermissionStatus.granted : PermissionStatus.denied,
        permissionRequestOverride: () async =>
            permissionApproved ? PermissionStatus.granted : PermissionStatus.denied,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider(
            create: (_) => DiagnosticsProvider(),
            child: DiagnosticIntakeScreen(audioRecorderService: mockRecorder),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap record when permission is denied
      await tester.tap(find.byKey(const Key('recordCoughSoundButton')));
      await tester.pumpAndSettle();

      // Verify graceful warning UI
      expect(mockRecorder.status, AudioRecorderStatus.permissionDenied);
      expect(find.byKey(const Key('grantMicPermissionButton')), findsOneWidget);
      expect(find.textContaining('Microphone permission denied'), findsOneWidget);

      // Simulate user granting permission on retry
      permissionApproved = true;
      await tester.tap(find.byKey(const Key('grantMicPermissionButton')));
      await tester.pump();

      // Should now begin recording
      expect(mockRecorder.status, AudioRecorderStatus.recording);
      expect(find.textContaining('Recording Cough...'), findsOneWidget);

      // Clean up timer
      mockRecorder.cancel();
      await tester.pumpAndSettle();
    });
  });

  group('4. DiagnosticPayload Audio Biomarker Integration Tests', () {
    test('Constructs DiagnosticPayload with audio metadata', () {
      final mockAudioBytes = AudioRecorderService.generateSyntheticRespiratoryWav();

      final payload = DiagnosticPayload(
        bodyLocation: 'Chest / Thorax',
        painSeverity: 6,
        symptomDurationDays: 3,
        temperatureCelsius: 38.2,
        secondarySymptoms: ['Wheezing / Stridor Sound', 'Persistent Cough'],
        demographics: const PatientDemographics(age: 45, gender: 'Male'),
        audioBytes: mockAudioBytes,
        audioFileName: 'patient_cough_16k.wav',
        notes: 'Dry barking cough with nocturnal wheeze',
      );

      expect(payload.bodyLocation, 'Chest / Thorax');
      expect(payload.audioBytes, isNotNull);
      expect(payload.audioBytes!.length, 160044);
      expect(payload.audioFileName, 'patient_cough_16k.wav');

      final map = payload.toMap();
      expect(map['hasAudio'], isTrue);
      expect(map['audioFileName'], 'patient_cough_16k.wav');

      final symptomVector = payload.toSymptomVector();
      expect(symptomVector.symptoms.contains('Wheezing / Stridor Sound'), isTrue);
    });
  });
}
