import 'dart:convert';
import 'symptom_vector.dart';
import 'risk_assessment.dart';

enum DiagnosticSessionStatus {
  intake,
  capturingImage,
  analyzing,
  completed,
  failed;

  static DiagnosticSessionStatus fromString(String? val) {
    if (val == null) return DiagnosticSessionStatus.intake;
    switch (val.toLowerCase()) {
      case 'capturingimage':
      case 'capturing_image':
        return DiagnosticSessionStatus.capturingImage;
      case 'analyzing':
        return DiagnosticSessionStatus.analyzing;
      case 'completed':
        return DiagnosticSessionStatus.completed;
      case 'failed':
        return DiagnosticSessionStatus.failed;
      case 'intake':
      default:
        return DiagnosticSessionStatus.intake;
    }
  }
}

/// Root domain entity representing a single clinical checkup screening session.
class DiagnosticSession {
  final String id;
  final String? patientId;
  final String institutionId;
  final SymptomVector symptomVector;
  final String? clinicalImageUrl;
  final RiskAssessment? riskAssessment;
  final String? xaiHeatmapUrl;
  final DiagnosticSessionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DiagnosticSession({
    required this.id,
    this.patientId,
    this.institutionId = 'edu-admin-123',
    required this.symptomVector,
    this.clinicalImageUrl,
    this.riskAssessment,
    this.xaiHeatmapUrl,
    this.status = DiagnosticSessionStatus.intake,
    required this.createdAt,
    required this.updatedAt,
  });

  DiagnosticSession copyWith({
    String? id,
    String? patientId,
    String? institutionId,
    SymptomVector? symptomVector,
    String? clinicalImageUrl,
    RiskAssessment? riskAssessment,
    String? xaiHeatmapUrl,
    DiagnosticSessionStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DiagnosticSession(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      institutionId: institutionId ?? this.institutionId,
      symptomVector: symptomVector ?? this.symptomVector,
      clinicalImageUrl: clinicalImageUrl ?? this.clinicalImageUrl,
      riskAssessment: riskAssessment ?? this.riskAssessment,
      xaiHeatmapUrl: xaiHeatmapUrl ?? this.xaiHeatmapUrl,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patientId': patientId,
      'institutionId': institutionId,
      'symptomVector': symptomVector.toMap(),
      'clinicalImageUrl': clinicalImageUrl,
      'riskAssessment': riskAssessment?.toMap(),
      'xaiHeatmapUrl': xaiHeatmapUrl,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  String toJson() => jsonEncode(toMap());

  factory DiagnosticSession.fromMap(Map<String, dynamic> map) {
    return DiagnosticSession(
      id: map['id'] as String? ?? 'session-${DateTime.now().millisecondsSinceEpoch}',
      patientId: map['patientId'] as String? ?? map['patient_id'] as String?,
      institutionId: map['institutionId'] as String? ?? map['institution_id'] as String? ?? 'edu-admin-123',
      symptomVector: map['symptomVector'] != null
          ? SymptomVector.fromMap(map['symptomVector'] as Map<String, dynamic>)
          : (map['symptom_payload'] != null
              ? SymptomVector.fromMap(map['symptom_payload'] as Map<String, dynamic>)
              : const SymptomVector(bodyLocation: 'Unspecified', durationDays: 1, painScale: 0, symptoms: [])),
      clinicalImageUrl: map['clinicalImageUrl'] as String? ?? map['image_url'] as String?,
      riskAssessment: map['riskAssessment'] != null
          ? RiskAssessment.fromMap(map['riskAssessment'] as Map<String, dynamic>)
          : null,
      xaiHeatmapUrl: map['xaiHeatmapUrl'] as String? ?? map['xai_heatmap_url'] as String?,
      status: DiagnosticSessionStatus.fromString(map['status'] as String?),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : (map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now()),
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : (map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : DateTime.now()),
    );
  }

  factory DiagnosticSession.fromJson(String source) => DiagnosticSession.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
