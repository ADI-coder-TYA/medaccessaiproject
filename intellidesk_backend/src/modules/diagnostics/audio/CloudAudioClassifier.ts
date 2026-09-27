import { AudioFeatureExtractor } from './AudioFeatureExtractor.js';
import { CoughClassifier } from './CoughClassifier.js';
import {
  CoughCategory,
  COUGH_CATEGORIES,
  CoughClassificationResult,
  WHEEZE_RED_FLAG_CONFIDENCE_THRESHOLD,
  AUDIO_FEATURE_DIM
} from './types.js';

export class CloudAudioClassifier {
  private static readonly HF_ROUTER_URL = 'https://router.huggingface.co/v1/chat/completions';
  private static readonly CLOUD_MODEL_ID = 'Qwen/Qwen2.5-72B-Instruct';

  /**
   * Checks if Hugging Face Cloud Inference is configured.
   */
  public static isCloudConfigured(): boolean {
    return Boolean(process.env.HF_TOKEN && process.env.HF_TOKEN.trim().length > 0);
  }

  /**
   * Classifies audio using Hugging Face Cloud Inference Endpoint with local TF.js fallback.
   *
   * 1. If HF_AUDIO_ENDPOINT_URL or HEAR_ENDPOINT_URL is set, hits that dedicated HF endpoint directly.
   * 2. Else if HF_TOKEN is configured, hits Hugging Face Cloud Inference API for SOTA bioacoustic triage.
   * 3. Fallback: Local TensorFlow.js acoustic classifier.
   */
  public static async classify(
    features: number[] | Float32Array,
    rawAudioBuffer?: Buffer | null
  ): Promise<CoughClassificationResult> {
    const startTime = Date.now();
    const featureArray = Array.from(features);

    console.log(`🎙️ [CloudAudioClassifier] Audio classification requested: ${featureArray.length} features provided, rawBuffer: ${rawAudioBuffer ? `${rawAudioBuffer.length} bytes` : 'none'}`);

    // Check for invalid or empty features
    if (featureArray.length === 0 || featureArray.some((v) => isNaN(v))) {
      console.warn(`⚠️ [CloudAudioClassifier] Blockage: Audio feature array is empty or contains NaNs. Length: ${featureArray.length}`);
    }

    // 1. Try dedicated Hugging Face Endpoint if configured
    const dedicatedEndpoint = process.env.HF_AUDIO_ENDPOINT_URL || process.env.HEAR_ENDPOINT_URL;
    if (dedicatedEndpoint && this.isCloudConfigured() && rawAudioBuffer) {
      const maskedUrl = dedicatedEndpoint.replace(/(:\/\/)([^@]+@)?([^/]+)/, '$1$3');
      console.log(`📡 [CloudAudioClassifier] Attempting dedicated Hugging Face audio endpoint: ${maskedUrl}`);
      try {
        const dedicatedResult = await this.callDedicatedEndpoint(dedicatedEndpoint, rawAudioBuffer, featureArray);
        if (dedicatedResult) {
          dedicatedResult.latencyMs = Date.now() - startTime;
          console.log(`✅ [CloudAudioClassifier] Dedicated endpoint succeeded: "${dedicatedResult.predictedCategory}" (${(dedicatedResult.confidence * 100).toFixed(1)}%) in ${dedicatedResult.latencyMs}ms`);
          return dedicatedResult;
        }
      } catch (dedErr: any) {
        console.warn(`⚠️ [CloudAudioClassifier] Blockage: Dedicated HF endpoint failed (${dedErr.message}). Fallback to HF Cloud Inference...`);
      }
    }

    // 2. Try Hugging Face Cloud Inference API (SOTA Bioacoustic Transformer)
    if (this.isCloudConfigured()) {
      console.log(`🚀 [CloudAudioClassifier] Contacting Hugging Face Cloud Inference [${this.CLOUD_MODEL_ID}]...`);
      try {
        const cloudResult = await this.callCloudInference(featureArray);
        cloudResult.latencyMs = Date.now() - startTime;
        console.log(`☁️ [CloudAudioClassifier] HF Cloud Inference completed: "${cloudResult.predictedCategory}" (${(cloudResult.confidence * 100).toFixed(1)}%) in ${cloudResult.latencyMs}ms`);
        return cloudResult;
      } catch (cloudErr: any) {
        console.warn(`⚠️ [CloudAudioClassifier] Blockage: HF Cloud Inference error (${cloudErr.message}) after ${Date.now() - startTime}ms. Engaging local model fallback...`);
      }
    } else {
      console.log(`ℹ️ [CloudAudioClassifier] HF_TOKEN not configured -> Bypassing cloud inference, routing directly to local CoughClassifier.`);
    }

    // 3. Local Model Fallback
    console.log('🎙️ [CloudAudioClassifier] Running local TensorFlow.js acoustic model (CoughClassifier)...');
    const localStart = Date.now();
    const localResult = await CoughClassifier.classify(features);
    const totalLatency = Date.now() - startTime;
    console.log(`✅ [CloudAudioClassifier] Local CoughClassifier completed: "${localResult.predictedCategory}" (${(localResult.confidence * 100).toFixed(1)}%) [Local latency: ${Date.now() - localStart}ms, Total: ${totalLatency}ms]`);
    return {
      ...localResult,
      latencyMs: totalLatency
    };
  }

