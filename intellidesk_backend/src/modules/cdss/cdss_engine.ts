/**
 * CDSS Engine - Differential Diagnosis & Anatomical Location Gating
 * Wraps DifferentialDiagnosisEngine with strict ICD-11 anatomical masking prior to Softmax.
 */

import { DifferentialDiagnosisEngine } from './DifferentialDiagnosisEngine.js';
import { CDSSInputPayload, DifferentialDiagnosisCandidate } from './types.js';

export { DifferentialDiagnosisEngine };
export const CDSSEngine = DifferentialDiagnosisEngine;

export function evaluateCDSS(
  payload: CDSSInputPayload,
  temperature = 1.25
): DifferentialDiagnosisCandidate[] {
  return DifferentialDiagnosisEngine.evaluateCandidates(payload, temperature);
}
