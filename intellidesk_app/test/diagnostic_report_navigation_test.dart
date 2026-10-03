import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intellidesk_app/modules/diagnostics/models/risk_assessment.dart';
import 'package:intellidesk_app/modules/diagnostics/ui/diagnostic_results_screen.dart';
import 'package:intellidesk_app/modules/diagnostics/providers/diagnostics_provider.dart';
import 'package:intellidesk_app/modules/diagnostics/providers/diagnostic_state_provider.dart';
import 'package:intellidesk_app/providers/auth_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final Map<String, dynamic> sampleDbScreening = {
    'id': '4954d82e-6ab1-478e-85f7-41ece85d1566',
    'patient_id': 'usr_pat_PAT-37B041',
    'institution_id': 'nano123',
    'multimodal_risk_score': 0.2736,
    'risk_level': 'MODERATE',
    'uncertainty_bounds': {
      'confidence': 0.9289,
      'ciLower': 0.2039,
      'ciUpper': 0.3433,
      'epistemicVariance': 0.001263,
      'monteCarloSamples': 10
    },
    'clinical_findings': [
      {
        'code': 'BA00',
        'condition': 'Hypertensive Emergency Rule-Out',
        'riskLevel': 'PROMPT_CARE',
        'probability': 0.29,
        'recommendation': 'Monitor symptoms over the next 24 to 48 hours.',
      },
      {
        'code': '9A03',
        'condition': 'Blepharitis',
        'riskLevel': 'ROUTINE',
        'probability': 0.27,
        'recommendation': 'Maintain hydration, rest, and follow symptomatic supportive care.',
      }
    ],
    'symptom_payload': {
      'chiefComplaint': 'Persistent ocular irritation and headache',
    },
    'cdss_evaluation': {
      'diagnosis': 'Hypertensive Emergency Rule-Out',
      'confidence': 0.88,
    }
  };

  group('Diagnostic Report Mapping & Screen Resolution Tests', () {
    test('RiskAssessment.fromDbScreening maps database screening accurately', () {
      final assessment = RiskAssessment.fromDbScreening(sampleDbScreening);

      expect(assessment.riskScore, closeTo(0.2736, 0.0001));
      expect(assessment.riskLevel, equals(ClinicalRiskLevel.moderate));
      expect(assessment.primaryDiagnosis, equals('Hypertensive Emergency Rule-Out'));
      expect(assessment.differentialDiagnoses.length, equals(2));
      expect(assessment.differentialDiagnoses[0].condition, equals('Hypertensive Emergency Rule-Out'));
      expect(assessment.differentialDiagnoses[0].probability, equals(0.29));
      expect(assessment.clinicalRecommendations.length, greaterThanOrEqualTo(2));
      expect(assessment.uncertaintyBounds.confidence, closeTo(0.9289, 0.0001));
      expect(assessment.cdssEvaluationPayload, isNotNull);
      expect(assessment.screeningId, equals('4954d82e-6ab1-478e-85f7-41ece85d1566'));
    });

    testWidgets('DiagnosticResultsScreen renders full report when assessment is passed', (tester) async {
      final assessment = RiskAssessment.fromDbScreening(sampleDbScreening);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => DiagnosticsProvider()),
            ChangeNotifierProvider(create: (_) => DiagnosticStateProvider()),
          ],
          child: MaterialApp(
            home: DiagnosticResultsScreen(assessmentOverride: assessment),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify the report title and content are displayed (NOT the "No active assessment results found" error)
      expect(find.text('Clinical Assessment Report'), findsOneWidget);
      expect(find.text('Hypertensive Emergency Rule-Out'), findsWidgets);
      expect(find.text('Moderate Risk'), findsOneWidget);
      expect(find.text('Primary Differential Finding'), findsOneWidget);
      expect(find.text('Differential Possibilities:'), findsOneWidget);
    });

    testWidgets('DiagnosticResultsScreen shows helpful empty state and checkup action when no assessment exists', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AuthProvider()),
            ChangeNotifierProvider(create: (_) => DiagnosticsProvider()),
            ChangeNotifierProvider(create: (_) => DiagnosticStateProvider()),
          ],
          child: const MaterialApp(
            home: DiagnosticResultsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Empty state should be friendly and include checkup CTA button
      expect(find.text('No Diagnostic Assessment Found'), findsOneWidget);
      expect(find.text('Start Clinical Checkup'), findsOneWidget);
      expect(find.text('No active assessment results found.'), findsNothing);
    });
  });
}
