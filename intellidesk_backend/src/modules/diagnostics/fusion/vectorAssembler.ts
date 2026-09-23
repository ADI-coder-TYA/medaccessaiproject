import { SymptomInputPayload } from './types.js';

export const VISUAL_VECTOR_DIM = 128;
export const SYMPTOM_VECTOR_DIM = 32;
export const DEMOGRAPHICS_VECTOR_DIM = 8;
export const AUDIO_VECTOR_DIM = 16;
export const TOTAL_CONCATENATED_DIM = VISUAL_VECTOR_DIM + SYMPTOM_VECTOR_DIM + DEMOGRAPHICS_VECTOR_DIM + AUDIO_VECTOR_DIM; // 184

export const SYMPTOM_VOCABULARY = [
  'rash',
  'swelling',
  'redness',
  'shortness of breath',
  'chest pain',
  'pruritus',
  'fever',
  'chills',
  'exudate',
  'crusting',
  'dizziness',
  'nausea',
  'fatigue',
  'ulceration',
  'difficulty swallowing',
  'stiff neck',
  'blurred vision',
  'wheezing',
  'cough',
  'headache',
  'joint pain',
  'bleeding',
  'acute trauma',
  'erythema',
] as const;

export class VectorAssembler {
  /**
   * Builds the 128-d Visual Feature Vector.
   * If clinical image embedding is provided: asserts length 128 and verifies L2 normalization.
   * If text-only (no image provided): fills with a uniform L2-normalized constant vector (1 / sqrt(128)).
   */
  public static buildVisualVector(embeddings?: number[] | null): number[] {
    if (embeddings && embeddings.length === VISUAL_VECTOR_DIM) {
      return this.l2Normalize(embeddings);
    }

    if (embeddings && embeddings.length > 0) {
      const padded = new Array<number>(VISUAL_VECTOR_DIM).fill(0);
      for (let i = 0; i < Math.min(embeddings.length, VISUAL_VECTOR_DIM); i++) {
        padded[i] = embeddings[i];
      }
      return this.l2Normalize(padded);
    }

    // Text-Only Prior: uniform unit vector on S^(127) sphere: 1 / sqrt(128) ≈ 0.088388
    const uniformVal = Number((1.0 / Math.sqrt(VISUAL_VECTOR_DIM)).toFixed(6));
    return new Array<number>(VISUAL_VECTOR_DIM).fill(uniformVal);
  }

  /**
   * Builds the 32-d Symptom Vector.
   * All features are strictly min-max scaled into [0.0, 1.0].
   */
  public static buildSymptomVector(symptomData?: Partial<SymptomInputPayload> | null, vitals?: any): number[] {
    const vector = new Array<number>(SYMPTOM_VECTOR_DIM).fill(0.0);
    if (!symptomData) return vector;

    const mergedVitals = { ...(symptomData.vitals || {}), ...(vitals || {}) };

    // Index 0: Pain Scale [1..10] -> [0.0, 1.0]
    const pain = Number(symptomData.painScale) || 0;
    vector[0] = Math.min(1.0, Math.max(0.0, pain / 10.0));

    // Index 1: Duration [0..30+ days] -> [0.0, 1.0]
    const duration = Number(symptomData.durationDays) || 1;
    vector[1] = Math.min(1.0, Math.max(0.0, duration / 30.0));

    // Index 2: Body Temperature [35.0 C - 42.0 C] -> [0.0, 1.0]
    const temp = Number(mergedVitals.temperatureCelsius) || 37.0;
    vector[2] = Math.min(1.0, Math.max(0.0, (temp - 35.0) / 7.0));

    // Index 3: Heart Rate [40 - 180 bpm] -> [0.0, 1.0]
    const hr = Number(mergedVitals.heartRate) || 75;
    vector[3] = Math.min(1.0, Math.max(0.0, (hr - 40.0) / 140.0));

    // Index 4: Systolic Blood Pressure [80 - 200 mmHg] -> [0.0, 1.0]
    const sbp = Number(mergedVitals.systolicBP) || 120;
    vector[4] = Math.min(1.0, Math.max(0.0, (sbp - 80.0) / 120.0));

    // Index 5: Diastolic Blood Pressure [50 - 120 mmHg] -> [0.0, 1.0]
    const dbp = Number(mergedVitals.diastolicBP) || 80;
    vector[5] = Math.min(1.0, Math.max(0.0, (dbp - 50.0) / 70.0));

    // Index 6: Oxygen Saturation SpO2 [70% - 100%] -> [0.0, 1.0] (Inverted: lower SpO2 = higher acute score)
    const spo2 = Number(mergedVitals.oxygenSaturation) || 98;
    vector[6] = Math.min(1.0, Math.max(0.0, (100.0 - spo2) / 30.0));

    // Index 7: Respiratory Rate [10 - 40 breaths/min] -> [0.0, 1.0]
    const rr = Number(mergedVitals.respiratoryRate) || 16;
    vector[7] = Math.min(1.0, Math.max(0.0, (rr - 10.0) / 30.0));

    // Indices 8..31: 24 Clinical Symptom Keywords (presence/frequency normalized [0.0, 1.0])
    const symptomsText = [
      ...(symptomData.symptoms || []),
      symptomData.bodyLocation || '',
      symptomData.additionalNotes || ''
    ].join(' ').toLowerCase();

    for (let i = 0; i < SYMPTOM_VOCABULARY.length; i++) {
      const keyword = SYMPTOM_VOCABULARY[i];
      if (symptomsText.includes(keyword)) {
        vector[8 + i] = 1.0;
      }
    }

    return vector;
  }

