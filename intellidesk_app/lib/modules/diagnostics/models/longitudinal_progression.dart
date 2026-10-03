import 'dart:convert';
import 'risk_assessment.dart';

enum ClinicalProgressionTier {
  improving,
  stable,
  deteriorating;

  static ClinicalProgressionTier fromString(String? val) {
    if (val == null) return ClinicalProgressionTier.stable;
    final lower = val.toLowerCase();
    if (lower.contains('improv') || lower.contains('heal')) {
      return ClinicalProgressionTier.improving;
    }
    if (lower.contains('deteriorat') || lower.contains('escalat')) {
      return ClinicalProgressionTier.deteriorating;
    }
    return ClinicalProgressionTier.stable;
  }

  String get label {
    switch (this) {
      case ClinicalProgressionTier.improving:
        return 'Improving / Healing';
      case ClinicalProgressionTier.stable:
        return 'Stable / Unchanged';
      case ClinicalProgressionTier.deteriorating:
        return 'Deteriorating / Escalating';
    }
  }
}

/// Domain point along a patient's historical screening progression
class ScreeningHistoryPoint {
  final String id;
  final String? previousScreeningId;
  final DateTime createdAt;
  final double riskScore;
  final ClinicalRiskLevel riskLevel;
  final String? imageUrl;
  final String? xaiHeatmapUrl;
  final Map<String, dynamic> symptomPayload;
  final Map<String, dynamic> uncertaintyBounds;

  const ScreeningHistoryPoint({
    required this.id,
    this.previousScreeningId,
    required this.createdAt,
    required this.riskScore,
    required this.riskLevel,
    this.imageUrl,
    this.xaiHeatmapUrl,
    this.symptomPayload = const {},
    this.uncertaintyBounds = const {},
  });

