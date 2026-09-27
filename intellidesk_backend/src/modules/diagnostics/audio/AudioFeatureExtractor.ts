import WavDecoder from 'wav-decoder';
import Meyda from 'meyda';
import {
  TARGET_SAMPLE_RATE,
  AUDIO_FEATURE_DIM,
  MFCC_COUNT,
  FRAME_SIZE,
  HOP_SIZE,
  AudioFeatureExtractionResult,
  SpectralMetrics,
  CoughClassificationResult,
  ACOUSTIC_MEANS,
  ACOUSTIC_STDS
} from './types.js';

export class AudioFeatureExtractor {
  /**
   * Universal audio buffer processor:
   * 1. Decodes WAV / PCM buffers
   * 2. Resamples to 16,000 Hz Mono 16-bit PCM
   * 3. Computes 12 MFCCs + Spectral Centroid + Rolloff + Flux + ZCR with Energy Weighting
   * 4. Z-score standardizes all 16 acoustic features to zero-mean unit-variance
   */
  public static async extractFeatures(
    audioBuffer?: Buffer | Uint8Array | null
  ): Promise<AudioFeatureExtractionResult> {
    if (!audioBuffer || audioBuffer.length === 0) {
      throw new Error("Invalid Audio Stream: Zero/NaN buffer received from DSP");
    }

    // Step 1: Decode Audio Buffer to Mono Float32Array
    let rawPcm: Float32Array;
    let sampleRate = TARGET_SAMPLE_RATE;

    try {
      const uint8 = audioBuffer instanceof Buffer ? audioBuffer : Buffer.from(audioBuffer);
      // Check for standard RIFF/WAV header
      if (uint8.length >= 12 && uint8.toString('ascii', 0, 4) === 'RIFF' && uint8.toString('ascii', 8, 12) === 'WAVE') {
        const decoded = await WavDecoder.decode(uint8);
        sampleRate = decoded.sampleRate || TARGET_SAMPLE_RATE;
        if (decoded.channelData.length > 1) {
          // Average stereo / multi-channel to mono
          rawPcm = new Float32Array(decoded.channelData[0].length);
          for (let i = 0; i < rawPcm.length; i++) {
            let sum = 0;
            for (let c = 0; c < decoded.channelData.length; c++) {
              sum += decoded.channelData[c][i];
            }
            rawPcm[i] = sum / decoded.channelData.length;
          }
        } else if (decoded.channelData.length === 1) {
          rawPcm = decoded.channelData[0];
        } else {
          rawPcm = this.parseRawInt16Pcm(uint8);
        }
      } else {
        // Fallback: Parse raw PCM byte stream
        rawPcm = this.parseRawInt16Pcm(uint8);
      }
    } catch (_) {
      // Robust fallback on malformed container
      const uint8 = audioBuffer instanceof Buffer ? audioBuffer : Buffer.from(audioBuffer);
      rawPcm = this.parseRawInt16Pcm(uint8);
    }

    if (!rawPcm || rawPcm.length < 128) {
      throw new Error("Invalid Audio Stream: Audio buffer too short or empty");
    }

    // Guardrail: Calculate Root Mean Square (RMS) volume on the raw PCM buffer
    let energySum = 0;
    for (let i = 0; i < rawPcm.length; i++) {
      energySum += rawPcm[i] * rawPcm[i];
    }
    const rms = Math.sqrt(energySum / rawPcm.length);
    if (rms < 0.01) {
      throw new Error("No cough sound detected. Please speak or cough directly into the microphone.");
    }

    // Step 2: Mandatory 16 kHz Mono Resampling
    let resampledPcm: Float32Array;
    let isResampled = false;
    if (sampleRate !== TARGET_SAMPLE_RATE) {
      resampledPcm = this.resampleLinear(rawPcm, sampleRate, TARGET_SAMPLE_RATE);
      isResampled = true;
    } else {
      resampledPcm = rawPcm;
    }

    const durationSeconds = Number((resampledPcm.length / TARGET_SAMPLE_RATE).toFixed(2));

    // Peak amplitude normalization to prevent clipping & stabilize frame energy
    this.peakNormalize(resampledPcm);

    // Step 3: Frame-by-Frame STFT & Feature Extraction
    const { mfccAverages, spectralMetrics } = this.computeAcousticMetrics(resampledPcm, TARGET_SAMPLE_RATE);

    // Step 4: Z-score standardization across all 16 features
    const featureVector = this.assembleAndScaleFeatureVector(mfccAverages, spectralMetrics);

    console.log(`🎙️ [AudioFeatureExtractor] Decoded acoustic sample: ${durationSeconds.toFixed(2)}s | SampleRate: ${sampleRate}Hz -> ${TARGET_SAMPLE_RATE}Hz (Resampled: ${isResampled})`);
    console.log(`📊 [AudioFeatureExtractor] Meyda 16-D Acoustic Vector: Centroid=${spectralMetrics.centroid.toFixed(4)} | Rolloff=${spectralMetrics.rolloff.toFixed(4)} | Flux=${spectralMetrics.flux.toFixed(4)} | ZCR=${spectralMetrics.zcr.toFixed(4)}`);

    const partialResult = {
      featureVector,
      originalSampleRate: sampleRate,
      resampledRate: TARGET_SAMPLE_RATE,
      durationSeconds,
      pcmSampleCount: resampledPcm.length,
      isResampled,
      spectralMetrics,
      mfccCoefficients: mfccAverages
    };

    const semanticAcousticProfile = this.formatAcousticProfileForLLM(partialResult);

    return {
      ...partialResult,
      semanticAcousticProfile
    };
  }

