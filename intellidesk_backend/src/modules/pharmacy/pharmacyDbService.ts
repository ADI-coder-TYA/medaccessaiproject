import { supabase } from '../../config/supabase.js';
import { PatientAllergy, PatientMedication, RxScanSummary } from './types.js';

export class PharmacyDbService {
  // In-memory fallback stores for test isolation and offline resilience
  private static _allergiesStore: Map<string, PatientAllergy[]> = new Map();
  private static _medicationsStore: Map<string, PatientMedication[]> = new Map();
  private static _scansStore: Map<string, RxScanSummary> = new Map();

  /**
   * Technical Guardrail 2: Test Isolation in Memory Fallbacks
   * Resets mock patient allergies, active medications, and scan records between test runs.
   */
  public static clearInMemoryStore(): void {
    this._allergiesStore.clear();
    this._medicationsStore.clear();
    this._scansStore.clear();
  }

  /**
   * Retrieves patient allergies from Supabase with fallback to local store.
   */
  public static async getPatientAllergies(patientId: string): Promise<PatientAllergy[]> {
    if (!patientId) return [];

    try {
      const { data, error } = await supabase
        .from('patient_allergies')
        .select('*')
        .eq('patient_id', patientId)
        .order('created_at', { ascending: false });

      if (!error && Array.isArray(data) && data.length > 0) {
        return data.map(row => ({
          id: row.id,
          patientId: row.patient_id,
          allergenGroup: row.allergen_group,
          reactionDescription: row.reaction_description,
          createdAt: row.created_at
        }));
      }
    } catch (err) {
      console.warn(`[Pharmacy DB] Supabase allergy query failed for patient ${patientId}:`, err);
    }

    return this._allergiesStore.get(patientId) || [];
  }

  /**
   * Adds or updates a patient allergy record.
   */
  public static async addPatientAllergy(allergy: PatientAllergy): Promise<PatientAllergy> {
    const record: PatientAllergy = {
      ...allergy,
      id: allergy.id || `alg-${Date.now()}-${Math.random().toString(36).substring(7)}`,
      createdAt: allergy.createdAt || new Date().toISOString()
    };

    try {
      const { data, error } = await supabase
        .from('patient_allergies')
        .insert([{
          id: record.id,
          patient_id: record.patientId,
          allergen_group: record.allergenGroup,
          reaction_description: record.reactionDescription
        }])
        .select()
        .single();

      if (!error && data) {
        record.id = data.id;
      }
    } catch (err) {
      console.warn('[Pharmacy DB] Supabase allergy insert failed, caching in memory:', err);
    }

    const current = this._allergiesStore.get(record.patientId) || [];
    current.push(record);
    this._allergiesStore.set(record.patientId, current);

    return record;
  }

  /**
   * Retrieves active patient medications from Supabase with in-memory fallback.
   */
  public static async getPatientMedications(
    patientId: string,
    onlyActive: boolean = true
  ): Promise<PatientMedication[]> {
    if (!patientId) return [];

    try {
      let query = supabase
        .from('patient_medications')
        .select('*')
        .eq('patient_id', patientId);

      if (onlyActive) {
        query = query.eq('is_active', true);
      }

      const { data, error } = await query.order('created_at', { ascending: false });

      if (!error && Array.isArray(data) && data.length > 0) {
        return data.map(row => ({
          id: row.id,
          patientId: row.patient_id,
          medicationName: row.medication_name,
          activeIngredient: row.active_ingredient,
          dosage: row.dosage,
          isActive: row.is_active,
          createdAt: row.created_at
        }));
      }
    } catch (err) {
      console.warn(`[Pharmacy DB] Supabase medication query failed for patient ${patientId}:`, err);
    }

    const cached = this._medicationsStore.get(patientId) || [];
    return onlyActive ? cached.filter(m => m.isActive) : cached;
  }

