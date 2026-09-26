import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/user_role.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ticket_provider.dart';
import '../../widgets/kanban_board.dart';
import 'admin_clinical_diagnoses_screen.dart';
import 'admin_health_funds_screen.dart';
import 'admin_war_room_screen.dart';
import 'admin_knowledge_base_screen.dart';
import '../profile/user_profile_screen.dart';
import '../../widgets/boutique_background.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/role_guard.dart';

class AdminMainScreen extends StatefulWidget {
  const AdminMainScreen({super.key});

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TicketProvider>().init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return RoleGuard(
      allowedRoles: const [UserRole.admin],
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 768;
          final isConnected = context.watch<TicketProvider>().isConnected;
          final user = context.watch<AuthProvider>().user;

          return Scaffold(
            bottomNavigationBar: isMobile ? _buildMobileNavBar() : null,
            body: BoutiqueBackground(
              child: SafeArea(
                child: Column(
                  children: [
                    _buildAdminHeader(isMobile, isConnected, user),
                    Expanded(
                      child: isMobile
                          ? _buildAdminBodyView(_selectedIndex)
                          : Row(
                              children: [
                                Container(
                                  margin: const EdgeInsets.fromLTRB(16, 8, 8, 16),
                                  child: GlassCard(
                                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                                    borderRadius: 24,
                                    child: NavigationRail(
                                      backgroundColor: Colors.transparent,
                                      selectedIndex: _selectedIndex,
                                      onDestinationSelected: (int index) {
                                        setState(() {
                                          _selectedIndex = index;
                                        });
                                      },
                                      leading: Padding(
                                        padding: const EdgeInsets.only(bottom: 16, top: 4),
                                        child: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              colors: [Color(0xFF0D9488), Color(0xFF0284C7)],
                                            ),
                                            borderRadius: BorderRadius.circular(12),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF0D9488).withValues(alpha: 0.35),
                                                blurRadius: 10,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(Icons.local_hospital, color: Colors.white, size: 20),
                                        ),
                                      ),
                                      labelType: NavigationRailLabelType.selected,
                                      selectedLabelTextStyle: GoogleFonts.outfit(
                                        color: const Color(0xFF0D9488),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                      unselectedLabelTextStyle: GoogleFonts.outfit(
                                        color: const Color(0xFF0F172A).withValues(alpha: 0.6),
                                        fontWeight: FontWeight.w500,
                                        fontSize: 11,
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
                                          icon: Icon(Icons.receipt_long_outlined),
                                          selectedIcon: Icon(Icons.receipt_long),
                                          label: Text('Claims & Copays'),
                                        ),
                                        NavigationRailDestination(
                                          icon: Icon(Icons.biotech_outlined),
                                          selectedIcon: Icon(Icons.biotech),
                                          label: Text('Patient Diagnoses'),
                                        ),
                                        NavigationRailDestination(
                                          icon: Icon(Icons.account_balance_wallet_outlined),
                                          selectedIcon: Icon(Icons.account_balance_wallet),
                                          label: Text('Health Funds'),
                                        ),

                                        NavigationRailDestination(
                                          icon: Icon(Icons.monitor_heart_outlined, color: Color(0xFFEF4444)),
                                          selectedIcon: Icon(Icons.monitor_heart, color: Color(0xFFEF4444)),
                                          label: Text('War Room', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
                                        ),
                                        NavigationRailDestination(
                                          icon: Icon(Icons.menu_book_outlined),
                                          selectedIcon: Icon(Icons.menu_book),
                                          label: Text('Clinical Policies'),
                                        ),
                                        NavigationRailDestination(
                                          icon: Icon(Icons.person_outline),
                                          selectedIcon: Icon(Icons.person),
                                          label: Text('Staff Profile'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: _buildAdminBodyView(_selectedIndex)),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdminBodyView(int index) {
    switch (index) {
      case 0:
        return const KanbanBoard();
      case 1:
        return const AdminClinicalDiagnosesScreen();
      case 2:
        return const AdminHealthFundsScreen();
      case 3:
        return const AdminWarRoomScreen();
      case 4:
        return const AdminKnowledgeBaseScreen();
      case 5:
        return const UserProfileScreen();
      default:
        return const KanbanBoard();
    }
  }

  Widget _buildMobileNavBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x1A0F172A), width: 1)),
      ),
      child: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        backgroundColor: Colors.white.withValues(alpha: 0.95),
        elevation: 0,
        indicatorColor: const Color(0xFF0D9488).withValues(alpha: 0.14),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: Color(0xFF0D9488)),
            label: 'Claims',
          ),
          NavigationDestination(
            icon: Icon(Icons.biotech_outlined),
            selectedIcon: Icon(Icons.biotech, color: Color(0xFF0D9488)),
            label: 'Diagnoses',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet, color: Color(0xFF0D9488)),
            label: 'Funds',
          ),
          NavigationDestination(
            icon: Icon(Icons.monitor_heart_outlined, color: Color(0xFFEF4444)),
            selectedIcon: Icon(Icons.monitor_heart, color: Color(0xFFEF4444)),
            label: 'War Room',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book, color: Color(0xFF0D9488)),
            label: 'Policies',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: Color(0xFF0D9488)),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  String _resolveAdminDisplayName(dynamic user) {
    final name = user?.name?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user?.email?.toString().trim();
    if (email != null && email.isNotEmpty && email.contains('@')) {
      final handle = email.split('@')[0];
      return handle
          .replaceAll(RegExp(r'[._-]'), ' ')
          .split(' ')
          .where((s) => s.isNotEmpty)
          .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
          .join(' ');
    }
    return 'Clinical Administrator';
  }

  Widget _buildAdminHeader(bool isMobile, bool isConnected, dynamic user) {
    final titles = [
      'Clinical Claims & Emergency Copays',
      'Patient Clinical Diagnoses & CDSS Oversight',
      'Health Funds & Pool Reserves',
      'Clinical Crisis War Room',
      'Institutional Clinical Policies',
      'Medical Administrator Profile',
    ];
    final currentTitle = _selectedIndex < titles.length ? titles[_selectedIndex] : 'Dashboard';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        border: const Border(bottom: BorderSide(color: Color(0x1A0F172A), width: 1.0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedIndex = 5; // Switch to Profile tab
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0D9488), Color(0xFF0284C7)],
                      ),
                    ),
                    child: CircleAvatar(
                      radius: isMobile ? 14 : 17,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.local_hospital, color: const Color(0xFF0D9488), size: isMobile ? 16 : 18),
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
                                _resolveAdminDisplayName(user),
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
                                color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'CHIEF MEDICAL OFFICER',
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
                          'MedAccess AI / $currentTitle',
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
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isConnected ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  isMobile ? (isConnected ? 'LIVE' : 'OFFLINE') : (isConnected ? 'LIVE BACKEND' : 'OFFLINE'),
                  style: GoogleFonts.outfit(
                    color: isConnected ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
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
