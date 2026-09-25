import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intellidesk_app/screens/profile/user_profile_screen.dart';
import 'package:intellidesk_app/providers/auth_provider.dart';

void main() {
  Widget createWidgetUnderTest({required AuthProvider auth}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ],
      child: const MaterialApp(
        home: UserProfileScreen(),
      ),
    );
  }

  group('UserProfileScreen Light Theme & Clean Layout Tests', () {
    testWidgets('renders light theme AppBar with correct title', (tester) async {
      final auth = AuthProvider();
      await tester.pumpWidget(createWidgetUnderTest(auth: auth));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Account & Clinical Profile'), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFFF8FAFC));
    });

    testWidgets('renders patient info header card with name, badges, and avatar', (tester) async {
      final auth = AuthProvider();
      await auth.loginAsPatient();

      await tester.pumpWidget(createWidgetUnderTest(auth: auth));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Alex Rivera'), findsOneWidget);
      expect(find.text('alex.rivera@campushealth.edu'), findsOneWidget);
      expect(find.text('Patient ID: inst-001'), findsOneWidget);
      expect(find.text('Active Session'), findsOneWidget);
      expect(find.text('AR'), findsOneWidget);
    });

    testWidgets('renders Security & Credentials card with inputs and update button', (tester) async {
      final auth = AuthProvider();
      await auth.loginAsPatient();

      await tester.pumpWidget(createWidgetUnderTest(auth: auth));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Security & Credentials'), findsOneWidget);
      expect(find.text('Update your authentication password'), findsOneWidget);
      expect(find.text('Current Password'), findsOneWidget);
      expect(find.text('New Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
      expect(find.text('Update Password'), findsOneWidget);
    });

    testWidgets('renders Institutional Network card and collapsible diagnostics', (tester) async {
      final auth = AuthProvider();
      await auth.loginAsPatient();

      await tester.pumpWidget(createWidgetUnderTest(auth: auth));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Institutional Network'), findsOneWidget);
      expect(find.text('Production API Gateway'), findsOneWidget);
      expect(find.text('Advanced Endpoint Diagnostics'), findsOneWidget);

      // Tap to expand diagnostics
      await tester.tap(find.text('Advanced Endpoint Diagnostics'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('API Endpoint'), findsOneWidget);
      expect(find.text('Socket Relay'), findsOneWidget);
      expect(find.text('Institution ID'), findsOneWidget);
    });

    testWidgets('renders Sign Out button and opens confirmation dialog', (tester) async {
      final auth = AuthProvider();
      await auth.loginAsPatient();

      await tester.pumpWidget(createWidgetUnderTest(auth: auth));
      await tester.pump(const Duration(milliseconds: 200));

      final signOutBtn = find.text('Sign Out of MedAccess AI');
      expect(signOutBtn, findsOneWidget);

      await tester.ensureVisible(signOutBtn);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(signOutBtn);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Are you sure you want to end your current session?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });
}