  /**
   * Resamples PCM samples to target sample rate using linear interpolation.
   */
  public static resampleLinear(
    input: Float32Array,
    inputRate: number,
    targetRate: number
  ): Float32Array {
    if (inputRate === targetRate || input.length === 0) return input;

    const ratio = inputRate / targetRate;
    const outputLength = Math.max(1, Math.round(input.length / ratio));
    const output = new Float32Array(outputLength);

    for (let i = 0; i < outputLength; i++) {
      const originalIdx = i * ratio;
      const lower = Math.floor(originalIdx);
      const upper = Math.min(input.length - 1, lower + 1);
      const fraction = originalIdx - lower;

      const sample1 = input[lower] || 0;
      const sample2 = input[upper] || 0;
      output[i] = sample1 + fraction * (sample2 - sample1);
    }

    return output;
  }

  /**
   * Formats raw Meyda DSP acoustic features into rich, clinical semantic text
   * structured specifically for LLMs (Qwen 2.5 Instruct) to perform medical reasoning.
   */
  public static formatAcousticProfileForLLM(
    result: {
      spectralMetrics: SpectralMetrics;
      mfccCoefficients: number[];
      durationSeconds: number;
    },
    classification?: CoughClassificationResult | null
  ): string {
    const { spectralMetrics, mfccCoefficients, durationSeconds } = result;

    const category = classification?.predictedCategory || 'Respiratory Sound Captured';
    const confidenceStr = classification?.confidence
      ? `${(classification.confidence * 100).toFixed(1)}%`
      : 'Measured';
    const isRedFlag = classification?.isRedFlagRespiratory
      ? '⚠️ RESPIRATORY RED-FLAG DETECTED'
      : 'Standard Respiratory Acoustic Pattern';

    // 1. Spectral Centroid (Pitch / Brightness in Hz)
    const centroidHz = Math.round(spectralMetrics.centroid * (TARGET_SAMPLE_RATE / 2));
    let centroidDesc = '';
    if (centroidHz > 1500) {
      centroidDesc = `${centroidHz} Hz (High-Frequency / Bright — typical of upper airway constriction, stridor, or expiratory wheeze harmonics)`;
    } else if (centroidHz > 700) {
      centroidDesc = `${centroidHz} Hz (Mid-Frequency — characteristic of active bronchial cough with mucus/fluid mobilization)`;
    } else {
      centroidDesc = `${centroidHz} Hz (Low-Frequency / Deep — characteristic of deep bronchial rhonchi or lower tracheal resonance)`;
    }

    // 2. High-Frequency Spectral Rolloff (85% energy boundary)
    const rolloffHz = Math.round(spectralMetrics.rolloff * (TARGET_SAMPLE_RATE / 2));
    let rolloffDesc = '';
    if (rolloffHz > 3200) {
      rolloffDesc = `${rolloffHz} Hz (Broadband Dispersion — significant high-frequency acoustic harmonics present)`;
    } else {
      rolloffDesc = `${rolloffHz} Hz (Band-Limited Energy — acoustic power concentrated in lower pulmonary frequencies)`;
    }

    // 3. Spectral Flux (Attack Dynamicity)
    let fluxDesc = '';
    if (spectralMetrics.flux > 0.035) {
      fluxDesc = `${spectralMetrics.flux.toFixed(4)} (Rapid Paroxysmal Attack — sudden explosive cough burst characteristic of acute coughing bouts)`;
    } else {
      fluxDesc = `${spectralMetrics.flux.toFixed(4)} (Smooth / Continuous Onset — steady acoustic energy flow)`;
    }

    // 4. Airway Turbulence & Friction (Zero-Crossing Rate)
    let zcrDesc = '';
    if (spectralMetrics.zcr > 0.10) {
      zcrDesc = `${spectralMetrics.zcr.toFixed(4)} (High Airflow Turbulence — high breathiness and airway friction, typical of narrowed bronchi)`;
    } else if (spectralMetrics.zcr > 0.045) {
      zcrDesc = `${spectralMetrics.zcr.toFixed(4)} (Moderate Airflow Friction — characteristic of active expiratory cough phase)`;
    } else {
      zcrDesc = `${spectralMetrics.zcr.toFixed(4)} (Low Noise Component — predominantly laminar or tonal sound)`;
    }

    // 5. Cepstral Timbre (MFCC Resonances)
    const mfccResonance = (mfccCoefficients[0] ?? 0) > 0
      ? 'Strong lower-frequency pulmonary resonance (MFCC 1-3 elevation), consistent with lower respiratory airway vibration'
      : 'Balanced harmonic timbre across speech and respiratory spectrum';

    // 6. Clinical Takeaway for LLM reasoning
    let clinicalTakeaway = '';
    if (category.includes('Wheeze') || category.includes('Stridor')) {
      clinicalTakeaway = 'Bioacoustic signs indicate obstructive airway narrowing, bronchospasm, or asthma/bronchiolitis exacerbation.';
    } else if (category.includes('Wet') || category.includes('Productive')) {
      clinicalTakeaway = 'Bioacoustic signs indicate active secretions in the lower respiratory tract (e.g., Acute Bronchitis, Pneumonia).';
    } else if (category.includes('Dry')) {
      clinicalTakeaway = 'Bioacoustic signs indicate irritative, non-productive inflammation (e.g., Acute URTI, viral tracheitis).';
    } else {
      clinicalTakeaway = 'Bioacoustic signs show normal laminar respiratory sounds without pathological adventitious components.';
    }

    return [
      `Auscultation Sound Phenotype: ${category} (Confidence: ${confidenceStr}) [${isRedFlag}]`,
      `Recording Duration: ${durationSeconds}s`,
      `Spectral Frequency Centroid: ${centroidDesc}`,
      `High-Frequency Rolloff (85% energy boundary): ${rolloffDesc}`,
      `Spectral Flux (Attack Dynamicity): ${fluxDesc}`,
      `Airway Turbulence (Zero-Crossing Rate): ${zcrDesc}`,
      `Cepstral Timbre (MFCC Resonances): ${mfccResonance}`,
      `Clinical Diagnostic Takeaway: ${clinicalTakeaway}`
    ].join('\n');
  }

