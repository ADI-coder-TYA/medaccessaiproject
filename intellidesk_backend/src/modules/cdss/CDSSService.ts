import crypto from 'crypto';
import { supabase } from '../../config/supabase.js';
import { logAuditEvent } from '../../services/auditLogger.js';
import {
  CDSSInputPayload,
  CDSSEvaluationResult,
  ClinicianApproval,
  MANDATORY_CDSS_DISCLAIMER,
  WHO_ICD11_URI_STEM
} from './types.js';
import { ICD11ConceptStore } from './ICD11ConceptStore.js';
import { DifferentialDiagnosisEngine } from './DifferentialDiagnosisEngine.js';
import { TreatmentPathwayAdvisor } from './TreatmentPathwayAdvisor.js';

export class CDSSService {
  // In-memory store for air-gapped / offline fallback and automated unit testing (Guardrail 4)
  private static _inMemoryStore: Map<string, CDSSEvaluationResult> = new Map();

  /**
   * Clears the in-memory cache to ensure unit test isolation.
   */
  public static clearInMemoryStore(): void {
    this._inMemoryStore.clear();
  }

  /**
   * Evaluates patient screening findings against WHO ICD-11 knowledge base.
   */
  public static async evaluateScreening(payload: CDSSInputPayload): Promise<CDSSEvaluationResult> {
    const temperature = payload.temperature ?? 1.25;

    // 1. Compute Differential Diagnosis Candidates with Guardrail 2 (T = 1.25, [-20, 20] logit clipping)
    const candidates = DifferentialDiagnosisEngine.evaluateCandidates(payload, temperature);
    const primaryCandidate = candidates[0];

    // 2. Formulate Evidence-Based Treatment Pathway
    const treatmentPathway = TreatmentPathwayAdvisor.recommendPathway(
      primaryCandidate,
      payload.multimodalRiskScore,
      false
    );

    // Resolve Institution from payload, patient rosters, or profiles
    let institutionId = payload.institutionId;
    let institutionName = payload.institutionName;

    if (!institutionId && payload.patientId && payload.patientId !== 'anonymous') {
      try {
        const { data: p } = await supabase
          .from('patient_rosters')
          .select('institution_id')
          .or(`patient_id.eq.${payload.patientId},email.eq.${payload.patientId}`)
          .maybeSingle();

        if (p?.institution_id) {
          institutionId = p.institution_id;
        } else {
          const { data: prof } = await supabase
            .from('profiles')
            .select('institution_id')
            .or(`id.eq.${payload.patientId},email.eq.${payload.patientId}`)
            .maybeSingle();
          if (prof?.institution_id) {
            institutionId = prof.institution_id;
          }
        }
      } catch (_) {}
    }

    if (institutionId && (!institutionName || institutionName === institutionId)) {
      try {
        const { data: inst } = await supabase
          .from('institutions')
          .select('name')
          .eq('id', institutionId)
          .maybeSingle();
        if (inst?.name) {
          institutionName = inst.name;
        }
      } catch (_) {}
    }

    const now = new Date().toISOString();
    const evaluationId = `cdss-${Date.now()}-${Math.random().toString(36).substring(2, 8)}`;

    const result: CDSSEvaluationResult = {
      id: evaluationId,
      screeningId: payload.screeningId || null,
      patientId: payload.patientId,
      institutionId,
      institutionName: institutionName || institutionId,
      primaryICD11Code: primaryCandidate.code,
      primaryICD11Title: primaryCandidate.title,
      primaryICD11Uri: primaryCandidate.uri,
      differentialDiagnoses: candidates,
      treatmentPathway,
      temperatureScaling: temperature,
      regulatoryDisclaimer: MANDATORY_CDSS_DISCLAIMER,
      attendingClinicianApproval: null,
      createdAt: now,
      updatedAt: now
    };

    // 3. Persist to Supabase with local memory fallback (Guardrail 4)
    try {
      const { data, error } = await supabase
        .from('cdss_evaluations')
        .insert({
          id: result.id,
          screening_id: result.screeningId || null,
          patient_id: result.patientId,
          primary_icd11_code: result.primaryICD11Code,
          differential_diagnoses: result.differentialDiagnoses,
          treatment_pathway: result.treatmentPathway,
          regulatory_disclaimer: result.regulatoryDisclaimer,
          temperature_scaling: result.temperatureScaling,
          attending_clinician_approval: null,
          created_at: result.createdAt,
          updated_at: result.updatedAt
        })
        .select('*')
        .single();

      if (!error && data) {
        result.id = data.id;
      }
    } catch (dbErr) {
      console.warn(`⚠️ [CDSSService] Offline / local cache fallback: ${dbErr}`);
    }

    this._inMemoryStore.set(result.id, result);
    return result;
  }

