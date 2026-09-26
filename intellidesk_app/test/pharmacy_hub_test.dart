import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellidesk_app/screens/patient/pharmacy_hub_screen.dart';
import 'package:intellidesk_app/modules/pharmacy/models/medication_entity.dart';
import 'package:intellidesk_app/modules/pharmacy/ui/prescription_review_modal.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testSafeSummary = RxScanSummary(
    id: 'scan-safe-001',
    patientId: 'PAT-2026-TEST',
    extractedDrugs: [
      ExtractedMedication(
        brandName: 'Amoxicillin Trihydrate 500mg Oral Capsule',
        activeIngredient: 'Amoxicillin',
        dosage: '500mg',
        frequency: 'TID',
        duration: '5 days',
        rawText: 'Amoxicillin 500mg TID 5 days',
        confidence: 0.98,
        allergenGroup: 'PENICILLINS',
      ),
      ExtractedMedication(
        brandName: 'Paracetamol 500mg Rapid Release Tablets',
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
    patientId: 'PAT-2026-TEST',
    extractedDrugs: [
      ExtractedMedication(
        brandName: 'Augmentin 625mg Extra Strength Tablets',
        activeIngredient: 'Amoxicillin-Clavulanate',
        dosage: '625mg',
        frequency: '1-0-1',
        duration: '7 days',
        rawText: 'Tab Augmentin 625mg 1-0-1 for 7 days',
        confidence: 0.96,
        allergenGroup: 'PENICILLINS',
      ),
      ExtractedMedication(
        brandName: 'Cardioprotective Aspirin 325mg EC',
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
        drugA: 'Warfarin Sodium',
        drugB: 'Aspirin',
        severity: DDISeverity.contraindicatedSevere,
        clinicalMechanism: 'Dual anticoagulation and antiplatelet potentiation compound severe risk of major hemorrhage.',
        mitigationAdvice: 'Avoid concurrent use unless strictly supervised by a specialist.',
      ),
    ],
    allergyConflicts: [
      AllergyConflictResult(
        allergenGroup: 'PENICILLINS',
        matchedDrug: 'Augmentin 625mg Extra Strength Tablets',
        activeIngredient: 'Amoxicillin-Clavulanate',
        patientReaction: 'Severe Anaphylaxis and Urticaria with Bronchospasm',
        severity: 'HIGH_RISK_ALLERGY',
        alertMessage: 'CRITICAL ALLERGY ALERT: Patient has documented allergy to "PENICILLINS". Prescribed Augmentin is a Penicillin derivative!',
      ),
    ],
    hasSafetyConflict: true,
    requiresPharmacistReview: true,
    rawOcrText: 'Augmentin 625mg 1-0-1 7d\nAspirin 325mg QD',
  );

  final sampleMedications = [
    {
      'id': 'med-001',
      'brand': 'Lipitor Film-Coated',
      'generic': 'Atorvastatin Calcium',
      'dosage': '20mg once daily',
      'frequency': 'At bedtime',
      'status': 'ACTIVE',
      'indication': 'Hypercholesterolemia Management',
    },
    {
      'id': 'med-002',
      'brand': 'Glucophage XR 500mg',
      'generic': 'Metformin Hydrochloride',
      'dosage': '500mg twice daily',
      'frequency': 'With meals (BID)',
      'status': 'ACTIVE',
      'indication': 'Type 2 Diabetes Mellitus Glycemic Control',
    },
  ];

  Widget buildTestScreen({
    List<Map<String, dynamic>>? initialMeds,
    List<String>? initialAllergies,
  }) {
    return MaterialApp(
      home: PharmacyHubScreen(
        initialMeds: initialMeds,
        initialAllergies: initialAllergies,
        autoFetch: false,
      ),
    );
  }

  group('PharmacyHubScreen Layout & Widget Tests', () {
    testWidgets('Renders Hero Banner, Scan Card, Allergy Tile, and Empty State Placeholder', (tester) async {
      await tester.pumpWidget(buildTestScreen(initialMeds: [], initialAllergies: []));
      await tester.pumpAndSettle();

      // Hero banner
      expect(find.text('Medication Safety Check'), findsOneWidget);
      expect(find.text('Real-Time Drug Interaction & Allergy Verification'), findsOneWidget);

      // Scan card
      expect(find.text('Scan Prescription Slip'), findsOneWidget);
      expect(find.text('Upload & Verify'), findsOneWidget);
      expect(find.text('Demo Slip'), findsOneWidget);

      // Recorded patient allergies tile
      expect(find.text('Recorded Patient Allergies'), findsOneWidget);
      expect(find.text('No active drug allergies on file'), findsOneWidget);

      // Empty state
      expect(find.text('No active medications in your database record.'), findsOneWidget);
      expect(find.text('0 in DB'), findsOneWidget);
      expect(find.text('Add Med'), findsOneWidget);
    });

    testWidgets('Renders Populated Medication Roster with Indications and Allergies', (tester) async {
      await tester.pumpWidget(
        buildTestScreen(
          initialMeds: sampleMedications,
          initialAllergies: ['PENICILLINS', 'SULFA'],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 in DB'), findsOneWidget);
      expect(find.text('Active: PENICILLINS, SULFA'), findsOneWidget);

      expect(find.text('Lipitor Film-Coated'), findsOneWidget);
      expect(find.text('(Atorvastatin Calcium)'), findsOneWidget);
      expect(find.text('20mg once daily • At bedtime'), findsOneWidget);
      expect(find.text('Indication: Hypercholesterolemia Management'), findsOneWidget);

      expect(find.text('Glucophage XR 500mg'), findsOneWidget);
      expect(find.text('(Metformin Hydrochloride)'), findsOneWidget);
      expect(find.text('500mg twice daily • With meals (BID)'), findsOneWidget);
      expect(find.text('Indication: Type 2 Diabetes Mellitus Glycemic Control'), findsOneWidget);
    });

    testWidgets('Add Med button opens Add Prescribed Medication dialog', (tester) async {
      await tester.pumpWidget(buildTestScreen(initialMeds: [], initialAllergies: []));
      await tester.pumpAndSettle();

      final addBtn = find.text('Add Med');
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      expect(find.text('Add Prescribed Medication'), findsOneWidget);
      expect(find.text('Brand / Commercial Name'), findsOneWidget);
      expect(find.text('Generic Active Ingredient'), findsOneWidget);
      expect(find.text('Dosage & Instructions'), findsOneWidget);
      expect(find.text('Save to Record'), findsOneWidget);

      // Tap Cancel to dismiss dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Add Prescribed Medication'), findsNothing);
    });

    testWidgets('Narrow viewport (320x600) renders without RenderFlex pixel overflows', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestScreen(
          initialMeds: sampleMedications,
          initialAllergies: ['PENICILLINS', 'CEPHALOSPORINS', 'SULFONAMIDES'],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Medication Safety Check'), findsOneWidget);
      expect(find.text('Scan Prescription Slip'), findsOneWidget);
      expect(find.text('Active Medications Roster'), findsOneWidget);
    });

    testWidgets('Extra narrow viewport (280x600) renders without RenderFlex pixel overflows', (tester) async {
      tester.view.physicalSize = const Size(280, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        buildTestScreen(
          initialMeds: sampleMedications,
          initialAllergies: ['PENICILLINS'],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Medication Safety Check'), findsOneWidget);
    });
  });

  group('PrescriptionReviewModal Tests & Overflow Prevention', () {
    testWidgets('Renders Safe Summary and handles Confirm button callback', (tester) async {
      bool confirmed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrescriptionReviewModal(
              summary: testSafeSummary,
              onConfirm: () => confirmed = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Prescription Safety Review'), findsOneWidget);
      expect(find.text('SAFE / CLEAR - NO ADVERSE INTERACTIONS'), findsOneWidget);
      expect(find.text('Confirm & Attach'), findsOneWidget);

      await tester.tap(find.text('Confirm & Attach'));
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
    });

    testWidgets('Renders Critical Summary and handles Discard button callback', (tester) async {
      bool discarded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrescriptionReviewModal(
              summary: testCriticalSummary,
              onDiscard: () => discarded = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CONTRAINDICATED ALLERGY / DDI ALERT'), findsOneWidget);
      expect(find.text('Acknowledge & Attach'), findsOneWidget);
      expect(find.text('Discard / Re-scan'), findsOneWidget);

      await tester.tap(find.text('Discard / Re-scan'));
      await tester.pumpAndSettle();

      expect(discarded, isTrue);
    });

    testWidgets('PrescriptionReviewModal renders on narrow screen (320x600) with zero RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrescriptionReviewModal(
              summary: testCriticalSummary,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Prescription Safety Review'), findsOneWidget);
      expect(find.text('CONTRAINDICATED ALLERGY / DDI ALERT'), findsOneWidget);
    });
  });
}
