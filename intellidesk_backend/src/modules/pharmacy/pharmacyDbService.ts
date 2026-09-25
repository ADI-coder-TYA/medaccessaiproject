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
    const isUuid = allergy.id && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(allergy.id);
    const insertPayload: any = {
      patient_id: allergy.patientId,
      allergen_group: allergy.allergenGroup,
      reaction_description: allergy.reactionDescription || 'Marked in patient health profile'
    };
    if (isUuid) {
      insertPayload.id = allergy.id;
    }

    const record: PatientAllergy = {
      ...allergy,
      createdAt: allergy.createdAt || new Date().toISOString()
    };

    try {
      const { data, error } = await supabase
        .from('patient_allergies')
        .insert([insertPayload])
        .select()
        .single();

      if (!error && data) {
        record.id = data.id;
        record.createdAt = data.created_at;
      } else if (error) {
        console.warn('[Pharmacy DB] Supabase allergy insert failed:', error.message);
      }
    } catch (err) {
      console.warn('[Pharmacy DB] Supabase allergy insert failed, caching in memory:', err);
    }

    if (!record.id) {
      record.id = `alg-${Date.now()}`;
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
    const isUuid = med.id && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(med.id);
    const insertPayload: any = {
      patient_id: med.patientId,
      medication_name: med.medicationName,
      active_ingredient: med.activeIngredient,
      dosage: med.dosage || 'Standard dose',
      is_active: med.isActive !== false
    };
    if (isUuid) {
      insertPayload.id = med.id;
    }

    const record: PatientMedication = {
      ...med,
      createdAt: med.createdAt || new Date().toISOString()
    };

    try {
      const { data, error } = await supabase
        .from('patient_medications')
        .insert([insertPayload])
        .select()
        .single();

      if (!error && data) {
        record.id = data.id;
        record.createdAt = data.created_at;
      } else if (error) {
        console.warn('[Pharmacy DB] Supabase medication insert failed:', error.message);
      }
    } catch (err) {
      console.warn('[Pharmacy DB] Supabase medication insert failed, caching in memory:', err);
    }

    if (!record.id) {
      record.id = `med-${Date.now()}`;
    }

    const current = this._medicationsStore.get(record.patientId) || [];
    current.push(record);
    this._medicationsStore.set(record.patientId, current);

    return record;
  }

  /**
   * Deletes a medication from patient roster by ID or medication name.
   */
  public static async deletePatientMedication(idOrName: string, patientId?: string): Promise<boolean> {
    try {
      const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(idOrName);
      let query = supabase.from('patient_medications').delete();
      if (isUuid) {
        query = query.eq('id', idOrName);
      } else {
        query = query.ilike('medication_name', `%${idOrName}%`);
      }
      if (patientId) {
        query = query.eq('patient_id', patientId);
      }
      const { error } = await query;
      if (error) {
        console.warn('[Pharmacy DB] Supabase delete medication notice:', error.message);
      }
      return true;
    } catch (e) {
      console.warn('[Pharmacy DB] Delete medication error:', e);
      return false;
    }
  }

  /**
   * Deletes an allergy from patient records by allergen group or record ID.
   */
  public static async deletePatientAllergy(patientId: string, allergenGroupOrId: string): Promise<boolean> {
    try {
      const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(allergenGroupOrId);
      let query = supabase.from('patient_allergies').delete();
      if (isUuid) {
        query = query.eq('id', allergenGroupOrId);
      } else {
        query = query.eq('patient_id', patientId);
        const term = allergenGroupOrId.toUpperCase();
        if (term === 'SULFA' || term === 'SULFONAMIDES' || term === 'SULFONAMIDE') {
          query = query.or('allergen_group.ilike.%sulfa%,allergen_group.ilike.%sulfonamide%');
        } else if (term.startsWith('PENICILLIN')) {
          query = query.or('allergen_group.ilike.%penicillin%');
        } else {
          query = query.ilike('allergen_group', allergenGroupOrId);
        }
      }
      const { error } = await query;
      if (error) {
        console.warn('[Pharmacy DB] Supabase delete allergy notice:', error.message);
      }
      return true;
    } catch (e) {
      console.warn('[Pharmacy DB] Delete allergy error:', e);
      return false;
    }
  }

  /**
   * Persists an evaluated prescription scan to Supabase with in-memory fallback.
   */
  public static async savePrescriptionScan(scan: RxScanSummary): Promise<RxScanSummary> {
    const isUuid = scan.id && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(scan.id);
    const insertPayload: any = {
      patient_id: scan.patientId,
      image_url: scan.imageUrl,
      extracted_drugs: scan.extractedDrugs,
      ddi_warnings: scan.ddiWarnings,
      allergy_conflicts: scan.allergyConflicts,
      has_safety_conflict: scan.hasSafetyConflict
    };
    if (isUuid) {
      insertPayload.id = scan.id;
    }

    const record: RxScanSummary = {
      ...scan,
      createdAt: scan.createdAt || new Date().toISOString()
    };

    try {
      const { data, error } = await supabase
        .from('prescription_scans')
        .insert([insertPayload])
        .select()
        .single();

      if (!error && data) {
        record.id = data.id;
        record.createdAt = data.created_at;
      }
    } catch (err) {
      console.warn('[Pharmacy DB] Supabase prescription_scan insert failed, caching in memory:', err);
    }

    if (!record.id) {
      record.id = `rxscan-${Date.now()}`;
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
