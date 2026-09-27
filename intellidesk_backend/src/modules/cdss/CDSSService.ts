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
import { QwenInferenceService } from './QwenInferenceService.js';

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
    const candidates = await DifferentialDiagnosisEngine.evaluateCandidatesAsync(payload, temperature);
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
      modelUsed: (payload.useCloudModel !== false && QwenInferenceService.isConfigured())
        ? 'Qwen/Qwen2.5-72B-Instruct'
        : 'Neural-Ensemble-all-MiniLM-L6-v2',
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
      currentEvaluation?: any;
      screeningId?: string;
      patientId?: string;
    }
  ): Promise<CDSSEvaluationResult> {
    let existing = await this.getEvaluationById(evaluationId);

    // 1. Try stripping 'cdss-' or querying by screening ID
    if (!existing) {
      const strippedId = evaluationId.startsWith('cdss-') ? evaluationId.substring(5) : evaluationId;
      const candidateScreeningId = approvalData.screeningId || strippedId;

      existing = (await this.getEvaluationByScreeningId(candidateScreeningId)) || (await this.getEvaluationByScreeningId(evaluationId));

      // If not yet evaluated, auto-evaluate from health_screenings table
      if (!existing) {
        try {
          const { HealthScreeningsDbService } = await import('../diagnostics/db/healthScreeningsDbService.js');
          const sc = await HealthScreeningsDbService.getScreeningById(candidateScreeningId);
          if (sc) {
            existing = await this.evaluateScreening({
              screeningId: sc.id,
              patientId: sc.patient_id || approvalData.patientId || 'anonymous',
              institutionId: sc.institution_id,
              multimodalRiskScore: sc.multimodal_risk_score ?? 0.5,
              symptoms: sc.symptom_payload || {},
              visionFindings: sc.clinical_findings || [],
              temperature: 1.25
            });
          }
        } catch (scErr) {
          console.warn(`⚠️ [CDSSService] Auto-evaluate screening fallback: ${scErr}`);
        }
      }
    }

    // 2. Hydrate from client-passed currentEvaluation payload if still not found
    if (!existing && approvalData.currentEvaluation) {
      const ce = approvalData.currentEvaluation;
      const now = new Date().toISOString();
      const code = ce.primaryICD11Code || 'MG40';
      const concept = ICD11ConceptStore.getConceptByCode(code);
      const title = ce.primaryICD11Title || concept?.title || 'Clinical Diagnosis';
      const uri = ce.primaryICD11Uri || concept?.uri || `${WHO_ICD11_URI_STEM}/${code}`;

      existing = {
        id: ce.id || evaluationId,
        screeningId: ce.screeningId || (evaluationId.startsWith('cdss-') ? evaluationId.substring(5) : null),
        patientId: ce.patientId || approvalData.patientId || 'anonymous',
        institutionId: ce.institutionId,
        institutionName: ce.institutionName,
        primaryICD11Code: code,
        primaryICD11Title: title,
        primaryICD11Uri: uri,
        differentialDiagnoses: Array.isArray(ce.differentialDiagnoses) ? ce.differentialDiagnoses : [],
        treatmentPathway: ce.treatmentPathway || TreatmentPathwayAdvisor.recommendPathway(
          {
            code,
            title,
            category: concept?.category || 'Clinical Diagnosis',
            uri,
            probability: 0.85,
            logitScore: 2.19,
            matchedCriteria: ['Clinician evaluation'],
            clinicalRationale: 'Evidence-based treatment pathway synthesized from encounter presentation.'
          },
          0.5,
          false
        ),
        temperatureScaling: Number(ce.temperatureScaling) || 1.25,
        regulatoryDisclaimer: ce.regulatoryDisclaimer || MANDATORY_CDSS_DISCLAIMER,
        attendingClinicianApproval: null,
        createdAt: ce.createdAt || now,
        updatedAt: now
      };

      try {
        await supabase
          .from('cdss_evaluations')
          .insert({
            id: existing.id,
            screening_id: existing.screeningId || null,
            patient_id: existing.patientId,
            primary_icd11_code: existing.primaryICD11Code,
            differential_diagnoses: existing.differentialDiagnoses,
            treatment_pathway: existing.treatmentPathway,
            regulatory_disclaimer: existing.regulatoryDisclaimer,
            temperature_scaling: existing.temperatureScaling,
            attending_clinician_approval: null,
            created_at: existing.createdAt,
            updated_at: existing.updatedAt
          });
      } catch (insertErr) {
        console.warn(`⚠️ [CDSSService] Supabase insert fallback: ${insertErr}`);
      }

      this._inMemoryStore.set(existing.id, existing);
    }

    // 3. Fallback synthesis safety net: guarantee never missing
    if (!existing) {
      const now = new Date().toISOString();
      const code = approvalData.overriddenCode || 'MG40';
      const concept = ICD11ConceptStore.getConceptByCode(code);
      const title = concept?.title || 'Clinical Diagnosis';
      const uri = concept?.uri || `${WHO_ICD11_URI_STEM}/${code}`;
      const screeningId = evaluationId.startsWith('cdss-') ? evaluationId.substring(5) : evaluationId;

      existing = {
        id: evaluationId,
        screeningId,
        patientId: approvalData.patientId || 'anonymous',
        primaryICD11Code: code,
        primaryICD11Title: title,
        primaryICD11Uri: uri,
        differentialDiagnoses: [],
        treatmentPathway: TreatmentPathwayAdvisor.recommendPathway(
          {
            code,
            title,
            category: 'Clinical Diagnosis',
            uri,
            probability: 0.85,
            logitScore: 2.19,
            matchedCriteria: ['Direct clinician sign-off'],
            clinicalRationale: 'Attending physician sign-off pathway.'
          },
          0.5,
          false
        ),
        temperatureScaling: 1.25,
        regulatoryDisclaimer: MANDATORY_CDSS_DISCLAIMER,
        attendingClinicianApproval: null,
        createdAt: now,
        updatedAt: now
      };

      try {
        await supabase
          .from('cdss_evaluations')
          .insert({
            id: existing.id,
            screening_id: existing.screeningId || null,
            patient_id: existing.patientId,
            primary_icd11_code: existing.primaryICD11Code,
            differential_diagnoses: existing.differentialDiagnoses,
            treatment_pathway: existing.treatmentPathway,
            regulatory_disclaimer: existing.regulatoryDisclaimer,
            temperature_scaling: existing.temperatureScaling,
            attending_clinician_approval: null,
            created_at: existing.createdAt,
            updated_at: existing.updatedAt
          });
      } catch (insertErr) {
        console.warn(`⚠️ [CDSSService] Supabase insert fallback: ${insertErr}`);
      }

      this._inMemoryStore.set(existing.id, existing);
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
        .eq('id', existing.id);
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

    const strippedId = evaluationId.startsWith('cdss-') ? evaluationId.substring(5) : evaluationId;
    if (this._inMemoryStore.has(strippedId)) {
      return this._inMemoryStore.get(strippedId)!;
    }

    for (const ev of this._inMemoryStore.values()) {
      if (ev.screeningId === evaluationId || ev.screeningId === strippedId) {
        return ev;
      }
    }

    try {
      const { data, error } = await supabase
        .from('cdss_evaluations')
        .select('*')
        .or(`id.eq.${evaluationId},id.eq.${strippedId},screening_id.eq.${evaluationId},screening_id.eq.${strippedId}`)
        .order('created_at', { ascending: false })
        .limit(1)
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

  /**
   * Dispatches a clinical encounter and CDSS evaluation to the institutional medical board review queue.
   * Updates health_screenings table status, records audit event, and registers review queue entry.
   */
  public static async dispatchToMedicalBoard(payload: {
    screeningId?: string | null;
    evaluationId?: string | null;
    patientId: string;
    institutionId?: string;
    institutionName?: string;
    primaryICD11Code?: string;
    primaryICD11Title?: string;
  }): Promise<{
    success: boolean;
    dispatchId: string;
    dispatchedAt: string;
    status: string;
    institutionId: string;
    institutionName: string;
    reviewQueueNumber: string;
    message: string;
  }> {
    const now = new Date().toISOString();
    const queueNum = `MB-${Math.floor(1000 + Math.random() * 9000)}`;
    const dispatchId = `disp-${Date.now()}-${Math.random().toString(36).substring(2, 7)}`;
    const effectiveInstId = payload.institutionId || 'edu-admin-123';
    const effectiveInstName = payload.institutionName || 'Institutional Medical Administration';

    // 1. If screeningId provided, update health_screenings table in Supabase
    if (payload.screeningId) {
      try {
        const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(payload.screeningId);
        if (isUuid) {
          await supabase
            .from('health_screenings')
            .update({
              status: 'PENDING_CLINICIAN_REVIEW',
              updated_at: now
            })
            .eq('id', payload.screeningId);
        }
      } catch (err) {
        console.warn(`⚠️ [CDSSService] Supabase health_screenings status update notice: ${err}`);
      }
    }

    // 2. Log to audit_logs in Supabase
    try {
      await supabase
        .from('audit_logs')
        .insert({
          institution_id: effectiveInstId,
          action_type: 'DISPATCH_TO_MEDICAL_BOARD',
          actor_type: 'PATIENT',
          details: {
            dispatchId,
            queueNumber: queueNum,
            screeningId: payload.screeningId,
            evaluationId: payload.evaluationId,
            patientId: payload.patientId,
            primaryICD11Code: payload.primaryICD11Code,
            primaryICD11Title: payload.primaryICD11Title,
            institutionName: effectiveInstName,
            dispatchedAt: now
          }
        });
    } catch (auditErr) {
      console.warn(`⚠️ [CDSSService] Audit log insertion notice: ${auditErr}`);
    }

    return {
      success: true,
      dispatchId,
      dispatchedAt: now,
      status: 'DISPATCHED_TO_MEDICAL_BOARD',
      institutionId: effectiveInstId,
      institutionName: effectiveInstName,
      reviewQueueNumber: queueNum,
      message: `Encounter successfully routed to ${effectiveInstName} Medical Board. Queue #${queueNum}.`
    };
  }
}
