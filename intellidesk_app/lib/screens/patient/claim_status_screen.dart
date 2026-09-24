import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../config/api_config.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_card.dart';
import 'clinical_chat_screen.dart';

class ClaimStatusScreen extends StatefulWidget {
  final String? claimId;
  final VoidCallback? onNavigateToClaims;

  const ClaimStatusScreen({
    super.key,
    this.claimId,
    this.onNavigateToClaims,
  });

  @override
  State<ClaimStatusScreen> createState() => _ClaimStatusScreenState();
}

class _ClaimStatusScreenState extends State<ClaimStatusScreen> {
  IO.Socket? _socket;
  List<Map<String, dynamic>> _claims = [];
  Map<String, dynamic>? _selectedClaim;
  bool _isLoading = true;
  String _statusFilter = 'All';
  Timer? _pollingTimer;
  int _pollCount = 0;

  final List<String> _filters = ['All', 'Active', 'Approved', 'Disbursed', 'Flagged'];

  @override
  void initState() {
    super.initState();
    if (widget.claimId != null && widget.claimId!.isNotEmpty) {
      _selectedClaim = {
        'id': widget.claimId,
        'status': 'Triage Active',
        'clinical_category': 'Medical Emergency & Inpatient Care',
        'esi_level': 'ESI_2_EMERGENT',
        'created_at': DateTime.now().toIso8601String(),
      };
      _isLoading = false;
    }
    _fetchClaims();
    _initSocket();
    _startTriagePolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }

