import * as tf from '@tensorflow/tfjs';
import '@tensorflow/tfjs-node';
import { pipeline, env } from '@xenova/transformers';
import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
import {
  CLINICAL_DISEASES,
  CLINICAL_SYMPTOM_VOCABULARY,
  DiseaseProfile
} from './diseaseBenchmarkData.js';
import { DifferentialDiagnosis, SymptomInputPayload } from './types.js';

// Configure transformers cache directory
env.cacheDir = path.join(os.tmpdir(), '.transformers_cache');

export const SYMPTOM_DIM = CLINICAL_SYMPTOM_VOCABULARY.length;
export const METRIC_DIM = 8; // Normalized HR, BP, Temp, RR, SpO2, Pain, Duration
export const TOTAL_INPUT_DIM = SYMPTOM_DIM + METRIC_DIM;
export const NUM_DISEASE_CLASSES = CLINICAL_DISEASES.length;

export const DISEASE_MODEL_DIR = path.resolve(process.cwd(), 'models', 'disease_prediction');
export const DISEASE_MODEL_JSON_PATH = path.join(DISEASE_MODEL_DIR, 'model.json');

/**
 * Deep Neural Network + Hugging Face Transformer Clinical Disease Predictor.
 * Replaces heuristic if-else rules with continuous ML inference:
 *  1. TensorFlow.js Deep Neural Classifier (Multi-hot symptoms & vitals -> Softmax distribution over 20+ diseases)
 *  2. Hugging Face Sentence Transformer (all-MiniLM-L6-v2) for 384-D dense clinical semantic embeddings
 *  3. Multi-modality Late Ensemble Fusion
 */
export class DiseasePredictionModel {
  private static cachedModel: tf.LayersModel | null = null;
  private static hfPipeline: any = null;
  private static prototypeEmbeddings: Map<string, number[]> = new Map();
  private static isInitializing = false;

  /**
   * Initializes or loads both the TensorFlow neural classifier and Hugging Face transformer.
   */
  public static async initialize(): Promise<void> {
    if (this.cachedModel && this.hfPipeline) return;
    if (this.isInitializing) {
      while (this.isInitializing) {
        await new Promise((r) => setTimeout(r, 100));
      }
      return;
    }

    this.isInitializing = true;
    try {
      // 1. Initialize or Load Neural Network
      if (fs.existsSync(DISEASE_MODEL_JSON_PATH)) {
        try {
          this.cachedModel = await tf.loadLayersModel(`file://${DISEASE_MODEL_JSON_PATH}`);
          console.log('✅ [DiseasePredictionML] Loaded pre-trained Deep Neural Disease Classifier.');
        } catch (loadErr) {
          console.warn('⚠️ [DiseasePredictionML] Re-training Neural Classifier:', loadErr);
          await this.trainAndPersistModel();
        }
      } else {
        await this.trainAndPersistModel();
      }

      // 2. Initialize Hugging Face Transformer Pipeline
      try {
        console.log('🤖 [DiseasePredictionML] Loading Hugging Face Clinical Transformer (Xenova/all-MiniLM-L6-v2)...');
        this.hfPipeline = await pipeline('feature-extraction', 'Xenova/all-MiniLM-L6-v2');
        await this.computePrototypeEmbeddings();
        console.log('✅ [DiseasePredictionML] Hugging Face Dense Embeddings initialized for all clinical diseases.');
      } catch (hfErr) {
        console.warn('⚠️ [DiseasePredictionML] Could not initialize Hugging Face transformer, running pure Neural inference:', hfErr);
      }
    } finally {
      this.isInitializing = false;
    }
  }

  /**
   * Computes dense 384-D semantic embeddings for all disease descriptions.
   */
  private static async computePrototypeEmbeddings(): Promise<void> {
    if (!this.hfPipeline) return;
    for (const disease of CLINICAL_DISEASES) {
      const text = `${disease.name}: ${disease.semanticDescription}. Typical symptoms: ${disease.symptoms.join(', ')}. Common regions: ${disease.bodyLocations.join(', ')}.`;
      const output = await this.hfPipeline(text, { pooling: 'mean', normalize: true });
      this.prototypeEmbeddings.set(disease.id, Array.from(output.data));
    }
  }

