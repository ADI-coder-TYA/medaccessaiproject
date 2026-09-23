import 'dart:convert';

/// Represents clinical vitals measured or input by the patient/clinician.
class ClinicalVitals {
  final double? heartRate;
  final double? temperatureCelsius;
  final double? systolicBP;
  final double? diastolicBP;
  final double? oxygenSaturation;
  final double? respiratoryRate;
  final String? source;
  final Map<String, dynamic>? rppgResult;

  const ClinicalVitals({
    this.heartRate,
    this.temperatureCelsius,
    this.systolicBP,
    this.diastolicBP,
    this.oxygenSaturation,
    this.respiratoryRate,
    this.source,
    this.rppgResult,
  });

  Map<String, dynamic> toMap() {
    return {
      if (heartRate != null) 'heartRate': heartRate,
      if (temperatureCelsius != null) 'temperatureCelsius': temperatureCelsius,
      if (systolicBP != null) 'systolicBP': systolicBP,
      if (diastolicBP != null) 'diastolicBP': diastolicBP,
      if (oxygenSaturation != null) 'oxygenSaturation': oxygenSaturation,
      if (respiratoryRate != null) 'respiratoryRate': respiratoryRate,
      if (source != null) 'source': source,
      if (rppgResult != null) 'rppgResult': rppgResult,
    };
  }

  factory ClinicalVitals.fromMap(Map<String, dynamic> map) {
    return ClinicalVitals(
      heartRate: map['heartRate'] != null ? (map['heartRate'] as num).toDouble() : null,
      temperatureCelsius: map['temperatureCelsius'] != null ? (map['temperatureCelsius'] as num).toDouble() : null,
      systolicBP: map['systolicBP'] != null ? (map['systolicBP'] as num).toDouble() : null,
      diastolicBP: map['diastolicBP'] != null ? (map['diastolicBP'] as num).toDouble() : null,
      oxygenSaturation: map['oxygenSaturation'] != null ? (map['oxygenSaturation'] as num).toDouble() : null,
      respiratoryRate: map['respiratoryRate'] != null ? (map['respiratoryRate'] as num).toDouble() : null,
      source: map['source'] as String?,
      rppgResult: map['rppgResult'] as Map<String, dynamic>?,
    );
  }
}

/// Represents the structured symptom vector extracted from questionnaire, body map, and vitals.
class SymptomVector {
  final String bodyLocation;
  final int durationDays;
  final int painScale; // 0 - 10
  final List<String> symptoms;
  final ClinicalVitals vitals;
  final Map<String, dynamic> demographics;
  final String? additionalNotes;
  final List<double> numericalVector;

  const SymptomVector({
    required this.bodyLocation,
    required this.durationDays,
    required this.painScale,
    required this.symptoms,
    this.vitals = const ClinicalVitals(),
    this.demographics = const {},
    this.additionalNotes,
    this.numericalVector = const [],
  });

  /// Produces a normalized numerical representation suitable for late-fusion ML tensors.
  List<double> toNumericalEmbedding({int targetDim = 32}) {
    if (numericalVector.isNotEmpty) return numericalVector;

    final embedding = List<double>.filled(targetDim, 0.0);
    // Latent indices encoding clinical indicators
    embedding[0] = (painScale / 10.0).clamp(0.0, 1.0);
    embedding[1] = (durationDays / 30.0).clamp(0.0, 1.0);
    embedding[2] = ((vitals.heartRate ?? 75.0) / 180.0).clamp(0.0, 1.0);
    embedding[3] = (((vitals.temperatureCelsius ?? 37.0) - 35.0) / 7.0).clamp(0.0, 1.0);
    embedding[4] = ((vitals.oxygenSaturation ?? 98.0) / 100.0).clamp(0.0, 1.0);
    embedding[5] = (symptoms.length / 10.0).clamp(0.0, 1.0);

    for (int i = 0; i < symptoms.length && (6 + i) < targetDim; i++) {
      embedding[6 + i] = 1.0;
    }

    return embedding;
  }

  Map<String, dynamic> toMap() {
    return {
      'bodyLocation': bodyLocation,
      'durationDays': durationDays,
      'painScale': painScale,
      'symptoms': symptoms,
      'vitals': vitals.toMap(),
      'demographics': demographics,
      'additionalNotes': additionalNotes,
      'numericalVector': toNumericalEmbedding(),
    };
  }

  String toJson() => jsonEncode(toMap());

  factory SymptomVector.fromMap(Map<String, dynamic> map) {
    return SymptomVector(
      bodyLocation: map['bodyLocation'] as String? ?? 'General / Unspecified',
      durationDays: (map['durationDays'] as num?)?.toInt() ?? 1,
      painScale: (map['painScale'] as num?)?.toInt() ?? 0,
      symptoms: (map['symptoms'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      vitals: map['vitals'] != null ? ClinicalVitals.fromMap(map['vitals'] as Map<String, dynamic>) : const ClinicalVitals(),
      demographics: (map['demographics'] as Map<String, dynamic>?) ?? {},
      additionalNotes: map['additionalNotes'] as String?,
      numericalVector: (map['numericalVector'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [],
    );
  }

  factory SymptomVector.fromJson(String source) => SymptomVector.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
