/**
 * HL7 FHIR R4 Standard Data Types & Clinical Diagnostic Resource Models
 * Conforming to HL7 FHIR Release 4 (v4.0.1) Specification
 */

export interface FHIRCoding {
  system: string;
  version?: string;
  code: string;
  display?: string;
  userSelected?: boolean;
}

export interface FHIRCodeableConcept {
  coding: FHIRCoding[];
  text?: string;
}

export interface FHIRReference {
  reference: string;
  type?: string;
  identifier?: Record<string, any>;
  display?: string;
}

export interface FHIRQuantity {
  value: number;
  comparator?: '<' | '<=' | '>=' | '>';
  unit?: string;
  system?: string;
  code?: string;
}

export interface FHIRComponent {
  code: FHIRCodeableConcept;
  valueQuantity?: FHIRQuantity;
  valueCodeableConcept?: FHIRCodeableConcept;
  valueString?: string;
  valueBoolean?: boolean;
  interpretation?: FHIRCodeableConcept[];
}

export interface FHIRAnnotation {
  authorString?: string;
  time?: string;
  text: string;
}

export interface FHIRAttachment {
  contentType?: string;
  language?: string;
  data?: string; // base64
  url?: string;
  size?: number;
  hash?: string;
  title?: string;
  creation?: string;
}

export interface FHIRMediaReport {
  comment?: string;
  link: FHIRReference;
}

/**
 * HL7 FHIR R4 Observation Resource
 * http://hl7.org/fhir/R4/observation.html
 */
export interface FHIRObservation {
  resourceType: 'Observation';
  id: string;
  meta?: {
    profile?: string[];
    lastUpdated?: string;
  };
  status: 'registered' | 'preliminary' | 'final' | 'amended' | 'corrected' | 'cancelled' | 'entered-in-error' | 'unknown';
  category: FHIRCodeableConcept[];
  code: FHIRCodeableConcept;
  subject: FHIRReference;
  effectiveDateTime: string;
  issued?: string;
  valueQuantity?: FHIRQuantity;
  valueCodeableConcept?: FHIRCodeableConcept;
  interpretation?: FHIRCodeableConcept[];
  note?: FHIRAnnotation[];
  component?: FHIRComponent[];
}

/**
 * HL7 FHIR R4 DiagnosticReport Resource
 * http://hl7.org/fhir/R4/diagnosticreport.html
 */
export interface FHIRDiagnosticReport {
  resourceType: 'DiagnosticReport';
  id: string;
  meta?: {
    profile?: string[];
    lastUpdated?: string;
  };
  status: 'registered' | 'partial' | 'preliminary' | 'final' | 'amended' | 'corrected' | 'appended' | 'cancelled' | 'entered-in-error' | 'unknown';
  category?: FHIRCodeableConcept[];
  code: FHIRCodeableConcept;
  subject: FHIRReference;
  effectiveDateTime: string;
  issued?: string;
  performer?: FHIRReference[];
  result?: FHIRReference[];
  media?: FHIRMediaReport[];
  conclusion?: string;
  conclusionCode?: FHIRCodeableConcept[];
  presentedForm?: FHIRAttachment[];
}

export interface FHIRBundleEntry {
  fullUrl: string;
  resource: FHIRObservation | FHIRDiagnosticReport | Record<string, any>;
}

/**
 * HL7 FHIR R4 Bundle Resource
 * http://hl7.org/fhir/R4/bundle.html
 */
export interface FHIRBundle {
  resourceType: 'Bundle';
  id: string;
  meta?: {
    lastUpdated?: string;
  };
  type: 'document' | 'message' | 'transaction' | 'transaction-response' | 'batch' | 'batch-response' | 'history' | 'searchset' | 'collection';
  timestamp: string;
  total?: number;
  entry: FHIRBundleEntry[];
}

/**
 * Standard Clinical LOINC & UCUM Mapping Constants
 */
export const LOINC_SYSTEM = 'http://loinc.org';
export const UCUM_SYSTEM = 'http://unitsofmeasure.org';
export const SNOMED_SYSTEM = 'http://snomed.info/sct';
export const OBSERVATION_CATEGORY_SYSTEM = 'http://terminology.hl7.org/CodeSystem/observation-category';
export const DIAGNOSTIC_SERVICE_SYSTEM = 'http://terminology.hl7.org/CodeSystem/v2-0074';
export const OBSERVATION_INTERPRETATION_SYSTEM = 'http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation';

export const CLINICAL_CODINGS = {
  // Multimodal Health Risk Assessment LOINC
  RISK_SCORE: {
    system: LOINC_SYSTEM,
    code: '98144-9',
    display: 'Clinical risk assessment score'
  },
  MULTIMODAL_REPORT: {
    system: LOINC_SYSTEM,
    code: '75275-8',
    display: 'Health risk assessment report'
  },
  // Vitals LOINC Codings
  BODY_TEMPERATURE: {
    system: LOINC_SYSTEM,
    code: '8310-5',
    display: 'Body temperature',
    unit: 'Cel',
    unitDisplay: '°C'
  },
  HEART_RATE: {
    system: LOINC_SYSTEM,
    code: '8867-4',
    display: 'Heart rate',
    unit: '/min',
    unitDisplay: 'bpm'
  },
  SYSTOLIC_BP: {
    system: LOINC_SYSTEM,
    code: '8480-6',
    display: 'Systolic blood pressure',
    unit: 'mm[Hg]',
    unitDisplay: 'mmHg'
  },
  DIASTOLIC_BP: {
    system: LOINC_SYSTEM,
    code: '8462-4',
    display: 'Diastolic blood pressure',
    unit: 'mm[Hg]',
    unitDisplay: 'mmHg'
  },
  OXYGEN_SATURATION: {
    system: LOINC_SYSTEM,
    code: '2708-6',
    display: 'Oxygen saturation in Arterial blood',
    unit: '%',
    unitDisplay: '%'
  },
  RESPIRATORY_RATE: {
    system: LOINC_SYSTEM,
    code: '9279-1',
    display: 'Respiratory rate',
    unit: '/min',
    unitDisplay: 'breaths/min'
  },
  PAIN_SEVERITY: {
    system: LOINC_SYSTEM,
    code: '72514-3',
    display: 'Pain severity - 0-10 verbal numeric rating score',
    unit: '{score}',
    unitDisplay: 'score (0-10)'
  },
  SYMPTOM_DURATION: {
    system: LOINC_SYSTEM,
    code: '68516-4',
    display: 'Symptom duration',
    unit: 'd',
    unitDisplay: 'days'
  }
} as const;
