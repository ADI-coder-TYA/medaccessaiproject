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
    );
  }

  factory RiskAssessment.fromJson(String source) => RiskAssessment.fromMap(jsonDecode(source) as Map<String, dynamic>);
}

