import { DBHealthScreeningRow } from '../db/healthScreeningsDbService.js';
import {
  FHIRObservation,
  FHIRDiagnosticReport,
  FHIRBundle,
  FHIRComponent,
  FHIRReference,
  FHIRCodeableConcept,
  CLINICAL_CODINGS,
  OBSERVATION_CATEGORY_SYSTEM,
  DIAGNOSTIC_SERVICE_SYSTEM,
  OBSERVATION_INTERPRETATION_SYSTEM,
  UCUM_SYSTEM,
  LOINC_SYSTEM,
  SNOMED_SYSTEM
} from './types.js';

/**
 * FHIRConverterService
 * Transforms internal IntelliDesk diagnostic screenings into HL7 FHIR Release 4 (v4.0.1) standard resources.
 * Fully aligned with LOINC, UCUM, and EHR interoperability standards (Epic, Cerner).
 */
export class FHIRConverterService {
  /**
   * Builds a valid FHIR R4 Patient Reference.
   * Technical Guardrail 4: Provides de-identified structural fallback when patient is unlinked or anonymous.
   */
  public static buildPatientReference(patientId?: string | null, screeningId: string = 'unknown'): FHIRReference {
    if (patientId && patientId.trim().length > 0 && patientId !== 'null' && patientId !== 'anonymous') {
      return {
        reference: `Patient/${patientId.trim()}`,
        type: 'Patient',
        display: `Patient ${patientId.trim()}`
      };
    }

    // De-identified fallback for unlinked/anonymous screenings
    const safeHash = screeningId.replace(/[^a-zA-Z0-9]/g, '').substring(0, 12);
    return {
      reference: `urn:uuid:patient-deidentified-${safeHash}`,
      type: 'Patient',
      display: 'De-identified Patient (Intake Screening)'
    };
  }

  /**
   * Maps Clinical Risk Tier to HL7 FHIR Observation Interpretation code.
   */
  public static mapRiskInterpretation(riskLevel: string, riskScore: number): FHIRCodeableConcept[] {
    const normalized = (riskLevel || '').toUpperCase();

    if (normalized.includes('CRITICAL') || riskScore >= 0.75) {
      return [
        {
          coding: [
            {
              system: OBSERVATION_INTERPRETATION_SYSTEM,
              code: 'H',
              display: 'High / Critical Referral'
            }
          ],
          text: 'Critical Clinical Referral - Immediate Evaluation Required'
        }
      ];
    } else if (normalized.includes('MODERATE') || riskScore >= 0.40) {
      return [
        {
          coding: [
            {
              system: OBSERVATION_INTERPRETATION_SYSTEM,
              code: 'A',
              display: 'Abnormal / Moderate Need'
            }
          ],
          text: 'Moderate Need - Clinical Consultation Recommended within 24-48 Hours'
        }
      ];
    }

    return [
      {
        coding: [
          {
            system: OBSERVATION_INTERPRETATION_SYSTEM,
            code: 'N',
            display: 'Normal / Low Risk'
          }
        ],
        text: 'Low Risk - Routine Self-Care and Monitoring'
      }
    ];
  }

