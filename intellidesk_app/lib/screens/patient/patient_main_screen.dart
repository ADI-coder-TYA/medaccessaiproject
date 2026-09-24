import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../config/api_config.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ticket_provider.dart';
import '../profile/user_profile_screen.dart';
import '../../widgets/boutique_background.dart';
import '../../widgets/role_guard.dart';
import 'patient_clinical_dashboard.dart';
import 'pharmacy_hub_screen.dart';
import 'emergency_hub_screen.dart';
import 'health_records_screen.dart';
import '../../modules/diagnostics/ui/diagnostic_intake_screen.dart';

class PatientMainScreen extends StatefulWidget {
  const PatientMainScreen({super.key});

  @override
  State<PatientMainScreen> createState() => _PatientMainScreenState();
}

class _PatientMainScreenState extends State<PatientMainScreen> {
  int _selectedIndex = 0;

  void _onNavigateTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RoleGuard(
      allowedRoles: const [UserRole.patient, UserRole.student],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 768;
          final isConnected = context.select<TicketProvider, bool>((p) => p.isConnected);
          final user = context.select<AuthProvider, dynamic>((p) => p.user);

          return Scaffold(
            backgroundColor: const Color(0xFF0B132B), // Deep Clinical Navy
            body: BoutiqueBackground(
              child: SafeArea(
                child: Column(
                  children: [
                    _buildPatientHeader(isMobile, isConnected, user),
                    Expanded(
                      child: isMobile
                          ? _buildBodyView(_selectedIndex)
                          : Row(
                              children: [
                                Material(
                                  color: const Color(0xFF0F172A).withValues(alpha: 0.95),
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        right: BorderSide(
                                          color: Color(0x1A1F1B2C),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                    child: NavigationRail(
                                      selectedIndex: _selectedIndex,
                                      onDestinationSelected: _onNavigateTab,
                                      labelType: NavigationRailLabelType.all,
                                      backgroundColor: Colors.transparent,
                                      selectedLabelTextStyle: GoogleFonts.outfit(
                                        color: const Color(0xFF5EEAD4),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                      unselectedLabelTextStyle: GoogleFonts.outfit(
                                        color: Colors.grey[400],
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      unselectedIconTheme: IconThemeData(
                                        color: Colors.grey[500],
                                        size: 22,
                                      ),
                                      selectedIconTheme: const IconThemeData(
                                        color: Color(0xFF14B8A6),
                                        size: 26,
                                      ),
                                      indicatorColor: const Color(0xFF0D9488).withValues(alpha: 0.25),
                                      destinations: const [
                                        NavigationRailDestination(
                                          icon: Icon(Icons.dashboard_outlined),
                                          selectedIcon: Icon(Icons.dashboard_rounded),
                                          label: Text('AI Hub'),
                                        ),
                                        NavigationRailDestination(
                                          icon: Icon(Icons.health_and_safety_outlined),
                                          selectedIcon: Icon(Icons.health_and_safety_rounded),
                                          label: Text('Checkup'),
                                        ),
                                        NavigationRailDestination(
                                          icon: Icon(Icons.medication_outlined),
                                          selectedIcon: Icon(Icons.medication_rounded),
                                          label: Text('Pharmacy'),
                                        ),
                                        NavigationRailDestination(
                                          icon: Icon(Icons.emergency_outlined),
                                          selectedIcon: Icon(Icons.emergency_rounded),
                                          label: Text('Emergency'),
                                        ),
                                        NavigationRailDestination(
                                          icon: Icon(Icons.folder_shared_outlined),
                                          selectedIcon: Icon(Icons.folder_shared_rounded),
                                          label: Text('Records'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(child: _buildBodyView(_selectedIndex)),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
            bottomNavigationBar: isMobile ? _buildMobileNavBar() : null,
          );
        },
      ),
    );
  }

  Widget _buildBodyView(int index) {
    switch (index) {
      case 0:
        return PatientClinicalDashboard(onNavigateTab: _onNavigateTab);
      case 1:
        return const DiagnosticIntakeScreen();
      case 2:
        return const PharmacyHubScreen();
      case 3:
        return const EmergencyHubScreen();
      case 4:
        return const HealthRecordsScreen();
      default:
        return PatientClinicalDashboard(onNavigateTab: _onNavigateTab);
    }
  }

  Widget _buildMobileNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFF0D9488).withOpacity(0.12),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF0D9488),
              );
            }
            return GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF94A3B8),
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onNavigateTab,
          height: 66,
          elevation: 0,
          backgroundColor: Colors.transparent,
          indicatorColor: const Color(0xFF0D9488).withOpacity(0.12),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined, color: Color(0xFF94A3B8), size: 22),
              selectedIcon: Icon(Icons.dashboard_rounded, color: Color(0xFF0D9488), size: 22),
              label: 'AI Hub',
            ),
            NavigationDestination(
              icon: Icon(Icons.health_and_safety_outlined, color: Color(0xFF94A3B8), size: 22),
              selectedIcon: Icon(Icons.health_and_safety_rounded, color: Color(0xFF0D9488), size: 22),
              label: 'Checkup',
            ),
            NavigationDestination(
              icon: Icon(Icons.medication_outlined, color: Color(0xFF94A3B8), size: 22),
              selectedIcon: Icon(Icons.medication_rounded, color: Color(0xFF0D9488), size: 22),
              label: 'Pharmacy',
            ),
            NavigationDestination(
              icon: Icon(Icons.emergency_outlined, color: Color(0xFF94A3B8), size: 22),
              selectedIcon: Icon(Icons.emergency_rounded, color: Color(0xFFEF4444), size: 22),
              label: 'Emergency',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_shared_outlined, color: Color(0xFF94A3B8), size: 22),
              selectedIcon: Icon(Icons.folder_shared_rounded, color: Color(0xFF0D9488), size: 22),
              label: 'Records',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPatientHeader(bool isMobile, bool isConnected, dynamic user) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 14 : 24,
        vertical: isMobile ? 10 : 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const UserProfileScreen()),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF0D9488), Color(0xFF0284C7)],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: isMobile ? 15 : 18,
                      backgroundColor: const Color(0xFFF1F5F9),
                      child: const Icon(Icons.person, color: Color(0xFF0D9488), size: 18),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                (user?.name != null && user!.name.isNotEmpty)
                                    ? user.name
                                    : (user?.email != null ? user!.email.split('@')[0] : 'Patient Member'),
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: const Color(0xFF0F172A),
                                  fontSize: isMobile ? 14 : 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D9488).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.4)),
                              ),
                              child: Text(
                                'CLINICAL AI',
                                style: GoogleFonts.outfit(
                                  color: const Color(0xFF0F766E),
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${user?.institutionId ?? ApiConfig.activeInstitutionId} • Beneficiary',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF64748B),
                            fontSize: isMobile ? 10.5 : 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Live Network Status Indicator
          Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 10, vertical: 4),
            decoration: BoxDecoration(
              color: isConnected
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isConnected
                    ? const Color(0xFF10B981).withOpacity(0.5)
                    : const Color(0xFFEF4444).withOpacity(0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  isConnected ? 'LIVE' : 'OFFLINE',
                  style: GoogleFonts.outfit(
                    color: isConnected ? const Color(0xFF065F46) : const Color(0xFFB91C1C),
                    fontSize: isMobile ? 9.5 : 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Backward compatibility alias
typedef StudentMainScreen = PatientMainScreen;