  /**
   * Builds the TensorFlow.js Deep Neural Classifier architecture.
   */
  public static buildModel(): tf.LayersModel {
    const input = tf.input({ shape: [TOTAL_INPUT_DIM], name: 'clinical_features' });

    let x = tf.layers.dense({
      units: 128,
      activation: 'relu',
      kernelInitializer: 'glorotNormal',
      name: 'disease_dense_1'
    }).apply(input) as tf.SymbolicTensor;

    x = tf.layers.batchNormalization({ name: 'disease_bn_1' }).apply(x) as tf.SymbolicTensor;
    x = tf.layers.dropout({ rate: 0.25, name: 'disease_drop_1' }).apply(x) as tf.SymbolicTensor;

    x = tf.layers.dense({
      units: 64,
      activation: 'relu',
      kernelInitializer: 'heNormal',
      name: 'disease_dense_2'
    }).apply(x) as tf.SymbolicTensor;

    x = tf.layers.dropout({ rate: 0.2, name: 'disease_drop_2' }).apply(x) as tf.SymbolicTensor;

    const output = tf.layers.dense({
      units: NUM_DISEASE_CLASSES,
      activation: 'softmax',
      name: 'disease_distribution'
    }).apply(x) as tf.SymbolicTensor;

    const model = tf.model({ inputs: input, outputs: output });
    model.compile({
      optimizer: tf.train.adam(0.003),
      loss: 'categoricalCrossentropy',
      metrics: ['accuracy']
    });

    return model;
  }

  /**
   * Encodes clinical input into a standardized numerical feature vector.
   */
  public static assembleFeatureVector(
    symptomData?: Partial<SymptomInputPayload> | null,
    visionFindings?: any[]
  ): number[] {
    const vector = new Array<number>(TOTAL_INPUT_DIM).fill(0);
    const symptoms = (symptomData?.symptoms || []).map((s) => s.toLowerCase());
    const bodyLocation = ((symptomData as any)?.anatomicalLocation || symptomData?.bodyLocation || '').toLowerCase();
    const additionalNotes = (symptomData?.additionalNotes || '').toLowerCase();
    const combinedText = `${symptoms.join(' ')} ${bodyLocation} ${additionalNotes}`;

    // 1. One-hot / multi-hot symptom encoding against clinical vocabulary
    for (let i = 0; i < CLINICAL_SYMPTOM_VOCABULARY.length; i++) {
      const vocabWord = CLINICAL_SYMPTOM_VOCABULARY[i].toLowerCase();
      let matched = false;

      if (
        symptoms.some((s) => s.includes(vocabWord) || vocabWord.includes(s)) ||
        combinedText.includes(vocabWord)
      ) {
        matched = true;
      } else {
        // Semantic token overlap matching (e.g. "erythema / redness" in "eye" matches "redness of eyes" & "ocular erythema")
        const vocabTokens = vocabWord.split(/[\s_/-]+/).filter((t) => t.length > 3);
        const hasTokenOverlap = vocabTokens.some((vt) => symptoms.some((s) => s.includes(vt)));
        if (hasTokenOverlap) {
          if (vocabWord.includes('eye') || vocabWord.includes('ocular')) {
            if (bodyLocation.includes('eye') || bodyLocation.includes('ophthalm') || bodyLocation.includes('ocular')) {
              matched = true;
            }
          } else if (vocabWord.includes('skin')) {
            if (bodyLocation.includes('skin') || bodyLocation.includes('epidermis')) {
              matched = true;
            }
          } else {
            matched = true;
          }
        }
      }

      if (matched) {
        vector[i] = 1.0;
      }
    }

    // 2. Incorporate vision findings if present
    if (visionFindings && visionFindings.length > 0) {
      for (const finding of visionFindings) {
        const label = (finding.className || finding.label || '').toLowerCase();
        for (let i = 0; i < CLINICAL_SYMPTOM_VOCABULARY.length; i++) {
          if (label.includes(CLINICAL_SYMPTOM_VOCABULARY[i])) {
            vector[i] = Math.max(vector[i], finding.probability || finding.confidence || 0.8);
          }
        }
      }
    }

    // 3. Normalized vitals & metrics
    const offset = SYMPTOM_DIM;
    const v = symptomData?.vitals || {};
    const hr = v.heartRateBpm ?? v.heartRate ?? 74;
    const spo2 = v.oxygenSaturationSpo2 ?? v.oxygenSaturation ?? 98;
    const sys = v.bloodPressureSystolicMmHg ?? v.systolicBP ?? 120;
    const temp = v.temperatureCelsius ?? v.temperature ?? 37.0;
    const rr = v.respiratoryRateBpm ?? v.respiratoryRate ?? 16;
    const pain = symptomData?.painScale ?? 5;
    const duration = symptomData?.durationDays ?? 3;

    vector[offset + 0] = Math.min(1.0, Math.max(0.0, (hr - 40) / 120)); // HR [40..160]
    vector[offset + 1] = Math.min(1.0, Math.max(0.0, (spo2 - 80) / 20)); // SpO2 [80..100]
    vector[offset + 2] = Math.min(1.0, Math.max(0.0, (sys - 80) / 100)); // Systolic BP [80..180]
    vector[offset + 3] = Math.min(1.0, Math.max(0.0, (temp - 35) / 5));  // Temp [35..40]
    vector[offset + 4] = Math.min(1.0, Math.max(0.0, (rr - 8) / 24));   // RR [8..32]
    vector[offset + 5] = Math.min(1.0, Math.max(0.0, pain / 10));       // Pain [0..10]
    vector[offset + 6] = Math.min(1.0, Math.max(0.0, duration / 30));   // Duration [0..30]
    vector[offset + 7] = bodyLocation.length > 0 ? 1.0 : 0.0;

    return vector;
  }

