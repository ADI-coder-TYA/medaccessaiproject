import 'dart:convert';
import 'dart:typed_data';
import 'symptom_vector.dart';

/// Demographics data model for patient clinical profiling.
class PatientDemographics {
  final int? age;
  final String? gender;
  final List<String> preExistingConditions;

  const PatientDemographics({
    this.age,
    this.gender,
    this.preExistingConditions = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      if (age != null) 'age': age,
      if (gender != null) 'gender': gender,
      'preExistingConditions': preExistingConditions,
    };
  }

  factory PatientDemographics.fromMap(Map<String, dynamic> map) {
    return PatientDemographics(
      age: (map['age'] as num?)?.toInt(),
      gender: map['gender'] as String?,
      preExistingConditions: (map['preExistingConditions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

/// Metadata and validation for clinical image capture.
class ClinicalImageMetadata {
  final String? path;
  final Uint8List? bytes;
  final int width;
  final int height;
  final String mimeType;
  final DateTime capturedAt;

  const ClinicalImageMetadata({
    this.path,
    this.bytes,
    required this.width,
    required this.height,
    this.mimeType = 'image/jpeg',
    required this.capturedAt,
  });

  /// Real-time resolution check: must be at least 512x512 pixels.
  bool get isResolutionValid => width >= 512 && height >= 512;

  String get resolutionString => '$width x $height px';

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'width': width,
      'height': height,
      'mimeType': mimeType,
      'capturedAt': capturedAt.toIso8601String(),
      'isResolutionValid': isResolutionValid,
    };
  }
}

/// Unified diagnostic payload binding questionnaire responses, clinical sliders,
/// patient demographics, and verified clinical image metadata.
class DiagnosticPayload {
  final String bodyLocation; // Head, Throat, Skin/Chest, Abdomen, Extremities
  final int painSeverity; // 1 - 10
  final int symptomDurationDays; // 1 - 30+
  final double temperatureCelsius; // 35.0 - 42.0 C
  final List<String> secondarySymptoms;
  final PatientDemographics demographics;
  final ClinicalImageMetadata? imageMetadata;
  final Uint8List? audioBytes;
  final String? audioFileName;
  final String? notes;

  const DiagnosticPayload({
    required this.bodyLocation,
    required this.painSeverity,
    required this.symptomDurationDays,
    required this.temperatureCelsius,
    required this.secondarySymptoms,
    required this.demographics,
    this.imageMetadata,
    this.audioBytes,
    this.audioFileName,
    this.notes,
  });

  /// Converts this unified payload to the underlying SymptomVector for ML late-fusion inference.
  SymptomVector toSymptomVector() {
    return SymptomVector(
      bodyLocation: bodyLocation,
      durationDays: symptomDurationDays,
      painScale: painSeverity,
      symptoms: secondarySymptoms,
      vitals: ClinicalVitals(
        temperatureCelsius: temperatureCelsius,
      ),
      demographics: demographics.toMap(),
      additionalNotes: notes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bodyLocation': bodyLocation,
      'painSeverity': painSeverity,
      'symptomDurationDays': symptomDurationDays,
      'temperatureCelsius': temperatureCelsius,
      'secondarySymptoms': secondarySymptoms,
      'demographics': demographics.toMap(),
      'imageMetadata': imageMetadata?.toMap(),
      'hasAudio': audioBytes != null && audioBytes!.isNotEmpty,
      if (audioFileName != null) 'audioFileName': audioFileName,
      'notes': notes,
    };
  }

  String toJson() => jsonEncode(toMap());
}