  static Map<String, dynamic> _safeMap(dynamic val) {
    if (val == null) return {};
    if (val is Map<String, dynamic>) return val;
    if (val is Map) return Map<String, dynamic>.from(val);
    if (val is String) {
      try {
        final decoded = jsonDecode(val);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return {};
  }

  factory ScreeningHistoryPoint.fromJson(Map<String, dynamic> json) {
    final rLevelStr = json['risk_level'] as String? ?? 'LOW';
    ClinicalRiskLevel rLevel;
    switch (rLevelStr.toUpperCase()) {
      case 'CRITICAL':
        rLevel = ClinicalRiskLevel.critical;
        break;
      case 'HIGH':
        rLevel = ClinicalRiskLevel.high;
        break;
      case 'MODERATE':
        rLevel = ClinicalRiskLevel.moderate;
        break;
      case 'LOW':
      default:
        rLevel = ClinicalRiskLevel.low;
        break;
    }

    return ScreeningHistoryPoint(
      id: json['id'] as String? ?? 'scr-${DateTime.now().millisecondsSinceEpoch}',
      previousScreeningId: json['previous_screening_id'] as String?,
      createdAt: json['created_at'] != null 
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      riskScore: (json['multimodal_risk_score'] as num?)?.toDouble() ?? 0.0,
      riskLevel: rLevel,
      imageUrl: json['image_url'] as String?,
      xaiHeatmapUrl: json['xai_heatmap_url'] as String?,
      symptomPayload: _safeMap(json['symptom_payload']),
      uncertaintyBounds: _safeMap(json['uncertainty_bounds']),
    );
  }

  int get painScore {
    final vitals = symptomPayload['vitals'] as Map<String, dynamic>?;
    if (vitals != null && vitals['pain_score'] is num) {
      return (vitals['pain_score'] as num).toInt();
    }
    if (symptomPayload['painScale'] is num) {
      return (symptomPayload['painScale'] as num).toInt();
    }
    return 0;
  }

  double? get temperature {
    final vitals = symptomPayload['vitals'] as Map<String, dynamic>?;
    if (vitals != null && vitals['temperature'] is num) {
      return (vitals['temperature'] as num).toDouble();
    }
    return null;
  }
}

/// Pairwise delta comparison between T0 baseline and T1 follow-up
class ScreeningDeltaResult {
  final String baselineScreeningId;
  final String followupScreeningId;
  final DateTime baselineDate;
  final DateTime followupDate;
  final double timeElapsedDays;
  final double timeElapsedHours;

  final double baselineRiskScore;
  final double followupRiskScore;
  final double riskDelta; // followup - baseline
  final double riskDeltaPercentage; // e.g. -24.5 means -24.5%

  final ClinicalProgressionTier statusTier;
  final String statusLabel;

  final double? ssim; // Structural similarity [0.0 - 1.0]
  final String ssimCategory;

  final double? painDelta;
  final double? tempDelta;
  final double? spo2Delta;
  final double? heartRateDelta;

  final String? baselineImageUrl;
  final String? followupImageUrl;

  final String clinicalSummary;
  final List<String> recommendations;

  const ScreeningDeltaResult({
    required this.baselineScreeningId,
    required this.followupScreeningId,
    required this.baselineDate,
    required this.followupDate,
    required this.timeElapsedDays,
    required this.timeElapsedHours,
    required this.baselineRiskScore,
    required this.followupRiskScore,
    required this.riskDelta,
    required this.riskDeltaPercentage,
    required this.statusTier,
    required this.statusLabel,
    this.ssim,
    this.ssimCategory = 'N/A',
    this.painDelta,
    this.tempDelta,
    this.spo2Delta,
    this.heartRateDelta,
    this.baselineImageUrl,
    this.followupImageUrl,
    required this.clinicalSummary,
    this.recommendations = const [],
  });

  factory ScreeningDeltaResult.fromJson(Map<String, dynamic> json) {
    final vitals = json['vitalsDelta'] as Map<String, dynamic>? ?? {};
    final statusStr = json['status'] as String? ?? 'Stable / Unchanged';

    return ScreeningDeltaResult(
      baselineScreeningId: json['baselineScreeningId'] as String? ?? '',
      followupScreeningId: json['followupScreeningId'] as String? ?? '',
      baselineDate: json['baselineDate'] != null
          ? DateTime.tryParse(json['baselineDate'].toString()) ?? DateTime.now()
          : DateTime.now(),
      followupDate: json['followupDate'] != null
          ? DateTime.tryParse(json['followupDate'].toString()) ?? DateTime.now()
          : DateTime.now(),
      timeElapsedDays: (json['timeElapsedDays'] as num?)?.toDouble() ?? 0.0,
      timeElapsedHours: (json['timeElapsedHours'] as num?)?.toDouble() ?? 0.0,
      baselineRiskScore: (json['baselineRiskScore'] as num?)?.toDouble() ?? 0.0,
      followupRiskScore: (json['followupRiskScore'] as num?)?.toDouble() ?? 0.0,
      riskDelta: (json['riskDelta'] as num?)?.toDouble() ?? 0.0,
      riskDeltaPercentage: (json['riskDeltaPercentage'] as num?)?.toDouble() ?? 0.0,
      statusTier: ClinicalProgressionTier.fromString(statusStr),
      statusLabel: statusStr,
      ssim: (json['ssim'] as num?)?.toDouble(),
      ssimCategory: json['ssimCategory'] as String? ?? 'N/A',
      painDelta: (vitals['painDelta'] as num?)?.toDouble(),
      tempDelta: (vitals['tempDelta'] as num?)?.toDouble(),
      spo2Delta: (vitals['spo2Delta'] as num?)?.toDouble(),
      heartRateDelta: (vitals['heartRateDelta'] as num?)?.toDouble(),
      baselineImageUrl: json['baselineImageUrl'] as String?,
      followupImageUrl: json['followupImageUrl'] as String?,
      clinicalSummary: json['clinicalSummary'] as String? ?? '',
      recommendations: (json['recommendations'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}
