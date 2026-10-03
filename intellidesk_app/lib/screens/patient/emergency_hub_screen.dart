import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../modules/diagnostics/models/emergency_facility.dart';
import '../../modules/diagnostics/services/HospitalLocatorService.dart';
import '../../modules/diagnostics/ui/EmergencyFacilityCard.dart';

class EmergencyHubScreen extends StatefulWidget {
  const EmergencyHubScreen({super.key});

  @override
  State<EmergencyHubScreen> createState() => _EmergencyHubScreenState();
}

class _EmergencyHubScreenState extends State<EmergencyHubScreen> {
  final HospitalLocatorService _locatorService = HospitalLocatorService();
  bool _isLoading = true;
  List<EmergencyFacility> _facilities = [];
  double _searchRadiusKm = 20.0;
  String? _selectedType;

  @override
  void initState() {
    super.initState();
    _fetchFacilities();
  }

  Future<void> _fetchFacilities({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    try {
      final results = await _locatorService.getNearbyFacilities(
        radiusKm: _searchRadiusKm,
        forceRefresh: forceRefresh,
      );
      final filtered = (_selectedType == null || _selectedType == 'All')
          ? results
          : results.where((f) => f.type.toLowerCase().contains(_selectedType!.toLowerCase())).toList();
      if (mounted) {
        setState(() {
          _facilities = filtered;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _dialCampusEmergency() async {
    final uri = Uri.parse('tel:+1-555-0199');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _dial911() async {
    final uri = Uri.parse('tel:911');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Emergency Care & Facility Navigator',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: const Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh GPS & Facilities',
            icon: const Icon(Icons.my_location, color: Color(0xFF0D9488)),
            onPressed: () => _fetchFacilities(forceRefresh: true),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _fetchFacilities(forceRefresh: true),
        color: const Color(0xFF0D9488),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. High-Priority Dispatch Banner
              _buildDispatchBanner(),
              const SizedBox(height: 16),

              // 2. Search Radius & Category Filter Row
              _buildFilterChips(),
              const SizedBox(height: 16),

              // 3. Facility List Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Nearby Facilities within ${_searchRadiusKm.round()} km',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF0F172A),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!_isLoading)
                    Text(
                      '${_facilities.length} Found',
                      style: const TextStyle(color: Color(0xFF0D9488), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // 4. Loading or Facility Cards
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: CircularProgressIndicator(color: Color(0xFF0D9488)),
                  ),
                )
              else if (_facilities.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      'No emergency care facilities found within selected radius.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    ),
                  ),
                )
              else
                ..._facilities.map((fac) => EmergencyFacilityCard(facility: fac)),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDispatchBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFDC2626), Color(0xFFEF4444), Color(0xFFF97316)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.emergency, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '24/7 Immediate Emergency Dispatch',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Severe chest pain, respiratory distress, or trauma',
                      style: TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFDC2626),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.phone, size: 16),
                  label: const Text('Call 911', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _dial911,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.local_hospital, size: 16),
                  label: const Text('Trauma Desk', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _dialCampusEmergency,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildRadiusChip('5 km', 5.0),
          const SizedBox(width: 8),
          _buildRadiusChip('10 km', 10.0),
          const SizedBox(width: 8),
          _buildRadiusChip('20 km', 20.0),
          const SizedBox(width: 16),
          _buildTypeChip('All Facilities', null),
          const SizedBox(width: 8),
          _buildTypeChip('Trauma Centers', 'Trauma Center'),
          const SizedBox(width: 8),
          _buildTypeChip('Emergency Rooms', 'Emergency Department'),
          const SizedBox(width: 8),
          _buildTypeChip('Campus Clinics', 'Campus Health Center'),
        ],
      ),
    );
  }

  Widget _buildRadiusChip(String label, double radius) {
    final isSelected = _searchRadiusKm == radius;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _searchRadiusKm = radius);
          _fetchFacilities();
        }
      },
      selectedColor: const Color(0xFF0D9488),
      backgroundColor: const Color(0xFFF1F5F9),
      side: BorderSide(color: isSelected ? const Color(0xFF0D9488) : const Color(0xFFE2E8F0)),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : const Color(0xFF334155),
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
      ),
    );
  }

  Widget _buildTypeChip(String label, String? type) {
    final isSelected = _selectedType == type;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedType = selected ? type : null);
        _fetchFacilities();
      },
      selectedColor: const Color(0xFF0D9488),
      backgroundColor: const Color(0xFFF1F5F9),
      side: BorderSide(color: isSelected ? const Color(0xFF0D9488) : const Color(0xFFE2E8F0)),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : const Color(0xFF334155),
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
      ),
    );
  }
}
