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
import 'claim_intake_screen.dart';
import 'clinical_chat_screen.dart';
import 'claim_status_screen.dart';
import '../../modules/diagnostics/ui/diagnostic_intake_screen.dart';
import '../../modules/diagnostics/ui/symptom_questionnaire_screen.dart';

class PatientMainScreen extends StatefulWidget {
  const PatientMainScreen({super.key});

  @override
  State<PatientMainScreen> createState() => _PatientMainScreenState();
}

class _PatientMainScreenState extends State<PatientMainScreen> {
  int _selectedIndex = 0;

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
            body: BoutiqueBackground(
              child: SafeArea(
                child: Column(
                  children: [
                    _buildPatientHeader(isMobile, isConnected, user),
                    if (_selectedIndex == 0) _buildAiHealthCheckupCard(context, isMobile),
                    Expanded(
                      child: isMobile
                          ? _buildBodyView(_selectedIndex)
                          : Row(
                              children: [
                                Material(
                                  color: Colors.white.withValues(alpha: 0.6),
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
                                      onDestinationSelected: (int index) {
                                        setState(() {
                                          _selectedIndex = index;
                                        });
                                      },
                                      labelType: NavigationRailLabelType.all,
                                      backgroundColor: Colors.transparent,
                                      selectedLabelTextStyle: GoogleFonts.outfit(
                                        color: const Color(0xFF0D9488),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                      unselectedLabelTextStyle: GoogleFonts.outfit(
                                        color: const Color(0xFF0F172A).withValues(alpha: 0.7),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      unselectedIconTheme: IconThemeData(
                                        color: const Color(0xFF0F172A).withValues(alpha: 0.5),
                                        size: 24,
                                      ),
                                      selectedIconTheme: const IconThemeData(
                                        color: Color(0xFF0D9488),
                                        size: 26,
                                      ),
                                      indicatorColor: const Color(0xFF0D9488).withValues(alpha: 0.12),
                                      destinations: const [
                                        NavigationRailDestination(
                                          icon: Icon(Icons.medical_services_outlined),
                                          selectedIcon: Icon(Icons.medical_services),
                                          label: Text('Intake & Claims'),
                                        ),
                                        NavigationRailDestination(
                                          icon: Icon(Icons.psychology_outlined),
                                          selectedIcon: Icon(Icons.psychology),
                                          label: Text('AI Counselor'),
                                        ),
                                        NavigationRailDestination(
                                          icon: Icon(Icons.receipt_long_outlined),
                                          selectedIcon: Icon(Icons.receipt_long),
                                          label: Text('Claim Tracker'),
                                        ),
                                        NavigationRailDestination(
                                          icon: Icon(Icons.person_outline),
                                          selectedIcon: Icon(Icons.person),
                                          label: Text('Health Profile'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
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
        return const ClaimIntakeScreen();
      case 1:
        return const ClinicalChatScreen();
      case 2:
        return ClaimStatusScreen(
          onNavigateToClaims: () => setState(() => _selectedIndex = 0),
        );
      case 3:
        return const UserProfileScreen();
      default:
        return const ClaimIntakeScreen();
    }
  }

  Widget _buildMobileNavBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x1A1F1B2C), width: 1)),
      ),
      child: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        backgroundColor: Colors.white.withValues(alpha: 0.85),
        indicatorColor: const Color(0xFF0D9488).withValues(alpha: 0.15),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.medical_services_outlined, color: Color(0xFF0F172A)),
            selectedIcon: Icon(Icons.medical_services, color: Color(0xFF0D9488)),
            label: 'Claims',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined, color: Color(0xFF0F172A)),
            selectedIcon: Icon(Icons.psychology, color: Color(0xFF0D9488)),
            label: 'Counselor',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined, color: Color(0xFF0F172A)),
            selectedIcon: Icon(Icons.receipt_long, color: Color(0xFF0D9488)),
            label: 'Status',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, color: Color(0xFF0F172A)),
            selectedIcon: Icon(Icons.person, color: Color(0xFF0D9488)),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildPatientHeader(bool isMobile, bool isConnected, dynamic user) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 24,
        vertical: isMobile ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        border: const Border(
          bottom: BorderSide(color: Color(0x1A1F1B2C), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedIndex = 3;
                });
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
                      radius: isMobile ? 14 : 17,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, color: const Color(0xFF0D9488), size: isMobile ? 16 : 18),
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
                                  fontSize: isMobile ? 13 : 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'PATIENT HEALTH PORTAL',
                                style: GoogleFonts.outfit(
                                  color: const Color(0xFF0D9488),
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
                            fontSize: isMobile ? 10 : 11,
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
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            icon: const Icon(Icons.biotech, size: 16),
            label: Text(
              isMobile ? 'Checkup' : 'AI Health Checkup',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: isMobile ? 11 : 12),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SymptomQuestionnaireScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
          Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: 5),
            decoration: BoxDecoration(
              color: isConnected
                  ? const Color(0xFFDCFCE7).withValues(alpha: 0.95)
                  : const Color(0xFFFEE2E2).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isConnected
                    ? const Color(0xFF16A34A).withValues(alpha: 0.2)
                    : const Color(0xFFDC2626).withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isConnected ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isConnected ? 'LIVE' : 'OFFLINE',
                  style: GoogleFonts.outfit(
                    color: isConnected ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                    fontSize: isMobile ? 9 : 10,
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

  Widget _buildAiHealthCheckupCard(BuildContext context, bool isMobile) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D9488).withOpacity(0.22),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.biotech, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'AI Health Checkup & Screening',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isMobile ? 14 : 16,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'NEW',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Interactive questionnaire & clinical computer vision with Grad-CAM heatmaps.',
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: isMobile ? 11 : 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0D9488),
              elevation: 0,
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SymptomQuestionnaireScreen()),
              );
            },
            child: Text(
              'Start',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// Backward compatibility alias
typedef StudentMainScreen = PatientMainScreen;