  /**
   * Technical Guardrail 2: Validates and converts vitals into strictly compliant LOINC & UCUM components.
   */
  public static buildVitalsComponents(vitals?: Record<string, any>, painScale?: number, durationDays?: number): FHIRComponent[] {
    const components: FHIRComponent[] = [];

    if (!vitals && painScale === undefined && durationDays === undefined) {
      return components;
    }

    // 1. Body Temperature (LOINC 8310-5, UCUM: Cel)
    const temp = vitals?.temperatureCelsius ?? vitals?.temp;
    if (temp !== undefined && temp !== null && !isNaN(Number(temp))) {
      components.push({
        code: {
          coding: [
            {
              system: CLINICAL_CODINGS.BODY_TEMPERATURE.system,
              code: CLINICAL_CODINGS.BODY_TEMPERATURE.code,
              display: CLINICAL_CODINGS.BODY_TEMPERATURE.display
            }
          ],
          text: 'Body Temperature'
        },
        valueQuantity: {
          value: Number(Number(temp).toFixed(1)),
          unit: CLINICAL_CODINGS.BODY_TEMPERATURE.unitDisplay,
          system: UCUM_SYSTEM,
          code: CLINICAL_CODINGS.BODY_TEMPERATURE.unit
        }
      });
    }

    // 2. Heart Rate (LOINC 8867-4, UCUM: /min)
    const hr = vitals?.heartRate ?? vitals?.hr;
    if (hr !== undefined && hr !== null && !isNaN(Number(hr))) {
      components.push({
        code: {
          coding: [
            {
              system: CLINICAL_CODINGS.HEART_RATE.system,
              code: CLINICAL_CODINGS.HEART_RATE.code,
              display: CLINICAL_CODINGS.HEART_RATE.display
            }
          ],
          text: 'Heart Rate'
        },
        valueQuantity: {
          value: Math.round(Number(hr)),
          unit: CLINICAL_CODINGS.HEART_RATE.unitDisplay,
          system: UCUM_SYSTEM,
          code: CLINICAL_CODINGS.HEART_RATE.unit
        }
      });
    }

    // 3. Systolic Blood Pressure (LOINC 8480-6, UCUM: mm[Hg])
    const sbp = vitals?.systolicBP ?? vitals?.systolic;
    if (sbp !== undefined && sbp !== null && !isNaN(Number(sbp))) {
      components.push({
        code: {
          coding: [
            {
              system: CLINICAL_CODINGS.SYSTOLIC_BP.system,
              code: CLINICAL_CODINGS.SYSTOLIC_BP.code,
              display: CLINICAL_CODINGS.SYSTOLIC_BP.display
            }
          ],
          text: 'Systolic Blood Pressure'
        },
        valueQuantity: {
          value: Math.round(Number(sbp)),
          unit: CLINICAL_CODINGS.SYSTOLIC_BP.unitDisplay,
          system: UCUM_SYSTEM,
          code: CLINICAL_CODINGS.SYSTOLIC_BP.unit
        }
      });
    }

    // 4. Diastolic Blood Pressure (LOINC 8462-4, UCUM: mm[Hg])
    const dbp = vitals?.diastolicBP ?? vitals?.diastolic;
    if (dbp !== undefined && dbp !== null && !isNaN(Number(dbp))) {
      components.push({
        code: {
          coding: [
            {
              system: CLINICAL_CODINGS.DIASTOLIC_BP.system,
              code: CLINICAL_CODINGS.DIASTOLIC_BP.code,
              display: CLINICAL_CODINGS.DIASTOLIC_BP.display
            }
          ],
          text: 'Diastolic Blood Pressure'
        },
        valueQuantity: {
          value: Math.round(Number(dbp)),
          unit: CLINICAL_CODINGS.DIASTOLIC_BP.unitDisplay,
          system: UCUM_SYSTEM,
          code: CLINICAL_CODINGS.DIASTOLIC_BP.unit
        }
      });
    }

    // 5. Oxygen Saturation SpO2 (LOINC 2708-6, UCUM: %)
    const spo2 = vitals?.oxygenSaturation ?? vitals?.spo2;
    if (spo2 !== undefined && spo2 !== null && !isNaN(Number(spo2))) {
      components.push({
        code: {
          coding: [
            {
              system: CLINICAL_CODINGS.OXYGEN_SATURATION.system,
              code: CLINICAL_CODINGS.OXYGEN_SATURATION.code,
              display: CLINICAL_CODINGS.OXYGEN_SATURATION.display
            }
          ],
          text: 'Oxygen Saturation'
        },
        valueQuantity: {
          value: Number(Number(spo2).toFixed(1)),
          unit: CLINICAL_CODINGS.OXYGEN_SATURATION.unitDisplay,
          system: UCUM_SYSTEM,
          code: CLINICAL_CODINGS.OXYGEN_SATURATION.unit
        }
      });
    }

    // 6. Respiratory Rate (LOINC 9279-1, UCUM: /min)
    const rr = vitals?.respiratoryRate ?? vitals?.rr;
    if (rr !== undefined && rr !== null && !isNaN(Number(rr))) {
      components.push({
        code: {
          coding: [
            {
              system: CLINICAL_CODINGS.RESPIRATORY_RATE.system,
              code: CLINICAL_CODINGS.RESPIRATORY_RATE.code,
              display: CLINICAL_CODINGS.RESPIRATORY_RATE.display
            }
          ],
          text: 'Respiratory Rate'
        },
        valueQuantity: {
          value: Math.round(Number(rr)),
          unit: CLINICAL_CODINGS.RESPIRATORY_RATE.unitDisplay,
          system: UCUM_SYSTEM,
          code: CLINICAL_CODINGS.RESPIRATORY_RATE.unit
        }
      });
    }

    // 7. Pain Severity Scale (LOINC 72514-3, UCUM: {score})
    if (painScale !== undefined && painScale !== null && !isNaN(Number(painScale))) {
      components.push({
        code: {
          coding: [
            {
              system: CLINICAL_CODINGS.PAIN_SEVERITY.system,
              code: CLINICAL_CODINGS.PAIN_SEVERITY.code,
              display: CLINICAL_CODINGS.PAIN_SEVERITY.display
            }
          ],
          text: 'Pain Severity'
        },
        valueQuantity: {
          value: Math.round(Number(painScale)),
          unit: CLINICAL_CODINGS.PAIN_SEVERITY.unitDisplay,
          system: UCUM_SYSTEM,
          code: CLINICAL_CODINGS.PAIN_SEVERITY.unit
        }
      });
    }

    // 8. Symptom Duration (LOINC 68516-4, UCUM: d)
    if (durationDays !== undefined && durationDays !== null && !isNaN(Number(durationDays))) {
      components.push({
        code: {
          coding: [
            {
              system: CLINICAL_CODINGS.SYMPTOM_DURATION.system,
              code: CLINICAL_CODINGS.SYMPTOM_DURATION.code,
              display: CLINICAL_CODINGS.SYMPTOM_DURATION.display
            }
          ],
          text: 'Symptom Duration'
        },
        valueQuantity: {
          value: Math.round(Number(durationDays)),
          unit: CLINICAL_CODINGS.SYMPTOM_DURATION.unitDisplay,
          system: UCUM_SYSTEM,
          code: CLINICAL_CODINGS.SYMPTOM_DURATION.unit
        }
      });
    }

    return components;
  }

