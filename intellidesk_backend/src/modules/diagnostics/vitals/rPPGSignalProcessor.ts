import { BioSignalFrame, rPPGAnalysisResult, PhysiologicalAlert } from './types.js';
import { ButterworthFilter } from './ButterworthFilter.js';
import { PhysiologicalRedFlagSentinel } from './PhysiologicalRedFlagSentinel.js';

export interface SignalSeriesInput {
  red: number[];
  green: number[];
  blue: number[];
  timestampsMs?: number[];
  samplingRate?: number;
}

export class rPPGSignalProcessor {
  private filter: ButterworthFilter;
  private readonly targetSamplingRate: number = 30.0; // 30.0 Hz standard

  constructor(targetSamplingRate: number = 30.0) {
    this.targetSamplingRate = targetSamplingRate;
    this.filter = new ButterworthFilter(targetSamplingRate, 0.75, 3.5);
  }

  /**
   * Technical Guardrail 1: Uniform 30.0 Hz Time-Series Resampling
   * Interpolates non-uniform timestamped frame sequences onto an exact 30.0 Hz uniform time grid.
   */
  public resampleToUniform30Hz(
    values: number[],
    timestampsMs: number[]
  ): number[] {
    const n = values.length;
    if (n <= 1) return [...values];

    const tStart = timestampsMs[0];
    const tEnd = timestampsMs[n - 1];
    const durationMs = tEnd - tStart;
    if (durationMs <= 0) return [...values];

    const dtUniform = 1000.0 / this.targetSamplingRate; // 33.333 ms
    const uniformLength = Math.max(2, Math.floor(durationMs / dtUniform) + 1);
    const resampled = new Array<number>(uniformLength);

    let srcIdx = 0;
    for (let i = 0; i < uniformLength; i++) {
      const tTarget = tStart + i * dtUniform;

      // Advance source index to interval [srcIdx, srcIdx + 1] containing tTarget
      while (srcIdx < n - 2 && timestampsMs[srcIdx + 1] < tTarget) {
        srcIdx++;
      }

      const t0 = timestampsMs[srcIdx];
      const t1 = timestampsMs[srcIdx + 1];
      const v0 = values[srcIdx];
      const v1 = values[srcIdx + 1];

      if (t1 === t0) {
        resampled[i] = v0;
      } else {
        const factor = Math.max(0.0, Math.min(1.0, (tTarget - t0) / (t1 - t0)));
        resampled[i] = v0 + factor * (v1 - v0);
      }
    }

    return resampled;
  }

  /**
   * Radix-2 / Zero-Padded Fast Fourier Transform.
   */
  public computePowerSpectrum(signal: number[], zeroPadLength: number = 1024): {
    frequencies: number[];
    powers: number[];
  } {
    const n = signal.length;
    const fftSize = Math.max(zeroPadLength, 1 << Math.ceil(Math.log2(n)));
    const real = new Float64Array(fftSize);
    const imag = new Float64Array(fftSize);

    // Apply Hanning Window to prevent spectral leakage
    for (let i = 0; i < n; i++) {
      const window = 0.5 * (1.0 - Math.cos((2.0 * Math.PI * i) / (n - 1)));
      real[i] = signal[i] * window;
    }

    // Cooley-Tukey Radix-2 In-Place Decimation-in-Time FFT
    let j = 0;
    for (let i = 0; i < fftSize - 1; i++) {
      if (i < j) {
        const tempR = real[i];
        real[i] = real[j];
        real[j] = tempR;

        const tempI = imag[i];
        imag[i] = imag[j];
        imag[j] = tempI;
      }
      let k = fftSize >> 1;
      while (k <= j) {
        j -= k;
        k >>= 1;
      }
      j += k;
    }

    for (let len = 2; len <= fftSize; len <<= 1) {
      const angle = (-2.0 * Math.PI) / len;
      const wStepR = Math.cos(angle);
      const wStepI = Math.sin(angle);

      for (let i = 0; i < fftSize; i += len) {
        let wR = 1.0;
        let wI = 0.0;
        const halfLen = len >> 1;

        for (let k = 0; k < halfLen; k++) {
          const uR = real[i + k];
          const uI = imag[i + k];

          const vR = real[i + k + halfLen] * wR - imag[i + k + halfLen] * wI;
          const vI = real[i + k + halfLen] * wI + imag[i + k + halfLen] * wR;

          real[i + k] = uR + vR;
          imag[i + k] = uI + vI;

          real[i + k + halfLen] = uR - vR;
          imag[i + k + halfLen] = uI - vI;

          const nextWR = wR * wStepR - wI * wStepI;
          wI = wR * wStepI + wI * wStepR;
          wR = nextWR;
        }
      }
    }

    // One-sided power spectrum up to Nyquist frequency
    const halfSize = fftSize >> 1;
    const frequencies = new Array<number>(halfSize);
    const powers = new Array<number>(halfSize);
    const freqStep = this.targetSamplingRate / fftSize;

    for (let k = 0; k < halfSize; k++) {
      frequencies[k] = k * freqStep;
      powers[k] = real[k] * real[k] + imag[k] * imag[k];
    }

    return { frequencies, powers };
  }

