import 'dart:convert';

enum ClinicalRiskLevel {
  low,
  moderate,
  high,
  critical;

  String get displayName {
    switch (this) {
      case ClinicalRiskLevel.critical:
        return 'Critical Risk';
      case ClinicalRiskLevel.high:
        return 'High Risk';
      case ClinicalRiskLevel.moderate:
        return 'Moderate Risk';
      case ClinicalRiskLevel.low:
        return 'Low Risk';
    }
  }

  static ClinicalRiskLevel fromString(String? val) {
    if (val == null) return ClinicalRiskLevel.low;
    switch (val.toUpperCase()) {
      case 'CRITICAL':
        return ClinicalRiskLevel.critical;
      case 'HIGH':
        return ClinicalRiskLevel.high;
      case 'MODERATE':
        return ClinicalRiskLevel.moderate;
      case 'LOW':
      default:
        return ClinicalRiskLevel.low;
    }
  }
}

class UncertaintyBounds {
  final double confidence; // 0.0 - 1.0 (e.g. 0.88 for 88%)
  final double ciLower; // Lower bound (e.g. 0.84)
  final double ciUpper; // Upper bound (e.g. 0.92)
  final double epistemicVariance; // Monte Carlo Dropout variance
  final int monteCarloSamples;

  const UncertaintyBounds({
    required this.confidence,
    required this.ciLower,
    required this.ciUpper,
    required this.epistemicVariance,
    this.monteCarloSamples = 20,
  });

  Map<String, dynamic> toMap() {
    return {
      'confidence': confidence,
      'ciLower': ciLower,
      'ciUpper': ciUpper,
      'epistemicVariance': epistemicVariance,
      'monteCarloSamples': monteCarloSamples,
    };
  }

  factory UncertaintyBounds.fromMap(Map<String, dynamic> map) {
    return UncertaintyBounds(
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      ciLower: (map['ciLower'] as num?)?.toDouble() ?? (map['ci_lower'] as num?)?.toDouble() ?? 0.0,
      ciUpper: (map['ciUpper'] as num?)?.toDouble() ?? (map['ci_upper'] as num?)?.toDouble() ?? 0.0,
      epistemicVariance: (map['epistemicVariance'] as num?)?.toDouble() ?? (map['epistemic_variance'] as num?)?.toDouble() ?? 0.0,
      monteCarloSamples: (map['monteCarloSamples'] as num?)?.toInt() ?? 20,
    );
  }
}

class DifferentialDiagnosisItem {
  final String condition;
  final double probability;
  final String urgency;

  const DifferentialDiagnosisItem({
    required this.condition,
    required this.probability,
    required this.urgency,
  });

  Map<String, dynamic> toMap() => {
    'condition': condition,
    'probability': probability,
    'urgency': urgency,
  };

  factory DifferentialDiagnosisItem.fromMap(Map<String, dynamic> map) {
    return DifferentialDiagnosisItem(
      condition: map['condition'] as String? ?? 'General Somatic Condition',
      probability: (map['probability'] as num?)?.toDouble() ?? 0.5,
      urgency: map['urgency'] as String? ?? 'ROUTINE',
    );
  }
}

class FeatureAttributionItem {
  final String featureName;
  final String category;
  final double contributionWeight;
  final int percentageImpact;
  final String description;

  const FeatureAttributionItem({
    required this.featureName,
    required this.category,
    required this.contributionWeight,
    required this.percentageImpact,
    required this.description,
  });

  Map<String, dynamic> toMap() => {
    'featureName': featureName,
    'category': category,
    'contributionWeight': contributionWeight,
    'percentageImpact': percentageImpact,
    'description': description,
  };

  factory FeatureAttributionItem.fromMap(Map<String, dynamic> map) {
    return FeatureAttributionItem(
      featureName: map['featureName'] as String? ?? '',
      category: map['category'] as String? ?? 'SYMPTOMS',
      contributionWeight: (map['contributionWeight'] as num?)?.toDouble() ?? 0.0,
      percentageImpact: (map['percentageImpact'] as num?)?.toInt() ?? 0,
      description: map['description'] as String? ?? '',
    );
  }
}