  /**
   * Transforms a DB health screening record into a valid HL7 FHIR R4 Observation resource.
   */
  public static buildFHIRObservation(screening: DBHealthScreeningRow): FHIRObservation {
    const patientRef = this.buildPatientReference(screening.patient_id, screening.id);
    const symptoms = screening.symptom_payload || {};
    const vitals = symptoms.vitals;
    const painScale = symptoms.painScale !== undefined ? Number(symptoms.painScale) : undefined;
    const durationDays = symptoms.durationDays !== undefined ? Number(symptoms.durationDays) : undefined;

    const components = this.buildVitalsComponents(vitals, painScale, durationDays);

    // Add Uncertainty Bounds component if available
    const uncertainty = screening.uncertainty_bounds;
    if (uncertainty && typeof uncertainty === 'object') {
      const ciLower = uncertainty.ciLower ?? uncertainty.lower;
      const ciUpper = uncertainty.ciUpper ?? uncertainty.upper;
      const variance = uncertainty.epistemicVariance;

      if (ciLower !== undefined && ciUpper !== undefined) {
        components.push({
          code: {
            coding: [
              {
                system: 'https://intellidesk.ai/fhir/CodeSystem/ai-metrics',
                code: 'epistemic-uncertainty-ci',
                display: 'Monte Carlo Epistemic Uncertainty (95% CI)'
              }
            ],
            text: 'Monte Carlo Dropout 95% Confidence Interval'
          },
          valueString: `[${Number(ciLower).toFixed(3)} - ${Number(ciUpper).toFixed(3)}] (Variance: ${variance !== undefined ? Number(variance).toFixed(6) : 'N/A'})`
        });
      }
    }

    const notes: { text: string }[] = [];
    if (symptoms.bodyLocation) {
      notes.push({ text: `Anatomical Location: ${symptoms.bodyLocation}` });
    }
    if (symptoms.symptoms && Array.isArray(symptoms.symptoms) && symptoms.symptoms.length > 0) {
      notes.push({ text: `Reported Symptoms: ${symptoms.symptoms.join(', ')}` });
    }
    if (symptoms.additionalNotes) {
      notes.push({ text: `Patient Clinical Notes: ${symptoms.additionalNotes}` });
    }
    if (screening.clinical_findings && Array.isArray(screening.clinical_findings) && screening.clinical_findings.length > 0) {
      const findings = screening.clinical_findings.map((f: any) => typeof f === 'string' ? f : f.condition || JSON.stringify(f)).join('; ');
      notes.push({ text: `AI Vision Findings: ${findings}` });
    }

    return {
      resourceType: 'Observation',
      id: `obs-${screening.id}`,
      meta: {
        profile: ['http://hl7.org/fhir/StructureDefinition/Observation'],
        lastUpdated: screening.updated_at || screening.created_at || new Date().toISOString()
      },
      status: 'final',
      category: [
        {
          coding: [
            {
              system: OBSERVATION_CATEGORY_SYSTEM,
              code: 'exam',
              display: 'Exam'
            }
          ],
          text: 'Clinical Physical Examination & Multimodal Screening'
        }
      ],
      code: {
        coding: [
          {
            system: CLINICAL_CODINGS.RISK_SCORE.system,
            code: CLINICAL_CODINGS.RISK_SCORE.code,
            display: CLINICAL_CODINGS.RISK_SCORE.display
          }
        ],
        text: 'Multimodal Health Risk Score'
      },
      subject: patientRef,
      effectiveDateTime: screening.created_at || new Date().toISOString(),
      issued: screening.created_at || new Date().toISOString(),
      valueQuantity: {
        value: Number(Number(screening.multimodal_risk_score).toFixed(3)),
        unit: '{score}',
        system: UCUM_SYSTEM,
        code: '{score}'
      },
      interpretation: this.mapRiskInterpretation(screening.risk_level, screening.multimodal_risk_score),
      note: notes.length > 0 ? notes : undefined,
      component: components.length > 0 ? components : undefined
    };
  }

