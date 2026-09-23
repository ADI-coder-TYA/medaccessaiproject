import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intellidesk_app/modules/diagnostics/models/longitudinal_progression.dart';
import 'package:intellidesk_app/modules/diagnostics/models/risk_assessment.dart';
import 'package:intellidesk_app/modules/diagnostics/ui/LongitudinalHistoryScreen.dart';
import 'package:intellidesk_app/modules/diagnostics/services/diagnostics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 23, 14, 0);

  final testScreenings = [
    ScreeningHistoryPoint(
      id: 'scr-t0-baseline',
      previousScreeningId: null,
      createdAt: now.subtract(const Duration(days: 3)),
      riskScore: 0.78,
      riskLevel: ClinicalRiskLevel.critical,
      imageUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      symptomPayload: {
        'painScale': 8,
        'vitals': {'pain_score': 8, 'temperature': 38.5}
      },
    ),
    ScreeningHistoryPoint(
      id: 'scr-t1-followup',
      previousScreeningId: 'scr-t0-baseline',
      createdAt: now,
      riskScore: 0.32,
      riskLevel: ClinicalRiskLevel.low,
      imageUrl: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      symptomPayload: {
        'painScale': 2,
        'vitals': {'pain_score': 2, 'temperature': 36.7}
      },
    ),
  ];

  final testDeltaImproving = ScreeningDeltaResult(
    baselineScreeningId: 'scr-t0-baseline',
    followupScreeningId: 'scr-t1-followup',
    baselineDate: now.subtract(const Duration(days: 3)),
    followupDate: now,
    timeElapsedDays: 3.0,
    timeElapsedHours: 72.0,
    baselineRiskScore: 0.78,
    followupRiskScore: 0.32,
    riskDelta: -0.46,
    riskDeltaPercentage: -46.0,
    statusTier: ClinicalProgressionTier.improving,
    statusLabel: 'Improving / Healing',
    ssim: 0.84,
    ssimCategory: 'High Concordance',
    painDelta: -6.0,
    tempDelta: -1.8,
    baselineImageUrl: testScreenings[0].imageUrl,
    followupImageUrl: testScreenings[1].imageUrl,
    clinicalSummary: 'Patient exhibits positive clinical trajectory with marked reduction in unified health risk score (-46%).',
    recommendations: [
      'Continue prescribed conservative care regimen',
      'Follow-up routine checkup in 72 hours',
    ],
  );

  group('LongitudinalHistoryScreen Widget & Visual Slider Tests', () {
    testWidgets('Renders FL Chart LineChart, Progression Header, and Interactive Slider', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: LongitudinalHistoryScreen(
            patientId: 'patient-test-123',
            initialScreenings: testScreenings,
            initialDelta: testDeltaImproving,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. App Bar Title
      expect(find.text('Longitudinal Progression Tracker'), findsOneWidget);

      // 2. Progression Status Banner
      expect(find.text('IMPROVING / HEALING'), findsOneWidget);
      expect(find.text('46.0% Risk Reduction'), findsOneWidget);
      expect(find.text('SSIM'), findsOneWidget);
      expect(find.text('84%'), findsOneWidget);

      // 3. FL Chart LineChart exists
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('Health Risk Score Trajectory'), findsOneWidget);

      // 4. Photo Comparison Card & Technical Guardrail 4 (AspectRatio 1.0)
      expect(find.text('Visual Progression Comparison'), findsOneWidget);
      final aspectRatioFinder = find.ancestor(
        of: find.byType(ClipRRect),
        matching: find.byType(AspectRatio),
      );
      expect(aspectRatioFinder, findsWidgets);

      // Verify at least one AspectRatio has aspectRatio == 1.0
      final aspectRatios = tester.widgetList<AspectRatio>(aspectRatioFinder);
      final hasSquareAspect = aspectRatios.any((ar) => ar.aspectRatio == 1.0);
      expect(hasSquareAspect, isTrue, reason: 'Technical Guardrail 4 mandates AspectRatio(1.0)');

      // 5. Drag handle and labels present in slider
      expect(find.byIcon(Icons.compare_arrows), findsOneWidget);
      expect(find.text('T0 Baseline'), findsWidgets);
      expect(find.text('T1 Follow-up'), findsWidgets);

      // 6. Test dragging interaction on slider
      final sliderGestureFinder = find.byType(GestureDetector);
      expect(sliderGestureFinder, findsWidgets);
      await tester.drag(find.byIcon(Icons.compare_arrows), const Offset(50, 0));
      await tester.pumpAndSettle();

      // 7. Toggle to Side-by-Side mode
      final toggleButton = find.byTooltip('Switch to Side-by-Side');
      expect(toggleButton, findsOneWidget);
      await tester.tap(toggleButton);
      await tester.pumpAndSettle();
      expect(find.text('Side-by-Side'), findsOneWidget);

      // 8. Clinical Synthesis Card and Directives
      expect(find.text('Clinical Delta Analysis'), findsOneWidget);
      expect(find.textContaining('Patient exhibits positive clinical trajectory'), findsOneWidget);
      expect(find.text('Pain: -6'), findsOneWidget);
      expect(find.text('Temp: -1.8°C'), findsOneWidget);
      expect(find.text('Continue prescribed conservative care regimen'), findsOneWidget);

      // 9. Recorded Checkups Timeline List
      expect(find.text('Recorded Timeline Checkups'), findsOneWidget);
      expect(find.text('T0'), findsWidgets);
      expect(find.text('T1'), findsWidgets);
    });

    testWidgets('Renders Escalating status badge for deteriorating presentation', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testDeltaDeteriorating = ScreeningDeltaResult(
        baselineScreeningId: 'scr-t0',
        followupScreeningId: 'scr-t1',
        baselineDate: now.subtract(const Duration(days: 2)),
        followupDate: now,
        timeElapsedDays: 2.0,
        timeElapsedHours: 48.0,
        baselineRiskScore: 0.35,
        followupRiskScore: 0.75,
        riskDelta: 0.40,
        riskDeltaPercentage: 40.0,
        statusTier: ClinicalProgressionTier.deteriorating,
        statusLabel: 'Deteriorating / Escalating',
        ssim: 0.65,
        ssimCategory: 'Moderate Shift',
        painDelta: 4.0,
        tempDelta: 1.2,
        clinicalSummary: 'Presentation exhibits symptom escalation (+40% risk increase).',
        recommendations: ['Immediate clinician review recommended'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LongitudinalHistoryScreen(
            patientId: 'patient-test-456',
            initialScreenings: testScreenings,
            initialDelta: testDeltaDeteriorating,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DETERIORATING / ESCALATING'), findsOneWidget);
      expect(find.text('+40.0% Risk Escalation'), findsOneWidget);
      expect(find.text('Pain: +4'), findsOneWidget);
      expect(find.text('Temp: +1.2°C'), findsOneWidget);
    });

    testWidgets('Renders Stable status badge for minimal delta', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testDeltaStable = ScreeningDeltaResult(
        baselineScreeningId: 'scr-t0',
        followupScreeningId: 'scr-t1',
        baselineDate: now.subtract(const Duration(days: 1)),
        followupDate: now,
        timeElapsedDays: 1.0,
        timeElapsedHours: 24.0,
        baselineRiskScore: 0.45,
        followupRiskScore: 0.46,
        riskDelta: 0.01,
        riskDeltaPercentage: 1.0,
        statusTier: ClinicalProgressionTier.stable,
        statusLabel: 'Stable / Unchanged',
        ssim: 0.92,
        ssimCategory: 'High Concordance',
        painDelta: 0.0,
        tempDelta: 0.0,
        clinicalSummary: 'Presentation remains stable with minimal risk change (+1%).',
        recommendations: ['Continue routine monitoring'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LongitudinalHistoryScreen(
            patientId: 'patient-test-789',
            initialScreenings: testScreenings,
            initialDelta: testDeltaStable,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('STABLE / UNCHANGED'), findsOneWidget);
      expect(find.text('+1.0% (Stable)'), findsOneWidget);
      expect(find.textContaining('Presentation remains stable'), findsOneWidget);
    });
  });
}
