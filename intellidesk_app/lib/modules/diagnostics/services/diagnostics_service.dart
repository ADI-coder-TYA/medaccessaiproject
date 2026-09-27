import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../config/api_config.dart';
import 'inference_engine_interface.dart';
import 'local_inference_service.dart';
import 'remote_backend_inference_engine.dart';
import '../models/symptom_vector.dart';
import '../models/risk_assessment.dart';
import '../models/diagnostic_session.dart';
import '../models/longitudinal_progression.dart';

/// Facade service orchestrating local vs remote inference execution and asset upload.
class DiagnosticsService {
  final LocalInferenceService _localInferenceService;
  final RemoteBackendInferenceEngine _remoteEngine;
  ExecutionMode _currentMode = ExecutionMode.backendApi;

  DiagnosticsService({
    LocalInferenceService? localInferenceService,
    RemoteBackendInferenceEngine? remoteEngine,
    ExecutionMode initialMode = ExecutionMode.backendApi,
  })  : _localInferenceService = localInferenceService ?? LocalInferenceService(),
        _remoteEngine = remoteEngine ?? RemoteBackendInferenceEngine(),
        _currentMode = initialMode;

  ExecutionMode get currentMode => _currentMode;
  LocalInferenceService get localService => _localInferenceService;

  InferenceEngineInterface get activeEngine {
    return _currentMode == ExecutionMode.localTflite ? _localInferenceService : _remoteEngine;
  }

  void setExecutionMode(ExecutionMode mode) {
    _currentMode = mode;
  }

  /// Runs full diagnostic screening on the active engine, automatically routing
  /// to LocalInferenceService if offline (ConnectivityResult.none) or if backend is unreachable.
  Future<RiskAssessment> analyzeSymptoms({
    required SymptomVector symptomVector,
    String? imageUrl,
    dynamic imageFile,
    dynamic audioBytes,
    List<double>? audioFeatures,
  }) async {
    // 1. Check network connectivity for automatic on-device routing
    final isDeviceOffline = await LocalInferenceService.isOffline();

    if (_currentMode == ExecutionMode.localTflite || isDeviceOffline) {
      List<double>? visionEmbeddings;
      if (imageFile != null) {
        visionEmbeddings = await _localInferenceService.extractVisualEmbeddings(imageFile);
      }
      return await _localInferenceService.runMultimodalInference(
        symptomVector,
        visionEmbeddings: visionEmbeddings,
        imageUrl: imageUrl,
        audioBytes: audioBytes,
        audioFeatures: audioFeatures,
      );
    }

    // 2. Online Backend Execution with Automatic Edge Fallback
    try {
      return await _remoteEngine.runMultimodalInference(
        symptomVector,
        imageUrl: imageUrl,
        audioBytes: audioBytes,
        audioFeatures: audioFeatures,
      );
    } catch (e) {
      // Automatic edge fallback if cloud inference errors or connection fails
      List<double>? visionEmbeddings;
      if (imageFile != null) {
        visionEmbeddings = await _localInferenceService.extractVisualEmbeddings(imageFile);
      }
      return await _localInferenceService.runMultimodalInference(
        symptomVector,
        visionEmbeddings: visionEmbeddings,
        imageUrl: imageUrl,
        audioBytes: audioBytes,
        audioFeatures: audioFeatures,
      );
    }
  }

