import { supabase } from '../config/supabase.js';
import { PharmacyDbService } from '../modules/pharmacy/pharmacyDbService.js';
import { PatientAllergy, PatientMedication } from '../modules/pharmacy/types.js';

export interface PatientProfileSummary {
  id: string;
  fullName?: string;
  email?: string;
  phone?: string;
  institutionId?: string;
  emergencyContact?: string;
}

export interface HealthScreeningSummary {
  id: string;
  riskLevel?: string;
  multimodalRiskScore?: number;
  clinicalFindings?: any;
  rppgVitals?: {
    heartRate?: number;
    breathingRate?: number;
    stressIndex?: number;
    spo2?: number;
  };
  physiologicalAlerts?: string[];
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
   */
  public static async retrievePatientContext(
    patientId: string,
    activeClaimId?: string
  ): Promise<PatientRagContext> {
    const cleanId = (patientId || '').trim();

    // 1. Fetch profile, medications, allergies, screenings, and claims in parallel
    const [
      profileRes,
      medications,
      allergies,
      screeningsRes,
      claimsRes
    ] = await Promise.all([
      // Profile
      supabase
        .from('profiles')
        .select('id, full_name, email, phone, institution_id, emergency_contact')
        .eq('id', cleanId)
        .maybeSingle(),

      // Medications via PharmacyDbService
      PharmacyDbService.getPatientMedications(cleanId, true).catch(() => []),

      // Allergies via PharmacyDbService
      PharmacyDbService.getPatientAllergies(cleanId).catch(() => []),

      // Health Screenings & Vitals
      supabase
        .from('health_screenings')
        .select('id, risk_level, multimodal_risk_score, clinical_findings, rppg_vitals_payload, physiological_alerts, created_at')
        .eq('patient_id', cleanId)
        .order('created_at', { ascending: false })
        .limit(3),

      // Claims & Copay Allocations
      supabase
        .from('claims')
        .select('id, clinical_category, description, status, extracted_bill_amount, approved_amount, currency, created_at')
        .or(`patient_id.eq.${cleanId},patient_phone.eq.${cleanId}`)
        .order('created_at', { ascending: false })
        .limit(5)
    ]);

    const profileData = profileRes?.data;
    const profile: PatientProfileSummary | null = profileData
      ? {
          id: profileData.id,
          fullName: profileData.full_name,
          email: profileData.email,
          phone: profileData.phone,
          institutionId: profileData.institution_id,
          emergencyContact: profileData.emergency_contact
        }
      : null;

    const screenings: HealthScreeningSummary[] = (screeningsRes?.data || []).map(s => {
      const vitals = s.rppg_vitals_payload || {};
      return {
        id: s.id,
        riskLevel: s.risk_level,
        multimodalRiskScore: s.multimodal_risk_score,
        clinicalFindings: s.clinical_findings,
        rppgVitals: {
          heartRate: vitals.heartRate || vitals.hr || vitals.pulse,
          breathingRate: vitals.breathingRate || vitals.rr,
          stressIndex: vitals.stressIndex || vitals.stress,
          spo2: vitals.spo2 || vitals.oxygen
        },
        physiologicalAlerts: Array.isArray(s.physiological_alerts) ? s.physiological_alerts : [],
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
        // Query explicit claim if not in patient list
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
   * Resolves patient_id from claim and returns the full clinical dossier.
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
      parts.push(`Patient: ${context.profile.fullName}`);
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
      if (latest.rppgVitals?.stressIndex) vitalsParts.push(`Stress Level: ${latest.rppgVitals.stressIndex}/100`);

      const vitalsStr = vitalsParts.length > 0 ? ` (${vitalsParts.join(', ')})` : '';
      parts.push(`Latest Clinical Screening: Risk ${latest.riskLevel || 'Normal'}${vitalsStr}`);

      if (latest.physiologicalAlerts && latest.physiologicalAlerts.length > 0) {
        parts.push(`Physiological Alerts: ${latest.physiologicalAlerts.join(', ')}`);
      }
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
