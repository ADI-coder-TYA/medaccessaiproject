import { supabase } from '../config/supabase.js';
import { PharmacyDbService } from '../modules/pharmacy/pharmacyDbService.js';
import { PatientAllergy, PatientMedication } from '../modules/pharmacy/types.js';

export interface PatientProfileSummary {
  id: string;
  fullName?: string;
  email?: string;
  phone?: string;
  studentId?: string;
  institutionId?: string;
  emergencyContact?: string;
}

export interface CDSSEvaluationSummary {
  id: string;
  screeningId?: string | null;
  primaryICD11Code: string;
  primaryICD11Title: string;
  clinicalRationale?: string;
  treatmentPathway?: any;
  differentialDiagnoses?: Array<{
    code: string;
    title: string;
    probability: number;
  }>;
  isOverridden?: boolean;
  overriddenCode?: string;
  createdAt?: string;
}

export interface HealthScreeningSummary {
  id: string;
  riskLevel?: string;
  multimodalRiskScore?: number;
  primaryDiagnosis?: string;
  clinicalFindings?: any[];
  symptoms?: string[];
  bodyLocation?: string;
  painScale?: number;
  clinicalNotes?: string;
  rppgVitals?: {
    heartRate?: number;
    breathingRate?: number;
    stressIndex?: number;
    spo2?: number;
    temperatureCelsius?: number;
    systolicBP?: number;
    diastolicBP?: number;
  };
  physiologicalAlerts?: string[];
  cdssEvaluation?: CDSSEvaluationSummary | null;
  createdAt?: string;
}

export interface ClaimSummary {
  id: string;
  clinicalCategory?: string;
  description?: string;
  status?: string;
  extractedBillAmount?: number;
  approvedAmount?: number;
  currency?: string;
  createdAt?: string;
}

export interface PatientRagContext {
  patientId: string;
  profile?: PatientProfileSummary | null;
  medications: PatientMedication[];
  allergies: PatientAllergy[];
  screenings: HealthScreeningSummary[];
  claims: ClaimSummary[];
  activeClaim?: ClaimSummary | null;
  retrievedAt: string;
}

