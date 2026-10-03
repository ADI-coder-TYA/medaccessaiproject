import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/diagnostic_payload.dart';
import '../models/risk_assessment.dart';
import '../services/diagnostics_service.dart';

/// MVVM ViewModel managing questionnaire state, real-time image validation,
/// and building the unified DiagnosticPayload.
class DiagnosticStateProvider extends ChangeNotifier {
  final DiagnosticsService _diagnosticsService;

  // Questionnaire State
  String? _selectedBodyLocation;
  int _painSeverity = 4;
  int _symptomDurationDays = 3;
  double _temperatureCelsius = 37.0;
  final Set<String> _selectedSecondarySymptoms = {'Redness', 'Swelling'};

  // Demographics State
  int? _age;
  String? _gender;
  final Set<String> _preExistingConditions = {};
  String? _notes;

  // Clinical Image & Resolution Validation State
  ClinicalImageMetadata? _imageMetadata;
  bool _isValidatingImage = false;
  String? _imageResolutionWarning;

  // Audio Biomarker State
  Uint8List? _audioBytes;
  String? _audioFileName;

  // Analysis State
  bool _isAnalyzing = false;
  String? _errorMessage;
  RiskAssessment? _assessmentResult;

  DiagnosticStateProvider({DiagnosticsService? diagnosticsService})
      : _diagnosticsService = diagnosticsService ?? DiagnosticsService();

  // Getters
  String? get selectedBodyLocation => _selectedBodyLocation;
  int get painSeverity => _painSeverity;
  int get symptomDurationDays => _symptomDurationDays;
  double get temperatureCelsius => _temperatureCelsius;
  Set<String> get selectedSecondarySymptoms => Set.unmodifiable(_selectedSecondarySymptoms);
  int? get age => _age;
  String? get gender => _gender;
  Set<String> get preExistingConditions => Set.unmodifiable(_preExistingConditions);
  String? get notes => _notes;
  ClinicalImageMetadata? get imageMetadata => _imageMetadata;
  bool get isValidatingImage => _isValidatingImage;
  String? get imageResolutionWarning => _imageResolutionWarning;
  Uint8List? get audioBytes => _audioBytes;
  String? get audioFileName => _audioFileName;
  bool get hasAudio => _audioBytes != null && _audioBytes!.isNotEmpty;
  bool get isAnalyzing => _isAnalyzing;
  String? get errorMessage => _errorMessage;
  RiskAssessment? get assessmentResult => _assessmentResult;

  /// Guardrail: Form validation blocks progression if no body location selected.
  bool get isQuestionnaireValid => _selectedBodyLocation != null && _selectedBodyLocation!.isNotEmpty;

  // Setters & Actions
  void setBodyLocation(String location) {
    _selectedBodyLocation = location;
    notifyListeners();
  }

  void setPainSeverity(int severity) {
    _painSeverity = severity.clamp(1, 10);
    notifyListeners();
  }

  void setSymptomDuration(int days) {
    _symptomDurationDays = days.clamp(1, 60);
    notifyListeners();
  }

  void setTemperature(double temp) {
    _temperatureCelsius = double.parse(temp.toStringAsFixed(1));
    notifyListeners();
  }

  void toggleSecondarySymptom(String symptom) {
    if (_selectedSecondarySymptoms.contains(symptom)) {
      _selectedSecondarySymptoms.remove(symptom);
    } else {
      _selectedSecondarySymptoms.add(symptom);
    }
    notifyListeners();
  }

  void setAge(int? age) {
    _age = age;
    notifyListeners();
  }

  void setGender(String? gender) {
    _gender = gender;
    notifyListeners();
  }

  void togglePreExistingCondition(String condition) {
    if (_preExistingConditions.contains(condition)) {
      _preExistingConditions.remove(condition);
    } else {
      _preExistingConditions.add(condition);
    }
    notifyListeners();
  }

  void setNotes(String? notes) {
    _notes = notes;
    notifyListeners();
  }

