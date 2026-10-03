import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intellidesk_app/models/user_role.dart';
import 'package:intellidesk_app/providers/auth_provider.dart';
import 'package:intellidesk_app/providers/ticket_provider.dart';
import 'package:intellidesk_app/modules/diagnostics/providers/diagnostics_provider.dart';
import 'package:intellidesk_app/modules/diagnostics/providers/diagnostic_state_provider.dart';
import 'package:intellidesk_app/screens/patient/patient_main_screen.dart';
import 'package:intellidesk_app/screens/patient/patient_clinical_dashboard.dart';
import 'package:intellidesk_app/services/socket_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestApp({Widget? child, AuthProvider? auth}) {
    final authProvider = auth ?? AuthProvider();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider(create: (_) => TicketProvider()),
        ChangeNotifierProvider(create: (_) => DiagnosticsProvider()),
        ChangeNotifierProvider(create: (_) => DiagnosticStateProvider()),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: child ?? const PatientMainScreen(),
      ),
    );
  }

  group('Patient Clinical AI Dashboard Tests', () {
    testWidgets('Renders executive header, flagship checkup hero, vitals pulse bar, and EHR passport', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final auth = AuthProvider();
      await auth.loginAsPatient();

      await tester.pumpWidget(buildTestApp(
        auth: auth,
        child: const Scaffold(
          body: PatientClinicalDashboard(
            enablePulseAnimation: false,
            autoFetchOverview: false,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      // Executive Header
      expect(find.text('Clinical Monitoring Active'), findsOneWidget);
      expect(find.text('SOS 911'), findsOneWidget);

      // Hero Multimodal Clinical Checkup Card (Core Flagship Feature)
      expect(find.text('Complete Multimodal Health Checkup'), findsOneWidget);
      expect(find.text('Optical Vision'), findsOneWidget);
      expect(find.text('Acoustic Cough'), findsOneWidget);
      expect(find.text('Touchless Vitals'), findsWidgets);
      expect(find.text('CDSS Co-pilot'), findsOneWidget);
      final checkupBtn = find.byKey(const Key('heroStartCheckupButton'));
      expect(checkupBtn, findsOneWidget);

      // Real-time vitals card
      expect(find.text('Contactless Vitals Pulse'), findsOneWidget);
      expect(find.text('Heart Rate'), findsOneWidget);
      expect(find.text('Blood O₂'), findsOneWidget);
      expect(find.text('Respiration'), findsOneWidget);
      expect(find.text('HRV'), findsOneWidget);

      // Instant 15s rPPG Trigger Button
      final vitalsBtn = find.byKey(const Key('dashboardQuickVitalsScanButton'));
      expect(vitalsBtn, findsOneWidget);
      final RenderBox box = tester.renderObject(vitalsBtn);
      expect(box.size.height, greaterThanOrEqualTo(48.0));

      // AI Clinical Suites Grid
      expect(find.text('Multimodal Checkup'), findsOneWidget);
      expect(find.text('Pharmacy & Safety'), findsOneWidget);
      expect(find.text('Emergency Locator'), findsOneWidget);
      expect(find.text('Healing Progression'), findsOneWidget);
      expect(find.text('Clinical Health Chat'), findsOneWidget);
      expect(find.text('Medical Passport & EHR'), findsOneWidget);

      // Emergency Medical Passport Card
      expect(find.text('Emergency Medical Passport'), findsOneWidget);
      expect(find.text('Verified EHR'), findsOneWidget);
      expect(find.text('ALLERGIES'), findsOneWidget);
      expect(find.text('MEDICATIONS'), findsOneWidget);
      expect(find.text('EMERGENCY CONTACT'), findsOneWidget);
      expect(find.text('BLOOD GROUP'), findsNothing);
      expect(find.text('HEALTH PLAN'), findsNothing);
      expect(find.text('CARE STATUS'), findsNothing);
      expect(find.text('Clinical Consultation'), findsOneWidget);
      expect(find.text('Open EHR Vault'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('PatientMainScreen renders 5-tab executive clinical navigation bar and navigates', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final auth = AuthProvider();
      await auth.loginAsPatient();

      await tester.pumpWidget(buildTestApp(
        auth: auth,
        child: const PatientMainScreen(),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      // Check all 5 navigation destination labels
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Checkup'), findsWidgets);
      expect(find.text('Pharmacy'), findsWidgets);
      expect(find.text('Emergency'), findsWidgets);
      expect(find.text('Records'), findsWidgets);

      // Tap on Checkup tab
      await tester.tap(find.text('Checkup').first);
      await tester.pump(const Duration(milliseconds: 300));

      // Should show Clinical Health Intake screen
      expect(find.text('Clinical Health Intake'), findsOneWidget);

      // Tap on Pharmacy tab
      await tester.tap(find.text('Pharmacy').first);
      await tester.pump(const Duration(milliseconds: 300));

      // Should show Clinical Pharmacy Hub screen
      expect(find.text('Clinical Pharmacy Hub'), findsOneWidget);
      expect(find.text('Medication Safety Check'), findsOneWidget);

      // Tap on Emergency tab
      await tester.tap(find.text('Emergency').first);
      await tester.pump(const Duration(milliseconds: 300));

      // Should show Emergency Care Navigator
      expect(find.text('Emergency Care & Facility Navigator'), findsOneWidget);
      expect(find.text('24/7 Immediate Emergency Dispatch'), findsOneWidget);

      // Tap on Records tab
      await tester.tap(find.text('Records').first);
      await tester.pump(const Duration(milliseconds: 300));

      // Should show Electronic Health Records & History
      expect(find.text('Electronic Health Records & History'), findsOneWidget);
      expect(find.text('Recovery & Trends'), findsOneWidget);
      expect(find.text('Medical Passport'), findsOneWidget);
      expect(find.text('Coverage & Benefits'), findsOneWidget);

      // Tap back on Dashboard tab
      await tester.tap(find.text('Dashboard').first);
      await tester.pump(const Duration(milliseconds: 300));

      SocketService().disconnect();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });

    testWidgets('RecordsScreen Coverage & Benefits renders without overflow on standard mobile viewport', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final auth = AuthProvider();
      await auth.loginAsPatient();

      await tester.pumpWidget(buildTestApp(
        auth: auth,
        child: const PatientMainScreen(),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      expect(tester.takeException(), isNull);

      // Navigate to Records tab
      await tester.tap(find.text('Records').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Check Recovery & Trends (Sub-Tab 1)
      expect(find.text('Recovery & Trends'), findsOneWidget);

      // Tap on Coverage & Benefits (Sub-Tab 3)
      await tester.tap(find.text('Coverage & Benefits'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Verify empty state card renders cleanly without overflow
      expect(find.text('Institutional Health Access Pass'), findsOneWidget);
      expect(find.text('No Care Documentation Submitted'), findsOneWidget);
      expect(find.text('Add Care Documentation'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
    });
  });
}

