import sharp from 'sharp';
import { DBHealthScreeningRow, HealthScreeningsDbService } from '../db/healthScreeningsDbService.js';

export type ClinicalProgressionStatus = 
  | 'Improving / Healing'
  | 'Stable / Unchanged'
  | 'Deteriorating / Escalating';

export interface VitalsDelta {
  painDelta: number | null;
  tempDelta: number | null;
  spo2Delta: number | null;
  heartRateDelta: number | null;
}

export interface ScreeningDeltaComparison {
  baselineScreeningId: string;
  followupScreeningId: string;
  baselineDate: string;
  followupDate: string;
  timeElapsedDays: number;
  timeElapsedHours: number;

  baselineRiskScore: number;
  followupRiskScore: number;
  riskDelta: number; // followup - baseline (-1.0 to +1.0)
  riskDeltaPercentage: number; // e.g. -25.0 means -25%

  status: ClinicalProgressionStatus;

  ssim: number | null; // Mean Structural Similarity Index [0.0 - 1.0]
  ssimCategory: 'High Concordance' | 'Moderate Shift' | 'Substantial Remodeling' | 'N/A';

  vitalsDelta: VitalsDelta;

  baselineImageUrl: string | null;
  followupImageUrl: string | null;

  clinicalSummary: string;
  recommendations: string[];
}

export class ScreeningDeltaAnalyzer {
  // SSIM standard window size and dynamic range
  private static readonly WINDOW_SIZE = 8;
  private static readonly DYNAMIC_RANGE_L = 255;

  /**
   * Technical Guardrail 3: Division-by-Zero SSIM Guardrail
   * Wang et al. (2004) regularizing constants:
   * C1 = (K1 * L)^2 with K1 = 0.01 -> C1 = (0.01 * 255)^2 = 6.5025
   * C2 = (K2 * L)^2 with K2 = 0.03 -> C2 = (0.03 * 255)^2 = 58.5225
   * Strictly prevents division by zero in flat or zero-contrast regions.
   */
  private static readonly C1 = 6.5025;
  private static readonly C2 = 58.5225;

  /**
   * Evaluates longitudinal progression between two health screening records.
   * Accepts either screening IDs or pre-loaded DBHealthScreeningRow objects.
   */
  public static async analyzeDelta(
    baselineInput: string | DBHealthScreeningRow,
    followupInput: string | DBHealthScreeningRow,
    options?: {
      baselineImageBuffer?: Buffer;
      followupImageBuffer?: Buffer;
    }
  ): Promise<ScreeningDeltaComparison> {
    // 1. Resolve baseline and follow-up screening records
    const baseline = typeof baselineInput === 'string'
      ? await HealthScreeningsDbService.getScreeningById(baselineInput)
      : baselineInput;

    const followup = typeof followupInput === 'string'
      ? await HealthScreeningsDbService.getScreeningById(followupInput)
      : followupInput;

    if (!baseline) {
      throw new Error(`Baseline screening not found: ${typeof baselineInput === 'string' ? baselineInput : 'unknown'}`);
    }
    if (!followup) {
      throw new Error(`Follow-up screening not found: ${typeof followupInput === 'string' ? followupInput : 'unknown'}`);
    }

    // 2. Compute Timing Deltas
    const t0Date = new Date(baseline.created_at);
    const t1Date = new Date(followup.created_at);
    const msDiff = Math.max(0, t1Date.getTime() - t0Date.getTime());
    const timeElapsedHours = Math.round((msDiff / (1000 * 60 * 60)) * 10) / 10;
    const timeElapsedDays = Math.round((msDiff / (1000 * 60 * 60 * 24)) * 10) / 10;

    // 3. Technical Guardrail 2: Clinical Delta Priority
    // Primary driver is risk score delta and vital changes
    const r0 = baseline.multimodal_risk_score;
    const r1 = followup.multimodal_risk_score;
    const riskDelta = Math.round((r1 - r0) * 1000) / 1000;
    const riskDeltaPercentage = Math.round(riskDelta * 1000) / 10; // e.g. -15.5%

    // 4. Extract Vital Deltas
    const vitalsDelta = this.extractVitalsDelta(baseline, followup);

    // 5. Compute SSIM (Secondary visual similarity metric)
    const ssim = await this.computeSSIMSafe(
      baseline,
      followup,
      options?.baselineImageBuffer,
      options?.followupImageBuffer
    );

    let ssimCategory: 'High Concordance' | 'Moderate Shift' | 'Substantial Remodeling' | 'N/A' = 'N/A';
    if (ssim !== null) {
      if (ssim >= 0.85) ssimCategory = 'High Concordance';
      else if (ssim >= 0.60) ssimCategory = 'Moderate Shift';
      else ssimCategory = 'Substantial Remodeling';
    }

    // 6. Categorize Progression Status (Guardrail 2)
    const status = this.categorizeProgression(riskDelta, vitalsDelta);

    // 7. Synthesize Clinical Narrative Summary & Actionable Directives
    const { clinicalSummary, recommendations } = this.synthesizeClinicalInsights(
      status,
      riskDelta,
      ssim,
      vitalsDelta,
      timeElapsedDays
    );

    return {
      baselineScreeningId: baseline.id,
      followupScreeningId: followup.id,
      baselineDate: baseline.created_at,
      followupDate: followup.created_at,
      timeElapsedDays,
      timeElapsedHours,
      baselineRiskScore: r0,
      followupRiskScore: r1,
      riskDelta,
      riskDeltaPercentage,
      status,
      ssim,
      ssimCategory,
      vitalsDelta,
      baselineImageUrl: baseline.image_url,
      followupImageUrl: followup.image_url,
      clinicalSummary,
      recommendations
    };
  }