  /// Real-time cross-platform image resolution verification using raw byte decoding via dart:ui.
  Future<bool> setImage(Uint8List bytes, {String? filePath, String mimeType = 'image/jpeg'}) async {
    _isValidatingImage = true;
    _imageResolutionWarning = null;
    notifyListeners();

    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      final width = frameInfo.image.width;
      final height = frameInfo.image.height;

      final metadata = ClinicalImageMetadata(
        path: filePath,
        bytes: bytes,
        width: width,
        height: height,
        mimeType: mimeType,
        capturedAt: DateTime.now(),
      );

      _imageMetadata = metadata;

      if (!metadata.isResolutionValid) {
        _imageResolutionWarning =
            'Image resolution too low (${metadata.resolutionString}). Must be at least 512x512 for diagnostic computer vision accuracy.';
      } else {
        _imageResolutionWarning = null;
      }

      _isValidatingImage = false;
      notifyListeners();
      return metadata.isResolutionValid;
    } catch (e) {
      _isValidatingImage = false;
      _imageResolutionWarning = 'Failed to decode image dimensions: $e';
      notifyListeners();
      return false;
    }
  }

  void clearImage() {
    _imageMetadata = null;
    _imageResolutionWarning = null;
    notifyListeners();
  }

  void setAudio(Uint8List bytes, {String? fileName}) {
    _audioBytes = bytes;
    _audioFileName = fileName ?? 'cough_sample_${DateTime.now().millisecondsSinceEpoch}.wav';
    notifyListeners();
  }

  void clearAudio() {
    _audioBytes = null;
    _audioFileName = null;
    notifyListeners();
  }

  /// Constructs the unified DiagnosticPayload object from state.
  DiagnosticPayload buildPayload() {
    if (!isQuestionnaireValid) {
      throw StateError('Cannot build payload: body location must be selected.');
    }

    return DiagnosticPayload(
      bodyLocation: _selectedBodyLocation!,
      painSeverity: _painSeverity,
      symptomDurationDays: _symptomDurationDays,
      temperatureCelsius: _temperatureCelsius,
      secondarySymptoms: _selectedSecondarySymptoms.toList(),
      demographics: PatientDemographics(
        age: _age,
        gender: _gender,
        preExistingConditions: _preExistingConditions.toList(),
      ),
      imageMetadata: _imageMetadata,
      audioBytes: _audioBytes,
      audioFileName: _audioFileName,
      notes: _notes,
    );
  }

  /// Dispatches the unified payload to the Multimodal Diagnostic service.
  Future<RiskAssessment?> executeScreening() async {
    final payload = buildPayload();
    _isAnalyzing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      String? uploadedImageUrl;
      if (_imageMetadata?.bytes != null) {
        final filename = 'diag_${DateTime.now().millisecondsSinceEpoch}.jpg';
        uploadedImageUrl = await _diagnosticsService.uploadSymptomPhoto(_imageMetadata!.bytes!, filename);
      }

      final assessment = await _diagnosticsService.analyzeSymptoms(
        symptomVector: payload.toSymptomVector(),
        imageUrl: uploadedImageUrl,
        imageFile: _imageMetadata?.bytes,
        audioBytes: _audioBytes,
      );

      _assessmentResult = assessment;
      _isAnalyzing = false;
      notifyListeners();
      return assessment;
    } catch (e) {
      _errorMessage = e.toString();
      _isAnalyzing = false;
      notifyListeners();
      return null;
    }
  }

  void reset() {
    _selectedBodyLocation = null;
    _painSeverity = 4;
    _symptomDurationDays = 3;
    _temperatureCelsius = 37.0;
    _selectedSecondarySymptoms.clear();
    _age = null;
    _gender = null;
    _preExistingConditions.clear();
    _notes = null;
    _imageMetadata = null;
    _imageResolutionWarning = null;
    _audioBytes = null;
    _audioFileName = null;
    _isAnalyzing = false;
    _errorMessage = null;
    _assessmentResult = null;
    notifyListeners();
  }
}
