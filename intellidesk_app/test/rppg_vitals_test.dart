import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellidesk_app/modules/diagnostics/vitals/models/vitals_result.dart';
import 'package:intellidesk_app/modules/diagnostics/vitals/services/rppg_sensor_service.dart';
import 'package:intellidesk_app/modules/diagnostics/vitals/ui/vitals_scanner_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('rPPG Vitals Models Tests', () {
    test('PhysiologicalAlert serialization and deserialization', () {
      final alert = PhysiologicalAlert(
        type: 'CRITICAL_HYPOXIA',
        severity: 'CRITICAL_OVERRIDE',
        value: 88.5,
        threshold: 90.0,
        unit: '%',
        clinicalDirective: 'Emergency oxygen required',
      );

      final json = alert.toJson();
      expect(json['type'], 'CRITICAL_HYPOXIA');
      expect(json['severity'], 'CRITICAL_OVERRIDE');
      expect(json['value'], 88.5);

      final restored = PhysiologicalAlert.fromJson(json);
      expect(restored.type, 'CRITICAL_HYPOXIA');
      expect(restored.severity, 'CRITICAL_OVERRIDE');
      expect(restored.value, 88.5);
      expect(restored.clinicalDirective, 'Emergency oxygen required');
    });

    test('VitalsResult serialization and deserialization', () {
      final result = VitalsResult(
        heartRateBpm: 75.4,
        hrvRmssdMs: 42.1,
        respirationRateBpm: 16.0,
        oxygenSaturationSpo2: 98.2,
        confidenceScore: 0.95,
        snrDb: 18.4,
        sampleCount: 450,
        durationSeconds: 15.0,
        filteredWaveform: [1.2, 2.4, -0.8],
        interBeatIntervalsMs: [800.0, 790.0, 810.0],
        alerts: [
          PhysiologicalAlert(
            type: 'CRITICAL_TACHYCARDIA',
            severity: 'CRITICAL_OVERRIDE',
            value: 135.0,
            threshold: 130.0,
            unit: 'BPM',
            clinicalDirective: 'Severe tachycardia detected',
          ),
        ],
        hasCriticalDerangement: true,
      );

      final json = result.toJson();
      expect(json['heartRateBpm'], 75.4);
      expect(json['oxygenSaturationSpo2'], 98.2);
      expect(json['hasCriticalDerangement'], true);

      final restored = VitalsResult.fromJson(json);
      expect(restored.heartRateBpm, 75.4);
      expect(restored.hrvRmssdMs, 42.1);
      expect(restored.respirationRateBpm, 16.0);
      expect(restored.oxygenSaturationSpo2, 98.2);
      expect(restored.confidenceScore, 0.95);
      expect(restored.alerts.length, 1);
      expect(restored.hasCriticalDerangement, true);
    });
  });

  group('RPPGSensorService Tests', () {
    test('generateSyntheticFrames creates 15-second 30Hz optical data', () {
      final frames = RPPGSensorService.generateSyntheticFrames(
        durationSeconds: 15.0,
        heartRateBpm: 72.0,
        respirationRateBpm: 15.0,
        spo2Percent: 98.0,
      );

      expect(frames.length, 450);
      expect(frames.first.timestampMs, 0);
      expect(frames.last.timestampMs, 14967); // ~15000ms

      for (final f in frames) {
        expect(f.red, greaterThan(50.0));
        expect(f.green, greaterThan(50.0));
        expect(f.blue, greaterThan(50.0));
        expect(f.isFingerDetected, true);
        expect(f.isMotionArtifactDetected, false);
      }
    });

    test('toJson produces expected keys for backend payload', () {
      final frame = OpticalFrameData(
        frameIndex: 1,
        timestampMs: 33,
        red: 140.23,
        green: 110.45,
        blue: 90.12,
        isFingerDetected: true,
        isMotionArtifactDetected: false,
      );

      final json = frame.toJson();
      expect(json['frameIndex'], 1);
      expect(json['timestampMs'], 33);
      expect(json['red'], 140.23);
      expect(json['green'], 110.45);
      expect(json['blue'], 90.12);
    });
  });

  group('VitalsScannerModal Widget Tests', () {
    testWidgets('renders Touchless Vitals Scanner modal in simulation mode', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VitalsScannerModal(
              enableSimulationMode: true,
              autoStart: false,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Touchless Vitals Scanner'), findsOneWidget);
      expect(find.text('Simulation / Demo Mode'), findsOneWidget);
      expect(find.text('Start 15s Vitals Scan'), findsOneWidget);
      expect(find.text('Run Demo Simulation'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('displays active scanning view with heart icon and contact indicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VitalsScannerModal(
              enableSimulationMode: true,
              autoStart: true,
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Touchless Vitals Scanner'), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsWidgets);
      expect(find.text('Fingertip Detected'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