  /**
   * Technical Guardrail 2: Primary Categorization Logic
   * Risk Delta & Vitals are primary; SSIM informs visual remodeling context.
   */
  private static categorizeProgression(
    riskDelta: number,
    vitalsDelta: VitalsDelta
  ): ClinicalProgressionStatus {
    const painDelta = vitalsDelta.painDelta ?? 0;
    const tempDelta = vitalsDelta.tempDelta ?? 0;

    // Severe escalation red-flag check
    if (riskDelta >= 0.05 || painDelta >= 3 || tempDelta >= 1.5) {
      return 'Deteriorating / Escalating';
    }

    // Meaningful improvement: risk dropped by >= 5% or pain dropped significantly without risk rising
    if (riskDelta <= -0.05 || (painDelta <= -2 && riskDelta <= 0.02)) {
      return 'Improving / Healing';
    }

    // Stable within +/- 5% margin
    return 'Stable / Unchanged';
  }

  /**
   * Extracts delta changes between baseline and follow-up vitals.
   */
  private static extractVitalsDelta(
    baseline: DBHealthScreeningRow,
    followup: DBHealthScreeningRow
  ): VitalsDelta {
    const getVal = (row: DBHealthScreeningRow, keys: string[]): number | null => {
      const payload = row.symptom_payload || {};
      const vitals = payload.vitals || {};
      for (const k of keys) {
        if (typeof vitals[k] === 'number') return vitals[k];
        if (typeof payload[k] === 'number') return payload[k];
      }
      return null;
    };

    const p0 = getVal(baseline, ['pain_score', 'painScore', 'painLevel', 'pain']);
    const p1 = getVal(followup, ['pain_score', 'painScore', 'painLevel', 'pain']);

    const t0 = getVal(baseline, ['temperature', 'temp', 'bodyTemp']);
    const t1 = getVal(followup, ['temperature', 'temp', 'bodyTemp']);

    const s0 = getVal(baseline, ['spo2', 'spO2', 'oxygenSaturation']);
    const s1 = getVal(followup, ['spo2', 'spO2', 'oxygenSaturation']);

    const h0 = getVal(baseline, ['heart_rate', 'heartRate', 'pulse']);
    const h1 = getVal(followup, ['heart_rate', 'heartRate', 'pulse']);

    return {
      painDelta: (p0 !== null && p1 !== null) ? Math.round((p1 - p0) * 10) / 10 : null,
      tempDelta: (t0 !== null && t1 !== null) ? Math.round((t1 - t0) * 10) / 10 : null,
      spo2Delta: (s0 !== null && s1 !== null) ? Math.round((s1 - s0) * 10) / 10 : null,
      heartRateDelta: (h0 !== null && h1 !== null) ? Math.round((h1 - h0) * 10) / 10 : null
    };
  }

