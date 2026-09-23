import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/diagnostics_provider.dart';
import 'diagnostic_results_screen.dart';

class DiagnosticCameraScreen extends StatefulWidget {
  final String symptomCategoryHint;

  const DiagnosticCameraScreen({
    super.key,
    this.symptomCategoryHint = 'DERMATOLOGY_RASH',
  });

  @override
  State<DiagnosticCameraScreen> createState() => _DiagnosticCameraScreenState();
}

class _DiagnosticCameraScreenState extends State<DiagnosticCameraScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _capturedFile;
  bool _isProcessing = false;
  late String _currentCategoryHint;

  @override
  void initState() {
    super.initState();
    _currentCategoryHint = widget.symptomCategoryHint;
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1280,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _capturedFile = picked;
        });

        if (mounted) {
          context.read<DiagnosticsProvider>().setCapturedImage(picked.path, bytes);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to access camera/gallery: $e')),
        );
      }
    }
  }

  Future<void> _runAnalysis() async {
    setState(() => _isProcessing = true);
    final diag = context.read<DiagnosticsProvider>();

    final result = await diag.runAssessment();
    if (!mounted) return;

    setState(() => _isProcessing = false);

    if (result != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const DiagnosticResultsScreen(),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(diag.errorMessage ?? 'Clinical analysis failed. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final diag = context.watch<DiagnosticsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical Image Capture', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Clinical instructions header
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF0D9488), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Position the lesion/rash in bright, even lighting. Keep the camera ~15cm away and in sharp focus.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

            // Camera / Preview Area with Reticle
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Image Display or Placeholder
                      Container(
                        width: double.infinity,
                        height: double.infinity,
                        color: Colors.black,
                        child: _capturedFile != null
                            ? (kIsWeb
                                ? Image.network(_capturedFile!.path, fit: BoxFit.cover)
                                : Image.file(File(_capturedFile!.path), fit: BoxFit.cover))
                            : const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 64),
                                    SizedBox(height: 12),
                                    Text(
                                      'No photo captured yet',
                                      style: TextStyle(color: Colors.white70, fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                      ),

                      // Clinical Crosshair Reticle Overlay
                      IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF0D9488).withOpacity(0.6),
                              width: 2.0,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Container(
                              width: 180,
                              height: 180,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.7),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.crop_free,
                                size: 48,
                                color: Color(0xFF0D9488),
                              ),
                            ),
                          ),
                        ),
                      ),

                      if (_isProcessing)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(color: Color(0xFF0D9488)),
                                SizedBox(height: 16),
                                Text(
                                  'Extracting 128-d Visual Embeddings & Running Fusion...',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
            const SizedBox(height: 16),

            // Capture / Retake Triggers
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                      onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.camera_alt),
                      label: Text(_capturedFile == null ? 'Take Photo' : 'Retake'),
                      onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Run Analysis / Skip Image Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _capturedFile != null ? const Color(0xFF0284C7) : Colors.grey[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.biotech),
                  label: Text(
                    _capturedFile != null
                        ? 'Run Multimodal AI Checkup'
                        : 'Run Checkup (Without Photo)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  onPressed: _isProcessing ? null : _runAnalysis,
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