  /**
   * Detects local peaks in the filtered pulsatile signal.
   */
  public detectPeaks(signal: number[], minDistanceFrames: number = 8): number[] {
    const peaks: number[] = [];
    const n = signal.length;

    for (let i = 1; i < n - 1; i++) {
      if (signal[i] > signal[i - 1] && signal[i] > signal[i + 1] && signal[i] > 0) {
        if (peaks.length === 0 || (i - peaks[peaks.length - 1]) >= minDistanceFrames) {
          peaks.push(i);
        } else if (signal[i] > signal[peaks[peaks.length - 1]]) {
          // Replace with higher nearby peak
          peaks[peaks.length - 1] = i;
        }
      }
    }

    return peaks;
  }

  /**
   * Computes Heart Rate Variability (HRV) RMSSD in milliseconds from peaks.
   */
  public computeHrvRmssd(peaks: number[], fs: number = 30.0): {
    rmssdMs: number;
    ibisMs: number[];
  } {
    if (peaks.length < 3) {
      return { rmssdMs: 38.0, ibisMs: [] }; // Clinical baseline adult default
    }

    const ibisMs: number[] = [];
    const msPerFrame = 1000.0 / fs;

    for (let i = 0; i < peaks.length - 1; i++) {
      const ibi = (peaks[i + 1] - peaks[i]) * msPerFrame;
      // Filter non-physiological IBIs (valid cardiac interval: 300ms to 1500ms -> 40 to 200 BPM)
      if (ibi >= 280 && ibi <= 1500) {
        ibisMs.push(ibi);
      }
    }

    if (ibisMs.length < 2) {
      return { rmssdMs: 38.0, ibisMs };
    }

    let sumSquaredDiffs = 0.0;
    for (let i = 0; i < ibisMs.length - 1; i++) {
      const diff = ibisMs[i + 1] - ibisMs[i];
      sumSquaredDiffs += diff * diff;
    }

    const rmssd = Math.sqrt(sumSquaredDiffs / (ibisMs.length - 1));
    return {
      rmssdMs: Math.round(rmssd * 10) / 10,
      ibisMs
    };
  }

  /**
   * Estimates Respiration Rate from low-frequency modulation (RSA) in 0.15 - 0.40 Hz band.
   */
  public estimateRespirationRate(signal: number[]): number {
    const { frequencies, powers } = this.computePowerSpectrum(signal, 1024);

    let maxPower = -1;
    let respFreq = 0.25; // 15 breaths/min default

    for (let i = 0; i < frequencies.length; i++) {
      const f = frequencies[i];
      if (f >= 0.15 && f <= 0.40) {
        if (powers[i] > maxPower) {
          maxPower = powers[i];
          respFreq = f;
        }
      }
    }

    const respirationBpm = Math.round(respFreq * 60.0);
    return Math.max(8, Math.min(36, respirationBpm));
  }

  /**
   * Technical Guardrail 2: SpO2 AC/DC Baseline Normalization & [70.0%, 100.0%] Bounding
   */
  public computeSpO2(redSignal: number[], blueSignal: number[]): number {
    const calcAcDc = (series: number[]) => {
      let sum = 0;
      for (const v of series) sum += v;
      const dc = sum / series.length;

      let varSum = 0;
      for (const v of series) {
        const diff = v - dc;
        varSum += diff * diff;
      }
      const ac = Math.sqrt(varSum / series.length);
      return { ac, dc: dc === 0 ? 1.0 : dc };
    };

    const red = calcAcDc(redSignal);
    const blue = calcAcDc(blueSignal.length > 0 ? blueSignal : redSignal);

    const ratioRed = red.ac / red.dc;
    const ratioBlue = blue.ac / blue.dc;

    const rRatio = ratioBlue === 0 ? 0.6 : (ratioRed / ratioBlue);

    // Standard clinical calibration equation: SpO2 = 110 - 25 * R
    let spo2 = 110.0 - 25.0 * rRatio;

    // Technical Guardrail 2: Strictly clamp between 70.0% and 100.0%
    spo2 = Math.max(70.0, Math.min(100.0, spo2));

    return Math.round(spo2 * 10) / 10;
  }

