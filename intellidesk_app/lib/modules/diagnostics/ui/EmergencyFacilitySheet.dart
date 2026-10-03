import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../models/emergency_facility.dart';
import '../services/HospitalLocatorService.dart';
import 'EmergencyFacilityCard.dart';

class EmergencyFacilitySheet extends StatefulWidget {
  final List<EmergencyFacility>? preloadedFacilities;
  final HospitalLocatorService? locatorService;

  const EmergencyFacilitySheet({
    super.key,
    this.preloadedFacilities,
    this.locatorService,
  });

  /**
   * Technical Guardrail 4: Non-Blocking Dismissible Emergency Sheet
   * Launches non-blocking dismissible bottom sheet allowing full access to underlying report.
   */
  static Future<void> show(
    BuildContext context, {
    List<EmergencyFacility>? preloadedFacilities,
    HospitalLocatorService? locatorService,
  }) async {
    await showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EmergencyFacilitySheet(
        preloadedFacilities: preloadedFacilities,
        locatorService: locatorService,
      ),
    );
  }

  @override
  State<EmergencyFacilitySheet> createState() => _EmergencyFacilitySheetState();
}

class _EmergencyFacilitySheetState extends State<EmergencyFacilitySheet> {
  late HospitalLocatorService _locatorService;
  List<EmergencyFacility> _facilities = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _locatorService = widget.locatorService ?? HospitalLocatorService();

    if (widget.preloadedFacilities != null && widget.preloadedFacilities!.isNotEmpty) {
      _facilities = widget.preloadedFacilities!;
      _isLoading = false;
    } else {
      _loadFacilities();
    }
  }

  Future<void> _loadFacilities({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final list = await _locatorService.getNearbyFacilities(radiusKm: 20.0, forceRefresh: forceRefresh);
      setState(() {
        _facilities = list;
        _isLoading = false;
      });
    } catch (err) {
      setState(() {
        _errorMessage = 'Could not locate facilities: $err';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxH = MediaQuery.of(context).size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.4),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          // Red Urgent Triage Banner
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.emergency, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CRITICAL REFERRAL DETECTED',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF991B1B),
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Immediate emergency evaluation recommended. Nearest care centers within 20 km:',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF7F1D1D)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Color(0xFF991B1B)),
                  tooltip: 'Dismiss Sheet',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Facilities List
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFFEF4444)),
                          SizedBox(height: 16),
                          Text('Locating nearest emergency care centers (GPS)...'),
                        ],
                      ),
                    ),
                  )
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 40),
                              const SizedBox(height: 12),
                              Text(_errorMessage!),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () => _loadFacilities(forceRefresh: true),
                                child: const Text('Retry Search'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: _facilities.length,
                        itemBuilder: (context, index) {
                          return EmergencyFacilityCard(
                            facility: _facilities[index],
                          );
                        },
                      ),
          ),

          // Technical Guardrail 4: Dismiss button to access full report
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: const Color(0xFF64748B),
                    ),
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    label: Text(
                      'Dismiss & View Full Screening Report',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
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
