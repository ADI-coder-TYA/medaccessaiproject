import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ticket.dart';
import '../providers/ticket_provider.dart';
import '../utils/currency_formatter.dart';

class ApprovalDeskDialog extends StatefulWidget {
  final Ticket ticket;
  final Function(String method, double amount, String ref)? onDisbursed;
  final bool initialShowReceipt;

  const ApprovalDeskDialog({
    super.key,
    required this.ticket,
    this.onDisbursed,
    this.initialShowReceipt = false,
  });

  @override
  State<ApprovalDeskDialog> createState() => _ApprovalDeskDialogState();
}

class _ApprovalDeskDialogState extends State<ApprovalDeskDialog> {
  final TextEditingController _notesController = TextEditingController();
  late TextEditingController _amountController;
  late TextEditingController _nameController;
  late TextEditingController _vpaController;
  late TextEditingController _accountNumberController;
  late TextEditingController _ifscController;
  late TextEditingController _campusCardController;

  String _selectedPayoutMethod = 'RAZORPAY_UPI';
  String _selectedVoucherCategory = 'Campus Dining & Meal Plan';
  bool _isProcessing = false;
  Map<String, dynamic>? _successReceipt;

  final List<String> _voucherCategories = [
    'Campus Dining & Meal Plan',
    'Bookstore & Course Materials',
    'Emergency Housing & Utilities',
    'Medical & Health Services',
    'Off-Campus Transit & Commute',
    'General Hardship Relief',
  ];

  @override
  void initState() {
    super.initState();
    final requestedAmount = widget.ticket.calculatedAmount > 0
        ? widget.ticket.calculatedAmount
        : (widget.ticket.recommendedGrantAmount ?? 250.0);

    _amountController = TextEditingController(text: requestedAmount.toStringAsFixed(0));
    _nameController = TextEditingController(text: 'Student (${widget.ticket.studentPhone})');
    
    // Auto-fill UPI VPA from phone if available
    final cleanPhone = widget.ticket.studentPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final defaultVpa = cleanPhone.isNotEmpty ? '$cleanPhone@upi' : 'student@upi';
    _vpaController = TextEditingController(text: defaultVpa);
    
    _accountNumberController = TextEditingController(text: '999900001111');
    _ifscController = TextEditingController(text: 'HDFC0001234');
    _campusCardController = TextEditingController(text: 'CC-${cleanPhone.isNotEmpty ? cleanPhone.substring(cleanPhone.length > 6 ? cleanPhone.length - 6 : 0) : "882194"}');

    final isAlreadyApproved = widget.ticket.status == 'Approved' || widget.ticket.status == 'Resolved';
    if (widget.initialShowReceipt || isAlreadyApproved) {
      final payoutMethod = widget.ticket.payoutMethod ?? _selectedPayoutMethod;
      _selectedPayoutMethod = payoutMethod;
      final grantAmt = widget.ticket.recommendedGrantAmount ?? widget.ticket.calculatedAmount;
      final ref = widget.ticket.payoutReference ?? widget.ticket.voucherCode ?? 'POUT-CONFIRMED-${widget.ticket.id}';

      debugPrint('[ApprovalDeskDialog] Initialized in Receipt Mode for Ticket: ${widget.ticket.id} | Status: ${widget.ticket.status} | Ref: $ref | Amount: $grantAmt | Rail: $payoutMethod | Currency: ${widget.ticket.currency}');

      _successReceipt = {
        'transactionReference': ref,
        'payoutReference': ref,
        'grantAmount': grantAmt > 0 ? grantAmt : 0.0,
        'fundName': widget.ticket.fundSourceName ?? 'General Student Relief Fund',
        'voucherCode': widget.ticket.voucherCode,
        'payoutMethod': payoutMethod,
        'isLiveRecord': true,
      };
    } else {
      debugPrint('[ApprovalDeskDialog] Initialized in Disbursement Input Mode for Ticket: ${widget.ticket.id} | Status: ${widget.ticket.status} | Requested Amount: $requestedAmount');
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _amountController.dispose();
    _nameController.dispose();
    _vpaController.dispose();
    _accountNumberController.dispose();
    _ifscController.dispose();
    _campusCardController.dispose();
    super.dispose();
  }

  void _selectAmount(double amount) {
    setState(() {
      _amountController.text = amount.toStringAsFixed(0);
    });
  }

  void _handleApprove(BuildContext context) async {
    final parsedAmount = double.tryParse(_amountController.text.trim());
    if (parsedAmount == null || parsedAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid disbursement amount.')),
      );
      return;
    }

    setState(() => _isProcessing = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    
    try {
      debugPrint('[ApprovalDeskDialog] Processing approval for Ticket ID: ${widget.ticket.id} | Amount: $parsedAmount | Method: $_selectedPayoutMethod');
      final res = await context.read<TicketProvider>().approveTicket(
        widget.ticket.id,
        amount: parsedAmount,
        payoutMethod: _selectedPayoutMethod,
        studentName: _nameController.text.trim(),
        studentVpa: _selectedPayoutMethod == 'RAZORPAY_UPI' ? _vpaController.text.trim() : null,
        accountNumber: _selectedPayoutMethod == 'RAZORPAY_BANK' ? _accountNumberController.text.trim() : null,
        ifscCode: _selectedPayoutMethod == 'RAZORPAY_BANK' ? _ifscController.text.trim() : null,
      );

      final transactionRef = res['transactionReference'] ?? res['payoutReference'] ?? res['voucherCode'] ?? 'POUT-CONFIRMED';
      debugPrint('[ApprovalDeskDialog] Disbursement Confirmed | Ticket ID: ${widget.ticket.id} | Ref: $transactionRef');
      
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _successReceipt = res;
        });
      }