export class PatientClinicalRagService {
  /**
   * Retrieves comprehensive multi-entity clinical context for a patient.
   * Employs robust multi-identifier resolution across Supabase profile UUID, student ID, email, and phone.
   */
  public static async retrievePatientContext(
    patientId: string,
    activeClaimId?: string
  ): Promise<PatientRagContext> {
    const cleanId = (patientId || '').trim();

    // 1. Resolve all possible patient aliases
    const candidateIds = new Set<string>();
    if (cleanId) {
      candidateIds.add(cleanId);
      if (cleanId.startsWith('usr_pat_')) {
        candidateIds.add(cleanId.replace('usr_pat_', ''));
      }
      if (/^[0-9a-f]{8}-[0-9a-f]{4}/i.test(cleanId)) {
        const hex6 = cleanId.substring(0, 6).toUpperCase();
        candidateIds.add(`PAT-${hex6}`);
        candidateIds.add(`usr_pat_PAT-${hex6}`);
        candidateIds.add(`usr_pat_${cleanId}`);
      }
    }

    let profileData: any = null;
    try {
      // Look up profile by id, email, or phone (Note: profiles table does NOT have student_id column)
      const { data: prof, error: profErr } = await supabase
        .from('profiles')
        .select('id, full_name, email, phone, institution_id, emergency_contact')
        .or(`id.eq.${cleanId},email.eq.${cleanId},phone.eq.${cleanId}`)
        .maybeSingle();

      if (prof) {
        profileData = prof;
        if (prof.id) {
          candidateIds.add(prof.id);
          candidateIds.add(`usr_pat_${prof.id}`);
          const hex6 = prof.id.substring(0, 6).toUpperCase();
          candidateIds.add(`PAT-${hex6}`);
          candidateIds.add(`usr_pat_PAT-${hex6}`);
        }
        if (prof.email) candidateIds.add(prof.email);
        if (prof.phone) candidateIds.add(prof.phone);
      } else if (profErr) {
        console.warn(`[PatientClinicalRagService] Profile lookup notice: ${profErr.message}`);
      }
    } catch (e: any) {
      console.warn(`[PatientClinicalRagService] Notice resolving profile aliases for "${cleanId}": ${e.message}`);
    }

    // Also check patient_rosters for any mapped patient_id (e.g. PAT-2026-002)
    try {
      const rosterFilters = Array.from(candidateIds)
        .map(id => `patient_id.eq.${id},email.eq.${id},phone.eq.${id}`)
        .join(',');
      if (rosterFilters) {
        const { data: rosterEntries } = await supabase
          .from('patient_rosters')
          .select('id, patient_id, email, phone')
          .or(rosterFilters)
          .limit(5);

        if (rosterEntries) {
          for (const r of rosterEntries) {
            if (r.patient_id) {
              candidateIds.add(r.patient_id);
              candidateIds.add(`usr_pat_${r.patient_id}`);
            }
            if (r.id) candidateIds.add(r.id);
          }
        }
      }
    } catch (_) {}

    const idsArray = Array.from(candidateIds).filter(Boolean);
    const patientIdOrFilter = idsArray.length > 0 ? idsArray.map(id => `patient_id.eq.${id}`).join(',') : `patient_id.eq.${cleanId}`;
    const claimOrFilter = idsArray.length > 0
      ? idsArray.map(id => `patient_id.eq.${id},patient_phone.eq.${id}`).join(',')
      : `patient_id.eq.${cleanId}`;

    const effectiveProfileId = profileData?.id || cleanId;

    // 2. Fetch profile, medications, allergies, screenings, CDSS evaluations, and claims in parallel
    const [
      medications,
      allergies,
      screeningsRes,
      cdssRes,
      claimsRes
    ] = await Promise.all([
      // Medications via PharmacyDbService
      PharmacyDbService.getPatientMedications(effectiveProfileId, true).catch(() => []),

      // Allergies via PharmacyDbService
      PharmacyDbService.getPatientAllergies(effectiveProfileId).catch(() => []),

      // Health Screenings & Vitals
      supabase
        .from('health_screenings')
        .select('id, patient_id, risk_level, multimodal_risk_score, clinical_findings, symptom_payload, rppg_vitals_payload, physiological_alerts, created_at')
        .or(patientIdOrFilter)
        .order('created_at', { ascending: false })
        .limit(5),

      // CDSS Evaluations
      supabase
        .from('cdss_evaluations')
        .select('id, screening_id, patient_id, primary_icd11_code, primary_icd11_title, differential_diagnoses, treatment_pathway, attending_clinician_approval, created_at')
        .or(patientIdOrFilter)
        .order('created_at', { ascending: false })
        .limit(5),

      // Claims & Copay Allocations
      supabase
        .from('claims')
        .select('id, clinical_category, description, status, extracted_bill_amount, approved_amount, currency, created_at')
        .or(claimOrFilter)
        .order('created_at', { ascending: false })
        .limit(5)
    ]);

    const profile: PatientProfileSummary | null = profileData
      ? {
          id: profileData.id,
          fullName: profileData.full_name,
          email: profileData.email,
          phone: profileData.phone,
          studentId: `PAT-${profileData.id.substring(0, 6).toUpperCase()}`,
          institutionId: profileData.institution_id,
          emergencyContact: profileData.emergency_contact
        }
      : null;

    // Build CDSS map keyed by screening_id and id
    const cdssMap = new Map<string, CDSSEvaluationSummary>();
    const cdssList: CDSSEvaluationSummary[] = [];

    for (const c of cdssRes?.data || []) {
      const approval = c.attending_clinician_approval;
      const cdssSummary: CDSSEvaluationSummary = {
        id: c.id,
        screeningId: c.screening_id,
        primaryICD11Code: approval?.isOverridden && approval?.overriddenCode ? approval.overriddenCode : c.primary_icd11_code,
        primaryICD11Title: c.primary_icd11_title,
        treatmentPathway: c.treatment_pathway,
        differentialDiagnoses: Array.isArray(c.differential_diagnoses)
          ? c.differential_diagnoses.map((d: any) => ({
              code: d.code,
              title: d.title,
              probability: Math.round((d.probability ?? 0) * 100) / 100
            }))
          : [],
        isOverridden: approval?.isOverridden === true,
        overriddenCode: approval?.overriddenCode,
        createdAt: c.created_at
      };

      if (c.screening_id) {
        cdssMap.set(c.screening_id, cdssSummary);
      }
      cdssList.push(cdssSummary);
    }

    const screenings: HealthScreeningSummary[] = (screeningsRes?.data || []).map((s, idx) => {
      const vitals = s.rppg_vitals_payload || {};
      const sym = s.symptom_payload || {};
      const findings = Array.isArray(s.clinical_findings) ? s.clinical_findings : [];
      
      const primaryFinding = findings[0]?.condition || findings[0]?.diagnosis || sym?.primaryDiagnosis || sym?.clinicalImageDiagnosis;

      // Match CDSS evaluation by screening id, order fallback, or embedded in symptom_payload
      const embeddedCdss = sym?.cdss_evaluation || sym?.cdssEvaluation || sym?.clinical_decision_support;
      let matchingCdss = cdssMap.get(s.id) || cdssList[idx] || null;
      if (!matchingCdss && embeddedCdss) {
        matchingCdss = {
          id: embeddedCdss.id || s.id,
          screeningId: s.id,
          primaryICD11Code: embeddedCdss.primaryICD11Code || embeddedCdss.primary_icd11_code || 'WHO-ICD-11',
          primaryICD11Title: embeddedCdss.primaryICD11Title || embeddedCdss.primary_icd11_title || primaryFinding || 'Clinical Diagnosis',
          treatmentPathway: embeddedCdss.treatmentPathway || embeddedCdss.treatment_pathway,
          differentialDiagnoses: embeddedCdss.differentialDiagnoses || embeddedCdss.differential_diagnoses || [],
          isOverridden: false,
          createdAt: s.created_at
        };
      }

      const clinicalNotes = sym.clinicalNotes || sym.clinical_notes || sym.additionalNotes || sym.notes || undefined;

      return {
        id: s.id,
        riskLevel: s.risk_level,
        multimodalRiskScore: s.multimodal_risk_score,
        primaryDiagnosis: matchingCdss?.primaryICD11Title || primaryFinding || 'Multimodal Health Checkup',
        clinicalFindings: findings,
        symptoms: Array.isArray(sym.symptoms) ? sym.symptoms : [],
        bodyLocation: sym.bodyLocation || sym.anatomicalLocation,
        painScale: sym.painScale,
        clinicalNotes,
        rppgVitals: {
          heartRate: vitals.heartRateBpm ?? vitals.heartRate ?? vitals.hr ?? vitals.pulse,
          breathingRate: vitals.respiratoryRateBpm ?? vitals.breathingRate ?? vitals.respiratoryRate ?? vitals.rr,
          stressIndex: vitals.stressIndex ?? vitals.stress,
          spo2: vitals.oxygenSaturationSpo2 ?? vitals.spo2 ?? vitals.oxygen,
          temperatureCelsius: vitals.temperatureCelsius ?? vitals.temperature,
          systolicBP: vitals.bloodPressureSystolicMmHg ?? vitals.systolicBP,
          diastolicBP: vitals.bloodPressureDiastolicMmHg ?? vitals.diastolicBP
        },
        physiologicalAlerts: Array.isArray(s.physiological_alerts) ? s.physiological_alerts : [],
        cdssEvaluation: matchingCdss,
        createdAt: s.created_at
      };
    });

    const claims: ClaimSummary[] = (claimsRes?.data || []).map(c => ({
      id: c.id,
      clinicalCategory: c.clinical_category,
      description: c.description,
      status: c.status,
      extractedBillAmount: c.extracted_bill_amount,
      approvedAmount: c.approved_amount,
      currency: c.currency || 'INR',
      createdAt: c.created_at
    }));

    let activeClaim: ClaimSummary | null = null;
    if (activeClaimId) {
      activeClaim = claims.find(c => c.id === activeClaimId) || null;
      if (!activeClaim) {
        const { data: directClaim } = await supabase
          .from('claims')
          .select('id, clinical_category, description, status, extracted_bill_amount, approved_amount, currency, created_at')
          .eq('id', activeClaimId)
          .maybeSingle();

        if (directClaim) {
          activeClaim = {
            id: directClaim.id,
            clinicalCategory: directClaim.clinical_category,
            description: directClaim.description,
            status: directClaim.status,
            extractedBillAmount: directClaim.extracted_bill_amount,
            approvedAmount: directClaim.approved_amount,
            currency: directClaim.currency || 'INR',
            createdAt: directClaim.created_at
          };
        }
      }
    }

    return {
      patientId: cleanId,
      profile,
      medications,
      allergies,
      screenings,
      claims,
      activeClaim,
      retrievedAt: new Date().toISOString()
    };
  }

