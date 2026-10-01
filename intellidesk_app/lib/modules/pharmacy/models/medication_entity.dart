import 'dart:convert';

enum DDISeverity {
  contraindicatedSevere,
  moderateMonitor,
  minor,
  safe,
}

extension DDISeverityExtension on DDISeverity {
  String get displayName {
    switch (this) {
      case DDISeverity.contraindicatedSevere:
        return 'CONTRAINDICATED SEVERE';
      case DDISeverity.moderateMonitor:
        return 'MODERATE MONITOR';
      case DDISeverity.minor:
        return 'MINOR';
      case DDISeverity.safe:
        return 'SAFE';
    }
  }

  static DDISeverity fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'CONTRAINDICATED_SEVERE':
        return DDISeverity.contraindicatedSevere;
      case 'MODERATE_MONITOR':
        return DDISeverity.moderateMonitor;
      case 'MINOR':
        return DDISeverity.minor;
      default:
        return DDISeverity.safe;
    }
  }
}

class ExtractedMedication {
  final String brandName;
  final String activeIngredient;
  final String dosage;
  final String frequency;
  final String? duration;
  final String rawText;
  final double confidence;
  final String? matchedRxNormTerm;
  final String? allergenGroup;

  const ExtractedMedication({
    required this.brandName,
    required this.activeIngredient,
    required this.dosage,
    required this.frequency,
    this.duration,
    required this.rawText,
    required this.confidence,
    this.matchedRxNormTerm,
    this.allergenGroup,
  });

  factory ExtractedMedication.fromJson(Map<String, dynamic> json) {
    return ExtractedMedication(
      brandName: json['brandName'] ?? json['brand_name'] ?? 'Medication',
      activeIngredient: json['activeIngredient'] ?? json['active_ingredient'] ?? 'Active Ingredient',
      dosage: json['dosage'] ?? 'Standard Dose',
      frequency: json['frequency'] ?? 'QD',
      duration: json['duration'],
      rawText: json['rawText'] ?? json['raw_text'] ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      matchedRxNormTerm: json['matchedRxNormTerm'] ?? json['matched_rxnorm_term'],
      allergenGroup: json['allergenGroup'] ?? json['allergen_group'],
    );
  }

  Map<String, dynamic> toJson() => {
    'brandName': brandName,
    'activeIngredient': activeIngredient,
    'dosage': dosage,
    'frequency': frequency,
    'duration': duration,
    'rawText': rawText,
    'confidence': confidence,
    'matchedRxNormTerm': matchedRxNormTerm,
    'allergenGroup': allergenGroup,
  };

  ExtractedMedication copyWith({
    String? brandName,
    String? activeIngredient,
    String? dosage,
    String? frequency,
    String? duration,
    String? rawText,
    double? confidence,
    String? matchedRxNormTerm,
    String? allergenGroup,
  }) {
    return ExtractedMedication(
      brandName: brandName ?? this.brandName,
      activeIngredient: activeIngredient ?? this.activeIngredient,
      dosage: dosage ?? this.dosage,
      frequency: frequency ?? this.frequency,
      duration: duration ?? this.duration,
      rawText: rawText ?? this.rawText,
      confidence: confidence ?? this.confidence,
      matchedRxNormTerm: matchedRxNormTerm ?? this.matchedRxNormTerm,
      allergenGroup: allergenGroup ?? this.allergenGroup,
    );
  }
}

class DDIPairResult {
  final String drugA;
  final String drugB;
  final DDISeverity severity;
  final String clinicalMechanism;
  final String mitigationAdvice;

  const DDIPairResult({
    required this.drugA,
    required this.drugB,
    required this.severity,
    required this.clinicalMechanism,
    required this.mitigationAdvice,
  });

