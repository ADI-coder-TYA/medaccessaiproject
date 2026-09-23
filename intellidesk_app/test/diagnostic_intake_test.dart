import 'package:flutter_test/flutter_test.dart';
import 'package:intellidesk_app/modules/diagnostics/models/diagnostic_payload.dart';
import 'package:intellidesk_app/modules/diagnostics/providers/diagnostic_state_provider.dart';

void main() {
  group('DiagnosticPayload Tests', () {
    test('Constructs unified payload and verifies resolution', () {
      final validMetadata = ClinicalImageMetadata(
        width: 1080,
        height: 1920,
        capturedAt: DateTime.now(),
      );
      expect(validMetadata.isResolutionValid, isTrue);
      expect(validMetadata.resolutionString, '1080 x 1920 px');

      final lowResMetadata = ClinicalImageMetadata(
        width: 320,
        height: 480,
        capturedAt: DateTime.now(),
      );
      expect(lowResMetadata.isResolutionValid, isFalse);

      final payload = DiagnosticPayload(
        bodyLocation: 'Throat',
        painSeverity: 7,
        symptomDurationDays: 4,
        temperatureCelsius: 38.6,
        secondarySymptoms: ['Redness', 'Swelling', 'Fever / Chills'],
        demographics: const PatientDemographics(
          age: 26,
          gender: 'Female',
          preExistingConditions: ['Asthma'],
        ),
        imageMetadata: validMetadata,
        notes: 'Sore throat with fever',
      );

      expect(payload.bodyLocation, 'Throat');
      expect(payload.painSeverity, 7);
      expect(payload.temperatureCelsius, 38.6);
      expect(payload.secondarySymptoms.length, 3);
      expect(payload.demographics.age, 26);
      expect(payload.imageMetadata?.isResolutionValid, isTrue);

      final symptomVector = payload.toSymptomVector();
      expect(symptomVector.bodyLocation, 'Throat');
      expect(symptomVector.painScale, 7);
      expect(symptomVector.durationDays, 4);
      expect(symptomVector.vitals.temperatureCelsius, 38.6);
    });
  });

  group('DiagnosticStateProvider MVVM Tests', () {
    test('Validates questionnaire requirement before building payload', () {
      final provider = DiagnosticStateProvider();

      expect(provider.isQuestionnaireValid, isFalse);
      expect(() => provider.buildPayload(), throwsStateError);

      provider.setBodyLocation('Skin/Chest');
      expect(provider.isQuestionnaireValid, isTrue);

      provider.setPainSeverity(8);
      provider.setSymptomDuration(5);
      provider.setTemperature(38.2);
      provider.toggleSecondarySymptom('Rash');
      provider.setAge(30);
      provider.setGender('Male');
      provider.togglePreExistingCondition('Diabetes');

      final payload = provider.buildPayload();
      expect(payload.bodyLocation, 'Skin/Chest');
      expect(payload.painSeverity, 8);
      expect(payload.symptomDurationDays, 5);
      expect(payload.temperatureCelsius, 38.2);
      expect(payload.secondarySymptoms.contains('Rash'), isTrue);
      expect(payload.demographics.gender, 'Male');
      expect(payload.demographics.preExistingConditions.contains('Diabetes'), isTrue);
    });
  });
}