  /**
   * Technical Guardrail 3: Medico-Legal Provenance for Overridden Codes
   * Records clinician approval or code override with full audit trail.
   */
  public static async approveEvaluation(
    evaluationId: string,
    approvalData: {
      clinicianId: string;
      clinicianName: string;
      isOverridden?: boolean;
      overriddenCode?: string;
      overrideNotes?: string;
    }
  ): Promise<CDSSEvaluationResult> {
    const existing = await this.getEvaluationById(evaluationId);
    if (!existing) {
      throw new Error(`CDSS evaluation not found: ${evaluationId}`);
    }

    const now = new Date().toISOString();
    const isOverridden = Boolean(approvalData.isOverridden && approvalData.overriddenCode);
    const originalCode = existing.primaryICD11Code;
    const finalCode = isOverridden ? approvalData.overriddenCode!.trim().toUpperCase() : originalCode;

    // Cryptographic signature hash for medico-legal non-repudiation
    const signaturePayload = `${approvalData.clinicianId}:${now}:${originalCode}:${finalCode}:${approvalData.overrideNotes || ''}`;
    const signatureHash = crypto.createHash('sha256').update(signaturePayload).digest('hex');

    const approval: ClinicianApproval = {
      clinicianId: approvalData.clinicianId,
      clinicianName: approvalData.clinicianName,
      approvedAt: now,
      isOverridden,
      originalCode,
      overriddenCode: isOverridden ? finalCode : undefined,
      overrideNotes: approvalData.overrideNotes || (isOverridden ? 'Clinician override' : 'Standard approval'),
      signatureHash
    };

    // If overridden, update primary code, title, URI, and regenerate pathway
    if (isOverridden) {
      const concept = ICD11ConceptStore.getConceptByCode(finalCode);
      existing.primaryICD11Code = finalCode;
      existing.primaryICD11Title = concept ? concept.title : `Overridden Diagnosis (${finalCode})`;
      existing.primaryICD11Uri = concept ? concept.uri : `${WHO_ICD11_URI_STEM}/${finalCode}`;

      // Update treatment pathway to reflect the newly selected code
      existing.treatmentPathway = TreatmentPathwayAdvisor.recommendPathway(
        {
          code: finalCode,
          title: existing.primaryICD11Title,
          category: concept?.category || 'Clinical Diagnosis',
          uri: existing.primaryICD11Uri,
          probability: 1.0,
          logitScore: 10.0,
          matchedCriteria: ['Clinician manual selection override'],
          clinicalRationale: approvalData.overrideNotes || 'Attending physician manual diagnostic override'
        },
        0.5,
        true
      );
    }

    existing.attendingClinicianApproval = approval;
    existing.updatedAt = now;

    // 1. Update in Supabase
    try {
      await supabase
        .from('cdss_evaluations')
        .update({
          primary_icd11_code: existing.primaryICD11Code,
          treatment_pathway: existing.treatmentPathway,
          attending_clinician_approval: approval,
          updated_at: now
        })
        .eq('id', evaluationId);
    } catch (err) {
      console.warn(`⚠️ [CDSSService] Supabase update fallback: ${err}`);
    }

    // 2. Medico-Legal Provenance Audit Log (Guardrail 3)
    await logAuditEvent(
      'inst-001',
      existing.id,
      isOverridden ? 'CDSS_ICD11_OVERRIDE' : 'CDSS_PATHWAY_APPROVAL',
      approvalData.clinicianId,
      {
        patientId: existing.patientId,
        screeningId: existing.screeningId,
        originalCode,
        overriddenCode: isOverridden ? finalCode : null,
        isOverridden,
        overrideNotes: approval.overrideNotes,
        signatureHash,
        approvedAt: now
      },
      'CDSS_EVALUATION'
    );

    this._inMemoryStore.set(existing.id, existing);
    return existing;
  }

  /**
   * Retrieves a CDSS evaluation by ID.
   */
  public static async getEvaluationById(evaluationId: string): Promise<CDSSEvaluationResult | null> {
    if (this._inMemoryStore.has(evaluationId)) {
      return this._inMemoryStore.get(evaluationId)!;
    }

    try {
      const { data, error } = await supabase
        .from('cdss_evaluations')
        .select('*')
        .eq('id', evaluationId)
        .maybeSingle();

      if (!error && data) {
        const evalResult: CDSSEvaluationResult = {
          id: data.id,
          screeningId: data.screening_id,
          patientId: data.patient_id,
          primaryICD11Code: data.primary_icd11_code,
          primaryICD11Title: data.differential_diagnoses?.[0]?.title || data.primary_icd11_code,
          primaryICD11Uri: `${WHO_ICD11_URI_STEM}/${data.primary_icd11_code}`,
          differentialDiagnoses: data.differential_diagnoses || [],
          treatmentPathway: data.treatment_pathway,
          temperatureScaling: Number(data.temperature_scaling) || 1.25,
          regulatoryDisclaimer: data.regulatory_disclaimer || MANDATORY_CDSS_DISCLAIMER,
          attendingClinicianApproval: data.attending_clinician_approval || null,
          createdAt: data.created_at,
          updatedAt: data.updated_at
        };
        this._inMemoryStore.set(evalResult.id, evalResult);
        return evalResult;
      }
    } catch (e) {
      console.warn(`⚠️ [CDSSService] Fetch by ID fallback: ${e}`);
    }

    return null;
  }

  /**
   * Retrieves CDSS evaluation associated with a specific screening ID.
   */
  public static async getEvaluationByScreeningId(screeningId: string): Promise<CDSSEvaluationResult | null> {
    for (const ev of this._inMemoryStore.values()) {
      if (ev.screeningId === screeningId) {
        return ev;
      }
    }

    try {
      const { data, error } = await supabase
        .from('cdss_evaluations')
        .select('*')
        .eq('screening_id', screeningId)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();

      if (!error && data) {
        return this.getEvaluationById(data.id);
      }
    } catch (e) {
      console.warn(`⚠️ [CDSSService] Fetch by screeningId fallback: ${e}`);
    }

    return null;
  }
}