      widget.onDisbursed?.call(_selectedPayoutMethod, parsedAmount, transactionRef.toString());

      final formattedAmt = CurrencyFormatter.format(parsedAmount, currency: widget.ticket.currency);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Disbursed $formattedAmt via ${_getPayoutTitle(_selectedPayoutMethod)}! Ref: $transactionRef'),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('[ApprovalDeskDialog] Payout Execution Failed | Ticket ID: ${widget.ticket.id} | Error: $e');
      if (mounted) setState(() => _isProcessing = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error processing payout: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _handleDeny(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    
    if (_notesController.text.trim().isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Please enter justification notes for denial / info request.')),
      );
      return;
    }
    
    debugPrint('[ApprovalDeskDialog] Escalating/Denying Ticket ID: ${widget.ticket.id} | Notes: ${_notesController.text.trim()}');
    setState(() => _isProcessing = true);
    try {
      await context.read<TicketProvider>().denyTicket(
        widget.ticket.id, 
        notes: _notesController.text.trim(),
      );
      if (!context.mounted) return;
      navigator.pop();
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Ticket Marked as Denied / Information Requested'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error denying ticket: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  String _getPayoutTitle(String method) {
    switch (method) {
      case 'RAZORPAY_UPI':
        return 'Razorpay UPI';
      case 'RAZORPAY_BANK':
        return 'Razorpay Bank Transfer';
      case 'CAMPUS_VOUCHER':
        return 'Campus Digital Voucher';
      case 'EMERGENCY_DEBIT':
        return 'Relief Debit Card';
      case 'STRIPE_ACH':
        return 'Direct Bank Transfer (ACH / SEPA)';
      default:
        return method;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 860;
    
    return Dialog(
      backgroundColor: const Color(0xFFF4F1FB),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        width: isMobile ? size.width * 0.96 : size.width * 0.88,
        height: size.height * 0.88,
        padding: EdgeInsets.all(isMobile ? 16 : 24),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F1FB),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0x1A1F1B2C), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: _successReceipt != null 
            ? _buildSuccessView(context)
            : Column(
                children: [
                  _buildHeader(context),
                  const Divider(color: Color(0x1A1F1B2C), height: 20),
                  Expanded(
                    child: isMobile 
                        ? SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLeftPane(),
                                const SizedBox(height: 20),
                                const Divider(color: Color(0x1A1F1B2C), height: 1),
                                const SizedBox(height: 20),
                                _buildRightPane(context),
                              ],
                            ),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 5, child: SingleChildScrollView(child: _buildLeftPane())),
                              const SizedBox(width: 24),
                              const VerticalDivider(color: Color(0x1A1F1B2C), width: 1),
                              const SizedBox(width: 24),
                              Expanded(flex: 7, child: SingleChildScrollView(child: _buildRightPane(context))),
                            ],
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00BAF2), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.bolt, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 2,
                      children: [
                        Text(
                          'Disbursement Desk',
                          style: TextStyle(
                            color: Color(0xFF1F1B2C),
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Badge(
                          backgroundColor: Color(0xFF00BAF2),
                          label: Text('RazorpayX Live', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Multi-rail settlement: Razorpay UPI, Bank IMPS, & Vouchers',
                      style: TextStyle(color: Color(0x991F1B2C), fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.close, color: Color(0xFF1F1B2C), size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildSuccessView(BuildContext context) {
    final ref = _successReceipt!['transactionReference'] ?? _successReceipt!['payoutReference'] ?? _successReceipt!['voucherCode'] ?? 'SUCCESS';
    final rawAmount = _successReceipt!['grantAmount'];
    final num amountNum = (rawAmount is num)
        ? rawAmount
        : (double.tryParse(rawAmount?.toString() ?? '') ?? double.tryParse(_amountController.text) ?? 0.0);
    final fund = _successReceipt!['fundName'] ?? widget.ticket.fundSourceName ?? 'General Student Relief Fund';
    final payoutMethod = _successReceipt!['payoutMethod'] ?? widget.ticket.payoutMethod ?? _selectedPayoutMethod;
    final method = _getPayoutTitle(payoutMethod.toString());
    final voucherCode = _successReceipt!['voucherCode'] ?? widget.ticket.voucherCode;
    final isLiveRecord = _successReceipt!['isLiveRecord'] == true;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4), width: 2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 28),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFECFDF5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 36),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF1F1B2C), size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                isLiveRecord ? 'Live Disbursement Receipt' : 'Disbursement Successful!',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F1B2C),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                isLiveRecord
                    ? 'Official institutional grant disbursement record on live ledger.'
                    : 'Grant funds have been released and transaction confirmed.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),

              // Summary Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _buildSuccessRow(
                      'Disbursed Amount',
                      CurrencyFormatter.format(
                        amountNum,
                        currency: payoutMethod == 'STRIPE_ACH' ? 'USD' : (payoutMethod.toString().startsWith('RAZORPAY') ? 'INR' : widget.ticket.currency),
                        decimalDigits: 2,
                      ),
                      isHighlight: true,
                    ),
                    const Divider(height: 14),
                    _buildSuccessRow('Disbursement Rail', method),
                    const Divider(height: 14),
                    _buildSuccessRow('Transaction Reference', '$ref', isMono: true),
                    if (voucherCode != null && voucherCode.toString().isNotEmpty) ...[
                      const Divider(height: 14),
                      _buildSuccessRow('Voucher Code', '$voucherCode', isHighlight: true, isMono: true),
                    ],
                    const Divider(height: 14),
                    _buildSuccessRow('Fund Deducted', '$fund'),
                    const Divider(height: 14),
                    _buildSuccessRow('Student Recipient', widget.ticket.studentPhone),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.sms_outlined, color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Instant SMS confirmation dispatched to ${widget.ticket.studentPhone}.',
                      style: const TextStyle(color: Color(0xFF065F46), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F1B2C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Close & Return to Dashboard', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessRow(String label, String value, {bool isHighlight = false, bool isMono = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 4,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: isHighlight ? const Color(0xFF10B981) : const Color(0xFF1F1B2C),
              fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w600,
              fontFamily: isMono ? 'monospace' : null,
              fontSize: isHighlight ? 14 : 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeftPane() {
    final requestedAmt = widget.ticket.calculatedAmount;
    final recommendedAmt = widget.ticket.recommendedGrantAmount;
    final phoneDisplay = widget.ticket.studentPhone.isNotEmpty
        ? widget.ticket.studentPhone
        : 'Registered Patient #${widget.ticket.id.substring(0, widget.ticket.id.length > 8 ? 8 : widget.ticket.id.length)}';
    final statementDisplay = widget.ticket.rawMessage.isNotEmpty
        ? widget.ticket.rawMessage
        : 'Emergency medical assistance and copay relief claim.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Student & Distress Context',
          style: TextStyle(
            color: Color(0xFF1F1B2C),
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),

        // Requested Amount Highlight Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF8B5CF6).withValues(alpha: 0.12), const Color(0xFF00BAF2).withValues(alpha: 0.12)],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.payments_outlined, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'STUDENT REQUESTED AMOUNT',
                      style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      requestedAmt > 0
                          ? '${CurrencyFormatter.format(requestedAmt, currency: widget.ticket.currency)} (${widget.ticket.currency})'
                          : (recommendedAmt != null
                              ? '${CurrencyFormatter.format(recommendedAmt, currency: widget.ticket.currency)} (AI Est.)'
                              : 'Flexible Relief Request'),
                      style: const TextStyle(
                        color: Color(0xFF1F1B2C),
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            const Icon(Icons.phone, color: Color(0xFF8B5CF6), size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                phoneDisplay,
                style: const TextStyle(
                  color: Color(0xFF1F1B2C),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Submitted Statement',
          style: TextStyle(
            color: Color(0x991F1B2C),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x1A1F1B2C)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
              ),
            ],
          ),
          child: Text(
            statementDisplay,
            style: const TextStyle(
              color: Color(0xFF1F1B2C),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Matched Policy & Institutional Fund Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.policy_outlined, color: Color(0xFF2563EB), size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'Matched Policy & Coverage Cap',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.ticket.matchedPolicyName ?? 'Emergency & Acute Inpatient Trauma Policy 2026',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
              ),
              Text(
                'Policy Limit: ${widget.ticket.matchedPolicyCap ?? "₹2,50,000 per incident"} • 80% Copay Relief',
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
              const Divider(height: 14, color: Color(0xFFDBEAFE)),
              Row(
                children: [
                  const Icon(Icons.account_balance, color: Color(0xFF0F766E), size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Relief Fund Pool:', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        Text(
                          widget.ticket.fundSourceName ?? 'Institutional Healthcare Relief Reserve',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F766E)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (widget.ticket.mediaUrl != null && widget.ticket.mediaUrl!.isNotEmpty) ...[
          const Text(
            'Attached Document / Receipt',
            style: TextStyle(
              color: Color(0x991F1B2C),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 130,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0x1A1F1B2C)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.network(
              widget.ticket.mediaUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(Icons.broken_image, color: Color(0x661F1B2C), size: 36),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        const Text(
          'AI Assessment Metrics',
          style: TextStyle(
            color: Color(0x991F1B2C),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (widget.ticket.parsedCategory.isNotEmpty)
              Chip(
                backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                label: Text(
                  widget.ticket.parsedCategory,
                  style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            Chip(
              backgroundColor: _getUrgencyColor().withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              label: Text(
                widget.ticket.urgencyLevel,
                style: TextStyle(color: _getUrgencyColor(), fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
            if (widget.ticket.crisisSeverityIndex > 0)
              Chip(
                backgroundColor: const Color(0xFFEE4D9F).withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                label: Text(
                  'CSI: ${(widget.ticket.crisisSeverityIndex * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Color(0xFFEE4D9F), fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Color _getUrgencyColor() {
    switch (widget.ticket.urgencyLevel) {
      case 'Urgent':
      case 'Critical':
        return const Color(0xFFEF4444);
      case 'High':
        return const Color(0xFFF59E0B);
      case 'Routine':
      default:
        return const Color(0xFF10B981);
    }
  }

  Widget _buildRightPane(BuildContext context) {
    final isApproved = widget.ticket.status == 'Approved' || widget.ticket.status == 'Auto-Approved';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Disbursement Rails & Allocation',
          style: TextStyle(
            color: Color(0xFF1F1B2C),
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        if (isApproved) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'GRANT APPROVED & DISBURSED',
                        style: TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('RazorpayX Live', style: TextStyle(color: Color(0xFF065F46), fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Disbursed Relief:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    Text(
                      CurrencyFormatter.format(
                        widget.ticket.recommendedGrantAmount ?? widget.ticket.calculatedAmount,
                        currency: widget.ticket.currency,
                        decimalDigits: 2,
                      ),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                    ),
                  ],
                ),
                const Divider(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Settlement Rail:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _getPayoutTitle(widget.ticket.payoutMethod ?? "RAZORPAY_UPI"),
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Transaction Ref:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.ticket.payoutReference ?? widget.ticket.voucherCode ?? "TXN_MED_CONFIRMED",
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Color(0xFF334155)),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Fund Source:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    Flexible(
                      child: Text(
                        widget.ticket.fundSourceName ?? 'Trauma & Emergency Relief Endowment',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F766E)),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Matched Policy:', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    Flexible(
                      child: Text(
                        widget.ticket.matchedPolicyName ?? 'Emergency & Acute Inpatient Trauma Policy 2026',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2563EB)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ] else ...[
          // Payout Method Selector
          const Text(
            'Select Payment / Voucher Rail',
            style: TextStyle(color: Color(0x991F1B2C), fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          
          // 4 Disbursement Rails in Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: itemWidth,
                    child: _buildRailOption(
                      id: 'RAZORPAY_UPI',
                      title: 'Razorpay UPI',
                      subtitle: 'Instant VPA Transfer',
                      icon: Icons.bolt,
                      accentColor: const Color(0xFF00BAF2),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildRailOption(
                      id: 'RAZORPAY_BANK',
                      title: 'Razorpay Bank',
                      subtitle: 'IMPS Direct Deposit',
                      icon: Icons.account_balance,
                      accentColor: const Color(0xFF8B5CF6),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildRailOption(
                      id: 'CAMPUS_VOUCHER',
                      title: 'Digital Voucher',
                      subtitle: 'SMS Code (EDU-GRANT)',
                      icon: Icons.confirmation_number_outlined,
                      accentColor: const Color(0xFF10B981),
                    ),
                  ),
                  SizedBox(
                    width: itemWidth,
                    child: _buildRailOption(
                      id: 'EMERGENCY_DEBIT',
                      title: 'Relief Debit',
                      subtitle: 'Campus Card Credit',
                      icon: Icons.credit_card,
                      accentColor: const Color(0xFFF59E0B),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // Grant Amount Input & Preset Chips
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Disbursement Amount',
                style: TextStyle(color: Color(0x991F1B2C), fontSize: 12, fontWeight: FontWeight.w600),
              ),
              if (widget.ticket.calculatedAmount > 0)
                Text(
                  'Requested: ${CurrencyFormatter.format(widget.ticket.calculatedAmount, currency: widget.ticket.currency)}',
                  style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 11, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // Quick Presets
          Builder(
            builder: (context) {
              final activeCurrency = _selectedPayoutMethod == 'STRIPE_ACH' ? 'USD' : (_selectedPayoutMethod.startsWith('RAZORPAY') ? 'INR' : widget.ticket.currency);
              final isINR = activeCurrency == 'INR';

              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (widget.ticket.calculatedAmount > 0)
                    ActionChip(
                      label: Text('Exact Requested (${CurrencyFormatter.format(widget.ticket.calculatedAmount, currency: activeCurrency)})'),
                      backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      labelStyle: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold, fontSize: 11),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      onPressed: () => _selectAmount(widget.ticket.calculatedAmount),
                    ),
                  ActionChip(
                    label: Text(isINR ? '₹500' : '\$100'),
                    backgroundColor: Colors.white,
                    labelStyle: const TextStyle(color: Color(0xFF1F1B2C), fontSize: 11),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    onPressed: () => _selectAmount(isINR ? 500 : 100),
                  ),
                  ActionChip(
                    label: Text(isINR ? '₹1,000' : '\$250'),
                    backgroundColor: Colors.white,
                    labelStyle: const TextStyle(color: Color(0xFF1F1B2C), fontSize: 11),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    onPressed: () => _selectAmount(isINR ? 1000 : 250),
                  ),
                  ActionChip(
                    label: Text(isINR ? '₹2,500' : '\$500'),
                    backgroundColor: Colors.white,
                    labelStyle: const TextStyle(color: Color(0xFF1F1B2C), fontSize: 11),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    onPressed: () => _selectAmount(isINR ? 2500 : 500),
                  ),
                  ActionChip(
                    label: Text(isINR ? '₹5,000' : '\$1,000'),
                    backgroundColor: Colors.white,
                    labelStyle: const TextStyle(color: Color(0xFF1F1B2C), fontSize: 11),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    onPressed: () => _selectAmount(isINR ? 5000 : 1000),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                flex: 4,
                child: Builder(
                  builder: (context) {
                    final activeCurrency = _selectedPayoutMethod == 'STRIPE_ACH' ? 'USD' : (_selectedPayoutMethod.startsWith('RAZORPAY') ? 'INR' : widget.ticket.currency);
                    final currSymbol = CurrencyFormatter.getSymbol(activeCurrency);
                    return TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Color(0xFF1F1B2C), fontSize: 16, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: 'Amount ($currSymbol)',
                        labelStyle: const TextStyle(color: Color(0x991F1B2C), fontSize: 12),
                        prefixIcon: Center(
                          widthFactor: 1.0,
                          child: Text(
                            currSymbol,
                            style: const TextStyle(color: Color(0xFF10B981), fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0x1A1F1B2C)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Color(0xFF1F1B2C), fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Beneficiary Name',
                    labelStyle: const TextStyle(color: Color(0x991F1B2C), fontSize: 12),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0x1A1F1B2C)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Dynamic Payout Details Inputs
          if (_selectedPayoutMethod == 'RAZORPAY_UPI') ...[
            TextField(
              controller: _vpaController,
              style: const TextStyle(color: Color(0xFF1F1B2C), fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Student UPI ID / VPA',
                hintText: 'e.g. student@upi or phone@okhdfcbank',
                prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFF00BAF2), size: 18),
                labelStyle: const TextStyle(color: Color(0x991F1B2C), fontSize: 12),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0x1A1F1B2C)),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF00BAF2), width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF00BAF2).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF00BAF2).withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.bolt, color: Color(0xFF00BAF2), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚡ Instant 24/7 Payout via RazorpayX UPI rails directly to student VPA.',
                      style: TextStyle(color: Color(0xFF0284C7), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_selectedPayoutMethod == 'RAZORPAY_BANK') ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _accountNumberController,
                    style: const TextStyle(color: Color(0xFF1F1B2C), fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Account Number',
                      labelStyle: const TextStyle(color: Color(0x991F1B2C), fontSize: 12),
                      prefixIcon: const Icon(Icons.account_balance, color: Color(0xFF8B5CF6), size: 18),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0x1A1F1B2C)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _ifscController,
                    style: const TextStyle(color: Color(0xFF1F1B2C), fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'IFSC Code',
                      labelStyle: const TextStyle(color: Color(0x991F1B2C), fontSize: 12),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0x1A1F1B2C)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified, color: Color(0xFF8B5CF6), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '🏛️ IMPS / NEFT Direct Bank Transfer via RazorpayX Payouts.',
                      style: TextStyle(color: Color(0xFF6D28D9), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (_selectedPayoutMethod == 'CAMPUS_VOUCHER') ...[
            DropdownButtonFormField<String>(
              initialValue: _selectedVoucherCategory,
              dropdownColor: Colors.white,
              decoration: InputDecoration(
                labelText: 'Voucher Target Category',
                labelStyle: const TextStyle(color: Color(0x991F1B2C), fontSize: 12),
                prefixIcon: const Icon(Icons.storefront_outlined, color: Color(0xFF10B981), size: 18),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0x1A1F1B2C)),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFF10B981), width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              items: _voucherCategories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedVoucherCategory = val);
              },
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.confirmation_number, color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '🎟️ Generates EDU-GRANT code and dispatches via SMS to ${widget.ticket.studentPhone}.',
                      style: const TextStyle(color: Color(0xFF065F46), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            TextField(
              controller: _campusCardController,
              style: const TextStyle(color: Color(0xFF1F1B2C), fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Campus Card ID / Student ID',
                labelStyle: const TextStyle(color: Color(0x991F1B2C), fontSize: 12),
                prefixIcon: const Icon(Icons.credit_card, color: Color(0xFFF59E0B), size: 18),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0x1A1F1B2C)),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.badge_outlined, color: Color(0xFFF59E0B), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '💳 Relief funds loaded directly onto student campus debit card.',
                      style: TextStyle(color: Color(0xFFB45309), fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Admin Notes
          TextField(
            controller: _notesController,
            style: const TextStyle(color: Color(0xFF1F1B2C), fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Adjudication Note / Audit Comment (Optional)',
              labelStyle: const TextStyle(color: Color(0x991F1B2C), fontSize: 12),
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0x1A1F1B2C)),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
        ],

        // Action Buttons
        if (_isProcessing)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(14.0),
              child: Column(
                children: [
                  CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                  SizedBox(height: 10),
                  Text('Processing RazorpayX Payout & Voucher Dispatch...', style: TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
          )
        else if (!isApproved)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleDeny(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('✗ Deny / Request Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => _handleApprove(context),
                  icon: const Icon(Icons.flash_on, color: Colors.white, size: 18),
                  label: Text(
                    'Disburse via ${_getPayoutTitle(_selectedPayoutMethod)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F1B2C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildRailOption({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    final isSelected = _selectedPayoutMethod == id;

    return InkWell(
      onTap: () => setState(() => _selectedPayoutMethod = id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accentColor : const Color(0x1A1F1B2C),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(color: accentColor.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2)),
          ] : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isSelected ? accentColor : accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: isSelected ? Colors.white : accentColor, size: 16),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: const Color(0xFF1F1B2C),
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: const Color(0xFF1F1B2C).withValues(alpha: 0.5), fontSize: 9),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: accentColor, size: 16),
          ],
        ),
      ),
    );
  }
}