  /**
   * Adds a medication to patient's active roster.
   */
  public static async addPatientMedication(med: PatientMedication): Promise<PatientMedication> {
    const record: PatientMedication = {
      ...med,
      id: med.id || `med-${Date.now()}-${Math.random().toString(36).substring(7)}`,
      createdAt: med.createdAt || new Date().toISOString()
    };

    try {
      const { data, error } = await supabase
        .from('patient_medications')
        .insert([{
          id: record.id,
          patient_id: record.patientId,
          medication_name: record.medicationName,
          active_ingredient: record.activeIngredient,
          dosage: record.dosage,
          is_active: record.isActive
        }])
        .select()
        .single();

      if (!error && data) {
        record.id = data.id;
      }
    } catch (err) {
      console.warn('[Pharmacy DB] Supabase medication insert failed, caching in memory:', err);
    }

    const current = this._medicationsStore.get(record.patientId) || [];
    current.push(record);
    this._medicationsStore.set(record.patientId, current);

    return record;
  }

  /**
   * Persists an evaluated prescription scan to Supabase with in-memory fallback.
   */
  public static async savePrescriptionScan(scan: RxScanSummary): Promise<RxScanSummary> {
    const record: RxScanSummary = {
      ...scan,
      id: scan.id || `rxscan-${Date.now()}-${Math.random().toString(36).substring(7)}`,
      createdAt: scan.createdAt || new Date().toISOString()
    };

    try {
      const { data, error } = await supabase
        .from('prescription_scans')
        .insert([{
          id: record.id,
          patient_id: record.patientId,
          image_url: record.imageUrl,
          extracted_drugs: record.extractedDrugs,
          ddi_warnings: record.ddiWarnings,
          allergy_conflicts: record.allergyConflicts,
          has_safety_conflict: record.hasSafetyConflict
        }])
        .select()
        .single();

      if (!error && data) {
        record.id = data.id;
      }
    } catch (err) {
      console.warn('[Pharmacy DB] Supabase prescription_scan insert failed, caching in memory:', err);
    }

    this._scansStore.set(record.id!, record);
    return record;
  }

  /**
   * Retrieves a saved prescription scan by ID.
   */
  public static async getPrescriptionScan(id: string): Promise<RxScanSummary | null> {
    try {
      const { data, error } = await supabase
        .from('prescription_scans')
        .select('*')
        .eq('id', id)
        .maybeSingle();

      if (!error && data) {
        return {
          id: data.id,
          patientId: data.patient_id,
          imageUrl: data.image_url,
          extractedDrugs: data.extracted_drugs || [],
          ddiWarnings: data.ddi_warnings || [],
          allergyConflicts: data.allergy_conflicts || [],
          hasSafetyConflict: data.has_safety_conflict,
          requiresPharmacistReview: data.has_safety_conflict,
          createdAt: data.created_at
        };
      }
    } catch (err) {
      console.warn(`[Pharmacy DB] Supabase scan lookup failed for ${id}:`, err);
    }

    return this._scansStore.get(id) || null;
  }

  /**
   * Technical Guardrail 3: Patient Safety Banner Override
   * Sets requires_clinical_pharmacist_review: true on claims table in Supabase.
   */
  public static async setClaimPharmacistReviewFlag(
    claimId: string,
    requiresReview: boolean = true
  ): Promise<boolean> {
    if (!claimId) return false;

    try {
      const { error } = await supabase
        .from('claims')
        .update({
          requires_clinical_pharmacist_review: requiresReview,
          is_flagged: requiresReview
        })
        .eq('id', claimId);

      if (!error) {
        console.log(`🔒 [RxSentinel] Flagged Claim ${claimId} with requires_clinical_pharmacist_review = ${requiresReview}`);
        return true;
      }
    } catch (err) {
      console.warn(`[Pharmacy DB] Could not update claim review flag for ${claimId}:`, err);
    }

    return false;
  }
}