  /**
   * Trains the Neural Network on clinical disease benchmark training permutations.
   * Generates 11,500+ diverse clinical training cases across all 23 WHO ICD-11 classes.
   */
  public static async trainAndPersistModel(samplesPerDisease = 500): Promise<void> {
    console.log(`🧬 [DiseasePredictionML] Training Deep Neural Disease Classifier on Comprehensive Dataset (${samplesPerDisease * CLINICAL_DISEASES.length} cases)...`);
    const model = this.buildModel();

    const xs: number[][] = [];
    const ys: number[][] = [];

    // Box-Muller Gaussian noise generator
    const gaussianRandom = (mean = 0, std = 1): number => {
      let u = 1 - Math.random();
      let v = Math.random();
      let z = Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
      return mean + z * std;
    };

    // Synthesize clinical patient presentations with realistic physiological distributions
    for (let dIdx = 0; dIdx < CLINICAL_DISEASES.length; dIdx++) {
      const disease = CLINICAL_DISEASES[dIdx];

      for (let s = 0; s < samplesPerDisease; s++) {
        // 1. Primary symptom selection (1 to all disease symptoms)
        const symptomCount = Math.max(1, Math.floor(Math.random() * disease.symptoms.length) + 1);
        const shuffled = [...disease.symptoms].sort(() => 0.5 - Math.random());
        const chosenSymptoms = shuffled.slice(0, symptomCount);

        // 2. Realistic Co-morbidity / Non-specific symptom injection (20% probability)
        if (Math.random() < 0.20) {
          const nonSpecific = ['fatigue', 'mild fever', 'headache', 'restlessness', 'nausea'];
          const noiseSym = nonSpecific[Math.floor(Math.random() * nonSpecific.length)];
          if (!chosenSymptoms.includes(noiseSym)) {
            chosenSymptoms.push(noiseSym);
          }
        }

        // 3. Realistic Physiological Vitals Sampling
        let baseHr = disease.urgency === 'EMERGENCY' ? 110 : 75;
        let baseSpo2 = (disease.category === 'Pulmonology' || disease.category === 'Respiratory Diseases') ? 92 : 98;
        let baseTemp = disease.symptoms.some(sym => sym.includes('fever') || sym.includes('chills')) ? 38.6 : 37.0;
        let baseSys = disease.id === 'hypertension' ? 165 : 120;
        let basePain = disease.urgency === 'EMERGENCY' ? 8.5 : (disease.urgency === 'PROMPT_CARE' ? 5.5 : 3.0);

        const hr = Math.round(Math.max(45, Math.min(180, gaussianRandom(baseHr, 8))));
        const spo2 = Math.round(Math.max(75, Math.min(100, gaussianRandom(baseSpo2, 2.5))));
        const temp = Number(Math.max(35.0, Math.min(41.5, gaussianRandom(baseTemp, 0.4))).toFixed(1));
        const sys = Math.round(Math.max(85, Math.min(210, gaussianRandom(baseSys, 12))));
        const pain = Math.round(Math.max(1, Math.min(10, gaussianRandom(basePain, 1.2))));
        const duration = Math.max(1, Math.round(Math.abs(gaussianRandom(4, 3))));

        const syntheticPayload: Partial<SymptomInputPayload> = {
          symptoms: chosenSymptoms,
          bodyLocation: disease.bodyLocations[Math.floor(Math.random() * disease.bodyLocations.length)],
          painScale: pain,
          durationDays: duration,
          vitals: {
            heartRate: hr,
            temperatureCelsius: temp,
            oxygenSaturation: spo2,
            systolicBP: sys
          }
        };

        const x = this.assembleFeatureVector(syntheticPayload);

        // Label smoothing: 0.98 target, distributed remaining 0.02
        const y = new Array<number>(NUM_DISEASE_CLASSES).fill(0.02 / (NUM_DISEASE_CLASSES - 1));
        y[dIdx] = 0.98;

        xs.push(x);
        ys.push(y);
      }
    }

    const xTensor = tf.tensor2d(xs);
    const yTensor = tf.tensor2d(ys);

    console.log(`🧬 [DiseasePredictionML] Commencing neural training (${xs.length} training tensors)...`);
    const history = await model.fit(xTensor, yTensor, {
      epochs: 35,
      batchSize: 64,
      shuffle: true,
      validationSplit: 0.15,
      verbose: 0,
      callbacks: {
        onEpochEnd: (epoch: number, logs?: tf.Logs) => {
          if ((epoch + 1) % 10 === 0 || epoch === 34) {
            console.log(`  [Epoch ${epoch + 1}/35] Loss: ${logs?.loss?.toFixed(4)} | Acc: ${(Number(logs?.acc ?? 0) * 100).toFixed(1)}% | Val Loss: ${logs?.val_loss?.toFixed(4)} | Val Acc: ${(Number(logs?.val_acc ?? 0) * 100).toFixed(1)}%`);
          }
        }
      }
    });

    xTensor.dispose();
    yTensor.dispose();

    if (!fs.existsSync(DISEASE_MODEL_DIR)) {
      fs.mkdirSync(DISEASE_MODEL_DIR, { recursive: true });
    }

    await model.save(`file://${DISEASE_MODEL_DIR}`);
    this.cachedModel = model;
    console.log(`✅ [DiseasePredictionML] Neural Disease Classifier trained on ${xs.length} cases & saved to ${DISEASE_MODEL_DIR}`);
  }