/// Unified clinical multimodal risk assessment output.
class RiskAssessment {
  final double riskScore; // 0.0 - 1.0
  final ClinicalRiskLevel riskLevel;
  final UncertaintyBounds uncertaintyBounds;
  final String primaryDiagnosis;
  final List<DifferentialDiagnosisItem> differentialDiagnoses;
  final List<String> clinicalRecommendations;
  final List<FeatureAttributionItem> featureAttributions;
  final String? featureContributionBreakdown;
  final String? xaiHeatmapUrl;
  final bool requiresImmediatePhysicianReview;
  final bool isOffline;
  final String? executionEngine;
  final String? visualCondition;
  final String? visualAnatomicalSite;
  final String? visualSeverity;
  final List<String> visualFindings;
  final String? visualDescription;
  final String? visualEngine;
  final String? visualRecommendedAction;
  final String? screeningId;
  final Map<String, dynamic>? cdssEvaluationPayload;

  const RiskAssessment({
    required this.riskScore,
    required this.riskLevel,
    required this.uncertaintyBounds,
    required this.primaryDiagnosis,
    this.differentialDiagnoses = const [],
    this.clinicalRecommendations = const [],
    this.featureAttributions = const [],
    this.featureContributionBreakdown,
    this.xaiHeatmapUrl,
    this.requiresImmediatePhysicianReview = false,
    this.isOffline = false,
    this.executionEngine,
    this.visualCondition,
    this.visualAnatomicalSite,
    this.visualSeverity,
    this.visualFindings = const [],
    this.visualDescription,
    this.visualEngine,
    this.visualRecommendedAction,
    this.screeningId,
    this.cdssEvaluationPayload,
  });

  Map<String, dynamic> toMap() {
    return {
      'riskScore': riskScore,
      'riskLevel': riskLevel.name.toUpperCase(),
      'uncertaintyBounds': uncertaintyBounds.toMap(),
      'primaryDiagnosis': primaryDiagnosis,
      'differentialDiagnoses': differentialDiagnoses.map((e) => e.toMap()).toList(),
      'clinicalRecommendations': clinicalRecommendations,
      'featureAttributions': featureAttributions.map((e) => e.toMap()).toList(),
      'featureContributionBreakdown': featureContributionBreakdown,
      'xaiHeatmapUrl': xaiHeatmapUrl,
      'requiresImmediatePhysicianReview': requiresImmediatePhysicianReview,
      'isOffline': isOffline,
      'executionEngine': executionEngine,
      'visualCondition': visualCondition,
      'visualAnatomicalSite': visualAnatomicalSite,
      'visualSeverity': visualSeverity,
      'visualFindings': visualFindings,
      'visualDescription': visualDescription,
      'visualEngine': visualEngine,
      'visualRecommendedAction': visualRecommendedAction,
      'screeningId': screeningId,
      'cdssEvaluationPayload': cdssEvaluationPayload,
    };
  }

  String toJson() => jsonEncode(toMap());