  factory DDIPairResult.fromJson(Map<String, dynamic> json) {
    return DDIPairResult(
      drugA: json['drugA'] ?? json['drug_a'] ?? '',
      drugB: json['drugB'] ?? json['drug_b'] ?? '',
      severity: DDISeverityExtension.fromString(json['severity']),
      clinicalMechanism: json['clinicalMechanism'] ?? json['clinical_mechanism'] ?? '',
      mitigationAdvice: json['mitigationAdvice'] ?? json['mitigation_advice'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'drugA': drugA,
    'drugB': drugB,
    'severity': severity.displayName.replaceAll(' ', '_'),
    'clinicalMechanism': clinicalMechanism,
    'mitigationAdvice': mitigationAdvice,
  };
}

class AlternativeMedicationOption {
  final String activeIngredient;
  final String? brandName;
  final String drugClass;
  final String rationale;
  final String source;
  final String? rxcui;

  const AlternativeMedicationOption({
    required this.activeIngredient,
    this.brandName,
    required this.drugClass,
    required this.rationale,
    required this.source,
    this.rxcui,
  });

  factory AlternativeMedicationOption.fromJson(Map<String, dynamic> json) {
    return AlternativeMedicationOption(
      activeIngredient: json['activeIngredient'] ?? json['active_ingredient'] ?? '',
      brandName: json['brandName'] ?? json['brand_name'],
      drugClass: json['drugClass'] ?? json['drug_class'] ?? '',
      rationale: json['rationale'] ?? '',
      source: json['source'] ?? 'CLINICAL_GUIDELINE',
      rxcui: json['rxcui']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'activeIngredient': activeIngredient,
    'brandName': brandName,
    'drugClass': drugClass,
    'rationale': rationale,
    'source': source,
    'rxcui': rxcui,
  };
}

class AllergyConflictResult {
  final String allergenGroup;
  final String matchedDrug;
  final String activeIngredient;
  final String? patientReaction;
  final String severity;
  final String alertMessage;
  final List<AlternativeMedicationOption> suggestedAlternatives;

  const AllergyConflictResult({
    required this.allergenGroup,
    required this.matchedDrug,
    required this.activeIngredient,
    this.patientReaction,
    required this.severity,
    required this.alertMessage,
    this.suggestedAlternatives = const [],
  });

  factory AllergyConflictResult.fromJson(Map<String, dynamic> json) {
    final rawAlts = json['suggestedAlternatives'] ?? json['suggested_alternatives'];
    final List<AlternativeMedicationOption> alts = [];
    if (rawAlts is List) {
      for (final a in rawAlts) {
        if (a is Map<String, dynamic>) {
          alts.add(AlternativeMedicationOption.fromJson(a));
        }
      }
    }

    return AllergyConflictResult(
      allergenGroup: json['allergenGroup'] ?? json['allergen_group'] ?? '',
      matchedDrug: json['matchedDrug'] ?? json['matched_drug'] ?? '',
      activeIngredient: json['activeIngredient'] ?? json['active_ingredient'] ?? '',
      patientReaction: json['patientReaction'] ?? json['patient_reaction'],
      severity: json['severity'] ?? 'HIGH_RISK_ALLERGY',
      alertMessage: json['alertMessage'] ?? json['alert_message'] ?? '',
      suggestedAlternatives: alts,
    );
  }

  Map<String, dynamic> toJson() => {
    'allergenGroup': allergenGroup,
    'matchedDrug': matchedDrug,
    'activeIngredient': activeIngredient,
    'patientReaction': patientReaction,
    'severity': severity,
    'alertMessage': alertMessage,
    'suggestedAlternatives': suggestedAlternatives.map((a) => a.toJson()).toList(),
  };
}


class RxScanSummary {
  final String? id;
  final String? patientId;
  final String? imageUrl;
  final List<ExtractedMedication> extractedDrugs;
  final List<DDIPairResult> ddiWarnings;
  final List<AllergyConflictResult> allergyConflicts;
  final bool hasSafetyConflict;
  final bool requiresPharmacistReview;
  final String? rawOcrText;
  final String? createdAt;

  const RxScanSummary({
    this.id,
    this.patientId,
    this.imageUrl,
    required this.extractedDrugs,
    required this.ddiWarnings,
    required this.allergyConflicts,
    required this.hasSafetyConflict,
    required this.requiresPharmacistReview,
    this.rawOcrText,
    this.createdAt,
  });

  factory RxScanSummary.fromJson(Map<String, dynamic> json) {
    return RxScanSummary(
      id: json['id'],
      patientId: json['patientId'] ?? json['patient_id'],
      imageUrl: json['imageUrl'] ?? json['image_url'],
      extractedDrugs: (json['extractedDrugs'] as List? ?? json['extracted_drugs'] as List? ?? [])
          .map((item) => ExtractedMedication.fromJson(item))
          .toList(),
      ddiWarnings: (json['ddiWarnings'] as List? ?? json['ddi_warnings'] as List? ?? [])
          .map((item) => DDIPairResult.fromJson(item))
          .toList(),
      allergyConflicts: (json['allergyConflicts'] as List? ?? json['allergy_conflicts'] as List? ?? [])
          .map((item) => AllergyConflictResult.fromJson(item))
          .toList(),
      hasSafetyConflict: json['hasSafetyConflict'] ?? json['has_safety_conflict'] ?? false,
      requiresPharmacistReview: json['requiresPharmacistReview'] ?? json['requires_pharmacist_review'] ?? false,
      rawOcrText: json['rawOcrText'] ?? json['raw_ocr_text'],
      createdAt: json['createdAt'] ?? json['created_at'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientId': patientId,
    'imageUrl': imageUrl,
    'extractedDrugs': extractedDrugs.map((d) => d.toJson()).toList(),
    'ddiWarnings': ddiWarnings.map((w) => w.toJson()).toList(),
    'allergyConflicts': allergyConflicts.map((c) => c.toJson()).toList(),
    'hasSafetyConflict': hasSafetyConflict,
    'requiresPharmacistReview': requiresPharmacistReview,
    'rawOcrText': rawOcrText,
    'createdAt': createdAt,
  };
}

class PatientAllergy {
  final String? id;
  final String patientId;
  final String allergenGroup;
  final String? reactionDescription;
  final String? createdAt;

  const PatientAllergy({
    this.id,
    required this.patientId,
    required this.allergenGroup,
    this.reactionDescription,
    this.createdAt,
  });

  factory PatientAllergy.fromJson(Map<String, dynamic> json) {
    return PatientAllergy(
      id: json['id'],
      patientId: json['patientId'] ?? json['patient_id'] ?? '',
      allergenGroup: json['allergenGroup'] ?? json['allergen_group'] ?? '',
      reactionDescription: json['reactionDescription'] ?? json['reaction_description'],
      createdAt: json['createdAt'] ?? json['created_at'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientId': patientId,
    'allergenGroup': allergenGroup,
    'reactionDescription': reactionDescription,
    'createdAt': createdAt,
  };
}

class PatientMedication {
  final String? id;
  final String patientId;
  final String medicationName;
  final String activeIngredient;
  final String? dosage;
  final bool isActive;
  final String? createdAt;

  const PatientMedication({
    this.id,
    required this.patientId,
    required this.medicationName,
    required this.activeIngredient,
    this.dosage,
    this.isActive = true,
    this.createdAt,
  });

  factory PatientMedication.fromJson(Map<String, dynamic> json) {
    return PatientMedication(
      id: json['id'],
      patientId: json['patientId'] ?? json['patient_id'] ?? '',
      medicationName: json['medicationName'] ?? json['medication_name'] ?? '',
      activeIngredient: json['activeIngredient'] ?? json['active_ingredient'] ?? '',
      dosage: json['dosage'],
      isActive: json['isActive'] ?? json['is_active'] ?? true,
      createdAt: json['createdAt'] ?? json['created_at'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'patientId': patientId,
    'medicationName': medicationName,
    'activeIngredient': activeIngredient,
    'dosage': dosage,
    'isActive': isActive,
    'createdAt': createdAt,
  };
}
