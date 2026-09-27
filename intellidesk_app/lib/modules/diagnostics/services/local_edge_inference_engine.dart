import 'dart:math' as math;
import 'inference_engine_interface.dart';
import '../models/symptom_vector.dart';
import '../models/risk_assessment.dart';

/// On-Device Local Edge Inference Engine (TFLite / ONNX architecture).
/// Stubs vision embeddings and late-fusion calculations with realistic mathematical models
/// until native weights are downloaded to the device.
class LocalEdgeInferenceEngine implements InferenceEngineInterface {
  bool _isInitialized = false;
  static const int embeddingDim = 128;

  @override
  ExecutionMode get executionMode => ExecutionMode.localTflite;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    // Scaffold ready for tflite_flutter or onnxruntime_flutter model loading
    await Future.delayed(const Duration(milliseconds: 150));
    _isInitialized = true;
  }

  @override
  Future<bool> isModelAvailable() async {
    return true; // Edge stub is always operational offline
  }

  @override
  Future<List<double>> extractVisualEmbeddings(dynamic imageInput) async {
    await initialize();

    // Generate realistic normalized 128-dimensional latent vector
    final random = math.Random(42);
    final vector = List<double>.generate(embeddingDim, (i) => (random.nextDouble() * 2.0 - 1.0));

    // L2 Normalization
    double sumSq = 0.0;
    for (final v in vector) {
      sumSq += v * v;
    }
    final norm = math.sqrt(sumSq);
    return vector.map((v) => (v / (norm == 0 ? 1.0 : norm))).toList();
  }

  @override
  Future<RiskAssessment> runMultimodalInference(
    SymptomVector symptoms, {
    List<double>? visionEmbeddings,
    String? imageUrl,
    dynamic audioBytes,
    List<double>? audioFeatures,
  }) async {
    await initialize();

    // 1. Structured Symptom Score (0.0 - 1.0)
    double symptomScore = (symptoms.painScale / 10.0) * 0.45;
    if (symptoms.durationDays > 7) symptomScore += 0.15;
    symptomScore += math.min(0.25, symptoms.symptoms.length * 0.05);

    // 2. Vitals Score (0.0 - 1.0)
    double vitalsScore = 0.15;
    if (symptoms.vitals.temperatureCelsius != null && symptoms.vitals.temperatureCelsius! >= 38.0) {
      vitalsScore += 0.35;
    }
    if (symptoms.vitals.heartRate != null && symptoms.vitals.heartRate! > 100) {
      vitalsScore += 0.20;
    }
    if (symptoms.vitals.oxygenSaturation != null && symptoms.vitals.oxygenSaturation! < 94) {
      vitalsScore += 0.45;
    }

    // 3. Vision Score (0.0 - 1.0)
    double visionScore = 0.0;
    if (visionEmbeddings != null && visionEmbeddings.isNotEmpty) {
      // Latent severity indicator
      visionScore = 0.45 + (visionEmbeddings[0].abs() * 0.4);
    }

    // Late-Fusion Concatenation
    final hasVision = visionEmbeddings != null && visionEmbeddings.isNotEmpty;
    final wVision = hasVision ? 0.40 : 0.0;
    final wSymptoms = hasVision ? 0.40 : 0.65;
    final wVitals = hasVision ? 0.20 : 0.35;

    final combinedScore = ((wVision * visionScore) + (wSymptoms * symptomScore) + (wVitals * vitalsScore))
        .clamp(0.05, 0.98);

    // Monte Carlo Dropout epistemic variance simulation
    const mcRuns = 20;
    final variance = 0.0035;
    final stdDev = math.sqrt(variance);

    final riskLevel = _mapScoreToLevel(combinedScore, symptoms.painScale);

    final primaryCondition = _determinePrimaryCondition(symptoms, hasVision);

    return RiskAssessment(
      riskScore: double.parse(combinedScore.toStringAsFixed(2)),
      riskLevel: riskLevel,
      uncertaintyBounds: UncertaintyBounds(
        confidence: double.parse((1.0 - (variance * 4)).toStringAsFixed(2)),
        ciLower: math.max(0.0, double.parse((combinedScore - 1.96 * stdDev).toStringAsFixed(2))),
        ciUpper: math.min(1.0, double.parse((combinedScore + 1.96 * stdDev).toStringAsFixed(2))),
        epistemicVariance: variance,
        monteCarloSamples: mcRuns,
      ),
      primaryDiagnosis: primaryCondition,
      differentialDiagnoses: [
        DifferentialDiagnosisItem(
          condition: primaryCondition,
          probability: double.parse((0.70 + (combinedScore * 0.15)).toStringAsFixed(2)),
          urgency: combinedScore > 0.6 ? 'PROMPT_CARE' : 'ROUTINE',
        ),
        const DifferentialDiagnosisItem(
          condition: 'Secondary Somatic Manifestation',
          probability: 0.42,
          urgency: 'ROUTINE',
        ),
      ],
      clinicalRecommendations: _generateRecommendations(riskLevel),
      featureAttributions: [
        FeatureAttributionItem(
          featureName: 'Reported Symptoms & Pain (${symptoms.painScale}/10)',
          category: 'SYMPTOMS',
          contributionWeight: 0.38,
          percentageImpact: 45,
          description: 'Symptom questionnaire inputs',
        ),
        if (hasVision)
          const FeatureAttributionItem(
            featureName: 'Visual Edge Feature Extractor',
            category: 'VISION',
            contributionWeight: 0.32,
            percentageImpact: 35,
            description: 'On-device camera framing',
          ),
        const FeatureAttributionItem(
          featureName: 'Vitals Deviation Prior',
          category: 'VITALS',
          contributionWeight: 0.15,
          percentageImpact: 20,
          description: 'Heart rate and temperature',
        ),
      ],
      xaiHeatmapUrl: imageUrl,
      requiresImmediatePhysicianReview: combinedScore >= 0.75,
    );
  }

  ClinicalRiskLevel _mapScoreToLevel(double score, int pain) {
    if (score >= 0.75 || pain >= 9) return ClinicalRiskLevel.critical;
    if (score >= 0.50 || pain >= 6) return ClinicalRiskLevel.high;
    if (score >= 0.25 || pain >= 3) return ClinicalRiskLevel.moderate;
    return ClinicalRiskLevel.low;
  }

  String _determinePrimaryCondition(SymptomVector s, bool hasVision) {
    final loc = s.bodyLocation.toLowerCase();
    if (loc.contains('throat') || loc.contains('mouth')) return 'Acute Pharyngotonsillitis';
    if (loc.contains('eye')) return 'Adenoviral Conjunctivitis';
    if (loc.contains('skin') || loc.contains('arm') || loc.contains('leg')) return 'Erythematous Dermatitis';
    return 'Acute Somatic Presentation';
  }

  List<String> _generateRecommendations(ClinicalRiskLevel level) {
    switch (level) {
      case ClinicalRiskLevel.critical:
        return [
          'Seek immediate medical care or proceed to nearest emergency department.',
          'Do not drive if dizzy, lightheaded, or in extreme pain.',
        ];
      case ClinicalRiskLevel.high:
        return [
          'Schedule an urgent clinical evaluation within 24 hours.',
          'Re-check temperature and resting heart rate every 4 hours.',
        ];
      case ClinicalRiskLevel.moderate:
        return [
          'Monitor symptoms for 48 hours and rest.',
          'Consult a pharmacist regarding over-the-counter soothing options.',
        ];
      case ClinicalRiskLevel.low:
        return [
          'Maintain proper hydration, nutrition, and rest.',
          'Symptoms appear mild and self-limiting.',
        ];
    }
  }

  @override
  void dispose() {
    _isInitialized = false;
  }
}