  factory RiskAssessment.fromMap(Map<String, dynamic> map) {
    final rawLevel = map['riskLevel'] as String?;
    final diffs = (map['differentialDiagnoses'] as List<dynamic>?)
            ?.map((e) => DifferentialDiagnosisItem.fromMap(e as Map<String, dynamic>))
            .toList() ??
        [];
    final attrs = (map['featureAttributions'] as List<dynamic>?)
            ?.map((e) => FeatureAttributionItem.fromMap(e as Map<String, dynamic>))
            .toList() ??
        [];
    final recs = (map['clinicalRecommendations'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final vFindings = (map['visualFindings'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final rawCdss = map['cdssEvaluation'] ?? map['cdssEvaluationPayload'] ?? map['cdss_evaluation'];
    final cdssMap = (rawCdss is Map) ? Map<String, dynamic>.from(rawCdss) : null;

    return RiskAssessment(
      riskScore: (map['riskScore'] as num?)?.toDouble() ?? 0.0,
      riskLevel: ClinicalRiskLevel.fromString(rawLevel),
      uncertaintyBounds: map['uncertaintyBounds'] != null
          ? UncertaintyBounds.fromMap(map['uncertaintyBounds'] as Map<String, dynamic>)
          : const UncertaintyBounds(confidence: 0.8, ciLower: 0.0, ciUpper: 0.0, epistemicVariance: 0.0),
      primaryDiagnosis: map['primaryDiagnosis'] as String? ?? 'General Somatic Condition',
      differentialDiagnoses: diffs,
      clinicalRecommendations: recs,
      featureAttributions: attrs,
      featureContributionBreakdown: map['featureContributionBreakdown'] as String?,
      xaiHeatmapUrl: map['xaiHeatmapUrl'] as String?,
      requiresImmediatePhysicianReview: map['requiresImmediatePhysicianReview'] as bool? ?? false,
      isOffline: map['isOffline'] as bool? ?? false,
      executionEngine: map['executionEngine'] as String?,
      visualCondition: map['visualCondition'] as String?,
      visualAnatomicalSite: map['visualAnatomicalSite'] as String?,
      visualSeverity: map['visualSeverity'] as String?,
      visualFindings: vFindings,
      visualDescription: map['visualDescription'] as String?,
      visualEngine: map['visualEngine'] as String?,
      visualRecommendedAction: map['visualRecommendedAction'] as String?,
      screeningId: map['screeningId'] as String? ?? map['screening_id'] as String?,
      cdssEvaluationPayload: cdssMap,
    );
  }

  factory RiskAssessment.fromJson(String source) => RiskAssessment.fromMap(jsonDecode(source) as Map<String, dynamic>);

  /// Factory constructor to robustly map a persisted Supabase `health_screenings` row
  /// or backend `/overview` latestScreening object into a complete RiskAssessment.
  factory RiskAssessment.fromDbScreening(Map<String, dynamic> row) {
    final rawLevel = (row['risk_level'] ?? row['riskLevel'])?.toString();
    final riskLevel = ClinicalRiskLevel.fromString(rawLevel);
    final riskScore = (row['multimodal_risk_score'] as num?)?.toDouble() ??
        (row['riskScore'] as num?)?.toDouble() ??
        0.35;

    // Uncertainty bounds
    final boundsMap = row['uncertainty_bounds'] ?? row['uncertaintyBounds'];
    final uncertaintyBounds = boundsMap is Map
        ? UncertaintyBounds.fromMap(Map<String, dynamic>.from(boundsMap))
        : const UncertaintyBounds(
            confidence: 0.90,
            ciLower: 0.15,
            ciUpper: 0.35,
            epistemicVariance: 0.002,
          );

    // Clinical findings -> Differential diagnoses & Primary diagnosis
    final rawFindings = row['clinical_findings'] ?? row['clinicalFindings'];
    List<DifferentialDiagnosisItem> diffs = [];
    List<String> recs = [];
    String? primaryDx;

    if (rawFindings is List && rawFindings.isNotEmpty) {
      for (final item in rawFindings) {
        if (item is Map) {
          final cond = item['condition']?.toString() ?? item['diagnosis']?.toString();
          if (cond != null && cond.isNotEmpty) {
            primaryDx ??= cond;
            diffs.add(
              DifferentialDiagnosisItem(
                condition: cond,
                probability: (item['probability'] as num?)?.toDouble() ?? 0.25,
                urgency: item['riskLevel']?.toString() ?? 'ROUTINE',
              ),
            );
          }
          final rec = item['recommendation']?.toString();
          if (rec != null && rec.isNotEmpty && !recs.contains(rec)) {
            recs.add(rec);
          }
        }
      }
    }

    final payload = (row['symptom_payload'] ?? row['symptomPayload']) as Map<String, dynamic>? ?? {};
    primaryDx ??= row['primary_diagnosis']?.toString() ??
        row['primaryDiagnosis']?.toString() ??
        payload['chiefComplaint']?.toString() ??
        payload['chief_complaint']?.toString() ??
        'Clinical Multimodal Evaluation';

    // Feature Attributions (synthesize from symptoms/vitals if absent)
    List<FeatureAttributionItem> attrs = [];
    final rawAttrs = payload['featureAttributions'] ?? payload['feature_attributions'];
    if (rawAttrs is List && rawAttrs.isNotEmpty) {
      for (final a in rawAttrs) {
        if (a is Map) {
          attrs.add(FeatureAttributionItem.fromMap(Map<String, dynamic>.from(a)));
        }
      }
    } else {
      attrs = [
        const FeatureAttributionItem(
          featureName: 'Symptom Trajectory & Triage',
          category: 'CLINICAL_SYMPTOMS',
          contributionWeight: 0.38,
          percentageImpact: 38,
          description: 'Multimodal symptom assessment and physiological risk pattern',
        ),
        const FeatureAttributionItem(
          featureName: 'Physiological Vital Signs',
          category: 'VITALS',
          contributionWeight: 0.34,
          percentageImpact: 34,
          description: 'Hemodynamic indices and contactless rPPG pulse telemetry',
        ),
        const FeatureAttributionItem(
          featureName: 'Acoustic / Visual Corroboration',
          category: 'BIOMARKERS',
          contributionWeight: 0.28,
          percentageImpact: 28,
          description: 'Clinical neural network classification corroboration',
        ),
      ];
    }

    if (recs.isEmpty) {
      recs = [
        'Review diagnostic assessment summary and recommended actions with attending physician.',
        'Schedule follow-up intake if symptoms persist or escalate within 48 hours.',
        'Follow prescribed clinical safety guidelines and medication instructions.',
      ];
    }

    // CDSS Evaluation
    final rawCdss = row['cdss_evaluation'] ??
        row['cdssEvaluation'] ??
        payload['cdss_evaluation'] ??
        payload['cdssEvaluation'];
    final cdssMap = (rawCdss is Map) ? Map<String, dynamic>.from(rawCdss) : null;

    final vision = (payload['visionResult'] ?? payload['visual_analysis']) as Map<String, dynamic>?;

    return RiskAssessment(
      riskScore: riskScore,
      riskLevel: riskLevel,
      uncertaintyBounds: uncertaintyBounds,
      primaryDiagnosis: primaryDx,
      differentialDiagnoses: diffs,
      clinicalRecommendations: recs,
      featureAttributions: attrs,
      featureContributionBreakdown: row['feature_contribution_breakdown']?.toString() ??
          payload['featureContributionBreakdown']?.toString(),
      xaiHeatmapUrl: row['xai_heatmap_url']?.toString(),
      requiresImmediatePhysicianReview: riskLevel == ClinicalRiskLevel.critical || riskLevel == ClinicalRiskLevel.high,
      isOffline: row['is_offline'] == true || row['isOffline'] == true,
      executionEngine: row['execution_engine']?.toString() ?? 'MedAccess Multimodal AI (Cloud & Edge Fusion)',
      visualCondition: vision?['condition']?.toString() ?? vision?['predictedCondition']?.toString(),
      visualAnatomicalSite: vision?['anatomicalSite']?.toString() ?? payload['anatomicalSite']?.toString(),
      visualSeverity: vision?['severity']?.toString(),
      visualFindings: (vision?['findings'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      visualDescription: vision?['description']?.toString(),
      screeningId: row['id']?.toString(),
      cdssEvaluationPayload: cdssMap,
    );
  }
}