  /**
   * Helper to format an LLM acoustic section from a CoughClassificationResult alone
   */
  public static formatAcousticProfileFromClassification(
    classification: CoughClassificationResult
  ): string {
    const category = classification.predictedCategory;
    const confidenceStr = `${(classification.confidence * 100).toFixed(1)}%`;
    const isRedFlag = classification.isRedFlagRespiratory
      ? '⚠️ RESPIRATORY RED-FLAG DETECTED'
      : 'Standard Respiratory Pattern';

    let takeaway = '';
    if (category.includes('Wheeze') || category.includes('Stridor')) {
      takeaway = 'Acoustic signs strongly correlate with obstructive bronchospasm, asthma flare, or acute bronchiolitis.';
    } else if (category.includes('Wet') || category.includes('Productive')) {
      takeaway = 'Acoustic signs strongly correlate with active fluid/phlegm secretion in lower respiratory tract (e.g. Acute Bronchitis, Pneumonia).';
    } else if (category.includes('Dry')) {
      takeaway = 'Acoustic signs indicate irritative, non-productive inflammation (e.g. Acute URTI, early viral tracheitis).';
    } else {
      takeaway = 'Acoustic pattern shows normal laminar respiratory sounds.';
    }

    return [
      `Auscultation Sound Phenotype: ${category} (Confidence: ${confidenceStr}) [${isRedFlag}]`,
      `Class Probabilities: Normal=${(classification.probabilities.normalRespiratory * 100).toFixed(1)}%, Dry=${(classification.probabilities.dryIrritativeCough * 100).toFixed(1)}%, Wet=${(classification.probabilities.wetProductiveCough * 100).toFixed(1)}%, Wheeze=${(classification.probabilities.wheezeStridor * 100).toFixed(1)}%`,
      `Clinical Diagnostic Takeaway: ${takeaway}`
    ].join('\n');
  }

