import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../providers/diagnostic_state_provider.dart';
import '../providers/diagnostics_provider.dart';
import '../services/inference_engine_interface.dart';
import '../services/local_inference_service.dart';
import 'diagnostic_results_screen.dart';
import 'ScreeningResultScreen.dart';

class ClinicalCameraScreen extends StatefulWidget {
  const ClinicalCameraScreen({super.key});

  @override
  State<ClinicalCameraScreen> createState() => _ClinicalCameraScreenState();
}

class _ClinicalCameraScreenState extends State<ClinicalCameraScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedFile;
  bool _isAnalyzing = false;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    final offline = await LocalInferenceService.isOffline();
    if (mounted) {
      setState(() => _isOffline = offline);
    }
  }

  Future<void> _captureOrPickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 90,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _selectedFile = picked;
        });

        if (mounted) {
          final provider = context.read<DiagnosticStateProvider>();
          final mime = picked.mimeType ?? 'image/jpeg';
          await provider.setImage(bytes, filePath: picked.path, mimeType: mime);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.emergencyRed,
            content: Text('Failed to acquire image: $e'),
          ),
        );
      }
    }
  }

  Future<void> _submitScreening() async {
    final provider = context.read<DiagnosticStateProvider>();

    if (provider.imageMetadata != null && !provider.imageMetadata!.isResolutionValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.emergencyRed,
          content: Text('⚠️ Image resolution too low for diagnostic accuracy. Please capture a higher-resolution photo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isAnalyzing = true);

    final assessment = await provider.executeScreening();

    if (!mounted) return;
    setState(() => _isAnalyzing = false);

    if (assessment != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ScreeningResultScreen(assessmentOverride: assessment)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.emergencyRed,
          content: Text(provider.errorMessage ?? 'Clinical assessment failed. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DiagnosticStateProvider>();
    final metadata = provider.imageMetadata;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : AppTheme.surfaceSlate,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBrand,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Clinical Image Capture', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Step 2 of 2: Physical Symptom Photo', style: GoogleFonts.outfit(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Offline Mode Badge (Requirement: "Processed 100% On-Device (Offline Private Mode)")
            if (_isOffline || context.watch<DiagnosticsProvider>().executionMode == ExecutionMode.localTflite)
              Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.offline_bolt_rounded, color: Color(0xFF10B981), size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Processed 100% On-Device (Offline Private Mode)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF047857),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('OFFLINE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),

            // Lighting & Framing Clinical Guidance Card
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderSubtle),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.wb_sunny_outlined, color: Color(0xFFD97706), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Framing & Lighting Protocol',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textDark),
                        ),
                        Text(
                          'Keep distance ~15 cm from skin/throat/lesion. Ensure bright daylight or direct lamp illumination without heavy glare.',
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Camera / Viewfinder Box with Framing Box Overlay
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Viewfinder Area
                      Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.black,
                        child: _selectedFile != null
                            ? (kIsWeb
                                ? Image.network(_selectedFile!.path, fit: BoxFit.contain)
                                : Image.file(File(_selectedFile!.path), fit: BoxFit.contain))
                            : Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.camera_alt_outlined, color: Colors.white38, size: 68),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Target: ${provider.selectedBodyLocation ?? "Symptom Area"}',
                                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Take photo or choose from gallery',
                                      style: GoogleFonts.inter(color: Colors.white60, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                      ),

                      // Overlay Framing Box & Reticle
                      IgnorePointer(
                        child: Container(
                          margin: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: AppTheme.primaryBrand.withOpacity(0.8),
                              width: 2.0,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Stack(
                            children: [
                              // Top Left Corner
                              Positioned(
                                top: 0,
                                left: 0,
                                child: Container(width: 24, height: 24, decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white, width: 3), left: BorderSide(color: Colors.white, width: 3)))),
                              ),
                              // Top Right Corner
                              Positioned(
                                top: 0,
                                right: 0,
                                child: Container(width: 24, height: 24, decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white, width: 3), right: BorderSide(color: Colors.white, width: 3)))),
                              ),
                              // Bottom Left Corner
                              Positioned(
                                bottom: 0,
                                left: 0,
                                child: Container(width: 24, height: 24, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white, width: 3), left: BorderSide(color: Colors.white, width: 3)))),
                              ),
                              // Bottom Right Corner
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(width: 24, height: 24, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white, width: 3), right: BorderSide(color: Colors.white, width: 3)))),
                              ),
                              const Center(
                                child: Icon(Icons.add, color: Colors.white54, size: 28),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Analyzing Overlay
                      if (_isAnalyzing || provider.isValidatingImage)
                        Container(
                          color: Colors.black54,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(color: AppTheme.primaryBrand),
                                const SizedBox(height: 16),
                                Text(
                                  provider.isValidatingImage
                                      ? 'Validating 512x512 resolution...'
                                      : 'Fusing Multimodal Vision & Symptoms...',
                                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Real-Time Resolution Validation Warning / Success Badge
            if (metadata != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: metadata.isResolutionValid
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF16A34A).withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'Resolution: ${metadata.resolutionString} • Diagnostic Quality Verified',
                              style: GoogleFonts.inter(color: const Color(0xFF15803D), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.emergencyRed.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppTheme.emergencyRed, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Low Resolution (${metadata.resolutionString}). Must be at least 512x512. Please retake photo.',
                                style: GoogleFonts.inter(color: const Color(0xFF991B1B), fontSize: 11.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            const SizedBox(height: 12),

            // Image Acquisition Buttons (Camera & Gallery Switch)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: AppTheme.primaryBrand),
                        foregroundColor: AppTheme.primaryBrand,
                      ),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        'Gallery (PNG/JPEG)',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      onPressed: _isAnalyzing ? null : () => _captureOrPickImage(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBrand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.camera_alt),
                      label: Text(
                        _selectedFile == null ? 'Take Photo' : 'Retake',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      onPressed: _isAnalyzing ? null : () => _captureOrPickImage(ImageSource.camera),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Submit Screening Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (metadata != null && metadata.isResolutionValid)
                        ? AppTheme.accentCyan
                        : (metadata == null ? Colors.grey[700] : Colors.grey[400]),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: (metadata != null && metadata.isResolutionValid) ? 2 : 0,
                  ),
                  icon: const Icon(Icons.biotech),
                  label: Text(
                    metadata != null
                        ? (metadata.isResolutionValid ? 'Run Clinical Health Checkup' : 'Resolution Too Low (Retake Photo)')
                        : 'Run Checkup (Questionnaire Only)',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  onPressed: (_isAnalyzing || (metadata != null && !metadata.isResolutionValid))
                      ? null
                      : _submitScreening,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
