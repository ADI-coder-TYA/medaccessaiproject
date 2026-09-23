export type PhysiologicalAlertType =
  | 'CRITICAL_TACHYCARDIA'
  | 'CRITICAL_BRADYCARDIA'
  | 'CRITICAL_HYPOXIA'
  | 'CRITICAL_TACHYPNEA';

export interface PhysiologicalAlert {
  type: PhysiologicalAlertType;
  severity: 'CRITICAL_OVERRIDE' | 'MODERATE_WARNING';
  value: number;
  threshold: number;
  unit: string;
  clinicalDirective: string;
}

export interface BioSignalFrame {
  frameIndex: number;
  timestampMs: number;
  red: number;
  green: number;
  blue: number;
}

export interface rPPGAnalysisResult {
  heartRateBpm: number;
  hrvRmssdMs: number;
  respirationRateBpm: number;
  oxygenSaturationSpo2: number;
  confidenceScore: number;
  snrDb: number;
  sampleCount: number;
  durationSeconds: number;
  filteredWaveform: number[];
  interBeatIntervalsMs: number[];
  alerts: PhysiologicalAlert[];
  hasCriticalDerangement: boolean;
}

export interface VitalSignsPayload {
  temperatureCelsius?: number;
  heartRate?: number;
  oxygenSaturation?: number;
  respirationRate?: number;
  hrvRmssdMs?: number;
  bloodPressureSystolic?: number;
  bloodPressureDiastolic?: number;
  source?: 'rppg_camera' | 'manual_input';
  rppgResult?: rPPGAnalysisResult;
}
