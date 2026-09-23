import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intellidesk_app/modules/diagnostics/models/emergency_facility.dart';
import 'package:intellidesk_app/modules/diagnostics/models/risk_assessment.dart';
import 'package:intellidesk_app/modules/diagnostics/providers/diagnostics_provider.dart';
import 'package:intellidesk_app/modules/diagnostics/providers/diagnostic_state_provider.dart';
import 'package:intellidesk_app/modules/diagnostics/services/HospitalLocatorService.dart';
import 'package:intellidesk_app/modules/diagnostics/ui/EmergencyFacilityCard.dart';
import 'package:intellidesk_app/modules/diagnostics/ui/EmergencyFacilitySheet.dart';
import 'package:intellidesk_app/modules/diagnostics/ui/diagnostic_results_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testFacility = EmergencyFacility(
    id: 'fac-test-01',
    name: 'St. Jude University Level 1 Trauma Center',
    type: 'Trauma Center',
    address: '750 Hospital Plaza, University District',
    phone: '+1-555-0199',
    latitude: 40.7180,
    longitude: -74.0020,
    openStatus: 'Open 24/7',
    isOpen24Hours: true,
    capabilities: ['Level 1 Trauma', 'Comprehensive Stroke Center'],
    distanceKm: 0.8,
    travelTimeMinutes: 2,
  );

  const testCriticalAssessment = RiskAssessment(
    riskScore: 0.92,
    riskLevel: ClinicalRiskLevel.critical,
    uncertaintyBounds: UncertaintyBounds(
      confidence: 0.95,
      ciLower: 0.88,
      ciUpper: 0.96,
      epistemicVariance: 0.0004,
      monteCarloSamples: 10,
    ),
    primaryDiagnosis: 'Suspected Severe Cellulitis / Sepsis Red Flag',
    differentialDiagnoses: [],
    clinicalRecommendations: ['Immediate emergency evaluation required'],
    featureContributionBreakdown: 'Visual: 70%, Symptoms: 30%',
    isOffline: true,
    executionEngine: 'Multimodal Fusion Engine',
  );

  const testLowRiskAssessment = RiskAssessment(
    riskScore: 0.15,
    riskLevel: ClinicalRiskLevel.low,
    uncertaintyBounds: UncertaintyBounds(
      confidence: 0.98,
      ciLower: 0.12,
      ciUpper: 0.18,
      epistemicVariance: 0.0001,
      monteCarloSamples: 10,
    ),
    primaryDiagnosis: 'Mild Contact Irritation',
    differentialDiagnoses: [],
    clinicalRecommendations: ['Gentle home monitoring'],
    featureContributionBreakdown: 'Visual: 20%, Symptoms: 80%',
    isOffline: true,
    executionEngine: 'Multimodal Fusion Engine',
  );

  group('Location-Based Emergency Care & HospitalLocatorService Tests', () {
    test('HospitalLocatorService Haversine parity (R = 6371.0 km)', () {
      expect(HospitalLocatorService.earthRadiusKm, equals(6371.0));

      final distSelf = HospitalLocatorService.calculateDistanceKm(40.7128, -74.0060, 40.7128, -74.0060);
      expect(distSelf, equals(0.0));

      final dist = HospitalLocatorService.calculateDistanceKm(40.7128, -74.0060, 40.7589, -73.9851);
      expect(dist, greaterThanOrEqualTo(5.0));
      expect(dist, lessThanOrEqualTo(5.8));
    });

    test('HospitalLocatorService offline facilities query within 20 km', () async {
      final locator = HospitalLocatorService();
      final facilities = await locator.getNearbyFacilities(
        latitude: 40.7128,
        longitude: -74.0060,
        radiusKm: 20.0,
      );

      expect(facilities.isNotEmpty, isTrue);
      expect(facilities.length, greaterThanOrEqualTo(4));

      // Verify all facilities are within 20 km and sorted ascending
      for (int i = 0; i < facilities.length; i++) {
        expect(facilities[i].distanceKm, lessThanOrEqualTo(20.0));
        if (i > 0) {
          expect(facilities[i].distanceKm, greaterThanOrEqualTo(facilities[i - 1].distanceKm));
        }
      }
    });

    testWidgets('EmergencyFacilityCard renders facility info and actions', (tester) async {
      bool navigateTapped = false;
      bool callTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmergencyFacilityCard(
              facility: testFacility,
              onNavigatePressed: () => navigateTapped = true,
              onCallPressed: () => callTapped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify visual content
      expect(find.text('TRAUMA CENTER'), findsOneWidget);
      expect(find.text('St. Jude University Level 1 Trauma Center'), findsOneWidget);
      expect(find.text('0.8 km (2 min)'), findsOneWidget);
      expect(find.text('Open 24/7'), findsOneWidget);
      expect(find.text('Level 1 Trauma'), findsOneWidget);
      expect(find.text('750 Hospital Plaza, University District'), findsOneWidget);

      // Verify buttons exist and tap triggers
      final navButton = find.text('Navigate via Maps');
      expect(navButton, findsOneWidget);
      await tester.tap(navButton);
      expect(navigateTapped, isTrue);

      final callButton = find.text('Call Desk');
      expect(callButton, findsOneWidget);
      await tester.tap(callButton);
      expect(callTapped, isTrue);
    });

    testWidgets('DiagnosticResultsScreen automatically slides up EmergencyFacilitySheet on Critical Referral', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => DiagnosticsProvider()),
            ChangeNotifierProvider(create: (_) => DiagnosticStateProvider()),
          ],
          child: const MaterialApp(
            home: DiagnosticResultsScreen(
              assessmentOverride: testCriticalAssessment,
              emergencyFacilitiesOverride: [testFacility],
            ),
          ),
        ),
      );

      // Pump frame to trigger postFrameCallback
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Verify sheet auto-opened
      expect(find.byType(EmergencyFacilitySheet), findsOneWidget);
      expect(find.text('CRITICAL REFERRAL DETECTED'), findsOneWidget);
      expect(find.text('Dismiss & View Full Screening Report'), findsOneWidget);

      // Verify dismiss button closes sheet and restores underlying report access
      await tester.tap(find.text('Dismiss & View Full Screening Report'));
      await tester.pumpAndSettle();

      expect(find.byType(EmergencyFacilitySheet), findsNothing);
      expect(find.text('Clinical Assessment Report'), findsOneWidget);
      expect(find.text('EMERGENCY FACILITY ROUTER'), findsOneWidget);
    });

    testWidgets('DiagnosticResultsScreen does NOT auto slide-up sheet on Low Risk screening', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => DiagnosticsProvider()),
            ChangeNotifierProvider(create: (_) => DiagnosticStateProvider()),
          ],
          child: const MaterialApp(
            home: DiagnosticResultsScreen(
              assessmentOverride: testLowRiskAssessment,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Verify sheet did NOT open
      expect(find.byType(EmergencyFacilitySheet), findsNothing);
      expect(find.text('CRITICAL REFERRAL DETECTED'), findsNothing);
      expect(find.text('Clinical Assessment Report'), findsOneWidget);
      expect(find.text('Mild Contact Irritation'), findsOneWidget);
    });
  });
}
