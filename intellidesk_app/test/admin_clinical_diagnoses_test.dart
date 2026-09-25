import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intellidesk_app/providers/auth_provider.dart';
import 'package:intellidesk_app/providers/ticket_provider.dart';
import 'package:intellidesk_app/screens/admin/admin_clinical_diagnoses_screen.dart';
import 'package:intellidesk_app/screens/admin/admin_main_screen.dart';
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

      await tester.pumpWidget(buildAdminApp(
        child: const Scaffold(body: AdminClinicalDiagnosesScreen(autoFetch: false)),
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