  /**
   * Main bio-signal analysis engine:
   * Processes input RGB arrays, filters green channel, computes FFT spectral peak,
  /**
   * Technical Guardrail: Channel Candidate Spectral Analysis.
   * Evaluates a color channel time-series by applying the Butterworth bandpass filter (0.75 - 3.5 Hz),
   * computing the FFT power spectrum, determining dominant cardiac frequency, and calculating SNR & confidence.
   */
  public analyzeCandidateChannel(
    signal: number[],
    samplingRate: number = 30.0,
    channelName: string = 'channel'
  ): {
    filtered: number[];
    dominantFreq: number;
    heartRateBpm: number;
    cardiacBandPower: number;
    totalBandPower: number;
    snrLinear: number;
    snrDb: number;
    confidenceScore: number;
  } {
    // 1. 4th-Order Butterworth Bandpass Filtering (0.75 - 3.5 Hz)
    const filtered = this.filter.filter(signal);

    // 2. FFT Spectral Peak Extraction
    const { frequencies, powers } = this.computePowerSpectrum(filtered, 2048);

    let maxPower = -1;
    let peakBin = -1;

    for (let i = 0; i < frequencies.length; i++) {
      const f = frequencies[i];
      if (f >= 0.75 && f <= 3.5) {
        if (powers[i] > maxPower) {
          maxPower = powers[i];
          peakBin = i;
        }
      }
    }

    let dominantFreq = 1.25; // 75 BPM default
    if (peakBin > 0 && peakBin < frequencies.length - 1) {
      // Parabolic sub-bin interpolation for sub-BPM precision
      const y1 = powers[peakBin - 1];
      const y2 = powers[peakBin];
      const y3 = powers[peakBin + 1];
      const delta = (0.5 * (y1 - y3)) / (y1 - 2 * y2 + y3);
      const binExact = peakBin + (isNaN(delta) ? 0 : delta);
      const freqStep = samplingRate / 2048;
      dominantFreq = binExact * freqStep;
    } else if (peakBin >= 0) {
      dominantFreq = frequencies[peakBin];
    }

    const heartRateBpm = Math.round(dominantFreq * 60.0);

    // 3. Signal-to-Noise Ratio (SNR) via Normalized Power Spectral Density (PSD)
    let cardiacBandPower = 0;
    let totalBandPower = 0;
    let cardiacBins = 0;
    let totalBins = 0;

    for (let i = 0; i < frequencies.length; i++) {
      const f = frequencies[i];
      if (f >= 0.5 && f <= 4.0) {
        totalBandPower += powers[i];
        totalBins++;
        // Include fundamental pulse peak (+- 0.22 Hz) and 1st harmonic (+- 0.22 Hz)
        const isFundamental = Math.abs(f - dominantFreq) <= 0.22;
        const isHarmonic = Math.abs(f - (2.0 * dominantFreq)) <= 0.22;
        if (isFundamental || isHarmonic) {
          cardiacBandPower += powers[i];
          cardiacBins++;
        }
      }
    }

    const noisePower = Math.max(1e-6, totalBandPower - cardiacBandPower);
    const noiseBins = Math.max(1, totalBins - cardiacBins);

    // Power spectral density (power per bin) for signal window vs noise floor
    const cardiacPsd = cardiacBandPower / Math.max(1, cardiacBins);
    const noisePsd = Math.max(1e-6, noisePower / noiseBins);
    const snrLinear = cardiacPsd / noisePsd;
    const snrDb = Math.round(10.0 * Math.log10(Math.max(1.0, snrLinear)) * 10) / 10;
    const confidenceScore = Math.max(0.4, Math.min(0.99, snrLinear / (snrLinear + 2.5)));

    console.log(`🔍 [rPPG DSP] ${channelName} analysis: HR=${heartRateBpm}bpm (${dominantFreq.toFixed(2)}Hz) | peakPower=${maxPower.toExponential(2)} | cardiacPSD=${cardiacPsd.toExponential(2)} | noisePSD=${noisePsd.toExponential(2)} | SNR=${snrDb}dB | Conf=${Math.round(confidenceScore * 100)}%`);

    return {
      filtered,
      dominantFreq,
      heartRateBpm,
      cardiacBandPower,
      totalBandPower,
      snrLinear,
      snrDb,
      confidenceScore: Math.round(confidenceScore * 100) / 100
    };
  }

