import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/medication_entity.dart';

class PrescriptionReviewModal extends StatelessWidget {
  final RxScanSummary summary;
  final VoidCallback? onConfirm;
  final VoidCallback? onDiscard;

  const PrescriptionReviewModal({
    super.key,
    required this.summary,
    this.onConfirm,
    this.onDiscard,
  });

  static Future<void> show(
    BuildContext context, {
    required RxScanSummary summary,
    VoidCallback? onConfirm,
    VoidCallback? onDiscard,
  }) async {
    debugPrint('[PrescriptionReviewModal] Opening modal. Drugs: ${summary.extractedDrugs.length}, DDIs: ${summary.ddiWarnings.length}, Conflicts: ${summary.allergyConflicts.length}, SafetyConflict: ${summary.hasSafetyConflict}');
    await showModalBottomSheet(
      context: context,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PrescriptionReviewModal(
        summary: summary,
        onConfirm: onConfirm,
        onDiscard: onDiscard,
      ),
    );
  }

  Color _getStatusColor() {
    if (summary.hasSafetyConflict) {
      return const Color(0xFFEF4444); // Red
    }
    if (summary.ddiWarnings.any((d) => d.severity == DDISeverity.moderateMonitor)) {
      return const Color(0xFFF59E0B); // Amber
    }
    return const Color(0xFF10B981); // Green
  }

  String _getStatusTitle() {
    if (summary.hasSafetyConflict) {
      return 'CONTRAINDICATED ALLERGY / DDI ALERT';
    }
    if (summary.ddiWarnings.isNotEmpty) {
      return 'MODERATE INTERACTION WARNING';
    }
    return 'SAFE / CLEAR - NO ADVERSE INTERACTIONS';
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.35),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          summary.hasSafetyConflict
                              ? Icons.warning_amber_rounded
                              : Icons.verified_user_outlined,
                          color: statusColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Prescription Safety Review',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            Text(
                              'Prescription Verification & Safety Check',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // 1. Safety Status Alert Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: statusColor.withOpacity(0.6), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            summary.hasSafetyConflict
                                ? Icons.dangerous_outlined
                                : Icons.check_circle_outline,
                            color: statusColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _getStatusTitle(),
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (summary.hasSafetyConflict) ...[
                        const SizedBox(height: 8),
                        Text(
                          'CRITICAL WARNING: Adverse interaction or allergen cross-reactivity detected. Automatic copay review flagged for clinical pharmacist oversight before disbursement.',
                          style: TextStyle(
                            color: statusColor.withOpacity(0.95),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 6),
                        const Text(
                          'All extracted medications verified against your health record. No contraindicated combinations or known drug allergies found.',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                        ),
                      ],
                    ],
                  ),
                ),

                // 2. Allergy Conflicts Section
                if (summary.allergyConflicts.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'ALLERGY CONFLICTS DETECTED (${summary.allergyConflicts.length})',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFEF4444),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...summary.allergyConflicts.map(
                    (c) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.do_not_disturb_on, color: Color(0xFFDC2626), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  c.alertMessage,
                                  style: const TextStyle(
                                    color: Color(0xFF991B1B),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (c.patientReaction != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Prior Patient Reaction: ${c.patientReaction}',
                              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 11.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],

                // 3. Drug-Drug Interactions Section
                if (summary.ddiWarnings.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'DRUG INTERACTIONS (${summary.ddiWarnings.length})',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFB45309),
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...summary.ddiWarnings.map(
                    (d) {
                      final isSevere = d.severity == DDISeverity.contraindicatedSevere;
                      final cardColor = isSevere ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB);
                      final borderColor = isSevere ? const Color(0xFFFCA5A5) : const Color(0xFFFCD34D);
                      final textColor = isSevere ? const Color(0xFF991B1B) : const Color(0xFF92400E);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${d.drugA} + ${d.drugB}',
                                    style: TextStyle(
                                      color: textColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isSevere ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    d.severity.displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              d.clinicalMechanism,
                              style: TextStyle(color: textColor.withOpacity(0.9), fontSize: 12),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Directive: ${d.mitigationAdvice}',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],

                // 4. Extracted Medication Line Items
                const SizedBox(height: 18),
                Text(
                  'EXTRACTED MEDICATIONS (${summary.extractedDrugs.length})',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey[700],
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                if (summary.extractedDrugs.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('No individual medications parsed from document.'),
                  )
                else
                  ...summary.extractedDrugs.map(
                    (med) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  med.brandName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${(med.confidence * 100).round()}% match',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Active Ingredient: ${med.activeIngredient}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Chip(
                                label: Text(med.dosage, style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                              Chip(
                                label: Text(med.frequency, style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                              if (med.duration != null)
                                Chip(
                                  label: Text(med.duration!, style: const TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      debugPrint('[PrescriptionReviewModal] Discard button clicked');
                      Navigator.of(context).pop();
                      if (onDiscard != null) onDiscard!();
                    },
                    child: const Text('Discard / Re-scan'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: statusColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      debugPrint('[PrescriptionReviewModal] Confirm button clicked');
                      Navigator.of(context).pop();
                      if (onConfirm != null) onConfirm!();
                    },
                    child: Text(
                      summary.hasSafetyConflict
                          ? 'Acknowledge & Attach'
                          : 'Confirm & Attach',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
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
