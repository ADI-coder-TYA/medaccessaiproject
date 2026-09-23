import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/diagnostic_session.dart';
import '../models/symptom_vector.dart';
import '../models/risk_assessment.dart';
import '../services/diagnostics_service.dart';
import '../services/inference_engine_interface.dart';

class DiagnosticsProvider extends ChangeNotifier {
  final DiagnosticsService _service;

  DiagnosticSession? _currentSession;
  String? _capturedImagePath;
  List<int>? _capturedImageBytes;
  Uint8List? _capturedAudioBytes;
  String? _capturedAudioFileName;
  bool _isAnalyzing = false;
  String? _errorMessage;
  List<DiagnosticSession> _history = [];

  DiagnosticsProvider({DiagnosticsService? service})
      : _service = service ?? DiagnosticsService();

  // Getters
  DiagnosticSession? get currentSession => _currentSession;
  String? get capturedImagePath => _capturedImagePath;
  List<int>? get capturedImageBytes => _capturedImageBytes;
  Uint8List? get capturedAudioBytes => _capturedAudioBytes;
  String? get capturedAudioFileName => _capturedAudioFileName;
  bool get hasAudio => _capturedAudioBytes != null && _capturedAudioBytes!.isNotEmpty;
  bool get isAnalyzing => _isAnalyzing;
  String? get errorMessage => _errorMessage;
  List<DiagnosticSession> get history => _history;
  ExecutionMode get executionMode => _service.currentMode;
  RiskAssessment? get currentAssessment => _currentSession?.riskAssessment;

  void setExecutionMode(ExecutionMode mode) {
    _service.setExecutionMode(mode);
    notifyListeners();
  }

  void startNewSession({String? patientId}) {
    _currentSession = DiagnosticSession(
      id: 'diag-${DateTime.now().millisecondsSinceEpoch}',
      patientId: patientId,
      symptomVector: const SymptomVector(
        bodyLocation: 'General / Unspecified',
        durationDays: 1,
        painScale: 0,
        symptoms: [],
      ),
      status: DiagnosticSessionStatus.intake,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _capturedImagePath = null;
    _capturedImageBytes = null;
    _capturedAudioBytes = null;
    _capturedAudioFileName = null;
    _errorMessage = null;
    notifyListeners();
  }

  void updateSymptomVector(SymptomVector vector) {
    if (_currentSession == null) {
      startNewSession();
    }
    _currentSession = _currentSession!.copyWith(
      symptomVector: vector,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void setCapturedImage(String path, List<int> bytes) {
    _capturedImagePath = path;
    _capturedImageBytes = bytes;
    if (_currentSession != null) {
      _currentSession = _currentSession!.copyWith(
        status: DiagnosticSessionStatus.capturingImage,
        updatedAt: DateTime.now(),
      );
    }
    notifyListeners();
  }

  void setCapturedAudio(Uint8List bytes, {String? fileName}) {
    _capturedAudioBytes = bytes;
    _capturedAudioFileName = fileName ?? 'cough_sample_${DateTime.now().millisecondsSinceEpoch}.wav';
    notifyListeners();
  }

  void clearCapturedAudio() {
    _capturedAudioBytes = null;
    _capturedAudioFileName = null;
    notifyListeners();
  }

  Future<RiskAssessment?> runAssessment() async {
    if (_currentSession == null) return null;

    _isAnalyzing = true;
    _errorMessage = null;
    _currentSession = _currentSession!.copyWith(
      status: DiagnosticSessionStatus.analyzing,
      updatedAt: DateTime.now(),
    );
    notifyListeners();

    try {
      String? uploadedImageUrl;
      if (_capturedImageBytes != null) {
        final filename = 'diag_${DateTime.now().millisecondsSinceEpoch}.jpg';
        uploadedImageUrl = await _service.uploadSymptomPhoto(_capturedImageBytes!, filename);
      }

      final assessment = await _service.analyzeSymptoms(
        symptomVector: _currentSession!.symptomVector,
        imageUrl: uploadedImageUrl,
        imageFile: _capturedImageBytes,
        audioBytes: _capturedAudioBytes,
      );

      _currentSession = _currentSession!.copyWith(
        clinicalImageUrl: uploadedImageUrl ?? _capturedImagePath,
        riskAssessment: assessment,
        xaiHeatmapUrl: assessment.xaiHeatmapUrl,
        status: DiagnosticSessionStatus.completed,
        updatedAt: DateTime.now(),
      );

      _history.insert(0, _currentSession!);
      _isAnalyzing = false;
      notifyListeners();
      return assessment;
    } catch (e) {
      _errorMessage = e.toString();
      _isAnalyzing = false;
      _currentSession = _currentSession!.copyWith(
        status: DiagnosticSessionStatus.failed,
        updatedAt: DateTime.now(),
      );
      notifyListeners();
      return null;
    }
  }

  Future<void> loadPatientHistory(String patientId) async {
    final list = await _service.fetchPatientScreenings(patientId);
    _history = list;
    notifyListeners();
  }

  void resetSession() {
    _currentSession = null;
    _capturedImagePath = null;
    _capturedImageBytes = null;
    _capturedAudioBytes = null;
    _capturedAudioFileName = null;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