  /**
   * Predicts top differential diagnoses using Neural Network + Hugging Face Ensemble.
   * Completely replaces if-else rules with continuous ML inference.
   */
  public static async predictDifferentials(
    symptomData?: Partial<SymptomInputPayload> | null,
    visionFindings?: any[],
    riskScore: number = 0.5
  ): Promise<DifferentialDiagnosis[]> {
    await this.initialize();

    const featureVector = this.assembleFeatureVector(symptomData, visionFindings);

    // 1. TensorFlow Neural Network Prediction
    let nnProbabilities = new Array<number>(NUM_DISEASE_CLASSES).fill(1 / NUM_DISEASE_CLASSES);
    if (this.cachedModel) {
      const inputTensor = tf.tensor2d([featureVector]);
      const predTensor = this.cachedModel.predict(inputTensor) as tf.Tensor;
      const data = await predTensor.data();
      nnProbabilities = Array.from(data);
      inputTensor.dispose();
      predTensor.dispose();
    }

    // 2. Hugging Face Dense Semantic Embedding Cosine Similarity
    const hfScores = new Array<number>(NUM_DISEASE_CLASSES).fill(0.1);
    if (this.hfPipeline) {
      try {
        const symptoms = (symptomData?.symptoms || []).join(', ');
        const loc = (symptomData as any)?.anatomicalLocation || symptomData?.bodyLocation || 'systemic';
        const notes = symptomData?.additionalNotes || '';
        const patientText = `Patient presenting with ${symptoms} in anatomical location ${loc}. Clinical notes: ${notes}`;

        const output = await this.hfPipeline(patientText, { pooling: 'mean', normalize: true });
        const patientEmb = Array.from(output.data) as number[];

        for (let i = 0; i < CLINICAL_DISEASES.length; i++) {
          const disease = CLINICAL_DISEASES[i];
          const protoEmb = this.prototypeEmbeddings.get(disease.id);
          if (protoEmb) {
            // Cosine similarity
            let dot = 0;
            for (let k = 0; k < patientEmb.length; k++) {
              dot += patientEmb[k] * protoEmb[k];
            }
            // Normalize cosine similarity to [0..1]
            hfScores[i] = Math.max(0.01, (dot + 1) / 2);
          }
        }
      } catch (embErr) {
        console.warn('⚠️ [DiseasePredictionML] Hugging Face inference notice:', embErr);
      }
    }

    // 3. Ensemble Blending: 50% Neural Network + 50% Dense Semantic Embedding
    const scoredDiseases = CLINICAL_DISEASES.map((disease, idx) => {
      const nnP = nnProbabilities[idx] || 0.01;
      const hfS = hfScores[idx] || 0.01;
      const combinedScore = 0.50 * nnP + 0.50 * hfS;

      return {
        disease,
        probability: combinedScore,
      };
    });

    // Sort descending by predicted probability
    scoredDiseases.sort((a, b) => b.probability - a.probability);

    // Normalize probabilities of top 4 differentials to sum cleanly
    const top4 = scoredDiseases.slice(0, 4);
    const sum = top4.reduce((acc, curr) => acc + curr.probability, 0);

    const differentials: DifferentialDiagnosis[] = top4.map((item) => {
      const normalizedProb = sum > 0 ? Number((item.probability / sum).toFixed(2)) : 0.25;
      return {
        condition: item.disease.name,
        icd11Code: item.disease.icd11Code,
        code: item.disease.icd11Code,
        probability: normalizedProb,
        urgency: item.disease.urgency,
      };
    });

    return differentials;
  }