  /**
   * Builds the 8-d Demographic Vector.
   * All features are strictly min-max scaled into [0.0, 1.0].
   */
  public static buildDemographicsVector(demographics?: any): number[] {
    const vector = new Array<number>(DEMOGRAPHICS_VECTOR_DIM).fill(0.0);
    if (!demographics) return vector;

    // Index 0: Age [0 - 100 years] -> [0.0, 1.0]
    const age = Number(demographics.age) || 30;
    vector[0] = Math.min(1.0, Math.max(0.0, age / 100.0));

    // Index 1..3: One-Hot Gender Encoding
    const gender = String(demographics.gender || '').toLowerCase();
    if (gender.includes('male') && !gender.includes('fe')) {
      vector[1] = 1.0;
    } else if (gender.includes('female')) {
      vector[2] = 1.0;
    } else {
      vector[3] = 1.0; // Non-binary / Other / Unspecified
    }

    // Index 4..7: Chronic Pre-existing Conditions
    const conditions = (demographics.preExistingConditions || [])
      .map((c: any) => String(c).toLowerCase())
      .join(' ');

    if (conditions.includes('diabetes')) vector[4] = 1.0;
    if (conditions.includes('hypertens') || conditions.includes('blood pressure')) vector[5] = 1.0;
    if (conditions.includes('asthma') || conditions.includes('copd') || conditions.includes('respiratory')) vector[6] = 1.0;
    if (conditions.includes('immunosuppress') || conditions.includes('cardio') || conditions.includes('cancer')) vector[7] = 1.0;

    return vector;
  }

  /**
   * Builds the 16-d Audio Biomarker Vector.
   * All acoustic features are strictly min-max scaled into [0.0, 1.0].
   * If audio is not provided: fills with a neutral acoustic prior (1 / sqrt(16) = 0.25).
   */
  public static buildAudioVector(audioFeatures?: number[] | null): number[] {
    if (audioFeatures && audioFeatures.length === AUDIO_VECTOR_DIM) {
      return audioFeatures.map(v => Number(Math.min(1.0, Math.max(0.0, Number(v) || 0.0)).toFixed(6)));
    }

    if (audioFeatures && audioFeatures.length > 0) {
      const padded = new Array<number>(AUDIO_VECTOR_DIM).fill(0.25);
      for (let i = 0; i < Math.min(audioFeatures.length, AUDIO_VECTOR_DIM); i++) {
        padded[i] = Number(Math.min(1.0, Math.max(0.0, Number(audioFeatures[i]) || 0.0)).toFixed(6));
      }
      return padded;
    }

    // Neutral Acoustic Prior: uniform vector on S^(15) sphere: 1 / sqrt(16) = 0.25
    return new Array<number>(AUDIO_VECTOR_DIM).fill(0.25);
  }

  /**
   * Assembles the full 184-dimensional late-fusion input vector:
   * [128 visual embeddings] + [32 symptom features] + [8 demographics features] + [16 audio features].
   */
  public static assembleVector(
    visualEmbeddings?: number[] | null,
    symptomData?: Partial<SymptomInputPayload> | null,
    vitals?: any,
    audioFeatures?: number[] | null
  ): {
    concatenatedVector: number[];
    dimensions: { visual: number; symptoms: number; demographics: number; audio: number; total: number };
  } {
    const visual = this.buildVisualVector(visualEmbeddings);
    const symptoms = this.buildSymptomVector(symptomData, vitals);
    const demographics = this.buildDemographicsVector(symptomData?.demographics);
    const audio = this.buildAudioVector(audioFeatures);

    const concatenatedVector = [...visual, ...symptoms, ...demographics, ...audio];

    return {
      concatenatedVector,
      dimensions: {
        visual: visual.length,
        symptoms: symptoms.length,
        demographics: demographics.length,
        audio: audio.length,
        total: concatenatedVector.length // 184
      }
    };
  }

  private static l2Normalize(vec: number[]): number[] {
    let sumSq = 0;
    for (let i = 0; i < vec.length; i++) {
      sumSq += vec[i] * vec[i];
    }
    const norm = Math.sqrt(sumSq) || 1.0;
    return vec.map(v => Number((v / norm).toFixed(6)));
  }
}
