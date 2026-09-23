import { parsePrescriptionDocument } from './PrescriptionOCRParser.js';
import { DrugInteractionEngine } from './DrugInteractionEngine.js';
import { AllergySafetySentinel } from './AllergySafetySentinel.js';
import { PharmacyDbService } from './pharmacyDbService.js';
import { RxScanSummary } from './types.js';

export interface ParsePrescriptionOptions {
  input: Buffer | string;
  patientId?: string;
  claimId?: string;
  imageUrl?: string;
  activeMedicationsOverride?: string[];
  allergiesOverride?: string[];
}

export class RxSentinelService {
  /**
   * Complete RxSentinel pipeline:
   * 1. OCR parsing & entity extraction (Brand, Ingredient, Dosage, Frequency, Duration)
   * 2. Typo correction via fuzzy RxNorm matching
   * 3. Patient allergy conflict check with cross-reactivity mapping
   * 4. Pairwise Drug-Drug Interaction evaluation
   * 5. Claims table safety flag override
   * 6. Persistence to database
   */
  public static async analyzePrescription(options: ParsePrescriptionOptions): Promise<RxScanSummary> {
    const {
      input,
      patientId,
      claimId,
      imageUrl,
      activeMedicationsOverride,
      allergiesOverride
    } = options;

    // 1. OCR Text Extraction & Entity Parsing
    const { extractedText, medications } = await parsePrescriptionDocument(input);

    const extractedIngredients = medications.map(m => m.activeIngredient);

    // 2. Fetch or resolve patient allergies
    let patientAllergies = patientId ? await PharmacyDbService.getPatientAllergies(patientId) : [];
    if (allergiesOverride && allergiesOverride.length > 0) {
      patientAllergies = [
        ...patientAllergies,
        ...allergiesOverride.map(a => ({
          patientId: patientId || 'override-patient',
          allergenGroup: a,
          reactionDescription: 'Reported during intake'
        }))
      ];
    }

    // 3. Fetch or resolve patient active medications
    let activeMeds = patientId ? await PharmacyDbService.getPatientMedications(patientId, true) : [];
    const activeMedNames = activeMeds.map(m => m.activeIngredient);
    if (activeMedicationsOverride && activeMedicationsOverride.length > 0) {
      activeMedNames.push(...activeMedicationsOverride);
    }

    // 4. Allergy Safety Evaluation (Guardrail 2)
    const allergyConflicts = AllergySafetySentinel.evaluateAllergies(
      extractedIngredients,
      patientAllergies
    );

    // 5. Drug-Drug Interaction Evaluation
    const ddiWarnings = DrugInteractionEngine.evaluateInteractions(
      extractedIngredients,
      activeMedNames
    );

    // 6. Determine Critical Safety Conflict
    const hasSevereDDI = ddiWarnings.some(d => d.severity === 'CONTRAINDICATED_SEVERE');
    const hasAllergyConflict = allergyConflicts.length > 0;
    const hasSafetyConflict = hasSevereDDI || hasAllergyConflict;

    // 7. Technical Guardrail 3: Patient Safety Banner & Claim Review Override
    let requiresPharmacistReview = hasSafetyConflict;
    if (claimId && hasSafetyConflict) {
      await PharmacyDbService.setClaimPharmacistReviewFlag(claimId, true);
      requiresPharmacistReview = true;
    }

    // 8. Assemble Scan Summary Record
    const summary: RxScanSummary = {
      patientId,
      imageUrl,
      extractedDrugs: medications,
      ddiWarnings,
      allergyConflicts,
      hasSafetyConflict,
      requiresPharmacistReview,
      rawOcrText: extractedText
    };

    // 9. Persist Scan Record
    const saved = await PharmacyDbService.savePrescriptionScan(summary);
    return saved;
  }
}