  /**
   * Safe SSIM Computation Pipeline:
   * Handles text-only screenings, URL fetches, base64 strings, and raw image buffers.
   * Returns null if either image is missing or invalid.
   */
  public static async computeSSIMSafe(
    baseline: DBHealthScreeningRow,
    followup: DBHealthScreeningRow,
    overrideBuf0?: Buffer,
    overrideBuf1?: Buffer
  ): Promise<number | null> {
    try {
      const buf0 = overrideBuf0 || (await this.resolveImageBuffer(baseline.image_url));
      const buf1 = overrideBuf1 || (await this.resolveImageBuffer(followup.image_url));

      if (!buf0 || !buf1) {
        return null;
      }

      return await this.calculateMSSIM(buf0, buf1);
    } catch (err) {
      console.warn('⚠️ [ScreeningDeltaAnalyzer] Failed to compute SSIM:', err);
      return null;
    }
  }

  /**
   * Core Mathematical Mean SSIM (MSSIM) Implementation (Wang et al. 2004)
   * With Guardrail 3 (C1, C2 regularizers preventing division by zero).
   */
  public static async calculateMSSIM(imageA: Buffer, imageB: Buffer): Promise<number> {
    const TARGET_SIZE = 128;
    const B = this.WINDOW_SIZE; // 8x8 blocks

    // 1. Standardize both images to 128x128 8-bit grayscale raw pixel arrays
    const [rawA, rawB] = await Promise.all([
      sharp(imageA)
        .resize(TARGET_SIZE, TARGET_SIZE, { fit: 'fill' })
        .grayscale()
        .raw()
        .toBuffer(),
      sharp(imageB)
        .resize(TARGET_SIZE, TARGET_SIZE, { fit: 'fill' })
        .grayscale()
        .raw()
        .toBuffer()
    ]);

    const numBlocksX = TARGET_SIZE / B;
    const numBlocksY = TARGET_SIZE / B;
    const totalBlocks = numBlocksX * numBlocksY;
    const N = B * B; // 64 pixels per block

    let ssimSum = 0;

    for (let by = 0; by < numBlocksY; by++) {
      for (let bx = 0; bx < numBlocksX; bx++) {
        // Collect pixels for block
        let sumA = 0;
        let sumB = 0;

        for (let y = 0; y < B; y++) {
          const rowOffset = (by * B + y) * TARGET_SIZE;
          for (let x = 0; x < B; x++) {
            const idx = rowOffset + (bx * B + x);
            sumA += rawA[idx];
            sumB += rawB[idx];
          }
        }

        const muA = sumA / N;
        const muB = sumB / N;

        let varA = 0;
        let varB = 0;
        let covarAB = 0;

        for (let y = 0; y < B; y++) {
          const rowOffset = (by * B + y) * TARGET_SIZE;
          for (let x = 0; x < B; x++) {
            const idx = rowOffset + (bx * B + x);
            const diffA = rawA[idx] - muA;
            const diffB = rawB[idx] - muB;
            varA += diffA * diffA;
            varB += diffB * diffB;
            covarAB += diffA * diffB;
          }
        }

        const sigmaA2 = varA / (N - 1);
        const sigmaB2 = varB / (N - 1);
        const sigmaAB = covarAB / (N - 1);

        // Technical Guardrail 3: Strict C1 and C2 regularization
        const numerator = (2 * muA * muB + this.C1) * (2 * sigmaAB + this.C2);
        const denominator = (muA * muA + muB * muB + this.C1) * (sigmaA2 + sigmaB2 + this.C2);

        const blockSSIM = numerator / denominator;
        ssimSum += blockSSIM;
      }
    }

    const mssim = ssimSum / totalBlocks;
    // Bound within [-1.0, 1.0], clamped to [0.0, 1.0] for clinical comparison
    return Math.max(0.0, Math.min(1.0, Math.round(mssim * 1000) / 1000));
  }

