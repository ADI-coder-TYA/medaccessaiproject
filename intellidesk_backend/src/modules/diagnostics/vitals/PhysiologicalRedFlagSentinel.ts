import { PhysiologicalAlert, PhysiologicalAlertType } from './types.js';

export interface VitalsInput {
  heartRate?: number;
  oxygenSaturation?: number;
  respirationRate?: number;
  hrvRmssdMs?: number;
}

export class PhysiologicalRedFlagSentinel {
  /**
   * Evaluate vital signs against critical clinical physiological boundaries.
   */
  public static evaluateVitals(vitals: VitalsInput): PhysiologicalAlert[] {
    const alerts: PhysiologicalAlert[] = [];

    // 1. Oxygen Saturation (SpO2)
    if (typeof vitals.oxygenSaturation === 'number' && !isNaN(vitals.oxygenSaturation) && vitals.oxygenSaturation > 0) {
      if (vitals.oxygenSaturation <= 90.0) {
        alerts.push({
          type: 'CRITICAL_HYPOXIA',
          severity: 'CRITICAL_OVERRIDE',
          value: Number(vitals.oxygenSaturation.toFixed(1)),
          threshold: 90.0,
          unit: '%',
          clinicalDirective: `Critical Hypoxemia: SpO2 ${vitals.oxygenSaturation.toFixed(1)}% (<= 90%). Emergency supplemental oxygen and acute airway management protocol required.`
        });
      } else if (vitals.oxygenSaturation < 92.0) {
        alerts.push({
          type: 'CRITICAL_HYPOXIA',
          severity: 'MODERATE_WARNING',
          value: Number(vitals.oxygenSaturation.toFixed(1)),
          threshold: 92.0,
          unit: '%',
          clinicalDirective: `Hypoxia Warning: SpO2 ${vitals.oxygenSaturation.toFixed(1)}% (< 92%). Patient requires respiratory monitoring and clinical evaluation.`
        });
      }
    }

    // 2. Heart Rate (BPM)
    if (typeof vitals.heartRate === 'number' && !isNaN(vitals.heartRate) && vitals.heartRate > 0) {
      if (vitals.heartRate >= 130.0) {
        alerts.push({
          type: 'CRITICAL_TACHYCARDIA',
          severity: 'CRITICAL_OVERRIDE',
          value: Number(vitals.heartRate.toFixed(1)),
          threshold: 130.0,
          unit: 'BPM',
          clinicalDirective: `Severe Tachycardia: Heart rate ${vitals.heartRate.toFixed(1)} BPM (>= 130 BPM). Risk of hemodynamic collapse, supraventricular arrhythmia, or septic shock.`
        });
      } else if (vitals.heartRate <= 40.0) {
        alerts.push({
          type: 'CRITICAL_BRADYCARDIA',
          severity: 'CRITICAL_OVERRIDE',
          value: Number(vitals.heartRate.toFixed(1)),
          threshold: 40.0,
          unit: 'BPM',
          clinicalDirective: `Severe Bradycardia: Heart rate ${vitals.heartRate.toFixed(1)} BPM (<= 40 BPM). Risk of cardiogenic syncope, high-grade AV block, or sinus arrest.`
        });
      }
    }

    // 3. Respiration Rate (breaths/min)
    if (typeof vitals.respirationRate === 'number' && !isNaN(vitals.respirationRate) && vitals.respirationRate > 0) {
      if (vitals.respirationRate >= 28.0) {
        alerts.push({
          type: 'CRITICAL_TACHYPNEA',
          severity: 'CRITICAL_OVERRIDE',
          value: Number(vitals.respirationRate.toFixed(1)),
          threshold: 28.0,
          unit: 'breaths/min',
          clinicalDirective: `Critical Tachypnea: Respiration rate ${vitals.respirationRate.toFixed(1)} breaths/min (>= 28). Cardinal early warning of acute respiratory failure or metabolic acidosis.`
        });
      }
    }

    return alerts;
  }

  /**
   * Determine whether any alerts represent critical safety overrides (floor >= 0.85).
   */
  public static hasCriticalOverride(alerts: PhysiologicalAlert[]): boolean {
    return alerts.some((a) => a.severity === 'CRITICAL_OVERRIDE');
  }

  /**
   * Convert alerts to safety net reason strings for MultimodalRiskResult.
   */
  public static toSafetyNetReasons(alerts: PhysiologicalAlert[]): string[] {
    return alerts.map((a) => `[${a.type}] ${a.clinicalDirective}`);
  }
}
