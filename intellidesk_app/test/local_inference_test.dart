import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:intellidesk_app/modules/diagnostics/models/symptom_vector.dart';
import 'package:intellidesk_app/modules/diagnostics/models/risk_assessment.dart';
import 'package:intellidesk_app/modules/diagnostics/services/local_inference_service.dart';
import 'package:intellidesk_app/modules/diagnostics/services/inference_engine_interface.dart';
import 'package:intellidesk_app/modules/diagnostics/providers/diagnostics_provider.dart';
import 'package:intellidesk_app/modules/diagnostics/providers/diagnostic_state_provider.dart';
import 'package:intellidesk_app/modules/diagnostics/ui/diagnostic_results_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalInferenceService - Image Preprocessing Tests', () {
    late LocalInferenceService service;
    late Uint8List dummyPngBytes;

    setUp(() {
      service = LocalInferenceService();

      // Create a 100x100 solid color test image encoded as PNG
      final testImg = img.Image(width: 100, height: 100);
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 100; x++) {
          testImg.setPixelRgb(x, y, 128, 200, 50);
        }
      }
      dummyPngBytes = Uint8List.fromList(img.encodePng(testImg));
    });

    tearDown(() {
      service.dispose();
    });

    test('preprocessImage decodes, resizes to [1, 224, 224, 3], and normalizes to [-1.0, 1.0]', () {
      final tensor = service.preprocessImage(dummyPngBytes);

      // Verify shape: [1, 224, 224, 3]
      expect(tensor.length, 1);
      expect(tensor[0].length, 224);
      expect(tensor[0][0].length, 224);
      expect(tensor[0][0][0].length, 3);

      // Verify pixel channel bounds in [-1.0, 1.0]
      for (int y = 0; y < 10; y++) {
        for (int x = 0; x < 10; x++) {
          final r = tensor[0][y][x][0];
          final g = tensor[0][y][x][1];
          final b = tensor[0][y][x][2];
          expect(r, inInclusiveRange(-1.0, 1.0));
          expect(g, inInclusiveRange(-1.0, 1.0));
          expect(b, inInclusiveRange(-1.0, 1.0));
        }
      }
    });

    test('extractVisualEmbeddings with null input produces text-only prior of 1/sqrt(128)', () async {
      final embeddings = await service.extractVisualEmbeddings(null);

      expect(embeddings.length, 128);
      final expectedUniform = 1.0 / math.sqrt(128);
      for (final val in embeddings) {
        expect(val, closeTo(expectedUniform, 1e-4));
      }

      // Check L2 norm equals 1.0
      double sumSq = embeddings.fold(0.0, (acc, v) => acc + (v * v));
      expect(math.sqrt(sumSq), closeTo(1.0, 1e-4));
    });

    test('extractVisualEmbeddings with image input produces 128-d L2-normalized vector', () async {
      final embeddings = await service.extractVisualEmbeddings(dummyPngBytes);

      expect(embeddings.length, 128);
      double sumSq = embeddings.fold(0.0, (acc, v) => acc + (v * v));
      expect(math.sqrt(sumSq), closeTo(1.0, 1e-4));
    });
  });

  group('LocalInferenceService - Multimodal Inference & Clinical Safety Net', () {
    late LocalInferenceService service;

    setUp(() {
      service = LocalInferenceService();
    });

    tearDown(() {
      service.dispose();
    });

    test('Executes offline inference with standard symptoms', () async {
      const symptoms = SymptomVector(
        bodyLocation: 'Skin/Chest',
        durationDays: 4,
        painScale: 4,
        symptoms: ['Rash', 'Redness'],
        vitals: ClinicalVitals(temperatureCelsius: 37.2, heartRate: 72, oxygenSaturation: 98),
        demographics: {'age': 28, 'gender': 'Female'},
      );

      final assessment = await service.runMultimodalInference(symptoms);

      expect(assessment.isOffline, isTrue);
      expect(assessment.executionEngine, contains('On-Device'));
      expect(assessment.riskScore, inInclusiveRange(0.0, 1.0));
      expect(assessment.uncertaintyBounds.monteCarloSamples, 10);
      expect(assessment.featureContributionBreakdown, isNotNull);
      expect(assessment.clinicalRecommendations.isNotEmpty, isTrue);
    });

    test('Clinical Safety Net enforces floor >= 0.85 and Critical Referral on Red Flags', () async {
      const criticalSymptoms = SymptomVector(
        bodyLocation: 'Head',
        durationDays: 1,
        painScale: 10, // Debilitating pain
        symptoms: ['Severe Migraine'],
        vitals: ClinicalVitals(temperatureCelsius: 40.5, heartRate: 110, oxygenSaturation: 95),
        demographics: {'age': 45, 'gender': 'Male'},
      );

      final assessment = await service.runMultimodalInference(criticalSymptoms);

      expect(assessment.riskScore, greaterThanOrEqualTo(0.85));
      expect(assessment.riskLevel, equals(ClinicalRiskLevel.critical));
      expect(assessment.requiresImmediatePhysicianReview, isTrue);
      expect(assessment.clinicalRecommendations.first, contains('CRITICAL SAFETY OVERRIDE'));
    });

    test('Clinical Safety Net triggers on Chest Pain / Cardiopulmonary Red Flag', () async {
      const chestSymptoms = SymptomVector(
        bodyLocation: 'Skin/Chest',
        durationDays: 1,
        painScale: 6,
        symptoms: ['Chest Pain', 'Shortness of Breath'],
        vitals: ClinicalVitals(temperatureCelsius: 37.0, heartRate: 95, oxygenSaturation: 89), // Hypoxia
        demographics: {'age': 62, 'gender': 'Male'},
      );

      final assessment = await service.runMultimodalInference(chestSymptoms);

      expect(assessment.riskScore, greaterThanOrEqualTo(0.85));
      expect(assessment.riskLevel, equals(ClinicalRiskLevel.critical));
      expect(assessment.primaryDiagnosis, contains('Cardiopulmonary'));
      expect(assessment.requiresImmediatePhysicianReview, isTrue);
    });
  });

  group('DiagnosticResultsScreen UI Tests - Offline Mode Badge', () {
    testWidgets('Renders "Processed 100% On-Device (Offline Private Mode)" badge when assessment is offline', (tester) async {
      const offlineAssessment = RiskAssessment(
        riskScore: 0.35,
        riskLevel: ClinicalRiskLevel.low,
        uncertaintyBounds: UncertaintyBounds(
          confidence: 0.92,
          ciLower: 0.28,
          ciUpper: 0.42,
          epistemicVariance: 0.0014,
          monteCarloSamples: 10,
        ),
        primaryDiagnosis: 'Localized Contact Dermatitis',
        clinicalRecommendations: ['Keep area dry', 'Apply hydrocortisone'],
        isOffline: true,
        executionEngine: 'TFLite Edge (100% On-Device)',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => DiagnosticsProvider()),
            ChangeNotifierProvider(create: (_) => DiagnosticStateProvider()),
          ],
          child: const MaterialApp(
            home: DiagnosticResultsScreen(assessmentOverride: offlineAssessment),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the Offline Private Mode UI badge is present
      expect(find.text('Processed 100% On-Device (Offline Private Mode)'), findsOneWidget);
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.byIcon(Icons.offline_bolt_rounded), findsOneWidget);
      expect(find.text('Zero network transmission • TFLite Quantized Neural Pipeline • 100% HIPAA Private'), findsOneWidget);
      expect(find.text('Localized Contact Dermatitis'), findsOneWidget);
    });
  });
}