  /**
   * Computes 12 MFCC coefficients + Spectral Metrics (Centroid, Rolloff, Flux, ZCR)
   * with Meyda DSP native audio extraction and energy-weighted frame pooling.
   */
  private static computeAcousticMetrics(
    pcm: Float32Array,
    sampleRate: number
  ): { mfccAverages: number[]; spectralMetrics: SpectralMetrics } {
    const frameSize = FRAME_SIZE;
    const hopSize = HOP_SIZE;
    const numFrames = Math.max(1, Math.floor((pcm.length - frameSize) / hopSize) + 1);
    const nyquist = sampleRate / 2;

    // Configure Meyda DSP session parameters
    const meyda: any = Meyda;
    meyda.sampleRate = sampleRate;
    meyda.bufferSize = frameSize;
    meyda.numberOfMFCCCoefficients = MFCC_COUNT;
    meyda.windowingFunction = 'hamming';

    interface FrameData {
      energy: number;
      centroid: number;
      rolloff: number;
      flux: number;
      zcr: number;
      mfccs: number[];
    }
    const frames: FrameData[] = [];
    let previousSpectrum: Float32Array | null = null;
    let maxEnergy = 0;

    for (let f = 0; f < numFrames; f++) {
      const start = f * hopSize;
      const slice = pcm.subarray(start, start + frameSize);
      let frame: Float32Array;
      if (slice.length < frameSize) {
        frame = new Float32Array(frameSize);
        frame.set(slice);
      } else {
        frame = slice;
      }

      // Extract native DSP acoustic features via Meyda
      const mFeatures = meyda.extract(
        ['mfcc', 'spectralCentroid', 'spectralRolloff', 'zcr', 'energy', 'amplitudeSpectrum'],
        frame
      );

      if (!mFeatures) continue;

      const energy = Number(mFeatures.energy || 0);
      if (energy > maxEnergy) maxEnergy = energy;

      // Robust spectral flux calculation across consecutive amplitude spectra
      let flux = 0;
      const currentSpectrum = mFeatures.amplitudeSpectrum;
      if (previousSpectrum && currentSpectrum && currentSpectrum.length === previousSpectrum.length) {
        let diffSum = 0;
        for (let k = 0; k < currentSpectrum.length; k++) {
          const diff = currentSpectrum[k] - previousSpectrum[k];
          diffSum += diff * diff;
        }
        flux = Math.sqrt(diffSum) / (energy || 1.0);
      }
      if (currentSpectrum) {
        previousSpectrum = new Float32Array(currentSpectrum);
      }

      // Normalize features to [0.0, 1.0] for stable pooling
      // Meyda spectralCentroid returns a bin index in [0, frameSize/2]: normalize to [0, 1]
      const rawCentroid = mFeatures.spectralCentroid;
      const centroidNorm = (rawCentroid != null && isFinite(rawCentroid) && rawCentroid >= 0)
        ? Math.min(1.0, rawCentroid / (frameSize / 2))
        : 0.0;
      // Meyda spectralRolloff returns frequency in Hz: normalize by Nyquist
      const rawRolloff = mFeatures.spectralRolloff;
      const rolloffNorm = (rawRolloff != null && isFinite(rawRolloff) && rawRolloff >= 0)
        ? Math.min(1.0, Math.max(0.0, rawRolloff / nyquist))
        : 0.0;
      // Meyda zcr returns count of zero-crossings per bufferSize: normalize by frameSize
      const rawZcr = mFeatures.zcr;
      const zcrNorm = (rawZcr != null && isFinite(rawZcr) && rawZcr >= 0)
        ? Math.min(1.0, Math.max(0.0, rawZcr / frameSize))
        : 0.0;

      const rawMfccs: number[] = Array.isArray(mFeatures.mfcc) ? mFeatures.mfcc : [];
      const mfccs: number[] = rawMfccs.slice(0, MFCC_COUNT);
      while (mfccs.length < MFCC_COUNT) {
        mfccs.push(0);
      }

      frames.push({
        energy,
        centroid: centroidNorm,
        rolloff: rolloffNorm,
        flux: Math.min(1.0, Math.max(0.0, flux)),
        zcr: zcrNorm,
        mfccs
      });
    }

    // Energy-Weighted Acoustic Frame Accumulation (VAD Weighting)
    let weightSum = 0;
    let centroidW = 0;
    let rolloffW = 0;
    let fluxW = 0;
    let zcrW = 0;
    const mfccW = new Array<number>(MFCC_COUNT).fill(0);

    for (const fr of frames) {
      const w = Math.pow(fr.energy / (maxEnergy || 1.0), 1.5) + 0.05;
      weightSum += w;
      centroidW += fr.centroid * w;
      rolloffW += fr.rolloff * w;
      fluxW += fr.flux * w;
      zcrW += fr.zcr * w;
      for (let m = 0; m < MFCC_COUNT; m++) {
        mfccW[m] += fr.mfccs[m] * w;
      }
    }

    const mfccAverages = mfccW.map(val => Number((val / (weightSum || 1.0)).toFixed(6)));

    const spectralMetrics: SpectralMetrics = {
      centroid: Number((centroidW / (weightSum || 1.0)).toFixed(6)),
      rolloff: Number((rolloffW / (weightSum || 1.0)).toFixed(6)),
      flux: Number((fluxW / (weightSum || 1.0)).toFixed(6)),
      zcr: Number((zcrW / (weightSum || 1.0)).toFixed(6))
    };

    return { mfccAverages, spectralMetrics };
  }