  /**
   * Retrieves context starting from a claim identifier.
   */
  public static async retrieveClaimContext(claimId: string): Promise<PatientRagContext> {
    const { data: claim } = await supabase
      .from('claims')
      .select('id, patient_id, patient_phone, clinical_category, description, status, extracted_bill_amount, approved_amount, currency, created_at')
      .eq('id', claimId)
      .maybeSingle();

    const targetPatientId = claim?.patient_id || claim?.patient_phone || 'anonymous-claimant';
    const context = await this.retrievePatientContext(targetPatientId, claimId);

    if (claim && !context.activeClaim) {
      context.activeClaim = {
        id: claim.id,
        clinicalCategory: claim.clinical_category,
        description: claim.description,
        status: claim.status,
        extractedBillAmount: claim.extracted_bill_amount,
        approvedAmount: claim.approved_amount,
        currency: claim.currency || 'INR',
        createdAt: claim.created_at
      };
    }

    return context;
  }

  /**
   * Formats retrieved multi-entity clinical records into concise prompt blocks.
   * Optimizes token budget while maximizing clinical personalization.
   */
  public static formatRagContextForPrompt(
    context: PatientRagContext,
    domain: 'MENTAL_HEALTH' | 'CLAIM_TRIAGE'
  ): string {
    const parts: string[] = [];

    // 1. Patient Identifiers & Demographics
    if (context.profile?.fullName) {
      parts.push(`Patient: ${context.profile.fullName}${context.profile.studentId ? ` (ID: ${context.profile.studentId})` : ''}`);
    }

    // 2. Active Medications
    if (context.medications.length > 0) {
      const medList = context.medications
        .map(m => `${m.medicationName}${m.dosage ? ` (${m.dosage})` : ''}`)
        .join('; ');
      parts.push(`Active Medications: ${medList}`);
    } else {
      parts.push(`Active Medications: None recorded`);
    }

    // 3. Known Allergies
    if (context.allergies.length > 0) {
      const algList = context.allergies
        .map(a => `${a.allergenGroup}${a.reactionDescription ? ` (Reaction: ${a.reactionDescription})` : ''}`)
        .join('; ');
      parts.push(`Known Drug Allergies: ${algList}`);
    } else {
      parts.push(`Known Drug Allergies: No documented allergies`);
    }

    // 4. Recent Health Screenings & Biometric Vitals
    if (context.screenings.length > 0) {
      const latest = context.screenings[0];
      const vitalsParts: string[] = [];
      if (latest.rppgVitals?.heartRate) vitalsParts.push(`Pulse: ${latest.rppgVitals.heartRate} bpm`);
      if (latest.rppgVitals?.spo2) vitalsParts.push(`SpO2: ${latest.rppgVitals.spo2}%`);
      if (latest.rppgVitals?.temperatureCelsius) vitalsParts.push(`Temp: ${latest.rppgVitals.temperatureCelsius}°C`);
      if (latest.rppgVitals?.systolicBP) vitalsParts.push(`BP: ${latest.rppgVitals.systolicBP}/${latest.rppgVitals.diastolicBP || 80} mmHg`);
      if (latest.rppgVitals?.breathingRate) vitalsParts.push(`Resp Rate: ${latest.rppgVitals.breathingRate}/min`);
      if (latest.rppgVitals?.stressIndex) vitalsParts.push(`Stress Level: ${latest.rppgVitals.stressIndex}/100`);

      const vitalsStr = vitalsParts.length > 0 ? ` [Vitals: ${vitalsParts.join(', ')}]` : '';
      const dateStr = latest.createdAt ? new Date(latest.createdAt).toLocaleDateString() : 'Recent';

      parts.push(`Latest Health Screening (${dateStr}):`);
      parts.push(`- Risk Level: ${latest.riskLevel || 'Normal'} (Multimodal Score: ${latest.multimodalRiskScore ?? 'N/A'})${vitalsStr}`);

      if (latest.primaryDiagnosis) {
        parts.push(`- Primary Clinical Condition / Diagnosis: ${latest.primaryDiagnosis}`);
      }
      if (latest.bodyLocation) {
        parts.push(`- Anatomical Location: ${latest.bodyLocation}`);
      }
      if (latest.symptoms && latest.symptoms.length > 0) {
        parts.push(`- Reported Symptoms: ${latest.symptoms.join(', ')}`);
      }
      if (latest.clinicalNotes) {
        parts.push(`- Patient & Clinician Notes: "${latest.clinicalNotes}"`);
      }
      if (latest.clinicalFindings && latest.clinicalFindings.length > 0) {
        const findingsList = latest.clinicalFindings.slice(0, 3).map((f: any) => `${f.condition || f.diagnosis} (${Math.round((f.probability || 0.5) * 100)}%)`).join(', ');
        parts.push(`- Differential Diagnostic Findings: ${findingsList}`);
      }
      if (latest.cdssEvaluation?.primaryICD11Code) {
        parts.push(`- CDSS Clinical Evaluation: ICD-11 ${latest.cdssEvaluation.primaryICD11Code} — ${latest.cdssEvaluation.primaryICD11Title}`);
        if (latest.cdssEvaluation.treatmentPathway?.recommendedRx?.length > 0) {
          const rxList = latest.cdssEvaluation.treatmentPathway.recommendedRx
            .map((r: any) => `${r.genericName} (${r.dosage})`)
            .join(', ');
          parts.push(`- Recommended First-Line Pathway: ${rxList}`);
        }
      }
      if (latest.physiologicalAlerts && latest.physiologicalAlerts.length > 0) {
        parts.push(`- Physiological Alerts: ${latest.physiologicalAlerts.join(', ')}`);
      }
    } else {
      parts.push(`Latest Health Screening: No recent screening recorded`);
    }

    // 5. Emergency Claims / Copay Financial Relief
    if (context.activeClaim) {
      const ac = context.activeClaim;
      const bill = ac.extractedBillAmount ? `${ac.currency} ${ac.extractedBillAmount}` : 'Unspecified';
      const approved = ac.approvedAmount ? `${ac.currency} ${ac.approvedAmount}` : 'Pending calculation';
      parts.push(`Active Emergency Claim: Category "${ac.clinicalCategory || 'Emergency'}", Status: ${ac.status || 'Pending'}, Billed: ${bill}, Copay Relieved: ${approved}`);
    } else if (context.claims.length > 0) {
      const latestClaim = context.claims[0];
      parts.push(`Recent Emergency Claim: Category "${latestClaim.clinicalCategory}", Status: ${latestClaim.status}`);
    }

    if (domain === 'MENTAL_HEALTH') {
      return `\n[CLINICAL PATIENT DOSSIER — RAG RETRIEVED CONTEXT]\n${parts.join('\n')}\n[END CLINICAL PATIENT DOSSIER]\nUse this clinical context to personalize responses with deep empathy, acknowledging their health context without stating raw database fields abruptly.`;
    }

    return `\n[CLINICAL CLAIMS & COPAY DOSSIER — RAG RETRIEVED CONTEXT]\n${parts.join('\n')}\n[END CLINICAL CLAIMS & COPAY DOSSIER]\nDirectly address the user's claim status, bills, and medical category in your assistance.`;
  }
}