  /**
   * Main bio-signal analysis engine:
   * Dynamically evaluates both Green (contactless facial rPPG) and Red (contact fingertip PPG)
   * channels to select the optimal optical carrier with highest pulsatile SNR.
   */
  public processSignals(input: SignalSeriesInput): rPPGAnalysisResult {
    let rawRed = input.red;
    let rawGreen = input.green;
    let rawBlue = input.blue;

    // 1. Resample to uniform 30.0 Hz if non-uniform timestamps provided (Guardrail 1)
    if (input.timestampsMs && input.timestampsMs.length === rawGreen.length) {
      rawRed = this.resampleToUniform30Hz(rawRed, input.timestampsMs);
      rawGreen = this.resampleToUniform30Hz(rawGreen, input.timestampsMs);
      rawBlue = this.resampleToUniform30Hz(rawBlue, input.timestampsMs);
    }

    const sampleCount = rawGreen.length;
    const durationSeconds = sampleCount / this.targetSamplingRate;

    // 2. Adaptive Channel Selection: Compare Green (facial rPPG) vs Red (fingertip contact PPG)
    const greenAnalysis = this.analyzeCandidateChannel(rawGreen, this.targetSamplingRate, 'GREEN');
    const redAnalysis = this.analyzeCandidateChannel(rawRed, this.targetSamplingRate, 'RED');

    // Compute optical channel characteristics
    const meanRed = rawRed.length > 0 ? (rawRed.reduce((a, b) => a + b, 0) / rawRed.length) : 0;
    const meanGreen = rawGreen.length > 0 ? (rawGreen.reduce((a, b) => a + b, 0) / rawGreen.length) : 0;
    const isContactSignature = meanRed > 45.0 && meanRed > (meanGreen * 1.05);

    // Select optimal channel:
    // If contact fingertip mode is detected and Red has viable SNR, or if Red SNR exceeds Green by 20%, use Red.
    // Otherwise, default to Green channel (standard for contactless facial rPPG).
    const useRedChannel = (isContactSignature && redAnalysis.snrLinear > 1.02) ||
                          (redAnalysis.snrLinear > greenAnalysis.snrLinear * 1.2);

    const selectedAnalysis = useRedChannel ? redAnalysis : greenAnalysis;
    const primaryFiltered = selectedAnalysis.filtered;
    const dominantFreq = selectedAnalysis.dominantFreq;
    const heartRateBpm = selectedAnalysis.heartRateBpm;
    const snrDb = selectedAnalysis.snrDb;
    const confidenceScore = selectedAnalysis.confidenceScore;

    console.log(`📊 [rPPG Processor] ${sampleCount} frames (${durationSeconds.toFixed(1)}s) | Mean RGB: R=${meanRed.toFixed(1)}, G=${meanGreen.toFixed(1)} | ContactSignature=${isContactSignature} | Channel Selected: ${useRedChannel ? 'RED' : 'GREEN'} | HR=${heartRateBpm} BPM | SNR=${snrDb} dB | Conf=${Math.round(confidenceScore * 100)}%`);

    // 3. Peak Detection, Inter-Beat Intervals & RMSSD (HRV) using primary selected channel
    const minPeakDistance = Math.max(5, Math.floor(this.targetSamplingRate / 3.5));
    const peaks = this.detectPeaks(primaryFiltered, minPeakDistance);
    const { rmssdMs, ibisMs } = this.computeHrvRmssd(peaks, this.targetSamplingRate);

    // 4. Respiration Rate (breaths/min)
    const respirationRateBpm = this.estimateRespirationRate(primaryFiltered);

    // 5. Blood Oxygen SpO2 % (Guardrail 2)
    const oxygenSaturationSpo2 = this.computeSpO2(rawRed, rawBlue);

    // 6. Clinical Red Flag Sentinel Evaluation
    const alerts = PhysiologicalRedFlagSentinel.evaluateVitals({
      heartRate: heartRateBpm,
      oxygenSaturation: oxygenSaturationSpo2,
      respirationRate: respirationRateBpm
    });

    const hasCriticalDerangement = alerts.some(a => a.severity === 'CRITICAL_OVERRIDE');

    return {
      heartRateBpm,
      hrvRmssdMs: rmssdMs,
      respirationRateBpm,
      oxygenSaturationSpo2,
      confidenceScore,
      snrDb,
      sampleCount,
      durationSeconds: Math.round(durationSeconds * 10) / 10,
      filteredWaveform: primaryFiltered.slice(0, 150), // Sample snippet for UI preview
      interBeatIntervalsMs: ibisMs,
      alerts,
      hasCriticalDerangement
    };
  }

  /**
   * Helper accepting BioSignalFrame array from camera stream.
   */
  public processFrames(frames: BioSignalFrame[]): rPPGAnalysisResult {
    const red = frames.map(f => f.red);
    const green = frames.map(f => f.green);
    const blue = frames.map(f => f.blue);
    const timestampsMs = frames.map(f => f.timestampMs);

    return this.processSignals({
      red,
      green,
      blue,
      timestampsMs
    });
  }
}
