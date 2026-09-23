import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../theme/app_theme.dart';
import '../models/emergency_facility.dart';

class EmergencyFacilityCard extends StatelessWidget {
  final EmergencyFacility facility;
  final VoidCallback? onNavigatePressed;
  final VoidCallback? onCallPressed;

  const EmergencyFacilityCard({
    super.key,
    required this.facility,
    this.onNavigatePressed,
    this.onCallPressed,
  });

  /**
   * Technical Guardrail 1: Universal Cross-Platform Map Intents
   * Launches universal Maps intent via LaunchMode.externalApplication
   */
  Future<void> _launchMaps(BuildContext context) async {
    onNavigatePressed?.call();

    // Universal cross-platform intent URL
    final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=${facility.latitude},${facility.longitude}';
    final uri = Uri.parse(mapsUrl);

    try {
      final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open map navigation for ${facility.name}')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Navigation error: ${facility.address}')),
        );
      }
    }
  }

  Future<void> _callEmergencyDesk(BuildContext context) async {
    onCallPressed?.call();

    final cleanPhone = facility.phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final phoneUri = Uri(scheme: 'tel', path: cleanPhone);

    try {
      final success = await launchUrl(phoneUri, mode: LaunchMode.externalApplication);
      if (!success && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not initiate call to ${facility.phone}')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Direct dialer unavailable. Call: ${facility.phone}')),
        );
      }
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'Trauma Center':
        return const Color(0xFFDC2626); // Urgent Crimson
      case 'Emergency Department':
        return const Color(0xFFEA580C); // Urgent Orange
      case 'Urgent Care Center':
        return const Color(0xFF2563EB); // Royal Blue
      case 'Campus Health Center':
      default:
        return const Color(0xFF059669); // Forest Emerald
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final typeColor = _getTypeColor(facility.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: facility.type == 'Trauma Center'
              ? const Color(0xFFEF4444).withOpacity(0.5)
              : Colors.grey.withOpacity(0.2),
          width: facility.type == 'Trauma Center' ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Type Badge, Distance & Travel Time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  facility.type.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: typeColor,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.directions_car_outlined, size: 14, color: Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text(
                    '${facility.distanceKm.toStringAsFixed(1)} km (${facility.travelTimeMinutes} min)',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Facility Name & Open Status
          Text(
            facility.name,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: facility.isOpen24Hours ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                facility.openStatus,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: facility.isOpen24Hours ? const Color(0xFF059669) : const Color(0xFFD97706),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 3: Physical Address
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  facility.address,
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          // Capabilities Wrap
          if (facility.capabilities.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: facility.capabilities.take(3).map((cap) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    cap,
                    style: GoogleFonts.inter(fontSize: 10, color: Colors.grey[700]),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Row 4: Action Buttons (Maps Navigation + Call Emergency Desk)
          Row(
            children: [
              Expanded(
                flex: 5,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBrand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.navigation_outlined, size: 16),
                  label: Text(
                    'Navigate via Maps',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _launchMaps(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.phone_in_talk, size: 16),
                  label: Text(
                    'Call Desk',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _callEmergencyDesk(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
