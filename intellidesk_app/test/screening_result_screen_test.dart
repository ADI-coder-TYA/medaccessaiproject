import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intellidesk_app/modules/diagnostics/models/risk_assessment.dart';
import 'package:intellidesk_app/modules/diagnostics/providers/diagnostics_provider.dart';
import 'package:intellidesk_app/modules/diagnostics/providers/diagnostic_state_provider.dart';
import 'package:intellidesk_app/modules/diagnostics/ui/ScreeningResultScreen.dart';
import 'package:intellidesk_app/modules/diagnostics/services/diagnostics_service.dart';

class MockDiagnosticsService extends DiagnosticsService {
  @override
  Future<String> interpretScreeningResult({
    required RiskAssessment assessment,
    String? query,
  }) async {
    return generateLocalInterpretation(assessment, query);
  }

  @override
  Future<String> sendDiagnosticChatMessage({
    required RiskAssessment assessment,
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    return generateLocalChatMessage(assessment, message);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testAssessment = RiskAssessment(
    riskScore: 0.72,
    riskLevel: ClinicalRiskLevel.moderate,
    uncertaintyBounds: UncertaintyBounds(
      confidence: 0.88,
      ciLower: 0.69,
      ciUpper: 0.75,
      epistemicVariance: 0.0009,
      monteCarloSamples: 10,
    ),
    primaryDiagnosis: 'Localized Contact Dermatitis',
    differentialDiagnoses: [
      DifferentialDiagnosisItem(condition: 'Eczematous Dermatitis', probability: 0.72, urgency: 'PROMPT_CARE'),
      DifferentialDiagnosisItem(condition: 'Cellulitis', probability: 0.28, urgency: 'EMERGENCY'),
    ],
    clinicalRecommendations: [
      'Schedule a clinic consultation within 48 hours',
      'Apply clean cold compress to soothe area',
    ],
    featureContributionBreakdown: 'Visual Analysis: 55%, Symptoms: 35%, Age: 10%',
    xaiHeatmapUrl: 'https://example.com/gradcam_overlay.jpg',
    isOffline: false,
    executionEngine: 'Multimodal Fusion Network',
  );

  group('ScreeningResultScreen UI & Chat Drawer Tests', () {
    testWidgets('Renders Risk Score Bar with (Score ± Uncertainty) and Visual Saliency', (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => DiagnosticsProvider()),
            ChangeNotifierProvider(create: (_) => DiagnosticStateProvider()),
          ],
          child: MaterialApp(
            home: ScreeningResultScreen(
              assessmentOverride: testAssessment,
              diagnosticsService: MockDiagnosticsService(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify Unified Clinical Risk Assessment header
      expect(find.text('UNIFIED CLINICAL RISK ASSESSMENT'), findsOneWidget);
      expect(find.text('Moderate Risk'), findsOneWidget);

      // 2. Verify Risk Score bar: (Score ± Uncertainty) -> "72% ± 3%"
      expect(find.text('72% ± 3%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // 3. Verify Monte Carlo Dropout bounds
      expect(find.textContaining('95% CI: 69% - 75%'), findsOneWidget);

      // 4. Verify Visual Saliency Section: Original Photo alongside Grad-CAM Heatmap
      expect(find.text('Visual Diagnosis Saliency'), findsOneWidget);
      expect(find.text('Original Symptom Photo'), findsOneWidget);
      expect(find.text('Grad-CAM Heatmap'), findsOneWidget);
      expect(find.text('Active Hotspot'), findsOneWidget);

      // 5. Verify Primary Finding & Recommendations
      expect(find.text('Localized Contact Dermatitis'), findsOneWidget);
      expect(find.textContaining('Visual Analysis: 55%'), findsOneWidget);

      // 6. Verify "Discuss Results with Health AI" button exists
      expect(find.text('Discuss Results with Health AI (Qwen2.5 PFA)'), findsOneWidget);
    });

    testWidgets('Opens Qwen2.5 Health AI Chat Drawer with Mandatory Disclaimer and Next Steps', (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => DiagnosticsProvider()),
            ChangeNotifierProvider(create: (_) => DiagnosticStateProvider()),
          ],
          child: MaterialApp(
            home: ScreeningResultScreen(
              assessmentOverride: testAssessment,
              diagnosticsService: MockDiagnosticsService(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Tap "Discuss Results with Health AI (Qwen2.5 PFA)" button
      final chatBtn = find.text('Discuss Results with Health AI (Qwen2.5 PFA)');
      await tester.tap(chatBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify the Chat Drawer is open
      expect(find.byType(HealthAIChatDrawer), findsOneWidget);
      expect(find.text('Qwen2.5 Health Assistant'), findsOneWidget);
      expect(find.text('Local ONNX & Psychological First Aid'), findsOneWidget);

      // Verify Mandatory Disclaimer is displayed
      expect(find.text('This is an AI-assisted screening tool, not a final medical diagnosis.'), findsOneWidget);

      // Verify Quick Inquiry Chips
      expect(find.text('What should I do next?'), findsOneWidget);
      expect(find.text('Is this contagious?'), findsOneWidget);
      expect(find.text('How can I soothe the pain?'), findsOneWidget);

      // Verify automated empathetic interpretation with next steps inside drawer
      expect(
        find.descendant(of: find.byType(HealthAIChatDrawer), matching: find.textContaining('Localized Contact Dermatitis')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(HealthAIChatDrawer), matching: find.textContaining('Recommended Next Steps:')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(HealthAIChatDrawer), matching: find.textContaining('clinic consultation within 48 hours')),
        findsOneWidget,
      );

      // Send a follow-up inquiry via quick chip
      final contagiousChip = find.text('Is this contagious?');
      await tester.tap(contagiousChip);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify reply contains guidance and disclaimer
      expect(find.textContaining('contagion'), findsWidgets);
    });
  });
}
