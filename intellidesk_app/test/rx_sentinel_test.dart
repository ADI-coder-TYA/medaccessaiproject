import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellidesk_app/modules/pharmacy/models/medication_entity.dart';
import 'package:intellidesk_app/modules/pharmacy/ui/prescription_review_modal.dart';
import 'package:intellidesk_app/modules/pharmacy/ui/patient_allergy_profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testSafeSummary = RxScanSummary(
    id: 'scan-safe-001',
    patientId: 'patient-test-001',
    extractedDrugs: [
      ExtractedMedication(
        brandName: 'Amoxicillin 500mg',
        activeIngredient: 'Amoxicillin',
        dosage: '500mg',
        frequency: 'TID',
        duration: '5 days',
        rawText: 'Amoxicillin 500mg TID 5 days',
        confidence: 0.98,
        allergenGroup: 'PENICILLINS',
      ),
      ExtractedMedication(
        brandName: 'Paracetamol 500mg',
        activeIngredient: 'Acetaminophen',
        dosage: '500mg',
        frequency: 'PRN',
        duration: '3 days',
        rawText: 'Paracetamol 500mg PRN 3 days',
        confidence: 0.95,
      ),
    ],
    ddiWarnings: [],
    allergyConflicts: [],
    hasSafetyConflict: false,
    requiresPharmacistReview: false,
    rawOcrText: 'Amoxicillin 500mg TID 5 days\nParacetamol 500mg PRN',
  );

  const testCriticalSummary = RxScanSummary(
    id: 'scan-crit-002',
    patientId: 'patient-test-002',
    extractedDrugs: [
      ExtractedMedication(
        brandName: 'Augmentin 625mg',
        activeIngredient: 'Amoxicillin-Clavulanate',
        dosage: '625mg',
        frequency: '1-0-1',
        duration: '7 days',
        rawText: 'Tab Augmentin 625mg 1-0-1 for 7 days',
        confidence: 0.96,
        allergenGroup: 'PENICILLINS',
      ),
      ExtractedMedication(
        brandName: 'Aspirin 325mg',
        activeIngredient: 'Aspirin',
        dosage: '325mg',
        frequency: 'QD',
        rawText: 'Aspirin 325mg QD',
        confidence: 0.99,
        allergenGroup: 'NSAIDS',
      ),
    ],
    ddiWarnings: [
      DDIPairResult(
        drugA: 'Warfarin',
        drugB: 'Aspirin',
        severity: DDISeverity.contraindicatedSevere,
        clinicalMechanism: 'Dual anticoagulation and antiplatelet potentiation compound severe risk of major hemorrhage.',
        mitigationAdvice: 'Avoid concurrent use unless strictly supervised by a specialist.',
      ),
    ],
    allergyConflicts: [
      AllergyConflictResult(
        allergenGroup: 'PENICILLINS',
        matchedDrug: 'Augmentin 625mg',
        activeIngredient: 'Amoxicillin-Clavulanate',
        patientReaction: 'Severe Anaphylaxis and Urticaria',
        severity: 'HIGH_RISK_ALLERGY',
        alertMessage: 'CRITICAL ALLERGY ALERT: Patient has documented allergy to "PENICILLINS". Prescribed Augmentin is a Penicillin derivative!',
      ),
    ],
    hasSafetyConflict: true,
    requiresPharmacistReview: true,
    rawOcrText: 'Augmentin 625mg 1-0-1 7d\nAspirin 325mg QD',
  );

  group('RxSentinel Models & Serialization Tests', () {
    test('ExtractedMedication model JSON roundtrip', () {
      final json = testSafeSummary.extractedDrugs.first.toJson();
      final revived = ExtractedMedication.fromJson(json);

      expect(revived.brandName, equals('Amoxicillin 500mg'));
      expect(revived.activeIngredient, equals('Amoxicillin'));
      expect(revived.dosage, equals('500mg'));
      expect(revived.frequency, equals('TID'));
      expect(revived.duration, equals('5 days'));
      expect(revived.confidence, equals(0.98));
    });

    test('DDIPairResult severity mapping', () {
      final severe = DDIPairResult.fromJson({
        'drugA': 'Warfarin',
        'drugB': 'Aspirin',
        'severity': 'CONTRAINDICATED_SEVERE',
        'clinicalMechanism': 'Bleeding risk',
        'mitigationAdvice': 'Avoid concurrent use',
      });
      expect(severe.severity, equals(DDISeverity.contraindicatedSevere));
      expect(severe.severity.displayName, equals('CONTRAINDICATED SEVERE'));

      final mod = DDIPairResult.fromJson({
        'drugA': 'Cipro',
        'drugB': 'Calcium',
        'severity': 'MODERATE_MONITOR',
      });
      expect(mod.severity, equals(DDISeverity.moderateMonitor));

      final safe = DDIPairResult.fromJson({
        'drugA': 'Tylenol',
        'drugB': 'Amox',
        'severity': 'SAFE',
      });
      expect(safe.severity, equals(DDISeverity.safe));
    });

    test('RxScanSummary JSON serialization and flag parity', () {
      final json = testCriticalSummary.toJson();
      final revived = RxScanSummary.fromJson(json);

      expect(revived.hasSafetyConflict, isTrue);
      expect(revived.requiresPharmacistReview, isTrue);
      expect(revived.ddiWarnings.length, equals(1));
      expect(revived.allergyConflicts.length, equals(1));
    });
  });

  group('PrescriptionReviewModal Widget Tests', () {
    testWidgets('Renders Safe / Clear prescription review state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrescriptionReviewModal(summary: testSafeSummary),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RxSentinel Safety Review'), findsOneWidget);
      expect(find.text('SAFE / CLEAR - NO ADVERSE INTERACTIONS'), findsOneWidget);
      expect(find.text('Amoxicillin 500mg'), findsOneWidget);
      expect(find.text('Paracetamol 500mg'), findsOneWidget);
      expect(find.text('Confirm & Attach'), findsOneWidget);
      expect(find.text('ALLERGY CONFLICTS DETECTED'), findsNothing);
      expect(find.text('DRUG INTERACTIONS'), findsNothing);
    });

    testWidgets('Renders Critical Alert Banner on severe DDI and allergy conflict', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrescriptionReviewModal(summary: testCriticalSummary),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CONTRAINDICATED ALLERGY / DDI ALERT'), findsOneWidget);
      expect(find.text('ALLERGY CONFLICTS DETECTED (1)'), findsOneWidget);
      expect(find.text('DRUG INTERACTIONS (1)'), findsOneWidget);
      expect(find.text('Warfarin + Aspirin'), findsOneWidget);
      expect(find.text('CONTRAINDICATED SEVERE'), findsOneWidget);
      expect(find.text('Acknowledge & Attach'), findsOneWidget);
      expect(find.byIcon(Icons.dangerous_outlined), findsOneWidget);
    });
  });

  group('PatientAllergyProfileScreen Widget Tests', () {
    testWidgets('Renders known allergen chips and toggle interactions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PatientAllergyProfileScreen(patientId: 'patient-test-ui'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Medication & Allergy Sentinel'), findsOneWidget);
      expect(find.text('RxSentinel Safety Shield'), findsOneWidget);
      expect(find.text('KNOWN DRUG ALLERGIES'), findsOneWidget);
      expect(find.text('PENICILLINS'), findsOneWidget);
      expect(find.text('NSAIDS'), findsOneWidget);
      expect(find.text('SULFA'), findsOneWidget);
      expect(find.text('OPIOIDS'), findsOneWidget);

      // Tap on PENICILLINS chip to toggle
      await tester.tap(find.text('PENICILLINS'));
      await tester.pumpAndSettle();

      expect(find.text('PENICILLINS'), findsOneWidget);
    });
  });
}