  /**
   * Synchronous clinical disease prediction over all benchmark disease entities.
   * Uses neural network forward pass (.dataSync()) if initialized, or normalized continuous feature projection.
   */
  public static predictAllDiseaseProbabilitiesSync(
    symptomData?: Partial<SymptomInputPayload> | null,
    visionFindings?: any[]
  ): Map<string, { probability: number; logit: number; disease: DiseaseProfile }> {
    const featureVector = this.assembleFeatureVector(symptomData, visionFindings);
    let nnProbabilities = new Array<number>(NUM_DISEASE_CLASSES).fill(1 / NUM_DISEASE_CLASSES);

    if (this.cachedModel) {
      const inputTensor = tf.tensor2d([featureVector]);
      try {
        const predTensor = this.cachedModel.predict(inputTensor) as tf.Tensor;
        const data = predTensor.dataSync();
        nnProbabilities = Array.from(data);
        predTensor.dispose();
      } finally {
        inputTensor.dispose();
      }
    } else {
      const symptoms = (symptomData?.symptoms || []).map((s) => s.toLowerCase());
      const body = ((symptomData as any)?.anatomicalLocation || symptomData?.bodyLocation || '').toLowerCase();

      for (let i = 0; i < CLINICAL_DISEASES.length; i++) {
        const d = CLINICAL_DISEASES[i];
        let activation = 0.1;
        for (const sym of d.symptoms) {
          if (symptoms.some((s) => s.includes(sym.toLowerCase()) || sym.toLowerCase().includes(s))) {
            activation += 1.5;
          }
        }
        for (const loc of d.bodyLocations) {
          if (body.length > 0 && (body.includes(loc.toLowerCase()) || loc.toLowerCase().includes(body))) {
            activation += 2.0;
          }
        }
        nnProbabilities[i] = Math.exp(activation);
      }
      const sum = nnProbabilities.reduce((a, b) => a + b, 0) || 1.0;
      nnProbabilities = nnProbabilities.map((p) => p / sum);
    }

    const resultMap = new Map<string, { probability: number; logit: number; disease: DiseaseProfile }>();
    for (let i = 0; i < CLINICAL_DISEASES.length; i++) {
      const d = CLINICAL_DISEASES[i];
      const prob = Math.max(1e-5, Math.min(1.0 - 1e-5, nnProbabilities[i]));
      const logit = Math.log(prob / (1 - prob));
      resultMap.set(d.icd11Code.toUpperCase(), { probability: prob, logit, disease: d });
    }
    return resultMap;
  }

