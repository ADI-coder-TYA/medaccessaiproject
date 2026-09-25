import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/ticket_provider.dart';
import 'providers/job_tracking_manager.dart';
import 'providers/accessibility_provider.dart';
import 'providers/preferences_provider.dart';
import 'services/offline_sync_engine.dart';
import 'screens/auth/login_screen.dart';
import 'screens/patient/patient_main_screen.dart';
import 'screens/admin/admin_main_screen.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'config/api_config.dart';
import 'providers/claims_provider.dart';
import 'providers/clinical_chat_provider.dart';
import 'providers/war_room_provider.dart';
import 'modules/diagnostics/providers/diagnostics_provider.dart';
import 'modules/diagnostics/providers/diagnostic_state_provider.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.initialize();
  await ApiConfig.initHost();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PreferencesProvider()),
        ChangeNotifierProvider(create: (_) => AccessibilityProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => TicketProvider()),
        ChangeNotifierProvider(create: (_) => ClaimsProvider()),
        ChangeNotifierProvider(create: (_) => ClinicalChatProvider()),
        ChangeNotifierProvider(create: (_) => WarRoomProvider()),
        ChangeNotifierProvider(create: (_) => DiagnosticsProvider()),
        ChangeNotifierProvider(create: (_) => DiagnosticStateProvider()),
        ChangeNotifierProvider(create: (_) => OfflineQueueManager()),
        ChangeNotifierProvider(create: (_) => JobTrackingManager(
          socket: io.io(ApiConfig.socketUrl, io.OptionBuilder().setTransports(['websocket']).build()),
          httpClient: http.Client(),
          apiBaseUrl: ApiConfig.host,
        )),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<PreferencesProvider>();
    final isHighContrast = prefs.isHighContrast;

    return MaterialApp(
      title: 'MedAccess AI',
      debugShowCheckedModeBanner: false,
      theme: isHighContrast
          ? ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: Colors.black,
              primaryColor: const Color(0xFF0D9488), // Deep Clinical Teal
              cardColor: Colors.black,
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF00F0FF), // WCAG AAA Cyan
                secondary: Color(0xFFFFD600), // AAA Amber
                surface: Colors.black,
                error: Color(0xFFEF4444), // Urgent Coral
              ),
              cardTheme: const CardThemeData(
                color: Colors.black,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Color(0xFF00F0FF), width: 2.0),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF00F0FF), width: 2.0),
                  foregroundColor: const Color(0xFF00F0FF),
                ),
              ),
              textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
                bodyLarge: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                bodyMedium: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                titleLarge: const TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.w900, fontSize: 20),
              ),
              useMaterial3: true,
            )
          : AppTheme.lightTheme,
      home: const AuthGate(),
    );
  }
}

/// Dynamic Auth Gate routing between Login Screen, Patient Health Portal, and Admin Portal.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isAuthenticated) {
      return const LoginScreen();
    }

    if (auth.isPatient) {
      return const PatientMainScreen();
    }

    // Default to Clinical Admin Portal
    return const AdminMainScreen();
  }
}
