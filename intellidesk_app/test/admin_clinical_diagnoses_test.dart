import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intellidesk_app/providers/auth_provider.dart';
import 'package:intellidesk_app/providers/ticket_provider.dart';
import 'package:intellidesk_app/screens/admin/admin_clinical_diagnoses_screen.dart';
import 'package:intellidesk_app/screens/admin/admin_main_screen.dart';
import 'package:intellidesk_app/modules/pharmacy/models/medication_entity.dart';
import 'package:intellidesk_app/modules/pharmacy/ui/admin_patient_pharmacy_modal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockTicketProvider extends TicketProvider {
  @override
  Future<void> init() async {}

  @override
  bool get isConnected => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'intellidesk_auth_session': json.encode({
        'id': 'admin-01',
        'name': 'Dr. Jane Admin',
        'email': 'admin@intellidesk.health',
        'role': 'admin',
        'department': 'Emergency Medicine',
        'institutionId': 'inst-hosp-01',
      }),
    });
  });

  Widget buildAdminApp({Widget? child}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider<TicketProvider>(create: (_) => MockTicketProvider()),
      ],
      child: MaterialApp(
        theme: ThemeData.light(),
        home: child ?? const Scaffold(body: AdminClinicalDiagnosesScreen(autoFetch: false)),
      ),
    );
  }

  group('Admin Multimodal Clinical Diagnoses Tests', () {
    testWidgets('AdminClinicalDiagnosesScreen renders KPI cards, search bar, and patient roster', (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testPatients = [
        {
          'patientId': 'pat-test-01',
          'patientName': 'Alex Rivera',
          'institutionId': 'nano123',
          'totalDiagnoses': 1,
          'highestRiskLevel': 'LOW',
          'highestRiskScore': 0.18,
          'latestDiagnosis': 'Resolved Upper Respiratory Tract Infection',
          'latestICD11': 'CA01',
          'latestScreeningDate': DateTime.now().toIso8601String(),
          'hasPhysiologicalAlert': false,
          'hasDDIConflict': false,
          'screenings': [],
        }
      ];

      await tester.pumpWidget(buildAdminApp(
        child: Scaffold(
          body: AdminClinicalDiagnosesScreen(
            autoFetch: false,
            initialPatients: testPatients,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      // Verify KPI Metric Cards
      expect(find.text('Screened Patients'), findsOneWidget);
      expect(find.text('Urgent / High Flags'), findsOneWidget);
      expect(find.text('Diagnostic Encounters'), findsOneWidget);
      expect(find.text('Safety Interceptions'), findsOneWidget);

      // Verify Search bar and Risk Filter Chips
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('All Risks'), findsOneWidget);
      expect(find.text('CRITICAL'), findsWidgets);
      expect(find.text('HIGH'), findsWidgets);
      expect(find.text('MODERATE'), findsWidgets);
      expect(find.text('LOW'), findsWidgets);

      // Verify View Switcher Icons
      expect(find.byIcon(Icons.people_alt_outlined), findsOneWidget);
      expect(find.byIcon(Icons.view_agenda_outlined), findsOneWidget);

      // Verify Patient Roster cards are rendered
      expect(find.text('Alex Rivera'), findsWidgets);
    });

    testWidgets('Tapping patient avatar on card opens AdminPatientPharmacyModal', (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testPatients = [
        {
          'patientId': 'pat-test-01',
          'patientName': 'Alex Rivera',
          'institutionId': 'nano123',
          'totalDiagnoses': 1,
          'highestRiskLevel': 'LOW',
          'highestRiskScore': 0.18,
          'latestDiagnosis': 'Resolved Upper Respiratory Tract Infection',
          'latestICD11': 'CA01',
          'latestScreeningDate': DateTime.now().toIso8601String(),
          'hasPhysiologicalAlert': false,
          'hasDDIConflict': false,
          'screenings': [],
        }
      ];

      await tester.pumpWidget(buildAdminApp(
        child: Scaffold(
          body: AdminClinicalDiagnosesScreen(
            autoFetch: false,
            initialPatients: testPatients,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Find the patient avatar on the card
      final avatar = find.byType(CircleAvatar).first;
      expect(avatar, findsOneWidget);

      // Tap patient avatar to open pharmacy modal
      await tester.tap(avatar);
      await tester.pumpAndSettle();

      // Verify AdminPatientPharmacyModal opens with patient information
      expect(find.byType(AdminPatientPharmacyModal), findsOneWidget);
      expect(find.text('Admin Pharmacy Hub & Clinical Medication Dossier'), findsOneWidget);
      expect(find.text('ID: pat-test-01'), findsOneWidget);
      expect(find.text('Real-Time Safety Intelligence'), findsOneWidget);
    });

    testWidgets('AdminPatientPharmacyModal displays Active Meds, Allergies, and Prescriptions tabs', (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testMeds = [
        PatientMedication(
          id: 'med-01',
          patientId: 'pat-test-01',
          medicationName: 'Warfarin Sodium',
          activeIngredient: 'Warfarin',
          dosage: '5mg',
        ),
        PatientMedication(
          id: 'med-02',
          patientId: 'pat-test-01',
          medicationName: 'Aspirin Cardio',
          activeIngredient: 'Aspirin',
          dosage: '81mg',
        ),
      ];

      final testAllergies = [
        PatientAllergy(
          id: 'alg-01',
          patientId: 'pat-test-01',
          allergenGroup: 'PENICILLINS',
          reactionDescription: 'Severe rash and angioedema',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdminPatientPharmacyModal(
              patientId: 'pat-test-01',
              patientName: 'Alex Rivera',
              initialMeds: testMeds,
              initialAllergies: testAllergies,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header and DDI warning banner
      expect(find.text('Alex Rivera'), findsOneWidget);
      expect(find.text('CRITICAL SAFETY CONFLICT DETECTED'), findsOneWidget);
      expect(find.textContaining('Warfarin  ↔  Aspirin'), findsOneWidget);

      // Switch to Medications tab via ChoiceChip
      final medsChip = find.widgetWithText(ChoiceChip, 'Medications (2)');
      expect(medsChip, findsOneWidget);
      await tester.tap(medsChip);
      await tester.pumpAndSettle();

      expect(find.text('Warfarin Sodium'), findsOneWidget);
      expect(find.text('Aspirin Cardio'), findsOneWidget);

      // Switch to Allergies tab via ChoiceChip
      final algChip = find.widgetWithText(ChoiceChip, 'Allergies (1)');
      expect(algChip, findsOneWidget);
      await tester.tap(algChip);
      await tester.pumpAndSettle();

      expect(find.text('PENICILLINS'), findsOneWidget);
      expect(find.text('Severe rash and angioedema'), findsOneWidget);
    });

    testWidgets('AdminMainScreen displays Patient Diagnoses destination in NavigationRail and navigates', (tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildAdminApp(child: const AdminMainScreen()));
      await tester.pump(const Duration(milliseconds: 200));

      // Find biotech icon destination in NavigationRail
      final biotechIcon = find.byIcon(Icons.biotech_outlined);
      expect(biotechIcon, findsOneWidget);

      // Tap on Patient Diagnoses icon
      await tester.tap(biotechIcon, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));

      // Header title should contain Patient Clinical Diagnoses & CDSS Oversight
      expect(find.textContaining('Patient Clinical Diagnoses & CDSS Oversight'), findsOneWidget);
    });
  });
}

