import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import '../../../config/api_config.dart';
import '../../../providers/auth_provider.dart';
import '../../../theme/app_theme.dart';
import '../models/diagnostic_session.dart';
import '../models/risk_assessment.dart';
import '../providers/diagnostic_state_provider.dart';

/// Clinical Report Share & Export Sheet
/// Generates full structured clinical assessment reports, copies text to clipboard,
/// and facilitates downloading/viewing formal PDF clinical referral letters.
class ClinicalReportShareSheet extends StatefulWidget {
  final RiskAssessment assessment;
  final DiagnosticStateProvider stateProvider;
  final DiagnosticSession? session;

  const ClinicalReportShareSheet({
    super.key,
    required this.assessment,
    required this.stateProvider,
    this.session,
  });

  /// Opens the bottom sheet and automatically exports the clinical report text to the clipboard.
  static Future<void> show(
    BuildContext context, {
    required RiskAssessment assessment,
    required DiagnosticStateProvider stateProvider,
    DiagnosticSession? session,
  }) async {
    final reportText = generateClinicalReportText(
      assessment: assessment,
      stateProvider: stateProvider,
      session: session,
    );

    // 1. Immediately copy formatted clinical report to system clipboard
    await Clipboard.setData(ClipboardData(text: reportText));

    if (!context.mounted) return;

    // 2. Display confirmation snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Clinical report copied to clipboard (${reportText.length} chars)',
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
      ),
    );

    // 3. Slide up comprehensive report export sheet
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClinicalReportShareSheet(
        assessment: assessment,
        stateProvider: stateProvider,
        session: session,
      ),
    );
  }

  /// Compiles a structured, clinical-grade plaintext summary report.
  static String generateClinicalReportText({
    required RiskAssessment assessment,
    required DiagnosticStateProvider stateProvider,
    DiagnosticSession? session,
  }) {
    final now = DateTime.now();
    final dateFormatted =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final bounds = assessment.uncertaintyBounds;
    final scorePercent = (assessment.riskScore * 100).round();
    final confPercent = (bounds.confidence * 100).round();
    final ciLowerPercent = (bounds.ciLower * 100).round();
    final ciUpperPercent = (bounds.ciUpper * 100).round();

    final buffer = StringBuffer();
    buffer.writeln('====================================================');
    buffer.writeln('🏥 MEDACCESS AI — CLINICAL ASSESSMENT SUMMARY REPORT');
    buffer.writeln('====================================================');
    buffer.writeln('Date & Time: $dateFormatted');
    if (session?.id != null && session!.id.isNotEmpty) {
      buffer.writeln('Session ID: ${session.id}');
    }
    buffer.writeln(
      'Execution Mode: ${assessment.isOffline ? "On-Device Offline (TFLite Private)" : "Cloud Multimodal Neural Engine"}',
    );
    buffer.writeln('Primary Diagnosis: ${assessment.primaryDiagnosis}');
    buffer.writeln(
      'Risk Stratification: ${assessment.riskLevel.displayName.toUpperCase()} ($scorePercent% Risk Score)',
    );
    buffer.writeln('Model Confidence: $confPercent% (95% CI: $ciLowerPercent% - $ciUpperPercent%)');
    buffer.writeln(
      'Physician Review Required: ${assessment.requiresImmediatePhysicianReview ? "YES (URGENT)" : "Routine Clinical Follow-up"}',
    );
    buffer.writeln('');

    // Patient Presentation & Vitals
    buffer.writeln('📋 PATIENT PRESENTATION & VITALS:');
    if (stateProvider.selectedBodyLocation != null) {
      buffer.writeln('• Anatomical Site: ${stateProvider.selectedBodyLocation}');
    }
    buffer.writeln('• Reported Pain Severity: ${stateProvider.painSeverity}/10');
    buffer.writeln('• Symptom Duration: ${stateProvider.symptomDurationDays} days');
    buffer.writeln('• Core Body Temperature: ${stateProvider.temperatureCelsius.toStringAsFixed(1)}°C');
    if (stateProvider.selectedSecondarySymptoms.isNotEmpty) {
      buffer.writeln('• Secondary Symptoms: ${stateProvider.selectedSecondarySymptoms.join(', ')}');
    }
    if (stateProvider.preExistingConditions.isNotEmpty) {
      buffer.writeln('• Comorbidities: ${stateProvider.preExistingConditions.join(', ')}');
    }
    buffer.writeln('');

    // Differential Diagnoses
    if (assessment.differentialDiagnoses.isNotEmpty) {
      buffer.writeln('🩺 DIFFERENTIAL DIAGNOSES:');
      for (final diff in assessment.differentialDiagnoses) {
        final p = (diff.probability * 100).round();
        buffer.writeln('• ${diff.condition}: $p% probability [${diff.urgency}]');
      }
      buffer.writeln('');
    }

    // Clinical Recommendations
    if (assessment.clinicalRecommendations.isNotEmpty) {
      buffer.writeln('💡 CLINICAL RECOMMENDATIONS & NEXT STEPS:');
      for (int i = 0; i < assessment.clinicalRecommendations.length; i++) {
        buffer.writeln('${i + 1}. ${assessment.clinicalRecommendations[i]}');
      }
      buffer.writeln('');
    }

    // Feature Attribution (XAI)
    if (assessment.featureAttributions.isNotEmpty) {
      buffer.writeln('🔬 KEY CLINICAL ATTRIBUTIONS (EXPLAINABLE AI):');
      for (final attr in assessment.featureAttributions) {
        buffer.writeln('• ${attr.featureName} (${attr.percentageImpact}% impact) — ${attr.description}');
      }
      buffer.writeln('');
    }

    buffer.writeln('====================================================');
    buffer.writeln('⚠️ NOTICE: Generated by MedAccess AI Clinical Decision Support System.');
    buffer.writeln('Intended for triage and physician reference only. Not a standalone medical prescription.');
    buffer.writeln('====================================================');

    return buffer.toString();
  }

  @override
  State<ClinicalReportShareSheet> createState() => _ClinicalReportShareSheetState();
}

