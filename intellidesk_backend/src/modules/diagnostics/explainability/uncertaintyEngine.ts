import { MultimodalFusionModel, MultimodalPredictionOutput } from '../fusion/MultimodalFusionModel.js';
import { UncertaintyBounds } from '../fusion/types.js';

export type UncertaintyTier = 'LOW_UNCERTAINTY' | 'MODERATE_UNCERTAINTY' | 'HIGH_EPISTEMIC_UNCERTAINTY';

export interface EpistemicUncertaintyReport {
  meanRiskScore: number; // e.g. 0.542
  stdDev: number; // e.g. 0.048
  variance: number; // e.g. 0.0023
  uncertaintyScoreFormatted: string; // e.g. "54.2% ± 4.8%"
  rawScoreFormatted: string; // e.g. "0.542 ± 0.048"
  confidenceInterval95: [number, number]; // [0.448, 0.636]
  confidencePercentage: number; // e.g. 90.4%
  uncertaintyTier: UncertaintyTier;
  monteCarloSamples: number;
  sampleScores: number[];
  clinicalInterpretation: string;
}

/**
 * Monte Carlo Dropout Uncertainty Quantification Engine.
 * Evaluates model epistemic uncertainty across N=10 stochastic forward passes
 * with active dropout (model.apply(input, { training: true })).
 */
export class MonteCarloUncertaintyEngine {
  public static readonly DEFAULT_SAMPLES = 10;

  /**
   * Evaluates epistemic uncertainty for a given 168-dimensional multimodal feature vector.
   */
  public static async quantifyUncertainty(
    concatenatedVector: number[],
    numSamples = MonteCarloUncertaintyEngine.DEFAULT_SAMPLES
  ): Promise<EpistemicUncertaintyReport> {
    const prediction: MultimodalPredictionOutput = await MultimodalFusionModel.predictWithMCDropout(
      concatenatedVector,
      numSamples
    );

    const mean = prediction.meanScore;
    const stdDev = prediction.epistemicStdDev;
    const variance = prediction.epistemicVariance;

    const uncertaintyScoreFormatted = `${(mean * 100).toFixed(1)}% ± ${(stdDev * 100).toFixed(1)}%`;
    const rawScoreFormatted = `${mean.toFixed(3)} ± ${stdDev.toFixed(3)}`;

    // Epistemic Uncertainty Classification
    let uncertaintyTier: UncertaintyTier = 'LOW_UNCERTAINTY';
    let clinicalInterpretation = 'Model exhibits high certainty with consistent multi-head convergence.';

    if (stdDev >= 0.12) {
      uncertaintyTier = 'HIGH_EPISTEMIC_UNCERTAINTY';
      clinicalInterpretation = 'High epistemic uncertainty detected. Presentation lies near the decision boundary between tiers; secondary clinical review strongly advised.';
    } else if (stdDev >= 0.05) {
      uncertaintyTier = 'MODERATE_UNCERTAINTY';
      clinicalInterpretation = 'Moderate uncertainty within acceptable clinical parameters. Predictions exhibit stable confidence interval spreads.';
    }

    return {
      meanRiskScore: mean,
      stdDev,
      variance,
      uncertaintyScoreFormatted,
      rawScoreFormatted,
      confidenceInterval95: [prediction.ciLower, prediction.ciUpper],
      confidencePercentage: Number((prediction.confidence * 100).toFixed(1)),
      uncertaintyTier,
      monteCarloSamples: numSamples,
      sampleScores: prediction.individualScores,
      clinicalInterpretation
    };
  }

  /**
   * Helper to format uncertainty bounds from standard MultimodalRiskResult.
   */
  public static formatUncertaintyBounds(bounds: UncertaintyBounds, score: number): string {
    const stdDev = Math.sqrt(bounds.epistemicVariance || 0);
    return `${(score * 100).toFixed(1)}% ± ${(stdDev * 100).toFixed(1)}%`;
  }
}
