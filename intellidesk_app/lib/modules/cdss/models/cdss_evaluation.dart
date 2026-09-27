/// Dart models for Clinical Decision Support System (CDSS) Module
/// Aligned with WHO ICD-11 (http://id.who.int/icd/release/11/mms)

class RecommendedMedication {
  final String? brandName;
  final String genericName;
  final String dosage;
  final String frequency;
  final String duration;
  final String clinicalNotes;

  RecommendedMedication({
    this.brandName,
    required this.genericName,
    required this.dosage,
    required this.frequency,
    required this.duration,
    required this.clinicalNotes,
  });

  factory RecommendedMedication.fromJson(Map<String, dynamic> json) {
    return RecommendedMedication(
      brandName: json['brandName'] as String?,
      genericName: json['genericName'] as String? ?? 'Medication',
      dosage: json['dosage'] as String? ?? '',
      frequency: json['frequency'] as String? ?? '',
      duration: json['duration'] as String? ?? '',
      clinicalNotes: json['clinicalNotes'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (brandName != null) 'brandName': brandName,
      'genericName': genericName,
      'dosage': dosage,
      'frequency': frequency,
      'duration': duration,
      'clinicalNotes': clinicalNotes,
    };
  }
}

class TreatmentPathway {
  final String primaryCode;
  final String primaryTitle;
  final List<RecommendedMedication> recommendedRx;
  final List<String> labOrders;
  final List<String> imagingOrders;
  final String monitoringFrequency;
  final int followUpDays;
  final List<String> urgentRedFlags;
  final String urgencyLevel; // 'ROUTINE' | 'PROMPT_EVALUATION' | 'IMMEDIATE_EMERGENCY'

  TreatmentPathway({
    required this.primaryCode,
    required this.primaryTitle,
    required this.recommendedRx,
    required this.labOrders,
    required this.imagingOrders,
    required this.monitoringFrequency,
    required this.followUpDays,
    required this.urgentRedFlags,
    required this.urgencyLevel,
  });

  factory TreatmentPathway.fromJson(Map<String, dynamic> json) {
    final rawRx = json['recommendedRx'];
    final rxList = (rawRx is List)
        ? rawRx.map((e) => RecommendedMedication.fromJson(e as Map<String, dynamic>)).toList()
        : <RecommendedMedication>[];

    final rawLabs = json['labOrders'];
    final labsList = (rawLabs is List) ? rawLabs.map((e) => e.toString()).toList() : <String>[];

    final rawImg = json['imagingOrders'];
    final imgList = (rawImg is List) ? rawImg.map((e) => e.toString()).toList() : <String>[];

    final rawFlags = json['urgentRedFlags'];
    final flagsList = (rawFlags is List) ? rawFlags.map((e) => e.toString()).toList() : <String>[];

    return TreatmentPathway(
      primaryCode: json['primaryCode'] as String? ?? '',
      primaryTitle: json['primaryTitle'] as String? ?? '',
      recommendedRx: rxList,
      labOrders: labsList,
      imagingOrders: imgList,
      monitoringFrequency: json['monitoringFrequency'] as String? ?? 'Daily monitoring',
      followUpDays: json['followUpDays'] as int? ?? 3,
      urgentRedFlags: flagsList,
      urgencyLevel: json['urgencyLevel'] as String? ?? 'ROUTINE',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'primaryCode': primaryCode,
      'primaryTitle': primaryTitle,
      'recommendedRx': recommendedRx.map((r) => r.toJson()).toList(),
      'labOrders': labOrders,
      'imagingOrders': imagingOrders,
      'monitoringFrequency': monitoringFrequency,
      'followUpDays': followUpDays,
      'urgentRedFlags': urgentRedFlags,
      'urgencyLevel': urgencyLevel,
    };
  }
}

class DifferentialDiagnosisCandidate {
  final String code;
  final String title;
  final String category;
  final String uri;
  final double probability;
  final double logitScore;
  final List<String> matchedCriteria;
  final String clinicalRationale;

  DifferentialDiagnosisCandidate({
    required this.code,
    required this.title,
    required this.category,
    required this.uri,
    required this.probability,
    required this.logitScore,
    required this.matchedCriteria,
    required this.clinicalRationale,
  });