  /**
   * Builds an HL7 FHIR R4 DiagnosticReport resource bundled with its constituent Observation and media attachments.
   */
  public static buildFHIRDiagnosticReport(
    screening: DBHealthScreeningRow,
    cdssEvaluation?: { primaryICD11Code: string; primaryICD11Title?: string; [key: string]: any } | null
  ): FHIRBundle {
    const patientRef = this.buildPatientReference(screening.patient_id, screening.id);
    const observation = this.buildFHIRObservation(screening);

    const reportId = `diagrep-${screening.id}`;
    const effectiveTime = screening.created_at || new Date().toISOString();

    // Media & Visual attachments (original photo + Grad-CAM heatmap)
    const media: { comment: string; link: FHIRReference }[] = [];
    const presentedForm = [];

    if (screening.image_url) {
      media.push({
        comment: 'Clinical Symptom Photo (Mobile / Camera Intake)',
        link: {
          reference: screening.image_url,
          display: 'Clinical Symptom Photo'
        }
      });
      presentedForm.push({
        contentType: 'image/jpeg',
        url: screening.image_url,
        title: 'Patient Intake Image'
      });
    }

    if (screening.xai_heatmap_url) {
      media.push({
        comment: 'Explainable AI Grad-CAM Visual Heatmap Overlay',
        link: {
          reference: screening.xai_heatmap_url,
          display: 'Grad-CAM Attention Heatmap'
        }
      });
      presentedForm.push({
        contentType: screening.xai_heatmap_url.startsWith('data:image/svg') ? 'image/svg+xml' : 'image/jpeg',
        url: screening.xai_heatmap_url,
        title: 'Grad-CAM Attention Saliency Map'
      });
    }

    // Determine conclusion
    const riskScorePct = Math.round(screening.multimodal_risk_score * 100);
    const riskTier = screening.risk_level || 'LOW';
    let conclusion = `Multimodal AI Clinical Screening Result: ${riskTier} (${riskScorePct}% Risk Score).`;

    const symptoms = screening.symptom_payload || {};
    if (symptoms.bodyLocation) {
      conclusion += ` Primary anatomical region: ${symptoms.bodyLocation}.`;
    }
    if (screening.clinical_findings && screening.clinical_findings.length > 0) {
      const topFinding = typeof screening.clinical_findings[0] === 'string'
        ? screening.clinical_findings[0]
        : screening.clinical_findings[0].condition;
      conclusion += ` Primary differential finding: ${topFinding}.`;
    }

    // Conclusion codes with SNOMED and Guardrail 3: WHO ICD-11 linkage
    const conclusionCodes: FHIRCodeableConcept[] = [
      {
        coding: [
          {
            system: SNOMED_SYSTEM,
            code: riskTier === 'CRITICAL' ? '410605003' : '260385009',
            display: riskTier === 'CRITICAL' ? 'Immediate priority referral' : 'Normal priority referral'
          }
        ],
        text: riskTier
      }
    ];

    if (cdssEvaluation) {
      const icdCode = cdssEvaluation.primaryICD11Code || (cdssEvaluation as any).primary_icd11_code;
      const icdTitle = cdssEvaluation.primaryICD11Title || (cdssEvaluation as any).primary_icd11_title || icdCode;
      if (icdCode) {
        conclusionCodes.push({
          coding: [
            {
              system: 'http://id.who.int/icd/release/11/mms',
              code: icdCode,
              display: icdTitle
            }
          ],
          text: `WHO ICD-11: ${icdCode} - ${icdTitle}`
        });
      }
    }

    const diagnosticReport: FHIRDiagnosticReport = {
      resourceType: 'DiagnosticReport',
      id: reportId,
      meta: {
        profile: ['http://hl7.org/fhir/StructureDefinition/DiagnosticReport'],
        lastUpdated: screening.updated_at || screening.created_at || new Date().toISOString()
      },
      status: 'final',
      category: [
        {
          coding: [
            {
              system: DIAGNOSTIC_SERVICE_SYSTEM,
              code: 'OTH',
              display: 'Other'
            }
          ],
          text: 'AI-Assisted Multimodal Clinical Diagnostic Screening'
        }
      ],
      code: {
        coding: [
          {
            system: CLINICAL_CODINGS.MULTIMODAL_REPORT.system,
            code: CLINICAL_CODINGS.MULTIMODAL_REPORT.code,
            display: CLINICAL_CODINGS.MULTIMODAL_REPORT.display
          }
        ],
        text: 'Comprehensive Multimodal AI Screening Report'
      },
      subject: patientRef,
      effectiveDateTime: effectiveTime,
      issued: effectiveTime,
      performer: [
        {
          reference: `Organization/${screening.institution_id || 'intellidesk-health'}`,
          type: 'Organization',
          display: 'IntelliDesk Clinical Diagnostic AI Engine'
        }
      ],
      result: [
        {
          reference: `Observation/${observation.id}`,
          type: 'Observation',
          display: 'Multimodal Health Risk Score & Vitals'
        }
      ],
      media: media.length > 0 ? media : undefined,
      conclusion,
      conclusionCode: conclusionCodes,
      presentedForm: presentedForm.length > 0 ? presentedForm : undefined
    };

    // Return encapsulated FHIR R4 Bundle
    const bundle: FHIRBundle = {
      resourceType: 'Bundle',
      id: `bundle-diag-${screening.id}`,
      meta: {
        lastUpdated: new Date().toISOString()
      },
      type: 'collection',
      timestamp: new Date().toISOString(),
      total: 2,
      entry: [
        {
          fullUrl: `urn:uuid:${diagnosticReport.id}`,
          resource: diagnosticReport
        },
        {
          fullUrl: `urn:uuid:${observation.id}`,
          resource: observation
        }
      ]
    };

    return bundle;
  }
}