  /**
   * Z-Score Standardizes all 16 acoustic features to zero-mean, unit-variance Gaussian.
   * - Indices 0..11: 12 MFCC coefficients (standardized via baseline mean/std)
   * - Index 12: Spectral Centroid
   * - Index 13: Spectral Rolloff
   * - Index 14: Spectral Flux
   * - Index 15: Zero Crossing Rate
   * All values clamped to [-4.0, +4.0] to eliminate extreme outlier saturation.
   */
  public static assembleAndScaleFeatureVector(
    mfccs: number[],
    spectral: SpectralMetrics
  ): number[] {
    const rawVector = new Array<number>(AUDIO_FEATURE_DIM).fill(0.0);

    for (let i = 0; i < MFCC_COUNT; i++) {
      rawVector[i] = mfccs[i] !== undefined ? mfccs[i] : 0.0;
    }
    rawVector[12] = spectral.centroid;
    rawVector[13] = spectral.rolloff;
    rawVector[14] = spectral.flux;
    rawVector[15] = spectral.zcr;

    const standardizedVector = new Array<number>(AUDIO_FEATURE_DIM).fill(0.0);
    for (let i = 0; i < AUDIO_FEATURE_DIM; i++) {
      const z = (rawVector[i] - ACOUSTIC_MEANS[i]) / (ACOUSTIC_STDS[i] || 1.0);
      standardizedVector[i] = Number(Math.max(-4.0, Math.min(4.0, z)).toFixed(6));
    }

    return standardizedVector;
  }