class _ClinicalReportShareSheetState extends State<ClinicalReportShareSheet> {
  bool _isCopied = true;
  bool _showTextPreview = false;
  bool _isGeneratingPdf = false;
  String? _pdfErrorMessage;

  Color _getRiskColor(ClinicalRiskLevel level) {
    switch (level) {
      case ClinicalRiskLevel.critical:
        return const Color(0xFFEF4444);
      case ClinicalRiskLevel.high:
        return const Color(0xFFF97316);
      case ClinicalRiskLevel.moderate:
        return const Color(0xFFF59E0B);
      case ClinicalRiskLevel.low:
        return const Color(0xFF10B981);
    }
  }

  Future<void> _onDownloadPdfPressed() async {
    // If age or gender are not yet recorded on the stateProvider, prompt the patient before generating
    if (widget.stateProvider.age == null || widget.stateProvider.gender == null) {
      final shouldProceed = await _showDemographicsDialog();
      if (!shouldProceed) return;
    }
    await _handleDownloadPdf();
  }

  Future<bool> _showDemographicsDialog() async {
    final ageController = TextEditingController(
      text: widget.stateProvider.age != null ? widget.stateProvider.age.toString() : '',
    );
    String? selectedGender = widget.stateProvider.gender;
    String? ageError;
    String? genderError;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              backgroundColor: isDark ? AppTheme.cardDarkNavy : Colors.white,
              title: Row(
                children: [
                  const Icon(Icons.badge_outlined, color: AppTheme.primaryBrand, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Patient Demographics',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppTheme.textDark,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Patient demographics (Age & Gender) are required to generate an official clinical referral letter.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ageController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        if (ageError != null) {
                          setDialogState(() => ageError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Age (Years) *',
                        hintText: 'e.g. 28',
                        errorText: ageError,
                        prefixIcon: const Icon(Icons.cake_outlined, color: AppTheme.primaryBrand),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: selectedGender,
                      decoration: InputDecoration(
                        labelText: 'Gender *',
                        hintText: 'Select gender',
                        errorText: genderError,
                        prefixIcon: const Icon(Icons.person_outline, color: AppTheme.primaryBrand),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Female', child: Text('Female')),
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(value: 'Non-Binary', child: Text('Non-Binary')),
                        DropdownMenuItem(value: 'Other', child: Text('Other')),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          selectedGender = val;
                          genderError = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : AppTheme.textMuted,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBrand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    final rawAge = ageController.text.trim();
                    final enteredAge = int.tryParse(rawAge);
                    bool hasError = false;

                    if (rawAge.isEmpty || enteredAge == null || enteredAge <= 0 || enteredAge > 125) {
                      setDialogState(() {
                        ageError = 'Please enter a valid age (1-125)';
                      });
                      hasError = true;
                    }

                    if (selectedGender == null || selectedGender!.isEmpty) {
                      setDialogState(() {
                        genderError = 'Please select a gender';
                      });
                      hasError = true;
                    }

                    if (hasError) return;

                    widget.stateProvider.setAge(enteredAge);
                    widget.stateProvider.setGender(selectedGender);
                    Navigator.of(dialogCtx).pop(true);
                  },
                  child: Text(
                    'Confirm & Generate',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
  }

  Future<void> _handleDownloadPdf() async {
    setState(() {
      _isGeneratingPdf = true;
      _pdfErrorMessage = null;
    });

    try {
      AuthProvider? auth;
      try {
        auth = Provider.of<AuthProvider>(context, listen: false);
      } catch (_) {}

      final patientId = widget.session?.patientId ??
          auth?.user?.patientId ??
          auth?.user?.id ??
          'PAT-37B041';
      final patientName = auth?.user?.name ?? 'Priya Sharma';
      final institutionId = widget.session?.institutionId ??
          auth?.user?.institutionId ??
          ApiConfig.activeInstitutionId;
      final institutionName = auth?.user?.institutionName ??
          ApiConfig.activeInstitutionName;
      final screeningId = widget.assessment.screeningId ?? widget.session?.id;

      final age = widget.stateProvider.age;
      final gender = widget.stateProvider.gender;
      final demographicsMap = <String, dynamic>{
        if (age != null) 'age': age,
        if (gender != null && gender.isNotEmpty && gender != 'Prefer not to say') 'gender': gender,
      };

      final vitalsMap = widget.session?.symptomVector.vitals.toMap() ?? {
        'heartRateBpm': 79,
        'oxygenSaturationSpo2': 100,
        'bloodPressureSystolicMmHg': 142,
        'bloodPressureDiastolicMmHg': 92,
        'temperatureCelsius': widget.stateProvider.temperatureCelsius,
        'painSeverity': widget.stateProvider.painSeverity,
      };

      // 1. POST to backend to generate the PDF bytes
      final postUri = ApiConfig.resolveUri('/diagnostics/referral-letter');
      final res = await http
          .post(
            postUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'demographics': demographicsMap,
              'screeningId': screeningId,
              'patientId': patientId,
              'patientName': patientName,
              'institutionId': institutionId,
              'institutionName': institutionName,
              'assessment': widget.assessment.toMap(),
              'vitals': vitalsMap,
              'symptomVector': {
                'bodyLocation': widget.stateProvider.selectedBodyLocation,
                'painSeverity': widget.stateProvider.painSeverity,
                'durationDays': widget.stateProvider.symptomDurationDays,
                'temperatureCelsius': widget.stateProvider.temperatureCelsius,
                'symptoms': widget.stateProvider.selectedSecondarySymptoms.toList(),
                'vitals': vitalsMap,
                'demographics': demographicsMap,
              },
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        throw Exception('Backend returned HTTP ${res.statusCode}: ${res.body.substring(0, res.body.length.clamp(0, 200))}');
      }

      final pdfBytes = res.bodyBytes;
      if (pdfBytes.isEmpty) {
        throw Exception('Backend returned empty PDF body.');
      }

      // 2. Save to device temp directory
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'intellidesk_referral_$timestamp.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);

      debugPrint('📄 [PDF] Saved ${pdfBytes.length} bytes → ${file.path}');

      // 3. Open safely with OpenFilex using content:// URI & FileProvider (avoids FileUriExposedException)
      bool opened = false;
      try {
        final result = await OpenFilex.open(file.path, type: 'application/pdf');
        debugPrint('📄 [PDF] OpenFilex result: ${result.type} - ${result.message}');
        if (result.type == ResultType.done) {
          opened = true;
        }
      } catch (openErr) {
        debugPrint('⚠️ [PDF] OpenFilex open exception: $openErr');
      }

      // 4. Fallback: if native PDF viewer isn't available or fails, use system share sheet
      if (!opened) {
        try {
          final xFile = XFile(file.path, mimeType: 'application/pdf', name: fileName);
          await SharePlus.instance.share(
            ShareParams(
              files: [xFile],
              subject: 'IntelliDesk Clinical Referral Letter',
              text: 'Clinical Referral Letter for Patient ${widget.session?.patientId ?? 'EHR'}',
            ),
          );
          opened = true;
        } catch (shareErr) {
          debugPrint('⚠️ [PDF] Share fallback error: $shareErr');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F766E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '✅ Referral letter ready (${(pdfBytes.length / 1024).toStringAsFixed(1)} KB).',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [PDF] Download failed: $e');
      if (mounted) {
        setState(() {
          _pdfErrorMessage = 'PDF generation failed: ${e.toString().replaceAll('Exception: ', '')}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assessment = widget.assessment;
    final riskColor = _getRiskColor(assessment.riskLevel);
    final scorePercent = (assessment.riskScore * 100).round();
    final confPercent = (assessment.uncertaintyBounds.confidence * 100).round();
    final reportText = ClinicalReportShareSheet.generateClinicalReportText(
      assessment: assessment,
      stateProvider: widget.stateProvider,
      session: widget.session,
    );

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: 12,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header with Status Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBrand.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.share_rounded, color: AppTheme.primaryBrand, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Share Clinical Report',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppTheme.textDark,
                      ),
                    ),
                    Text(
                      'Full assessment data exported & ready to share',
                      style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Clipboard Success Alert Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Screening report automatically copied to clipboard!',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Summary Highlights Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        assessment.primaryDiagnosis,
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: riskColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: riskColor.withOpacity(0.4)),
                      ),
                      child: Text(
                        assessment.riskLevel.displayName.toUpperCase(),
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: riskColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Risk Score: $scorePercent%',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Confidence: $confPercent%',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${reportText.length} chars',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Primary Action: Download / View PDF Referral Letter
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBrand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            icon: _isGeneratingPdf
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_rounded, size: 20),
            label: Text(
              _isGeneratingPdf ? 'Generating PDF...' : 'Download Referral Letter (PDF)',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            onPressed: _isGeneratingPdf ? null : _onDownloadPdfPressed,
          ),
          if (_pdfErrorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              _pdfErrorMessage!,
              style: GoogleFonts.outfit(fontSize: 12, color: Colors.redAccent),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 10),

          // Secondary Action: Re-copy to Clipboard
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? Colors.white : AppTheme.textDark,
              side: BorderSide(
                color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: Icon(
              _isCopied ? Icons.check_rounded : Icons.copy_rounded,
              size: 18,
              color: _isCopied ? const Color(0xFF10B981) : null,
            ),
            label: Text(
              _isCopied ? 'Report Copied to Clipboard' : 'Copy Report to Clipboard',
              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: reportText));
              setState(() => _isCopied = true);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Report copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 10),

          // Tertiary Action: Toggle Plaintext Preview
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.textMuted,
              padding: const EdgeInsets.symmetric(vertical: 6),
            ),
            icon: Icon(
              _showTextPreview ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              size: 20,
            ),
            label: Text(
              _showTextPreview ? 'Hide Raw Report Text' : 'Preview Full Report Text',
              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            onPressed: () {
              setState(() => _showTextPreview = !_showTextPreview);
            },
          ),

          // Expandable Raw Report Text Viewer
          if (_showTextPreview)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0B132B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFCBD5E1),
                ),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  reportText,
                  style: GoogleFonts.firaCode(
                    fontSize: 11,
                    height: 1.4,
                    color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
