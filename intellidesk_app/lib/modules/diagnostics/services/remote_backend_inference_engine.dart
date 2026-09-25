import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../config/api_config.dart';
import 'inference_engine_interface.dart';
import '../models/symptom_vector.dart';
import '../models/risk_assessment.dart';

/// Remote Cloud Backend Inference Engine calling MedAccess AI `/api/v1/diagnostics/analyze`.
class RemoteBackendInferenceEngine implements InferenceEngineInterface {
  final http.Client _client;

  RemoteBackendInferenceEngine({http.Client? client}) : _client = client ?? http.Client();

  @override
  ExecutionMode get executionMode => ExecutionMode.backendApi;

  @override
  Future<void> initialize() async {
    // Cloud connection ready
  }

  @override
  Future<bool> isModelAvailable() async {
    try {
      final res = await _client.get(Uri.parse('${ApiConfig.baseUrl}/health')).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<double>> extractVisualEmbeddings(dynamic imageInput) async {
    // In cloud mode, feature extraction is performed server-side by EfficientNet/MobileNet
    return [];
  }

  @override
  Future<RiskAssessment> runMultimodalInference(
    SymptomVector symptoms, {
    List<double>? visionEmbeddings,
    String? imageUrl,
    dynamic audioBytes,
    List<double>? audioFeatures,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/diagnostics/analyze');
    final Map<String, dynamic> payload = {
      'imageUrl': imageUrl,
      'symptoms': symptoms.toMap(),
    };

    if (audioBytes != null) {
      if (audioBytes is List<int>) {
        payload['audioBase64'] = base64Encode(audioBytes);
      }
    }
    if (audioFeatures != null && audioFeatures.isNotEmpty) {
      payload['audioFeatures'] = audioFeatures;
    }

    final body = jsonEncode(payload);

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception('Diagnostic analysis failed (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final riskData = data['riskAssessment'] as Map<String, dynamic>? ?? {};

    // Merge explainability if present
    final explain = data['explainability'] as Map<String, dynamic>?;
    final gradCam = explain?['gradCam'] as Map<String, dynamic>?;
    final shap = explain?['shap'] as Map<String, dynamic>?;

    final diffs = (riskData['differentialDiagnoses'] as List<dynamic>?)
            ?.map((e) => DifferentialDiagnosisItem.fromMap(e as Map<String, dynamic>))
            .toList() ??
        [];

    final recs = (riskData['clinicalRecommendations'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final attributions = (shap?['attributions'] as List<dynamic>?)
            ?.map((e) => FeatureAttributionItem.fromMap(e as Map<String, dynamic>))
            .toList() ??
        [];

    final bounds = riskData['uncertaintyBounds'] != null
        ? UncertaintyBounds.fromMap(riskData['uncertaintyBounds'] as Map<String, dynamic>)
        : const UncertaintyBounds(confidence: 0.85, ciLower: 0.1, ciUpper: 0.4, epistemicVariance: 0.005);

    return RiskAssessment(
      riskScore: (riskData['riskScore'] as num?)?.toDouble() ?? 0.35,
      riskLevel: ClinicalRiskLevel.fromString(riskData['riskLevel'] as String?),
      uncertaintyBounds: bounds,
      primaryDiagnosis: riskData['primaryDiagnosis'] as String? ?? 'Acute Clinical Presentation',
      differentialDiagnoses: diffs,
      clinicalRecommendations: recs,
      featureAttributions: attributions,
      xaiHeatmapUrl: gradCam?['overlaySvgDataUri'] as String? ?? imageUrl,
      requiresImmediatePhysicianReview: riskData['requiresImmediatePhysicianReview'] as bool? ?? false,
    );
  }

  @override
  void dispose() {
    _client.close();
  }
}