  /**
   * Neutral Acoustic Prior (used when no audio is submitted or audio is silent).
   * Returns a 16-d vector with uniform values (0.0) on standard normal distribution.
   */
  public static buildNeutralAcousticPrior(
    sampleRate: number = TARGET_SAMPLE_RATE,
    sampleCount: number = 0
  ): AudioFeatureExtractionResult {
    const featureVector = new Array<number>(AUDIO_FEATURE_DIM).fill(0.0);

    return {
      featureVector,
      originalSampleRate: sampleRate,
      resampledRate: TARGET_SAMPLE_RATE,
      durationSeconds: 0,
      pcmSampleCount: sampleCount,
      isResampled: false,
      spectralMetrics: {
        centroid: 0.18,
        rolloff: 0.28,
        flux: 0.045,
        zcr: 0.080
      },
      mfccCoefficients: new Array<number>(MFCC_COUNT).fill(0.0)
    };
  }

  // --- Helper DSP Functions ---

  private static parseRawInt16Pcm(buffer: Buffer | Uint8Array): Float32Array {
    const bytes = buffer instanceof Buffer ? buffer : Buffer.from(buffer);
    const sampleCount = Math.floor(bytes.length / 2);
    const pcm = new Float32Array(sampleCount);

    for (let i = 0; i < sampleCount; i++) {
      const int16 = bytes.readInt16LE(i * 2);
      pcm[i] = int16 / 32768.0;
    }
    return pcm;
  }

  private static peakNormalize(pcm: Float32Array): void {
    let max = 0;
    for (let i = 0; i < pcm.length; i++) {
      const abs = Math.abs(pcm[i]);
      if (abs > max) max = abs;
    }
    if (max > 1e-4 && max !== 1.0) {
      const scale = 0.95 / max;
      for (let i = 0; i < pcm.length; i++) {
        pcm[i] *= scale;
      }
    }
  }

  private static createHammingWindow(size: number): Float32Array {
    const win = new Float32Array(size);
    for (let i = 0; i < size; i++) {
      win[i] = 0.54 - 0.46 * Math.cos((2 * Math.PI * i) / (size - 1));
    }
    return win;
  }

  private static computePowerSpectrum(frame: Float32Array): Float32Array {
    const N = frame.length;
    const halfN = Math.floor(N / 2);
    const power = new Float32Array(halfN);

    // Real DFT for audio frame
    for (let k = 0; k < halfN; k++) {
      let real = 0;
      let imag = 0;
      const angleStep = (2 * Math.PI * k) / N;
      for (let n = 0; n < N; n++) {
        const angle = angleStep * n;
        real += frame[n] * Math.cos(angle);
        imag -= frame[n] * Math.sin(angle);
      }
      power[k] = (real * real + imag * imag) / N;
    }

    return power;
  }

  private static hzToMel(hz: number): number {
    return 2595 * Math.log10(1 + hz / 700);
  }

  private static melToHz(mel: number): number {
    return 700 * (Math.pow(10, mel / 2595) - 1);
  }

  private static createMelFilterbanks(
    numFilters: number,
    fftSize: number,
    sampleRate: number,
    lowFreq: number,
    highFreq: number
  ): Float32Array[] {
    const minMel = this.hzToMel(lowFreq);
    const maxMel = this.hzToMel(highFreq);
    const melStep = (maxMel - minMel) / (numFilters + 1);

    const melPoints: number[] = [];
    for (let i = 0; i <= numFilters + 1; i++) {
      melPoints.push(this.melToHz(minMel + i * melStep));
    }

    const halfSize = Math.floor(fftSize / 2);
    const binPoints = melPoints.map(hz => Math.floor(((fftSize + 1) * hz) / sampleRate));

    const filterbanks: Float32Array[] = [];
    for (let m = 1; m <= numFilters; m++) {
      const filter = new Float32Array(halfSize).fill(0);
      const left = binPoints[m - 1];
      const center = binPoints[m];
      const right = binPoints[m + 1];

      for (let k = left; k < center && k < halfSize; k++) {
        filter[k] = (k - left) / (center - left || 1);
      }
      for (let k = center; k <= right && k < halfSize; k++) {
        filter[k] = (right - k) / (right - center || 1);
      }
      filterbanks.push(filter);
    }

    return filterbanks;
  }
}