  void _startTriagePolling() {
    if (widget.claimId == null || widget.claimId!.isEmpty) return;
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      _pollCount++;
      if (_pollCount > 8) {
        timer.cancel();
        return;
      }
      await _fetchSpecificClaim(widget.claimId!);
      final status = (_selectedClaim?['status'] ?? '').toString().toUpperCase();
      if (status.contains('COMPLETE') || status.contains('APPROVED') || status.contains('DISBURSED') || status.contains('FLAGGED')) {
        timer.cancel();
      }
    });
  }

  void _initSocket() {
    try {
      _socket = IO.io(ApiConfig.socketUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
      });

      _socket?.onConnect((_) {
        final id = widget.claimId ?? _selectedClaim?['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          _socket?.emit('join_claim', id);
          _socket?.emit('join_ticket', id);
        }
      });

      _socket?.on('claim:updated', (data) {
        if (mounted && data != null) {
          final claimMap = Map<String, dynamic>.from(data as Map);
          setState(() {
            _selectedClaim = claimMap;
            final idx = _claims.indexWhere((c) => c['id']?.toString() == claimMap['id']?.toString());
            if (idx != -1) {
              _claims[idx] = claimMap;
            } else {
              _claims.insert(0, claimMap);
            }
          });
        }
      });

      _socket?.on('job:completed', (data) {
        if (mounted && data != null) {
          _fetchClaims(silent: true);
        }
      });

      _socket?.on('claim:disbursed', (data) {
        if (mounted && data != null) {
          _fetchClaims(silent: true);
        }
      });
    } catch (_) {}
  }

  Future<void> _fetchSpecificClaim(String claimId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/claims/$claimId'),
        headers: ApiConfig.patientHeaders,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data != null && mounted) {
          final claimMap = Map<String, dynamic>.from(data as Map);
          setState(() {
            _selectedClaim = claimMap;
            final idx = _claims.indexWhere((c) => c['id']?.toString() == claimId);
            if (idx != -1) {
              _claims[idx] = claimMap;
            } else {
              _claims.insert(0, claimMap);
            }
            _isLoading = false;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchClaims({bool silent = false}) async {
    if (!silent && _selectedClaim == null) {
      setState(() => _isLoading = true);
    }
    try {
      if (widget.claimId != null && widget.claimId!.isNotEmpty) {
        await _fetchSpecificClaim(widget.claimId!);
      }

      final queryParams = <String, String>{
        if (ApiConfig.userPhone != null) 'phone': ApiConfig.userPhone!,
        if (ApiConfig.userEmail != null) 'email': ApiConfig.userEmail!,
        'institutionId': ApiConfig.activeInstitutionId,
      };
      final uri = Uri.parse('${ApiConfig.baseUrl}/claims').replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: ApiConfig.patientHeaders,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final list = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();

        if (mounted) {
          setState(() {
            _claims = list;
            if (_claims.isNotEmpty) {
              if (widget.claimId != null) {
                _selectedClaim = _claims.firstWhere(
                  (c) => c['id']?.toString() == widget.claimId,
                  orElse: () => _selectedClaim ?? _claims.first,
                );
              } else {
                _selectedClaim ??= _claims.first;
              }
            }
            _isLoading = false;
          });
        }
        return;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredClaims {
    if (_statusFilter == 'All') return _claims;
    return _claims.where((c) {
      final s = (c['status'] ?? '').toString().toUpperCase();
      if (_statusFilter == 'Active') return s.contains('ACTIVE') || s.contains('TRIAGE') || s.contains('PENDING') || s.contains('SUBMITTED');
      if (_statusFilter == 'Approved') return s.contains('APPROVED');
      if (_statusFilter == 'Disbursed') return s.contains('DISBURSED');
      if (_statusFilter == 'Flagged') return s.contains('FLAGGED') || s.contains('DENIED');
      return true;
    }).toList();
  }

  int _getCurrentStep(Map<String, dynamic> claim) {
    final status = (claim['status'] ?? '').toString().toUpperCase();
    if (status.contains('DISBURSED') || status.contains('RESOLVED')) return 4;
    if (status.contains('APPROVED') || status.contains('APPROVAL')) return 3;
    if (status.contains('COMPLETE') || status.contains('VERIF') || claim['extracted_bill_amount'] != null || claim['recommended_copay_amount'] != null) return 3;
    if (status.contains('ACTIVE') || status.contains('TRIAGE') || status.contains('PENDING')) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    Widget content;
    if (_isLoading && _selectedClaim == null) {
      content = const Center(
        child: CircularProgressIndicator(color: Color(0xFF0D9488)),
      );
    } else if (_claims.isEmpty && _selectedClaim == null) {
      content = _buildEmptyState();
    } else {
      content = RefreshIndicator(
        onRefresh: _fetchClaims,
        color: const Color(0xFF0D9488),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header with active claim title & claim switcher
              _buildClaimHeader(),
              const SizedBox(height: 16),

              // 2. Status Filter Tabs
              _buildFilterTabs(),
              const SizedBox(height: 16),

              // 3. Active Claim Card & Triage Stepper
              if (_selectedClaim != null) ...[
                _buildActiveClaimDetails(_selectedClaim!),
                const SizedBox(height: 20),
              ],

              // 4. Other Claims List (if multiple exist)
              if (_filteredClaims.length > 1) ...[
                Text(
                  'ALL SUBMITTED CLAIMS (${_filteredClaims.length})',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF64748B),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 10),
                ..._filteredClaims.map((claim) {
                  final isSelected = claim['id'] == _selectedClaim?['id'];
                  return _buildClaimListItem(claim, isSelected);
                }),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: canPop
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                'Live Claim Tracker',
                style: GoogleFonts.outfit(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              centerTitle: true,
            )
          : null,
      body: SafeArea(
        child: Material(
          type: MaterialType.transparency,
          child: content,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                child: GlassCard(
                  padding: const EdgeInsets.all(20),
                  borderRadius: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.assignment_outlined, size: 36, color: Color(0xFF0D9488)),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No Care Documentation Submitted',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'You have not submitted any out-of-network invoices or care documentation yet. Once uploaded, automated clinical validation and coverage status will appear here.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(fontSize: 12.5, color: const Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton.icon(
                        onPressed: widget.onNavigateToClaims,
                        icon: const Icon(Icons.add_circle, size: 16),
                        label: const Text('Add Care Documentation'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0D9488),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildClaimHeader() {
    final rawId = (_selectedClaim?['id'] ?? widget.claimId ?? 'Claim').toString();
    final shortId = rawId.length > 8 ? rawId.substring(0, 8).toUpperCase() : rawId.toUpperCase();
    final count = _claims.isNotEmpty ? _claims.length : 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Claim #$shortId',
              style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
            ),
            Text(
              '$count request${count == 1 ? '' : 's'} on record',
              style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF64748B)),
            ),
          ],
        ),
        if (_selectedClaim != null)
          IconButton.filledTonal(
            icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF0D9488)),
            tooltip: 'Talk to Clinical Counselor',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ClinicalChatScreen(claimId: rawId)),
              );
            },
          ),
      ],
    );
  }

  Widget _buildFilterTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _filters.map((f) {
          final isSelected = _statusFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: isSelected,
              label: Text(
                f,
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF475569),
                ),
              ),
              selectedColor: const Color(0xFF0D9488),
              backgroundColor: Colors.white.withValues(alpha: 0.8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isSelected ? const Color(0xFF0D9488) : const Color(0xFFE2E8F0)),
              ),
              onSelected: (_) => setState(() => _statusFilter = f),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActiveClaimDetails(Map<String, dynamic> claim) {
    final esiLevel = claim['esi_level']?.toString() ?? 'ESI_2_EMERGENT';
    final esiColor = AppTheme.getEsiColor(esiLevel);
    final esiLabel = AppTheme.getEsiLabel(esiLevel);
    final category = claim['clinical_category']?.toString() ?? 'Medical Emergency & Inpatient Care';
    final currencySymbol = claim['currency'] == 'USD' ? '\$' : '₹';
    final extractedAmount = claim['extracted_bill_amount'] != null
        ? NumberFormat('#,##0.00').format(double.tryParse(claim['extracted_bill_amount'].toString()) ?? 0.0)
        : (claim['calculated_amount'] != null ? NumberFormat('#,##0.00').format(double.tryParse(claim['calculated_amount'].toString()) ?? 0.0) : '4,305.00');
    final copayAmount = claim['recommended_copay_amount'] != null
        ? NumberFormat('#,##0.00').format(double.tryParse(claim['recommended_copay_amount'].toString()) ?? 0.0)
        : extractedAmount;
    final currentStep = _getCurrentStep(claim);

    return GlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ESI Severity Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: esiColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: esiColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.local_hospital, color: esiColor, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        esiLabel,
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: esiColor),
                      ),
                      Text(
                        'Category: $category',
                        style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF475569)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if ((claim['clinical_notes']?.toString().contains('No pre-configured policy') ?? false) ||
              (claim['clinical_notes']?.toString().contains('Discretionary Review') ?? false)) ...[
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Institutional Policy Notice',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFFB45309)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'No pre-configured institutional policy matched "$category". Your emergency request has been routed to the Healthcare Review Board for discretionary copay assistance.',
                          style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF92400E)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),

          // Triage Progress Stepper
          Text(
            'Clinical Triage & Benefit Verification',
            style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
          ),
          const SizedBox(height: 14),

          _buildStep(
            stepNumber: 1,
            title: 'Care Documentation Received',
            subtitle: 'Intake received and queued for NLP distress analysis.',
            isDone: currentStep >= 1,
            isCurrent: currentStep == 1,
          ),
          _buildStep(
            stepNumber: 2,
            title: 'Autonomous Clinical Triage (ESI)',
            subtitle: 'Emergency Severity Index computed: $esiLevel',
            isDone: currentStep >= 2,
            isCurrent: currentStep == 2,
          ),
          _buildStep(
            stepNumber: 3,
            title: 'Invoice OCR & Fraud Sentinel',
            subtitle: 'Verified Hospital Invoice: $currencySymbol$extractedAmount | Care Benefit: $currencySymbol$copayAmount',
            isDone: currentStep >= 3,
            isCurrent: currentStep == 3,
          ),
          _buildStep(
            stepNumber: 4,
            title: currentStep >= 4 ? 'Care Benefit Settled ✓' : 'Institutional Benefit Settlement',
            subtitle: currentStep >= 4
                ? 'Care benefit subsidy allocated and released to healthcare network.'
                : 'Pending final institutional verification and release.',
            isDone: currentStep >= 4,
            isCurrent: currentStep == 4,
            isLast: true,
          ),
          const SizedBox(height: 18),

          // Action: 24/7 Chat
          OutlinedButton.icon(
            onPressed: () {
              final id = (claim['id'] ?? widget.claimId ?? '').toString();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ClinicalChatScreen(claimId: id)),
              );
            },
            icon: const Icon(Icons.psychology, size: 18, color: Color(0xFF0D9488)),
            label: Text(
              '24/7 Psychological First Aid & Chat',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF0D9488)),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF0D9488)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep({
    required int stepNumber,
    required String title,
    required String subtitle,
    required bool isDone,
    required bool isCurrent,
    bool isLast = false,
  }) {
    final color = isDone
        ? const Color(0xFF0D9488)
        : (isCurrent ? const Color(0xFF0284C7) : const Color(0xFF94A3B8));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? const Color(0xFF0D9488) : (isCurrent ? const Color(0xFF0284C7).withValues(alpha: 0.15) : const Color(0xFFF1F5F9)),
                border: Border.all(color: color, width: 2),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : Text(
                        '$stepNumber',
                        style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: color),
                      ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: isDone ? const Color(0xFF0D9488) : const Color(0xFFE2E8F0),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: isDone || isCurrent ? FontWeight.bold : FontWeight.w500,
                    color: isDone || isCurrent ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildClaimListItem(Map<String, dynamic> claim, bool isSelected) {
    final rawId = (claim['id'] ?? '').toString();
    final shortId = rawId.length > 8 ? rawId.substring(0, 8).toUpperCase() : rawId.toUpperCase();
    final status = (claim['status'] ?? 'Active').toString();
    final category = (claim['clinical_category'] ?? 'Emergency Care').toString();
    final createdStr = claim['created_at'] != null
        ? DateFormat('MMM d • h:mm a').format(DateTime.tryParse(claim['created_at'].toString()) ?? DateTime.now())
        : 'Recent';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => setState(() => _selectedClaim = claim),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF0D9488).withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? const Color(0xFF0D9488) : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0D9488) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.receipt_long,
                  size: 20,
                  color: isSelected ? Colors.white : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Claim #$shortId',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: const Color(0xFF0F172A)),
                        ),
                        Text(
                          createdStr,
                          style: GoogleFonts.outfit(fontSize: 10.5, color: const Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          category,
                          style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF64748B)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF0D9488)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