  /**
   * Asynchronous clinical disease prediction combining Neural Network + Hugging Face dense embeddings.
   */
  public static async predictAllDiseaseProbabilities(
    symptomData?: Partial<SymptomInputPayload> | null,
    visionFindings?: any[]
  ): Promise<Map<string, { probability: number; logit: number; disease: DiseaseProfile }>> {
    await this.initialize();

    const featureVector = this.assembleFeatureVector(symptomData, visionFindings);

    // 1. TensorFlow Neural Network Prediction
    let nnProbabilities = new Array<number>(NUM_DISEASE_CLASSES).fill(1 / NUM_DISEASE_CLASSES);
    if (this.cachedModel) {
      const inputTensor = tf.tensor2d([featureVector]);
      try {
        const predTensor = this.cachedModel.predict(inputTensor) as tf.Tensor;
        const data = await predTensor.data();
        nnProbabilities = Array.from(data);
        predTensor.dispose();
      } finally {
        inputTensor.dispose();
      }
    }

    // 2. Hugging Face Dense Semantic Embedding Cosine Similarity
    const hfScores = new Array<number>(NUM_DISEASE_CLASSES).fill(0.1);
    if (this.hfPipeline) {
      try {
        const symptoms = (symptomData?.symptoms || []).join(', ');
        const loc = (symptomData as any)?.anatomicalLocation || symptomData?.bodyLocation || 'systemic';
        const notes = symptomData?.additionalNotes || '';
        const patientText = `Patient presenting with ${symptoms} in anatomical location ${loc}. Clinical notes: ${notes}`;

        const output = await this.hfPipeline(patientText, { pooling: 'mean', normalize: true });
        const patientEmb = Array.from(output.data) as number[];

        for (let i = 0; i < CLINICAL_DISEASES.length; i++) {
          const disease = CLINICAL_DISEASES[i];
          const protoEmb = this.prototypeEmbeddings.get(disease.id);
          if (protoEmb) {
            let dot = 0;
            for (let k = 0; k < patientEmb.length; k++) {
              dot += patientEmb[k] * protoEmb[k];
            }
            hfScores[i] = Math.max(0.01, (dot + 1) / 2);
          }
        }
      } catch (embErr) {
        console.warn('⚠️ [DiseasePredictionML] Hugging Face inference notice:', embErr);
      }
    }

    const resultMap = new Map<string, { probability: number; logit: number; disease: DiseaseProfile }>();
    for (let i = 0; i < CLINICAL_DISEASES.length; i++) {
      const d = CLINICAL_DISEASES[i];
      const nnP = nnProbabilities[i] || 0.01;
      const hfS = hfScores[i] || 0.01;
      const combined = 0.50 * nnP + 0.50 * hfS;
      const safeProb = Math.max(1e-5, Math.min(1.0 - 1e-5, combined));
      const logit = Math.log(safeProb / (1 - safeProb));
      resultMap.set(d.icd11Code.toUpperCase(), { probability: safeProb, logit, disease: d });
    }
    return resultMap;
  }
}

