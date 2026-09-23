export interface BiquadCoefficients {
  b0: number;
  b1: number;
  b2: number;
  a1: number;
  a2: number;
}

/**
 * 4th-Order Zero-Phase Digital Butterworth Bandpass Filter
 * Designed for camera rPPG pulsatile signals sampled at Fs = 30.0 Hz.
 * Passband: 0.75 Hz to 3.5 Hz (45 BPM to 210 BPM cardiac frequency window).
 */
export class ButterworthFilter {
  private readonly lowpassCoeffs: BiquadCoefficients;
  private readonly highpassCoeffs: BiquadCoefficients;

  constructor(
    sampleRate: number = 30.0,
    fLow: number = 0.75,
    fHigh: number = 3.5
  ) {
    this.highpassCoeffs = this.computeHighpassCoefficients(fLow, sampleRate);
    this.lowpassCoeffs = this.computeLowpassCoefficients(fHigh, sampleRate);
  }

  /**
   * Computes 2nd-order Butterworth lowpass filter coefficients.
   */
  private computeLowpassCoefficients(fc: number, fs: number): BiquadCoefficients {
    const omega = Math.tan((Math.PI * fc) / fs);
    const omegaSq = omega * omega;
    const sqrt2Omega = Math.SQRT2 * omega;
    const norm = 1.0 / (1.0 + sqrt2Omega + omegaSq);

    return {
      b0: omegaSq * norm,
      b1: 2.0 * omegaSq * norm,
      b2: omegaSq * norm,
      a1: 2.0 * (omegaSq - 1.0) * norm,
      a2: (1.0 - sqrt2Omega + omegaSq) * norm
    };
  }

  /**
   * Computes 2nd-order Butterworth highpass filter coefficients.
   */
  private computeHighpassCoefficients(fc: number, fs: number): BiquadCoefficients {
    const omega = Math.tan((Math.PI * fc) / fs);
    const omegaSq = omega * omega;
    const sqrt2Omega = Math.SQRT2 * omega;
    const norm = 1.0 / (1.0 + sqrt2Omega + omegaSq);

    return {
      b0: 1.0 * norm,
      b1: -2.0 * norm,
      b2: 1.0 * norm,
      a1: 2.0 * (omegaSq - 1.0) * norm,
      a2: (1.0 - sqrt2Omega + omegaSq) * norm
    };
  }

  /**
   * Filters array with single biquad section in Direct Form II Transposed.
   */
  private applyBiquad(signal: number[], coeffs: BiquadCoefficients): number[] {
    const n = signal.length;
    const out = new Array<number>(n);
    let s1 = 0.0;
    let s2 = 0.0;

    for (let i = 0; i < n; i++) {
      const x = signal[i];
      const y = coeffs.b0 * x + s1;
      s1 = coeffs.b1 * x - coeffs.a1 * y + s2;
      s2 = coeffs.b2 * x - coeffs.a2 * y;
      out[i] = y;
    }

    return out;
  }

  /**
   * Zero-phase forward-backward filtering (filtfilt) doubling effective order to 4th-order.
   */
  private applyFiltFilt(signal: number[], coeffs: BiquadCoefficients): number[] {
    // Forward pass
    const forward = this.applyBiquad(signal, coeffs);
    // Backward pass
    forward.reverse();
    const backward = this.applyBiquad(forward, coeffs);
    backward.reverse();
    return backward;
  }

  /**
   * Detrends time-series signal by subtracting moving average baseline.
   */
  public detrend(signal: number[], windowSize: number = 15): number[] {
    const n = signal.length;
    if (n === 0) return [];
    const detrended = new Array<number>(n);
    const halfWin = Math.floor(windowSize / 2);

    for (let i = 0; i < n; i++) {
      const start = Math.max(0, i - halfWin);
      const end = Math.min(n, i + halfWin + 1);
      let sum = 0;
      for (let j = start; j < end; j++) {
        sum += signal[j];
      }
      const mean = sum / (end - start);
      detrended[i] = signal[i] - mean;
    }

    return detrended;
  }

  /**
   * Complete 4th-order zero-phase bandpass filtering pipeline:
   * 1. Detrend signal (baseline removal)
   * 2. 4th-order Highpass (0.75 Hz cut-off)
   * 3. 4th-order Lowpass (3.5 Hz cut-off)
   */
  public filter(signal: number[]): number[] {
    if (!signal || signal.length < 4) return signal ? [...signal] : [];

    // 1. Detrend
    const detrended = this.detrend(signal);

    // 2. Highpass filtering (attenuates < 0.75 Hz drift)
    const hpFiltered = this.applyFiltFilt(detrended, this.highpassCoeffs);

    // 3. Lowpass filtering (attenuates > 3.5 Hz camera noise)
    const bpFiltered = this.applyFiltFilt(hpFiltered, this.lowpassCoeffs);

    return bpFiltered;
  }
}