  /**
   * Helper to parse data URI, remote URL, or local image source to a Buffer.
   */
  private static async resolveImageBuffer(urlOrDataUri?: string | null): Promise<Buffer | null> {
    if (!urlOrDataUri) return null;

    if (urlOrDataUri.startsWith('data:')) {
      const parts = urlOrDataUri.split(',');
      if (parts.length > 1) {
        return Buffer.from(parts[1], 'base64');
      }
    }

    if (urlOrDataUri.startsWith('http://') || urlOrDataUri.startsWith('https://')) {
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 4000);
        const res = await fetch(urlOrDataUri, { signal: controller.signal });
        clearTimeout(timeout);
        if (res.ok) {
          const ab = await res.arrayBuffer();
          return Buffer.from(ab);
        }
      } catch (err) {
        // Fallback gracefully on fetch failures
      }
    }

    return null;
  }

  /**
   * Generates empathetic, actionable clinical summary and directives.
   */
  private static synthesizeClinicalInsights(
    status: ClinicalProgressionStatus,
    riskDelta: number,
    ssim: number | null,
    vitalsDelta: VitalsDelta,
    timeElapsedDays: number
  ): { clinicalSummary: string; recommendations: string[] } {
    const riskSign = riskDelta <= 0 ? '-' : '+';
    const absRiskPct = Math.abs(Math.round(riskDelta * 100));
    const timeStr = timeElapsedDays > 0 ? `over ${timeElapsedDays} day${timeElapsedDays === 1 ? '' : 's'}` : 'between checkups';

    let summary = '';
    const recommendations: string[] = [];

    switch (status) {
      case 'Improving / Healing':
        summary = `Patient exhibits positive clinical trajectory ${timeStr}, marked by a ${absRiskPct}% reduction in unified health risk score.`;
        if (ssim !== null) {
          summary += ` Structural visual similarity is ${(ssim * 100).toFixed(0)}%, indicating lesion resolution and tissue remodeling.`;
        }
        if (vitalsDelta.painDelta !== null && vitalsDelta.painDelta < 0) {
          summary += ` Reported pain decreased by ${Math.abs(vitalsDelta.painDelta)} point(s).`;
        }
        recommendations.push('Continue prescribed therapy / conservative home care regimen');
        recommendations.push('Perform follow-up routine self-check in 72 hours');
        recommendations.push('Maintain clean, protected lesion environment');
        break;

      case 'Deteriorating / Escalating':
        summary = `Clinical presentation indicates escalation ${timeStr} with a +${absRiskPct}% increase in multimodal risk score.`;
        if (vitalsDelta.painDelta !== null && vitalsDelta.painDelta > 0) {
          summary += ` Pain increased by +${vitalsDelta.painDelta} point(s).`;
        }
        if (vitalsDelta.tempDelta !== null && vitalsDelta.tempDelta > 0) {
          summary += ` Elevated body temperature observed (+${vitalsDelta.tempDelta}°C).`;
        }
        recommendations.push('Immediate in-person clinical physician evaluation recommended');
        recommendations.push('Do not delay care if red-flag symptoms (severe pain, fever, chest tightness) persist');
        recommendations.push('Export HL7 FHIR clinical referral report for triage physician review');
        break;

      case 'Stable / Unchanged':
      default:
        summary = `Patient presentation remains stable ${timeStr} with minimal risk delta (${riskSign}${absRiskPct}%).`;
        if (ssim !== null && ssim >= 0.80) {
          summary += ` Visual morphology shows high concordance (${(ssim * 100).toFixed(0)}%), suggesting dormant or steady-state condition.`;
        }
        recommendations.push('Continue monitoring symptoms on a regular daily schedule');
        recommendations.push('Consult clinical provider if new redness, warmth, or pain emerges');
        break;
    }

    return { clinicalSummary: summary, recommendations };
  }
}