  /// Classifies audio via backend /api/v1/diagnostics/audio/classify endpoint
  Future<Map<String, dynamic>?> classifyAudio(List<int> audioWavBytes) async {
    try {
      final uri = ApiConfig.resolveUri('diagnostics/audio/classify');
      debugPrint('🎙️ [DiagnosticsService] Sending audio for classification to $uri (${audioWavBytes.length} bytes)...');
      final stopwatch = Stopwatch()..start();
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'audioBase64': base64Encode(audioWavBytes),
        }),
      ).timeout(const Duration(seconds: 45)); // Up to 45s for Cloud Bioacoustic Transformer
      stopwatch.stop();

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final clf = data['classification'] as Map<String, dynamic>?;
        debugPrint('✅ [DiagnosticsService] Audio classification completed in ${stopwatch.elapsedMilliseconds}ms: "${clf?['predictedCategory']}" (${(((clf?['confidence'] ?? 0) as num) * 100).toStringAsFixed(1)}%)');
        return data;
      } else {
        debugPrint('⚠️ [DiagnosticsService] Audio classification returned HTTP ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('❌ [DiagnosticsService] Audio classification error/timeout: $e');
    }
    return null;
  }


  /// Uploads symptom photo to the `clinical-diagnostics` Supabase storage bucket.
  Future<String?> uploadSymptomPhoto(List<int> bytes, String filename) async {
    try {
      final uploadUri = Uri.parse('${ApiConfig.supabaseUrl}/storage/v1/object/clinical-diagnostics/$filename');
      final response = await http.post(
        uploadUri,
        headers: {
          'Authorization': 'Bearer ${ApiConfig.supabaseAnonKey}',
          'Content-Type': 'image/jpeg',
          'x-upsert': 'true',
        },
        body: bytes,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return '${ApiConfig.supabaseUrl}/storage/v1/object/public/clinical-diagnostics/$filename';
      }
    } catch (_) {
      // Fallback
    }
    return null;
  }

  /// Fetches historical screenings for a given patient.
  Future<List<DiagnosticSession>> fetchPatientScreenings(String patientId) async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/diagnostics/screenings/patient/$patientId'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['screenings'] as List<dynamic>?) ?? [];
        return list.map((e) => DiagnosticSession.fromMap(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Generates initial Qwen2.5 / PFA interpretation of diagnostic screening result.
  Future<String> interpretScreeningResult({
    required RiskAssessment assessment,
    String? query,
  }) async {
    final isDeviceOffline = assessment.isOffline || await LocalInferenceService.isOffline();
    if (!isDeviceOffline) {
      try {
        final uri = Uri.parse('${ApiConfig.baseUrl}/diagnostics/interpret');
        final bounds = assessment.uncertaintyBounds;
        final marginPercent = (((bounds.ciUpper - bounds.ciLower) / 2) * 100).round();
        final body = jsonEncode({
          'diagnosticContext': {
            'riskTier': assessment.riskLevel.displayName,
            'riskScore': assessment.riskScore,
            'uncertainty': '±$marginPercent%',
            'topFeatures': assessment.featureAttributions.map((a) => a.featureName).toList(),
            'heatMapGenerated': assessment.xaiHeatmapUrl != null,
            'primaryDiagnosis': assessment.primaryDiagnosis,
            'clinicalRecommendations': assessment.clinicalRecommendations,
          },
          'query': query,
        });
        final res = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['interpretation'] != null) {
            return data['interpretation'] as String;
          }
        }
      } catch (_) {
        // Fallback to local PFA interpretation
      }
    }

    return _generateLocalInterpretation(assessment, query);
  }

  /// Sends multi-turn chat message to Qwen2.5 health assistant grounded in screening context.
  Future<String> sendDiagnosticChatMessage({
    required RiskAssessment assessment,
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    final isDeviceOffline = assessment.isOffline || await LocalInferenceService.isOffline();
    if (!isDeviceOffline) {
      try {
        final uri = Uri.parse('${ApiConfig.baseUrl}/diagnostics/chat');
        final bounds = assessment.uncertaintyBounds;
        final marginPercent = (((bounds.ciUpper - bounds.ciLower) / 2) * 100).round();
        final body = jsonEncode({
          'message': message,
          'diagnosticContext': {
            'riskTier': assessment.riskLevel.displayName,
            'riskScore': assessment.riskScore,
            'uncertainty': '±$marginPercent%',
            'topFeatures': assessment.featureAttributions.map((a) => a.featureName).toList(),
            'heatMapGenerated': assessment.xaiHeatmapUrl != null,
            'primaryDiagnosis': assessment.primaryDiagnosis,
            'clinicalRecommendations': assessment.clinicalRecommendations,
          },
          'history': history,
        });

        final res = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data['reply'] != null) {
            return data['reply'] as String;
          }
        }
      } catch (_) {
        // Fallback to local PFA guidance
      }
    }

    return _generateLocalChatMessage(assessment, message);
  }

  /// Generates instant deterministic local Rogerian PFA interpretation without network latency.
  String generateLocalInterpretation(RiskAssessment assessment, [String? query]) {
    return _generateLocalInterpretation(assessment, query);
  }

  /// Generates instant deterministic local Rogerian PFA chat reply without network latency.
  String generateLocalChatMessage(RiskAssessment assessment, String message) {
    return _generateLocalChatMessage(assessment, message);
  }

  String _generateLocalInterpretation(RiskAssessment assessment, String? query) {
    final isCritical = assessment.riskLevel == ClinicalRiskLevel.critical || assessment.riskScore >= 0.75;
    final isModerate = assessment.riskLevel == ClinicalRiskLevel.moderate || assessment.riskScore >= 0.40;
    final scorePct = (assessment.riskScore * 100).round();
    final bounds = assessment.uncertaintyBounds;
    final marginPercent = (((bounds.ciUpper - bounds.ciLower) / 2) * 100).round();

    String finding;
    String nextSteps;

    if (isCritical) {
      finding = 'Your screening identified significant clinical indicators for ${assessment.primaryDiagnosis} (Risk: $scorePct% ±$marginPercent%).';
      nextSteps = 'Because of the critical urgency level, please proceed to the Emergency Room (ER) immediately or contact local emergency services. Do not attempt to drive yourself if experiencing dizziness or severe pain.';
    } else if (isModerate) {
      finding = 'Your screening indicates moderate clinical attention for ${assessment.primaryDiagnosis} (Risk: $scorePct% ±$marginPercent%).${assessment.xaiHeatmapUrl != null ? " Our visual attention heatmap highlighted localized inflammation in the symptom area." : ""}';
      nextSteps = 'We recommend scheduling a clinic consultation within 48 hours for an in-person evaluation. In the meantime, apply a clean cold compress to soothe the area, stay well hydrated, and rest.';
    } else {
      finding = 'Your screening reflects a low risk level ($scorePct% ±$marginPercent%) consistent with a mild, self-limiting condition.';
      nextSteps = 'Continue gentle monitoring over the next few days, keep the area clean and protected, and consult a healthcare provider if symptoms worsen or persist beyond 7 days.';
    }

    return '$finding\n\nRecommended Next Steps: $nextSteps\n\nDisclaimer: This is an AI-assisted screening tool, not a final medical diagnosis.';
  }

  String _generateLocalChatMessage(RiskAssessment assessment, String message) {
    final lower = message.toLowerCase();
    final isCritical = assessment.riskLevel == ClinicalRiskLevel.critical;

    if (isCritical) {
      return 'Please keep in mind that your results indicated critical urgency. We strongly advise having an emergency clinician evaluate your condition immediately.\n\nDisclaimer: This is an AI-assisted screening tool, not a final medical diagnosis.';
    }

    if (lower.contains('pain') || lower.contains('hurt') || lower.contains('compress') || lower.contains('burn')) {
      return 'To manage localized discomfort, applying a cool damp compress for 10-15 minutes can provide soothing relief. Avoid applying direct ice or scratching the area.\n\nRecommended Next Steps: Schedule a clinic consultation within 48 hours if pain persists.\n\nDisclaimer: This is an AI-assisted screening tool, not a final medical diagnosis.';
    }

    if (lower.contains('contagious') || lower.contains('spread') || lower.contains('catch')) {
      return 'Regarding contagion: avoid sharing personal towels, pillowcases, or direct contact with the affected area until an in-person clinician evaluates it.\n\nRecommended Next Steps: Wash hands frequently and schedule a clinic consultation within 48 hours.\n\nDisclaimer: This is an AI-assisted screening tool, not a final medical diagnosis.';
    }

    if (lower.contains('anxious') || lower.contains('worried') || lower.contains('scared') || lower.contains('stress')) {
      return 'It is completely understandable to feel anxious when health concerns arise. Take a slow, grounding breath with me—you have taken the right first step by screening early. Our team and campus welfare advisors are right here with you.\n\nDisclaimer: This is an AI-assisted screening tool, not a final medical diagnosis.';
    }

    return 'Thank you for asking. Based on your screening for ${assessment.primaryDiagnosis}, following the recommended supportive care plan and tracking your symptoms is key. If you notice any progressive swelling or new fever, seek clinical care promptly.\n\nDisclaimer: This is an AI-assisted screening tool, not a final medical diagnosis.';
  }

  /// Fetches chronological longitudinal screening history for a patient
  Future<List<ScreeningHistoryPoint>> fetchLongitudinalHistory(String patientId) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/diagnostics/screenings/patient/$patientId/longitudinal');
      final res = await http.get(uri, headers: ApiConfig.patientHeaders).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true && body['screenings'] is List) {
          return (body['screenings'] as List)
              .map((e) => ScreeningHistoryPoint.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
    } catch (_) {}

    return [];
  }

  /// Calculates delta progression between two screenings
  Future<ScreeningDeltaResult> compareScreenings(String baselineId, String followupId) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/diagnostics/progression/delta');
      final res = await http.post(
        uri,
        headers: ApiConfig.patientHeaders,
        body: jsonEncode({
          'baselineScreeningId': baselineId,
          'followupScreeningId': followupId,
        }),
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true && body['comparison'] != null) {
          return ScreeningDeltaResult.fromJson(body['comparison']);
        }
      }
    } catch (_) {}

    throw Exception('Could not retrieve delta comparison from server');
  }

  List<ScreeningHistoryPoint> _generateMockLongitudinalHistory(String patientId) {
    final now = DateTime.now();
    return [
      ScreeningHistoryPoint(
        id: 'scr-hist-001',
        createdAt: now.subtract(const Duration(days: 4)),
        riskScore: 0.76,
        riskLevel: ClinicalRiskLevel.critical,
        imageUrl: null,
        symptomPayload: {'painScale': 8, 'vitals': {'pain_score': 8, 'temperature': 38.6}},
      ),
      ScreeningHistoryPoint(
        id: 'scr-hist-002',
        createdAt: now.subtract(const Duration(days: 2)),
        riskScore: 0.52,
        riskLevel: ClinicalRiskLevel.moderate,
        imageUrl: null,
        symptomPayload: {'painScale': 5, 'vitals': {'pain_score': 5, 'temperature': 37.4}},
      ),
      ScreeningHistoryPoint(
        id: 'scr-hist-003',
        createdAt: now,
        riskScore: 0.28,
        riskLevel: ClinicalRiskLevel.low,
        imageUrl: null,
        symptomPayload: {'painScale': 2, 'vitals': {'pain_score': 2, 'temperature': 36.8}},
      ),
    ];
  }

  void dispose() {
    _localInferenceService.dispose();
    _remoteEngine.dispose();
  }
}
