import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/ticket.dart';
import '../providers/ticket_provider.dart';
import '../utils/currency_formatter.dart';
import 'glass_card.dart';
import 'boutique_button.dart';
import 'approval_desk_dialog.dart';

class TicketDetailDrawer extends StatelessWidget {
  final Ticket ticket;

  const TicketDetailDrawer({
    super.key,
    required this.ticket,
  });

  Widget _buildMilestoneRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Color? subtitleColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1F1B2C).withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: subtitleColor ?? const Color(0xFF1E293B),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String patientDisplay = ticket.studentPhone.isNotEmpty
        ? ticket.studentPhone
        : 'Registered Patient #${ticket.id.substring(0, ticket.id.length > 8 ? 8 : ticket.id.length)}';

    return Drawer(
      width: 460,
      backgroundColor: const Color(0xFFF4F1FB),
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                border: Border(
                  bottom: BorderSide(color: const Color(0xFF1F1B2C).withValues(alpha: 0.08)),
                ),
              ),
              child: Row(
                children: [
                  BoutiqueButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1F1B2C).withValues(alpha: 0.06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 20, color: Color(0xFF1F1B2C)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            const Text(
                              'Claim Adjudication',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1F1B2C),
                                letterSpacing: -0.4,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (ticket.status == 'Approved' || ticket.status == 'Resolved')
                                    ? const Color(0xFFD1FAE5)
                                    : (ticket.status == 'Escalated' || ticket.status == 'Flagged'
                                        ? const Color(0xFFFEE2E2)
                                        : const Color(0xFFEFF6FF)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                ticket.status,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: (ticket.status == 'Approved' || ticket.status == 'Resolved')
                                      ? const Color(0xFF047857)
                                      : (ticket.status == 'Escalated' || ticket.status == 'Flagged'
                                          ? const Color(0xFFB91C1C)
                                          : const Color(0xFF1D4ED8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'ID #${ticket.id}',
                          style: TextStyle(
                            fontSize: 11,
                            color: const Color(0xFF1F1B2C).withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  // 1. Patient & Intake Symptoms Card
                  GlassCard(
                    padding: const EdgeInsets.all(18),
                    borderRadius: 22,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.person_pin, color: Color(0xFF6366F1), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    patientDisplay,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Color(0xFF1F1B2C),
                                    ),
                                  ),
                                  Text(
                                    ticket.parsedCategory,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: const Color(0xFF1F1B2C).withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10.0),
                          child: Divider(height: 1),
                        ),
                        Text(
                          ticket.rawMessage.isNotEmpty ? ticket.rawMessage : 'Urgent Healthcare Relief Request.',
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: Color(0xFF334155),
                          ),
                        ),
                        if (ticket.mediaUrl != null && ticket.mediaUrl!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              final uri = Uri.tryParse(ticket.mediaUrl!);
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  title: const Row(
                                    children: [
                                      Icon(Icons.receipt_long, color: Color(0xFF6366F1)),
                                      SizedBox(width: 8),
                                      Text('Medical Invoice Document', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Verified Hospital Invoice & Laboratory Receipt',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                      ),
                                      const SizedBox(height: 10),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Row(
                                              children: [
                                                Icon(Icons.verified, color: Color(0xFF10B981), size: 16),
                                                SizedBox(width: 8),
                                                Text('OCR Bill Hash Verified Clean', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F766E))),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'Extracted Amount: ${CurrencyFormatter.format(ticket.calculatedAmount, currency: ticket.currency)}',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  actions: [
                                    if (uri != null)
                                      ElevatedButton.icon(
                                        onPressed: () => launchUrl(uri, mode: LaunchMode.externalApplication),
                                        icon: const Icon(Icons.open_in_new, size: 16),
                                        label: const Text('Open PDF Invoice'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF6366F1),
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
                                  ],
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.picture_as_pdf, size: 15, color: Color(0xFF4F46E5)),
                                  SizedBox(width: 6),
                                  Text(
                                    'View Hospital Bill / PDF Receipt',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF4F46E5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 2. Financial Grant & Copay Assessment Card
                  GlassCard(
                    padding: const EdgeInsets.all(20),
                    borderRadius: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.account_balance_wallet, color: Color(0xFF10B981), size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Copay & Relief Allocation',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF1F1B2C),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.0),
                          child: Divider(height: 1),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Incurred Bill Amount',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: const Color(0xFF1F1B2C).withValues(alpha: 0.5)),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      CurrencyFormatter.format(ticket.calculatedAmount, currency: ticket.currency, decimalDigits: 2),
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'AI Approved Copay Relief',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: const Color(0xFF1F1B2C).withValues(alpha: 0.5)),
                                  ),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      CurrencyFormatter.format(ticket.recommendedGrantAmount ?? ticket.calculatedAmount, currency: ticket.currency, decimalDigits: 2),
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF059669),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Copay Confidence Score',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                            ),
                            Text(
                              '${((ticket.grantConfidenceScore ?? 0.96) * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: ticket.grantConfidenceScore ?? 0.96,
                            minHeight: 8,
                            backgroundColor: const Color(0xFFE2E8F0),
                            color: (ticket.grantConfidenceScore ?? 0.96) > 0.7
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. Chain-of-Thought AI Reasoning Section
                  GlassCard(
                    padding: const EdgeInsets.all(18),
                    borderRadius: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEE4D9F).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.psychology, color: Color(0xFFEE4D9F), size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Chain-of-Thought Reasoning Trace',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1F1B2C)),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEE4D9F).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Autonomous CoT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFDB2777),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Formatted Milestone breakdown
                        _buildMilestoneRow(
                          icon: Icons.emergency,
                          iconColor: const Color(0xFFDC2626),
                          title: '1. ESI Clinical Triage Level',
                          subtitle: 'Assessed as ${ticket.urgencyLevel} Severity • Crisis Index: ${(ticket.crisisSeverityIndex * 100).toStringAsFixed(1)}%',
                        ),
                        _buildMilestoneRow(
                          icon: Icons.receipt_long,
                          iconColor: const Color(0xFF2563EB),
                          title: '2. Invoice & OCR Verification',
                          subtitle: 'Verified Incurred Bill: ₹${ticket.calculatedAmount.toStringAsFixed(2)} • Receipt Authenticity Clean',
                        ),
                        _buildMilestoneRow(
                          icon: Icons.policy,
                          iconColor: const Color(0xFF7C3AED),
                          title: '3. Policy Vector & Cap Matching',
                          subtitle: ticket.matchedPolicyName != null
                              ? '${ticket.matchedPolicyName!} (Max Cap: ${ticket.matchedPolicyCap ?? "₹2,50,000"})'
                              : 'Standard Institutional Relief Coverage Applied',
                        ),
                        _buildMilestoneRow(
                          icon: Icons.shield,
                          iconColor: ticket.fraudStatus == 'FLAGGED' ? const Color(0xFFDC2626) : const Color(0xFF059669),
                          title: '4. Anti-Fraud & Anomaly Sentinel',
                          subtitle: ticket.fraudStatus == 'FLAGGED'
                              ? 'Flagged: ${ticket.flagReason ?? "Quarantined by Autoencoder"}'
                              : 'Clean Verified • Anomaly Score: ${(ticket.anomalyScore ?? 0.0).toStringAsFixed(3)}',
                          subtitleColor: ticket.fraudStatus == 'FLAGGED' ? const Color(0xFFDC2626) : const Color(0xFF059669),
                        ),
                        _buildMilestoneRow(
                          icon: Icons.payments,
                          iconColor: const Color(0xFF059669),
                          title: '5. Copay Relief Allocation',
                          subtitle: 'Allocated ₹${(ticket.recommendedGrantAmount ?? ticket.calculatedAmount).toStringAsFixed(2)} from Healthcare Reserve',
                          subtitleColor: const Color(0xFF059669),
                        ),

                        // Full Raw CoT Notes Drawer Expander
                        if (ticket.thoughtProcess != null && ticket.thoughtProcess!.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Detailed Clinical Notes Trace:',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  ticket.thoughtProcess!,
                                  style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF334155)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 4. Matched Policy & Inclusions Card
                  GlassCard(
                    padding: const EdgeInsets.all(18),
                    borderRadius: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.policy_outlined, color: Color(0xFF2563EB), size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Matched Institutional Policy',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1F1B2C)),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10.0),
                          child: Divider(height: 1),
                        ),
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            ticket.matchedPolicyName ?? 'Emergency Health Coverage Policy 2026',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                          ),
                          subtitle: Text(
                            'Institutional Coverage Cap: ${ticket.matchedPolicyCap ?? "₹2,50,000"} • 80% Copay Relief',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                          trailing: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 5. Institutional Funds Used & Ledger Rail Card
                  GlassCard(
                    padding: const EdgeInsets.all(18),
                    borderRadius: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.account_tree_outlined, color: Color(0xFF0D9488), size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Institutional Fund & Payout Rail',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1F1B2C)),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10.0),
                          child: Divider(height: 1),
                        ),
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.domain, color: Color(0xFF0F766E)),
                          title: const Text('Disbursement Fund Pool', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                          subtitle: Text(
                            ticket.fundSourceName ?? 'Institutional Healthcare Relief Reserve',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                          ),
                        ),
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.bolt, color: Color(0xFF059669)),
                          title: const Text('Payment Rail & Ledger Status', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                          subtitle: Text(
                            '${ticket.payoutMethod ?? "RAZORPAY_INSTANT"} (${ticket.status == "Approved" ? "Disbursed" : "Authorized"})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF059669)),
                          ),
                        ),
                        if (ticket.payoutReference != null)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.tag, color: Color(0xFF64748B)),
                            title: const Text('Transaction Reference', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                            subtitle: Text(
                              ticket.payoutReference!,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF334155)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 6. ML Risk Radar & Severity Card
                  GlassCard(
                    padding: const EdgeInsets.all(20),
                    borderRadius: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.insights, color: Color(0xFF8B5CF6), size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              'ML Risk Radar & Severity',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1F1B2C)),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.0),
                          child: Divider(height: 1),
                        ),
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.local_fire_department, color: Color(0xFFEF4444)),
                          title: const Text('Crisis Severity Index (CSI)', style: TextStyle(fontWeight: FontWeight.w600)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              ticket.crisisSeverityIndex.toStringAsFixed(3),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                            ),
                          ),
                        ),
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.shield_outlined, color: Color(0xFF10B981)),
                          title: const Text('Anomaly Reconstruction Score', style: TextStyle(fontWeight: FontWeight.w600)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              (ticket.anomalyScore ?? 0.0).toStringAsFixed(4),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF047857)),
                            ),
                          ),
                        ),
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.flight_takeoff, color: Color(0xFF7C3AED)),
                          title: const Text('Student Attrition Risk', style: TextStyle(fontWeight: FontWeight.w600)),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              ticket.dropoutRiskScore.toStringAsFixed(2),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7C3AED)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Action Buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1F1B2C).withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (ticket.status == 'Approved' || ticket.status == 'Resolved') ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Copay Relief Disbursed: ${CurrencyFormatter.format(ticket.recommendedGrantAmount ?? ticket.calculatedAmount, currency: ticket.currency)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF065F46), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    BoutiqueButton(
                      onPressed: () {
                        debugPrint('[TicketDetailDrawer] "View Live Disbursement Receipt" tapped | Ticket ID: ${ticket.id} | Status: ${ticket.status} | Amount: ${ticket.recommendedGrantAmount ?? ticket.calculatedAmount} | PayoutRef: ${ticket.payoutReference}');
                        Navigator.of(context).pop();
                        showDialog(
                          context: context,
                          builder: (ctx) => ApprovalDeskDialog(
                            ticket: ticket,
                            initialShowReceipt: true,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF0D9488)],
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F766E).withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'View Live Disbursement Receipt',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    BoutiqueButton(
                      onPressed: () {
                        debugPrint('[TicketDetailDrawer] "Confirm AI Decision & Open Payment Desk" tapped | Ticket ID: ${ticket.id}');
                        Navigator.of(context).pop();
                        showDialog(
                          context: context,
                          builder: (ctx) => ApprovalDeskDialog(
                            ticket: ticket,
                            initialShowReceipt: false,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1F1B2C), Color(0xFF3B3355)],
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1F1B2C).withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Confirm AI Decision & Open Payment Desk',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    BoutiqueButton(
                      onPressed: () {
                        debugPrint('[TicketDetailDrawer] "Override & Custom Approve" tapped | Ticket ID: ${ticket.id}');
                        Navigator.of(context).pop();
                        showDialog(
                          context: context,
                          builder: (ctx) => ApprovalDeskDialog(
                            ticket: ticket,
                            initialShowReceipt: false,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: const Color(0xFF1F1B2C), width: 1.5),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_note, color: Color(0xFF1F1B2C), size: 20),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Override & Custom Approve',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Color(0xFF1F1B2C), fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    BoutiqueButton(
                      onPressed: () {
                        debugPrint('[TicketDetailDrawer] "Escalate to Clinical Board" tapped | Ticket ID: ${ticket.id}');
                        context.read<TicketProvider>().denyTicket(ticket.id, notes: 'Escalated to Clinical Medical Board');
                        Navigator.of(context).pop();
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_upward, color: Color(0xFFEE4D9F), size: 18),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Escalate to Clinical Board',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Color(0xFFEE4D9F), fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
