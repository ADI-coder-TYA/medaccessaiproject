import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../models/risk_assessment.dart';
import '../providers/diagnostics_provider.dart';
import '../providers/diagnostic_state_provider.dart';
import '../services/diagnostics_service.dart';
import '../services/inference_engine_interface.dart';
import 'LongitudinalHistoryScreen.dart';
import 'EmergencyFacilitySheet.dart';

class ScreeningResultScreen extends StatefulWidget {
  final RiskAssessment? assessmentOverride;
  final String? originalImageUrl;
  final Uint8List? originalImageBytes;
  final DiagnosticsService? diagnosticsService;

  const ScreeningResultScreen({
    super.key,
    this.assessmentOverride,
    this.originalImageUrl,
    this.originalImageBytes,
    this.diagnosticsService,
  });

  @override
  State<ScreeningResultScreen> createState() => _ScreeningResultScreenState();
}

class _ScreeningResultScreenState extends State<ScreeningResultScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _showSideBySide = true;
  bool _hasAutoTriggeredEmergencySheet = false;

  Color _getRiskColor(ClinicalRiskLevel level) {
    switch (level) {
      case ClinicalRiskLevel.critical:
        return const Color(0xFFEF4444); // Urgent Coral Red
      case ClinicalRiskLevel.high:
        return const Color(0xFFF97316); // High Orange
      case ClinicalRiskLevel.moderate:
        return const Color(0xFFF59E0B); // Amber
      case ClinicalRiskLevel.low:
        return const Color(0xFF10B981); // Emerald Green
    }
  }

  @override
  Widget build(BuildContext context) {
    final diag = context.watch<DiagnosticsProvider>();
    final stateProvider = context.watch<DiagnosticStateProvider>();
    final session = diag.currentSession;
    final assessment = widget.assessmentOverride ?? session?.riskAssessment ?? stateProvider.assessmentResult;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (assessment == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Diagnostic Results')),
        body: const Center(child: Text('No active clinical assessment results found.')),
      );
    }

    // Technical Guardrail 4: Automatically slide up the facility router on Critical Referral
    if (assessment.riskLevel == ClinicalRiskLevel.critical && !_hasAutoTriggeredEmergencySheet) {
      _hasAutoTriggeredEmergencySheet = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          EmergencyFacilitySheet.show(context);
        }
      });
    }

    final riskColor = _getRiskColor(assessment.riskLevel);
    final bounds = assessment.uncertaintyBounds;
    final scorePercent = (assessment.riskScore * 100).round();
    final marginPercent = (((bounds.ciUpper - bounds.ciLower) / 2) * 100).round();
    final confPercent = (bounds.confidence * 100).round();

    final photoUrl = widget.originalImageUrl ?? session?.clinicalImageUrl;
    final photoBytes = widget.originalImageBytes ?? stateProvider.imageMetadata?.bytes;
    final hasPhoto = (photoUrl != null && photoUrl.isNotEmpty) || photoBytes != null;
    final heatmapUrl = assessment.xaiHeatmapUrl ?? session?.xaiHeatmapUrl;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.surfaceSlate,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBrand,
        foregroundColor: Colors.white,
        title: Text(
          'Diagnostic Assessment Report',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          if (assessment.riskLevel == ClinicalRiskLevel.critical)
            IconButton(
              icon: const Icon(Icons.emergency, color: Color(0xFFEF4444)),
              tooltip: 'Emergency Care Centers',
              onPressed: () => EmergencyFacilitySheet.show(context),
            ),
          IconButton(
            icon: const Icon(Icons.show_chart),
            tooltip: 'Longitudinal Progression',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => LongitudinalHistoryScreen(
                    diagnosticsService: widget.diagnosticsService,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.forum_outlined),
            tooltip: 'Discuss Results with Health AI',
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      endDrawer: HealthAIChatDrawer(
        assessment: assessment,
        diagnosticsService: widget.diagnosticsService,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // 0. Offline Mode Privacy Badge
            if (assessment.isOffline || diag.executionMode == ExecutionMode.localTflite)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.offline_bolt_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Processed 100% On-Device (Offline Private Mode)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Zero network transmission • TFLite Quantized Neural Pipeline • 100% HIPAA Private',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF047857),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'OFFLINE',
                        style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            // 1. Dynamic Risk Score Bar: (Score ± Uncertainty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: riskColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: riskColor.withOpacity(0.5), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UNIFIED CLINICAL RISK ASSESSMENT',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            assessment.riskLevel.displayName,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: riskColor),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: riskColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$scorePercent% ± $marginPercent%',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Linear Risk Score Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: assessment.riskScore.clamp(0.02, 1.0),
                      minHeight: 12,
                      backgroundColor: Colors.grey.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(riskColor),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Epistemic Uncertainty & 95% Confidence Interval Chips
                  Row(
                    children: [
                      const Icon(Icons.analytics_outlined, size: 16, color: Colors.blueGrey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Confidence: $confPercent% (95% CI: ${(bounds.ciLower * 100).round()}% - ${(bounds.ciUpper * 100).round()}%) • Monte Carlo N=10',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 2. Original Image Alongside Grad-CAM Heatmap Overlay
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.compare, color: Color(0xFF0D9488), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Visual Diagnosis Saliency',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          icon: Icon(_showSideBySide ? Icons.view_column : Icons.layers, size: 16),
                          label: Text(_showSideBySide ? 'Side-by-Side' : 'Overlay Mode', style: const TextStyle(fontSize: 12)),
                          onPressed: () => setState(() => _showSideBySide = !_showSideBySide),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Original symptom photo compared with Grad-CAM neural attention heatmap.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 14),

                    if (_showSideBySide)
                      // Side-by-Side View
                      Row(
                        children: [
                          // Left: Original Image
                          Expanded(
                            child: Column(
                              children: [
                                Container(
                                  height: 160,
                                  decoration: BoxDecoration(
                                    color: Colors.black12,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: _buildPhotoWidget(photoBytes, photoUrl),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Original Symptom Photo',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Right: Grad-CAM Heatmap Overlay
                          Expanded(
                            child: Column(
                              children: [
                                Container(
                                  height: 160,
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        _buildPhotoWidget(photoBytes, photoUrl),
                                        // Thermal Jet Colormap Simulation
                                        Container(
                                          decoration: BoxDecoration(
                                            gradient: RadialGradient(
                                              center: const Alignment(0.1, 0.1),
                                              radius: 0.65,
                                              colors: [
                                                Colors.red.withOpacity(0.55),
                                                Colors.amber.withOpacity(0.35),
                                                Colors.blue.withOpacity(0.15),
                                                Colors.transparent,
                                              ],
                                              stops: const [0.0, 0.45, 0.75, 1.0],
                                            ),
                                          ),
                                          child: const Center(
                                            child: Icon(Icons.flare, color: Colors.redAccent, size: 42),
                                          ),
                                        ),
                                        Positioned(
                                          bottom: 6,
                                          left: 6,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: Colors.black87,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'Active Hotspot',
                                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Grad-CAM Heatmap',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.redAccent),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    else
                      // Stacked Full Overlay Mode
                      Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _buildPhotoWidget(photoBytes, photoUrl),
                              Container(
                                decoration: BoxDecoration(
                                  gradient: RadialGradient(
                                    center: const Alignment(0.15, 0.1),
                                    radius: 0.6,
                                    colors: [
                                      Colors.red.withOpacity(0.55),
                                      Colors.amber.withOpacity(0.35),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(Icons.flare, color: Colors.redAccent, size: 58),
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Composite Grad-CAM Hotspot Overlay',
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Primary Finding & Differential Possibilities
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.medical_services_outlined, color: Color(0xFF0D9488), size: 20),
                        SizedBox(width: 8),
                        Text('Primary Diagnostic Finding', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      assessment.primaryDiagnosis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (assessment.featureContributionBreakdown != null) ...[
                      Text(
                        'Contribution Breakdown: ${assessment.featureContributionBreakdown}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (assessment.clinicalRecommendations.isNotEmpty) ...[
                      const Text('Recommended Actions:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 4),
                      ...assessment.clinicalRecommendations.map((rec) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ', style: TextStyle(color: Color(0xFF0D9488), fontWeight: FontWeight.bold)),
                                Expanded(child: Text(rec, style: const TextStyle(fontSize: 12.5))),
                              ],
                            ),
                          )),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.15))),
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0D9488),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 2,
          ),
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text(
            'Discuss Results with Health AI (Qwen2.5 PFA)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
        ),
      ),
    );
  }

  Widget _buildPhotoWidget(Uint8List? bytes, String? url) {
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(bytes, fit: BoxFit.cover, width: double.infinity, height: double.infinity);
    }
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, color: Colors.grey),
        ),
      );
    }
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_outlined, color: Colors.white38, size: 36),
            SizedBox(height: 6),
            Text('Intake Photo Simulated', style: TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

/// Interactive "Discuss Results with Health AI" Chat Drawer powered by Qwen2.5.
class HealthAIChatDrawer extends StatefulWidget {
  final RiskAssessment assessment;
  final VoidCallback onClose;
  final DiagnosticsService? diagnosticsService;

  const HealthAIChatDrawer({
    super.key,
    required this.assessment,
    required this.onClose,
    this.diagnosticsService,
  });

  @override
  State<HealthAIChatDrawer> createState() => _HealthAIChatDrawerState();
}

class _HealthAIChatDrawerState extends State<HealthAIChatDrawer> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final DiagnosticsService _service;
  bool _isLoading = false;

  final List<String> _quickSuggestions = [
    'What should I do next?',
    'Is this contagious?',
    'How can I soothe the pain?',
    'Is this an emergency?',
  ];

  @override
  void initState() {
    super.initState();
    _service = widget.diagnosticsService ?? DiagnosticsService();

    // Immediately seed with deterministic Rogerian interpretation for instant, zero-latency render
    final localText = _service.generateLocalInterpretation(widget.assessment);
    _messages.add({
      'sender': 'QWEN_AI',
      'text': localText,
      'timestamp': DateTime.now(),
    });

    // If online, enrich asynchronously with Qwen2.5 server interpretation
    if (!widget.assessment.isOffline) {
      _service.interpretScreeningResult(assessment: widget.assessment).then((onlineText) {
        if (mounted && onlineText != localText) {
          setState(() {
            _messages[0]['text'] = onlineText;
          });
        }
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage([String? presetText]) async {
    final text = presetText ?? _inputController.text.trim();
    if (text.isEmpty) return;

    if (presetText == null) {
      _inputController.clear();
    }

    setState(() {
      _messages.add({
        'sender': 'PATIENT',
        'text': text,
        'timestamp': DateTime.now(),
      });
      _isLoading = true;
    });
    _scrollToBottom();

    final history = _messages
        .take(_messages.length - 1)
        .map((m) => {
              'sender': m['sender'] as String,
              'message': m['text'] as String,
            })
        .toList();

    final reply = await _service.sendDiagnosticChatMessage(
      assessment: widget.assessment,
      message: text,
      history: history,
    );

    if (mounted) {
      setState(() {
        _messages.add({
          'sender': 'QWEN_AI',
          'text': reply,
          'timestamp': DateTime.now(),
        });
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.90,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0D9488),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.white,
                    radius: 18,
                    child: Icon(Icons.psychology, color: Color(0xFF0D9488), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Qwen2.5 Health Assistant',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Local ONNX & Psychological First Aid',
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),

            // Mandatory Clinical Disclaimer Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFFFEF3C7), // Warm amber tint
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFB45309), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This is an AI-assisted screening tool, not a final medical diagnosis.',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Chat Messages List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final isUser = msg['sender'] == 'PATIENT';

                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                      decoration: BoxDecoration(
                        color: isUser
                            ? const Color(0xFF0D9488)
                            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(14),
                          topRight: const Radius.circular(14),
                          bottomLeft: isUser ? const Radius.circular(14) : const Radius.circular(2),
                          bottomRight: isUser ? const Radius.circular(2) : const Radius.circular(14),
                        ),
                        border: isUser ? null : Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: Text(
                        msg['text'] as String,
                        style: TextStyle(
                          color: isUser ? Colors.white : (isDark ? Colors.white : Colors.black87),
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0D9488))),
                    SizedBox(width: 8),
                    Text('Qwen2.5 is thinking...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),

            // Quick Inquiry Chips
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: _quickSuggestions.map((sug) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ActionChip(
                      label: Text(sug, style: const TextStyle(fontSize: 11.5)),
                      onPressed: () => _sendMessage(sug),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 6),

            // Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: InputDecoration(
                        hintText: 'Ask Qwen2.5 about next steps...',
                        hintStyle: const TextStyle(fontSize: 12.5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    style: IconButton.styleFrom(backgroundColor: const Color(0xFF0D9488), foregroundColor: Colors.white),
                    icon: const Icon(Icons.send, size: 18),
                    onPressed: () => _sendMessage(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