  factory DifferentialDiagnosisCandidate.fromJson(Map<String, dynamic> json) {
    final rawCriteria = json['matchedCriteria'];
    final criteriaList = (rawCriteria is List) ? rawCriteria.map((e) => e.toString()).toList() : <String>[];

    return DifferentialDiagnosisCandidate(
      code: json['code'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: json['category'] as String? ?? 'General Diagnosis',
      uri: json['uri'] as String? ?? 'http://id.who.int/icd/release/11/mms',
      probability: (json['probability'] as num?)?.toDouble() ?? 0.0,
      logitScore: (json['logitScore'] as num?)?.toDouble() ?? 0.0,
      matchedCriteria: criteriaList,
      clinicalRationale: json['clinicalRationale'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'title': title,
      'category': category,
      'uri': uri,
      'probability': probability,
      'logitScore': logitScore,
      'matchedCriteria': matchedCriteria,
      'clinicalRationale': clinicalRationale,
    };
  }
}

class ClinicianApproval {
  final String clinicianId;
  final String clinicianName;
  final String approvedAt;
  final bool isOverridden;
  final String originalCode;
  final String? overriddenCode;
  final String? overrideNotes;
  final String signatureHash;

  ClinicianApproval({
    required this.clinicianId,
    required this.clinicianName,
    required this.approvedAt,
    required this.isOverridden,
    required this.originalCode,
    this.overriddenCode,
    this.overrideNotes,
    required this.signatureHash,
  });

  factory ClinicianApproval.fromJson(Map<String, dynamic> json) {
    return ClinicianApproval(
      clinicianId: json['clinicianId'] as String? ?? 'clinician-default',
      clinicianName: json['clinicianName'] as String? ?? 'Attending Clinician, MD',
      approvedAt: json['approvedAt'] as String? ?? DateTime.now().toIso8601String(),
      isOverridden: json['isOverridden'] as bool? ?? false,
      originalCode: json['originalCode'] as String? ?? '',
      overriddenCode: json['overriddenCode'] as String?,
      overrideNotes: json['overrideNotes'] as String?,
      signatureHash: json['signatureHash'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'clinicianId': clinicianId,
      'clinicianName': clinicianName,
      'approvedAt': approvedAt,
      'isOverridden': isOverridden,
      'originalCode': originalCode,
      if (overriddenCode != null) 'overriddenCode': overriddenCode,
      if (overrideNotes != null) 'overrideNotes': overrideNotes,
      'signatureHash': signatureHash,
    };
  }
}

class CDSSEvaluationResult {
  final String id;
  final String? screeningId;
  final String patientId;
  final String? institutionId;
  final String? institutionName;
  final String primaryICD11Code;
  final String primaryICD11Title;
  final String primaryICD11Uri;
  final List<DifferentialDiagnosisCandidate> differentialDiagnoses;
  final TreatmentPathway treatmentPathway;
  final double temperatureScaling;
  final String regulatoryDisclaimer;
  final String? modelUsed;
  final ClinicianApproval? attendingClinicianApproval;
  final String createdAt;
  final String updatedAt;

  CDSSEvaluationResult({
    required this.id,
    this.screeningId,
    required this.patientId,
    this.institutionId,
    this.institutionName,
    required this.primaryICD11Code,
    required this.primaryICD11Title,
    required this.primaryICD11Uri,
    required this.differentialDiagnoses,
    required this.treatmentPathway,
    required this.temperatureScaling,
    required this.regulatoryDisclaimer,
    this.modelUsed,
    this.attendingClinicianApproval,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isApproved => attendingClinicianApproval != null;
  bool get isOverridden => attendingClinicianApproval?.isOverridden ?? false;

  factory CDSSEvaluationResult.fromJson(Map<String, dynamic> json) {
    final rawDDx = json['differentialDiagnoses'];
    final ddxList = (rawDDx is List)
        ? rawDDx.map((e) => DifferentialDiagnosisCandidate.fromJson(e as Map<String, dynamic>)).toList()
        : <DifferentialDiagnosisCandidate>[];

    final rawApproval = json['attendingClinicianApproval'];
    final approval = (rawApproval is Map<String, dynamic>)
        ? ClinicianApproval.fromJson(rawApproval)
        : null;

    final pathway = json['treatmentPathway'] is Map<String, dynamic>
        ? TreatmentPathway.fromJson(json['treatmentPathway'] as Map<String, dynamic>)
        : TreatmentPathway(
            primaryCode: json['primaryICD11Code'] as String? ?? '',
            primaryTitle: json['primaryICD11Title'] as String? ?? '',
            recommendedRx: [],
            labOrders: [],
            imagingOrders: [],
            monitoringFrequency: 'Daily monitoring',
            followUpDays: 3,
            urgentRedFlags: [],
            urgencyLevel: 'ROUTINE',
          );

    return CDSSEvaluationResult(
      id: json['id'] as String? ?? 'eval-${DateTime.now().millisecondsSinceEpoch}',
      screeningId: json['screeningId'] as String?,
      patientId: json['patientId'] as String? ?? 'anonymous',
      institutionId: json['institutionId'] as String?,
      institutionName: json['institutionName'] as String?,
      primaryICD11Code: json['primaryICD11Code'] as String? ?? '1B10.0',
      primaryICD11Title: json['primaryICD11Title'] as String? ?? 'Acute Respiratory Infection',
      primaryICD11Uri: json['primaryICD11Uri'] as String? ?? 'http://id.who.int/icd/release/11/mms/1B10.0',
      differentialDiagnoses: ddxList,
      treatmentPathway: pathway,
      temperatureScaling: (json['temperatureScaling'] as num?)?.toDouble() ?? 1.25,
      regulatoryDisclaimer: json['regulatoryDisclaimer'] as String? ??
          'AI Clinical Decision Support Tool — For Licensed Practitioner Reference Only. Requires Attending Physician Validation.',
      modelUsed: json['modelUsed'] as String?,
      attendingClinicianApproval: approval,
      createdAt: json['createdAt'] as String? ?? DateTime.now().toIso8601String(),
      updatedAt: json['updatedAt'] as String? ?? DateTime.now().toIso8601String(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (screeningId != null) 'screeningId': screeningId,
      'patientId': patientId,
      if (institutionId != null) 'institutionId': institutionId,
      if (institutionName != null) 'institutionName': institutionName,
      'primaryICD11Code': primaryICD11Code,
      'primaryICD11Title': primaryICD11Title,
      'primaryICD11Uri': primaryICD11Uri,
      'differentialDiagnoses': differentialDiagnoses.map((d) => d.toJson()).toList(),
      'treatmentPathway': treatmentPathway.toJson(),
      'temperatureScaling': temperatureScaling,
      'regulatoryDisclaimer': regulatoryDisclaimer,
      if (modelUsed != null) 'modelUsed': modelUsed,
      if (attendingClinicianApproval != null) 'attendingClinicianApproval': attendingClinicianApproval!.toJson(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