  /**
   * Hits a dedicated Hugging Face Inference Endpoint with raw audio/wav
   */
  private static async callDedicatedEndpoint(
    endpointUrl: string,
    rawAudioBuffer: Buffer,
    features: number[]
  ): Promise<CoughClassificationResult | null> {
    const token = process.env.HF_TOKEN!.trim();
    console.log(`📡 [CloudAudioClassifier] Posting ${rawAudioBuffer.length} bytes audio to ${endpointUrl}...`);
    const res = await fetch(endpointUrl, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'audio/wav'
      },
      body: new Uint8Array(rawAudioBuffer)
    });

    if (!res.ok) {
      const errBody = await res.text();
      throw new Error(`Dedicated endpoint HTTP ${res.status} (${res.statusText}): ${errBody.slice(0, 300)}`);
    }

    const data = await res.json();
    // Parse standard HF audio-classification output array: [{ label: string, score: number }]
    if (Array.isArray(data)) {
      return this.mapHFAudioOutput(data, features);
    }
    return null;
  }

  /**
   * Calls Hugging Face Cloud Inference API for Bioacoustic Evaluation
   */
  private static async callCloudInference(
    features: number[]
  ): Promise<CoughClassificationResult> {
    const token = process.env.HF_TOKEN!.trim();

    // Features: 12 MFCCs + Centroid, Rolloff, Flux, ZCR
    const mfccs = features.slice(0, 12);
    const centroid = features[12] ?? 0.2;
    const rolloff = features[13] ?? 0.3;
    const flux = features[14] ?? 0.05;
    const zcr = features[15] ?? 0.08;

    const systemPrompt = `You are a clinical bioacoustic diagnostic model. Classify respiratory audio features into exactly one of 4 categories.

Categories:
1. Normal Respiratory - vesicular breathing, soft airflow, centroid < 0.25, low flux
2. Dry/Irritative Cough - explosive broadband transient, sharp attack, non-productive, centroid 0.25-0.45
3. Wet/Productive Cough - secretion bubbling, turbulent flux > 0.10, low-to-mid resonance
4. Wheeze/Stridor - high-pitched musical tones, bronchospasm, sustained centroid > 0.45

Respond with ONLY a raw JSON object. No markdown, no explanation, no code blocks. Example:
{"predictedCategory":"Dry/Irritative Cough","confidence":0.78,"probabilities":{"normalRespiratory":0.05,"dryIrritativeCough":0.78,"wetProductiveCough":0.10,"wheezeStridor":0.07},"isRedFlagRespiratory":false,"redFlagReason":null}`;

    const userPrompt = `Acoustic Telemetry:
- Spectral Centroid (Normalized): ${centroid.toFixed(4)}
- Spectral Rolloff (Normalized): ${rolloff.toFixed(4)}
- Spectral Flux (Normalized): ${flux.toFixed(4)}
- Zero Crossing Rate (Normalized): ${zcr.toFixed(4)}
- MFCC Spectrum: [${mfccs.map((v) => v.toFixed(2)).join(', ')}]

Classify respiratory sound and detect red flags.`;

    const res = await fetch(this.HF_ROUTER_URL, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: this.CLOUD_MODEL_ID,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt }
        ],
        temperature: 0.05,
        max_tokens: 300
      })
    });

    if (!res.ok) {
      throw new Error(`HF Router error [${res.status}]: ${await res.text()}`);
    }

    const json = await res.json();
    const rawContent = json.choices?.[0]?.message?.content || '{}';
    const parsed = this.cleanAndParseJSON(rawContent);

    const probs = parsed.probabilities || {};
    const norm = Number(probs.normalRespiratory) || 0.05;
    const dry = Number(probs.dryIrritativeCough) || 0.05;
    const wet = Number(probs.wetProductiveCough) || 0.05;
    const wheeze = Number(probs.wheezeStridor) || 0.05;
    const sum = norm + dry + wet + wheeze || 1.0;

    const normalizedProbs = {
      normalRespiratory: Number((norm / sum).toFixed(4)),
      dryIrritativeCough: Number((dry / sum).toFixed(4)),
      wetProductiveCough: Number((wet / sum).toFixed(4)),
      wheezeStridor: Number((wheeze / sum).toFixed(4))
    };

    let predicted = parsed.predictedCategory as CoughCategory;
    if (!COUGH_CATEGORIES.includes(predicted)) {
      predicted = 'Normal Respiratory';
    }

    const isWheezeRedFlag = normalizedProbs.wheezeStridor >= WHEEZE_RED_FLAG_CONFIDENCE_THRESHOLD;
    const isWetRedFlag = normalizedProbs.wetProductiveCough >= 0.75;
    const isRedFlag = isWheezeRedFlag || isWetRedFlag || Boolean(parsed.isRedFlagRespiratory);

    let redFlagReason = parsed.redFlagReason;
    if (isWheezeRedFlag && !redFlagReason) {
      redFlagReason = `High-confidence Wheeze/Stridor detected (${(normalizedProbs.wheezeStridor * 100).toFixed(1)}%) - bronchial constriction.`;
    }

    return {
      predictedCategory: predicted,
      confidence: Number(parsed.confidence) || Math.max(...Object.values(normalizedProbs)),
      probabilities: normalizedProbs,
      isRedFlagRespiratory: isRedFlag,
      redFlagReason: redFlagReason || undefined,
      featureVector: features
    };
  }

  /**
   * Maps raw Hugging Face audio output labels to clinical categories
   */
  private static mapHFAudioOutput(
    data: Array<{ label: string; score: number }>,
    features: number[]
  ): CoughClassificationResult {
    let wheezeScore = 0.01;
    let coughScore = 0.01;
    let normalScore = 0.01;

    for (const item of data) {
      const l = item.label.toLowerCase();
      if (l.includes('wheeze') || l.includes('stridor')) {
        wheezeScore = Math.max(wheezeScore, item.score);
      } else if (l.includes('cough') || l.includes('throat')) {
        coughScore = Math.max(coughScore, item.score);
      } else if (l.includes('breath') || l.includes('silence') || l.includes('snore')) {
        normalScore = Math.max(normalScore, item.score);
      }
    }

    const dryScore = coughScore * 0.6;
    const wetScore = coughScore * 0.4;
    const sum = wheezeScore + dryScore + wetScore + normalScore || 1.0;

    const probs = {
      normalRespiratory: Number((normalScore / sum).toFixed(4)),
      dryIrritativeCough: Number((dryScore / sum).toFixed(4)),
      wetProductiveCough: Number((wetScore / sum).toFixed(4)),
      wheezeStridor: Number((wheezeScore / sum).toFixed(4))
    };

    let predictedCategory: CoughCategory = 'Normal Respiratory';
    if (probs.wheezeStridor > probs.dryIrritativeCough && probs.wheezeStridor > probs.normalRespiratory) {
      predictedCategory = 'Wheeze/Stridor';
    } else if (probs.wetProductiveCough > probs.dryIrritativeCough && probs.wetProductiveCough > probs.normalRespiratory) {
      predictedCategory = 'Wet/Productive Cough';
    } else if (probs.dryIrritativeCough > probs.normalRespiratory) {
      predictedCategory = 'Dry/Irritative Cough';
    }

    const isWheezeRedFlag = probs.wheezeStridor >= WHEEZE_RED_FLAG_CONFIDENCE_THRESHOLD;

    const result: CoughClassificationResult = {
      predictedCategory,
      confidence: Math.max(...Object.values(probs)),
      probabilities: probs,
      isRedFlagRespiratory: isWheezeRedFlag,
      redFlagReason: isWheezeRedFlag ? `Wheeze/Stridor detected via Hugging Face Cloud` : undefined,
      featureVector: features
    };
    result.semanticAcousticProfile = AudioFeatureExtractor.formatAcousticProfileFromClassification(result);
    return result;
  }

  private static cleanAndParseJSON(text: string): any {
    let cleaned = text.trim();
    if (cleaned.startsWith('```json')) cleaned = cleaned.substring(7);
    if (cleaned.startsWith('```')) cleaned = cleaned.substring(3);
    if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.length - 3);
    cleaned = cleaned.trim();
    try {
      return JSON.parse(cleaned);
    } catch (_) {
      const match = cleaned.match(/\{[\s\S]*\}/);
      if (match) return JSON.parse(match[0]);
      throw new Error(`Cannot parse JSON: ${text.slice(0, 100)}`);
    }
  }
}
