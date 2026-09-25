import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intellidesk_app/modules/cdss/models/cdss_evaluation.dart';
import 'package:intellidesk_app/modules/cdss/services/cdss_service.dart';
import 'package:intellidesk_app/modules/cdss/ui/cdss_decision_drawer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockEvaluation = CDSSEvaluationResult(
    id: 'CDSS-EVAL-TEST-001',
    screeningId: 'SCR-TEST-888',
    patientId: 'PATIENT-TEST-999',
    primaryICD11Code: 'CA00',
    primaryICD11Title: 'Acute Bronchitis',
    primaryICD11Uri: 'http://id.who.int/icd/release/11/mms/CA00',
    differentialDiagnoses: [
      DifferentialDiagnosisCandidate(
        code: 'CA00',
        title: 'Acute Bronchitis',
        category: 'Respiratory',
        uri: 'http://id.who.int/icd/release/11/mms/CA00',
        probability: 0.72,
        logitScore: 2.1,
        matchedCriteria: ['Persistent cough', 'Low-grade fever', 'Wheezing'],
        clinicalRationale: 'Classic lower airway acute inflammatory presentation.',
      ),
      DifferentialDiagnosisCandidate(
        code: 'CA40',
        title: 'Pneumonia',
        category: 'Respiratory',
        uri: 'http://id.who.int/icd/release/11/mms/CA40',
        probability: 0.18,
        logitScore: 0.8,
        matchedCriteria: ['Fever', 'Tachypnea'],
        clinicalRationale: 'Possible parenchymal involvement.',
      ),
      DifferentialDiagnosisCandidate(
        code: '1B10.0',
        title: 'Tuberculosis',
        category: 'Infectious',
        uri: 'http://id.who.int/icd/release/11/mms/1B10.0',
        probability: 0.10,
        logitScore: 0.2,
        matchedCriteria: ['Chronic cough'],
        clinicalRationale: 'Endemic risk consideration.',
      ),
    ],
    treatmentPathway: TreatmentPathway(
      primaryCode: 'CA00',
      primaryTitle: 'Acute Bronchitis',
      recommendedRx: [
        RecommendedMedication(
          genericName: 'Dextromethorphan',
          dosage: '15mg',
          frequency: 'TID PRN',
          duration: '5 days',
          clinicalNotes: 'Cough suppressant',
        ),
        RecommendedMedication(
          genericName: 'Guaifenesin',
          dosage: '400mg',
          frequency: 'Q4H PRN',
          duration: '5 days',
          clinicalNotes: 'Expectorant',
        ),
      ],
      labOrders: [
        'Complete Blood Count (CBC)',
        'C-Reactive Protein (CRP)',
      ],
      imagingOrders: [
        'Chest X-Ray (PA & Lateral)',
      ],
      monitoringFrequency: 'Daily vitals check',
      followUpDays: 5,
      urgentRedFlags: [
        'Hemoptysis',
        'Severe dyspnea at rest',
        'SpO2 < 92%',
      ],
      urgencyLevel: 'PROMPT_EVALUATION',
    ),
    temperatureScaling: 1.25,
    regulatoryDisclaimer:
        'AI Clinical Decision Support Tool — For Licensed Practitioner Reference Only. Requires Attending Physician Validation.',
    createdAt: DateTime.now().toIso8601String(),
    updatedAt: DateTime.now().toIso8601String(),
  );

  group('CDSS Data Models Tests', () {
    test('DifferentialDiagnosisCandidate serialization and deserialization', () {
      final candidate = DifferentialDiagnosisCandidate(
        code: 'CA40',
        title: 'Pneumonia',
        category: 'Respiratory',
        uri: 'http://id.who.int/icd/release/11/mms/CA40',
        probability: 0.28,
        logitScore: 1.5,
        matchedCriteria: ['Fever', 'SpO2 < 92%'],
        clinicalRationale: 'Parenchymal consolidation signs.',
      );

      final json = candidate.toJson();
      expect(json['code'], 'CA40');
      expect(json['uri'], 'http://id.who.int/icd/release/11/mms/CA40');
      expect(json['probability'], 0.28);

      final restored = DifferentialDiagnosisCandidate.fromJson(json);
      expect(restored.code, 'CA40');
      expect(restored.title, 'Pneumonia');
      expect(restored.matchedCriteria.length, 2);
    });

    test('TreatmentPathway serialization and deserialization', () {
      final pathway = TreatmentPathway(
        primaryCode: 'BA00',
        primaryTitle: 'Essential Hypertension',
        recommendedRx: [
          RecommendedMedication(
            genericName: 'Amlodipine',
            dosage: '5mg',
            frequency: 'QD',
            duration: '30 days',
            clinicalNotes: 'CCB first-line',
          ),
        ],
        labOrders: ['Basic Metabolic Panel (BMP)', 'Urinalysis'],
        imagingOrders: ['12-Lead ECG'],
        monitoringFrequency: 'Twice daily blood pressure logging',
        followUpDays: 14,
        urgentRedFlags: ['SBP > 180 mmHg or DBP > 120 mmHg', 'Chest pain'],
        urgencyLevel: 'ROUTINE',
      );

      final json = pathway.toJson();
      expect(json['primaryCode'], 'BA00');
      expect(json['followUpDays'], 14);
      expect((json['recommendedRx'] as List).length, 1);

      final restored = TreatmentPathway.fromJson(json);
      expect(restored.primaryCode, 'BA00');
      expect(restored.followUpDays, 14);
      expect(restored.labOrders.contains('12-Lead ECG'), false);
      expect(restored.imagingOrders.contains('12-Lead ECG'), true);
    });

    test('ClinicianApproval serialization and deserialization', () {
      final approval = ClinicianApproval(
        clinicianId: 'CMO-DR-PATEL',
        clinicianName: 'Dr. Priya Patel, MD',
        approvedAt: DateTime.now().toIso8601String(),
        isOverridden: true,
        originalCode: 'CA00',
        overriddenCode: 'CA40',
        overrideNotes: 'Chest crackles detected on auscultation, clinical signs consistent with lobar pneumonia.',
        signatureHash: 'a6c8e39f70b182d90a789123cba',
      );

      final json = approval.toJson();
      expect(json['isOverridden'], true);
      expect(json['originalCode'], 'CA00');
      expect(json['overriddenCode'], 'CA40');

      final restored = ClinicianApproval.fromJson(json);
      expect(restored.isOverridden, true);
      expect(restored.clinicianId, 'CMO-DR-PATEL');
      expect(restored.overrideNotes, contains('crackles'));
    });

    test('CDSSEvaluationResult full JSON roundtrip', () {
      final json = mockEvaluation.toJson();
      expect(json['id'], 'CDSS-EVAL-TEST-001');
      expect(json['primaryICD11Code'], 'CA00');
      expect((json['differentialDiagnoses'] as List).length, 3);
      expect(json['regulatoryDisclaimer'], contains('AI Clinical Decision Support Tool'));

      final restored = CDSSEvaluationResult.fromJson(json);
      expect(restored.id, 'CDSS-EVAL-TEST-001');
      expect(restored.primaryICD11Code, 'CA00');
      expect(restored.differentialDiagnoses.length, 3);
      expect(restored.treatmentPathway.recommendedRx.length, 2);
    });
  });

  group('CDSS Service Fallback & Offline Tests', () {
    test('CDSSService generates realistic fallback offline evaluation', () async {
      final service = CDSSService();
      final result = await service.evaluateScreening(
        screeningId: 'SCR-UNIT-TEST',
        patientId: 'PAT-UNIT-TEST',
        riskScore: 0.82,
        symptoms: {'rash': true, 'pruritus': true},
      );

      expect(result.screeningId, 'SCR-UNIT-TEST');
      expect(result.differentialDiagnoses.isNotEmpty, true);
      expect(result.primaryICD11Uri, contains('http://id.who.int/icd/release/11/mms'));
      expect(result.treatmentPathway.recommendedRx.isNotEmpty, true);
      expect(result.regulatoryDisclaimer, contains('AI Clinical Decision Support Tool'));
    });

    test('CDSSService maps Infectious Conjunctivitis primaryDiagnosis to 9A60 offline', () async {
      final service = CDSSService();
      final result = await service.evaluateScreening(
        screeningId: 'SCR-EYE-TEST',
        patientId: 'PAT-EYE-TEST',
        riskScore: 0.45,
        symptoms: {
          'primaryDiagnosis': 'Infectious Conjunctivitis',
          'clinicalSummary': 'Infectious Conjunctivitis. Erythema and ocular pruritus.',
          'recommendations': ['Erythromycin ointment', 'Artificial tears'],
          'riskLevel': 'MODERATE',
        },
      );

      expect(result.primaryICD11Code, '9A60');
      expect(result.primaryICD11Title, 'Infectious Conjunctivitis');
      expect(result.differentialDiagnoses.first.code, '9A60');
      expect(result.treatmentPathway.primaryCode, '9A60');
      expect(result.treatmentPathway.recommendedRx.any((rx) => rx.genericName.contains('Erythromycin')), true);
    });

    test('CDSSService approves and records signature offline', () async {
      final service = CDSSService();
      final updated = await service.approveEvaluation(
        evaluationId: 'CDSS-EVAL-OFFLINE-001',
        clinicianId: 'DR-TEST-007',
        clinicianName: 'Dr. James Tester',
        isOverridden: true,
        overriddenCode: 'CA40',
        overrideNotes: 'Confirmed by secondary imaging',
        currentEvaluation: mockEvaluation,
      );

      expect(updated.id, mockEvaluation.id);
      expect(updated.isOverridden, true);
      expect(updated.attendingClinicianApproval?.originalCode, 'CA00');
      expect(updated.primaryICD11Code, 'CA40');
      expect(updated.attendingClinicianApproval?.signatureHash.isNotEmpty, true);
    });
  });

  group('CDSS Decision Drawer Widget Tests', () {
    testWidgets('CDSS Decision Drawer renders disclaimer, DDx list and minimum 48px touch targets', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      CDSSEvaluationResult? capturedUpdatedEvaluation;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('launchDrawerBtn'),
                onPressed: () {
                  CDSSDecisionDrawer.show(
                    context,
                    evaluation: mockEvaluation,
                    isClinicianView: true,
                    onApproved: (updated) {
                      capturedUpdatedEvaluation = updated;
                    },
                  );
                },
                child: const Text('Open CDSS'),
              ),
            ),
          ),
        ),
      );

      // Open drawer
      await tester.tap(find.byKey(const Key('launchDrawerBtn')));
      await tester.pumpAndSettle();

      // Verify title & primary diagnosis
      expect(find.text('Clinical Decision Support (CDSS)'), findsOneWidget);
      expect(find.textContaining('CA00'), findsWidgets);

      // Verify WHO ICD-11 URI stem
      expect(find.textContaining('http://id.who.int/icd/release/11/mms/CA00'), findsOneWidget);

      // Verify mandatory disclaimer
      expect(find.text(mockEvaluation.regulatoryDisclaimer), findsOneWidget);

      // Verify Differential Diagnoses are rendered
      expect(find.textContaining('CA40'), findsWidgets);
      expect(find.textContaining('1B10.0'), findsWidgets);

      // Verify Treatment Pathway items
      expect(find.text('Complete Blood Count (CBC)'), findsOneWidget);
      expect(find.text('Chest X-Ray (PA & Lateral)'), findsOneWidget);

      // Verify Touch Targets: find approve button and check height >= 48px
      final approveBtnFinder = find.byKey(const Key('approveTreatmentPlanButton'));
      expect(approveBtnFinder, findsOneWidget);
      final RenderBox approveBox = tester.renderObject(approveBtnFinder);
      expect(approveBox.size.height, greaterThanOrEqualTo(48.0));

      // Tap Approve & Sign-Off button
      await tester.tap(approveBtnFinder);
      await tester.pumpAndSettle();

      // Verify approval callback received
      expect(capturedUpdatedEvaluation, isNotNull);
      expect(capturedUpdatedEvaluation!.primaryICD11Code, 'CA00');
      expect(capturedUpdatedEvaluation!.isApproved, true);
      expect(capturedUpdatedEvaluation!.isOverridden, false);
      expect(capturedUpdatedEvaluation!.attendingClinicianApproval?.signatureHash.isNotEmpty, true);
    });

    testWidgets('CDSS Decision Drawer supports diagnostic code override workflow', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      CDSSEvaluationResult? capturedUpdatedEvaluation;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('launchDrawerBtn2'),
                onPressed: () {
                  CDSSDecisionDrawer.show(
                    context,
                    evaluation: mockEvaluation,
                    isClinicianView: true,
                    onApproved: (updated) {
                      capturedUpdatedEvaluation = updated;
                    },
                  );
                },
                child: const Text('Open CDSS'),
              ),
            ),
          ),
        ),
      );

      // Open drawer
      await tester.tap(find.byKey(const Key('launchDrawerBtn2')));
      await tester.pumpAndSettle();

      // Tap Override ICD-11 Code toggle
      final overrideToggle = find.text('Override AI Diagnosis (ICD-11)');
      expect(overrideToggle, findsOneWidget);
      await tester.tap(overrideToggle);
      await tester.pumpAndSettle();

      // Enter override code and rationale notes
      final codeField = find.widgetWithText(TextField, 'New ICD-11 Code (e.g. CA40, QC10, 1B10.0)');
      final notesField = find.widgetWithText(TextField, 'Clinical Justification & Notes');
      expect(codeField, findsOneWidget);
      expect(notesField, findsOneWidget);

      await tester.enterText(codeField, 'CA40');
      await tester.enterText(notesField, 'Clinical presentation indicates consolidation.');
      await tester.pumpAndSettle();

      // Tap Sign & Confirm Override
      final confirmBtn = find.byKey(const Key('confirmOverrideButton'));
      expect(confirmBtn, findsOneWidget);
      final RenderBox confirmBox = tester.renderObject(confirmBtn);
      expect(confirmBox.size.height, greaterThanOrEqualTo(48.0));

      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Verify captured approval reflects override provenance
      expect(capturedUpdatedEvaluation, isNotNull);
      expect(capturedUpdatedEvaluation!.isOverridden, true);
      expect(capturedUpdatedEvaluation!.primaryICD11Code, 'CA40');
      expect(capturedUpdatedEvaluation!.attendingClinicianApproval?.originalCode, 'CA00');
      expect(capturedUpdatedEvaluation!.attendingClinicianApproval?.overriddenCode, 'CA40');
      expect(capturedUpdatedEvaluation!.attendingClinicianApproval?.overrideNotes, contains('consolidation'));
      expect(capturedUpdatedEvaluation!.attendingClinicianApproval?.signatureHash.isNotEmpty, true);
    });

    testWidgets('CDSS Decision Drawer patient view enforces institutional clinical assignment and hides clinician sign-off', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('launchDrawerPatientBtn'),
                onPressed: () {
                  CDSSDecisionDrawer.show(
                    context,
                    evaluation: mockEvaluation,
                    isClinicianView: false,
                    institutionId: 'inst-columbia',
                    institutionName: 'Columbia Health Network',
                  );
                },
                child: const Text('Open CDSS as Patient'),
              ),
            ),
          ),
        ),
      );

      // Open drawer as patient
      await tester.tap(find.byKey(const Key('launchDrawerPatientBtn')));
      await tester.pumpAndSettle();

      // Verify institutional assignment section is displayed
      expect(find.text('Institutional Clinical Assignment & Review'), findsOneWidget);
      expect(find.text('Columbia Health Network'), findsOneWidget);
      expect(find.text('Pending Review'), findsOneWidget);
      expect(find.textContaining('directly routed to your institution\'s medical administration'), findsOneWidget);

      // Verify patient CANNOT see clinician approval controls
      expect(find.byKey(const Key('approveTreatmentPlanButton')), findsNothing);
      expect(find.text('Override AI Diagnosis (ICD-11)'), findsNothing);
      expect(find.text('Clinician Name & Credentials'), findsNothing);

      // Verify dispatched to institution button and touch target >= 48px
      final dispatchBtnFinder = find.byKey(const Key('dispatchedToInstitutionButton'));
      expect(dispatchBtnFinder, findsOneWidget);
      final RenderBox dispatchBox = tester.renderObject(dispatchBtnFinder);
      expect(dispatchBox.size.height, greaterThanOrEqualTo(48.0));

      // Tap dispatched button and verify feedback
      await tester.tap(dispatchBtnFinder);
      await tester.pumpAndSettle();
      expect(find.textContaining('medical board. Attending physician will review shortly.'), findsOneWidget);
    });
  });
}
