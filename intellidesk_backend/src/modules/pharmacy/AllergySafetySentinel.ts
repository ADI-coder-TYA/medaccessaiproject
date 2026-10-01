import { AllergenGroup, AllergyConflictResult, PatientAllergy } from './types.js';
import { ALLERGEN_CROSS_REACTIVITY_MAP } from './rxNormDataset.js';
import { findBestRxNormMatch } from './fuzzyMatcher.js';
import { AlternativeMedicationService } from './AlternativeMedicationService.js';

export class AllergySafetySentinel {
  /**
   * Technical Guardrail 2: Cross-Reactivity Allergen Evaluation
   * Evaluates newly prescribed medications against patient allergy records.
   * Dynamically attaches evidence-based safe alternative medications via NIH NLM RxNav.
   */
  public static async evaluateAllergies(
    prescribedDrugs: string[],
    patientAllergies: PatientAllergy[] = []
  ): Promise<AllergyConflictResult[]> {

    if (!prescribedDrugs.length || !patientAllergies.length) {
      return [];
    }

    const conflicts: AllergyConflictResult[] = [];
    const seenConflicts = new Set<string>();

    for (const rawDrug of prescribedDrugs) {
      const match = findBestRxNormMatch(rawDrug, 0.75);
      const activeIng = (match.activeIngredient || rawDrug).toLowerCase();
      const matchedTerm = (match.matchedTerm || rawDrug).toLowerCase();

      for (const allergy of patientAllergies) {
        const rawGroup = (allergy.allergenGroup || '').toUpperCase().trim();
        const reaction = allergy.reactionDescription || 'Known Hypersensitivity';

        // Normalize allergen group from compound string (e.g. "Penicillin Allergy", "Sulfa Drugs", "NSAIDs")
        let normalizedGroup: AllergenGroup | null = null;
        if (rawGroup.includes('PENICILLIN')) normalizedGroup = 'PENICILLINS';
        else if (rawGroup.includes('SULFA') || rawGroup.includes('SULFONAMIDE')) normalizedGroup = 'SULFA';
        else if (rawGroup.includes('NSAID')) normalizedGroup = 'NSAIDS';
        else if (rawGroup.includes('OPIOID')) normalizedGroup = 'OPIOIDS';
        else if (rawGroup.includes('CEPHALOSPORIN')) normalizedGroup = 'CEPHALOSPORINS';
        else if (rawGroup.includes('STATIN')) normalizedGroup = 'STATINS';
        else if (rawGroup.includes('ACE_INHIBITOR') || rawGroup.includes('ACE INHIBITOR')) normalizedGroup = 'ACE_INHIBITORS';
        else if (rawGroup.includes('MACROLIDE')) normalizedGroup = 'MACROLIDES';
        else if (rawGroup.includes('FLUOROQUINOLONE') || rawGroup.includes('QUINOLONE')) normalizedGroup = 'FLUOROQUINOLONES';
        else if (rawGroup.includes('TETRACYCLINE')) normalizedGroup = 'TETRACYCLINES';
        else {
          let clean = rawGroup.replace(/[^A-Z]/g, '');
          if (clean === 'SULFONAMIDE' || clean === 'SULFONAMIDES') clean = 'SULFA';
          if (clean === 'PENICILLIN') clean = 'PENICILLINS';
          if (ALLERGEN_CROSS_REACTIVITY_MAP[clean as AllergenGroup]) {
            normalizedGroup = clean as AllergenGroup;
          }
        }

        const crossReactivityList = normalizedGroup ? (ALLERGEN_CROSS_REACTIVITY_MAP[normalizedGroup] || []) : [];

        // 1. Direct cross-reactivity list check
        const isCrossReactive = crossReactivityList.some(child => 
          activeIng.includes(child) || child.includes(activeIng) ||
          matchedTerm.includes(child) || child.includes(matchedTerm)
        );

        // 2. Direct name matching against allergen description or group name
        const groupLower = rawGroup.toLowerCase();
        const isDirectGroupMatch = groupLower.length > 2 && (
          activeIng.includes(groupLower) || groupLower.includes(activeIng) ||
          matchedTerm.includes(groupLower) || groupLower.includes(matchedTerm)
        );

        // 3. Tagged concept allergenGroup match
        const isConceptGroupMatch = normalizedGroup ? (match.concept?.allergenGroup === normalizedGroup) : false;

        if (isCrossReactive || isDirectGroupMatch || isConceptGroupMatch) {
          const conflictKey = `${normalizedGroup}::${match.activeIngredient}`.toLowerCase();
          if (!seenConflicts.has(conflictKey)) {
            seenConflicts.add(conflictKey);

            const activeDrugName = match.activeIngredient || rawDrug;
            const patientAllergyList = patientAllergies.map(a => a.allergenGroup);

            // Dynamically query safe, non-cross-reactive alternatives via NIH NLM RxNav / Clinical KB
            let suggestedAlternatives: any[] = [];
            try {
              suggestedAlternatives = await AlternativeMedicationService.getAlternativesForAllergy(
                normalizedGroup || rawGroup,
                activeDrugName,
                patientAllergyList
              );
            } catch (altErr) {
              console.warn('[AllergySafetySentinel] Alternative lookup warning:', altErr);
            }

            conflicts.push({
              allergenGroup: rawGroup,
              matchedDrug: rawDrug,
              activeIngredient: activeDrugName,
              patientReaction: reaction,
              severity: 'HIGH_RISK_ALLERGY',
              alertMessage: `CRITICAL ALLERGY ALERT: Patient has documented allergy to "${rawGroup}" (${reaction}). Prescribed medication "${activeDrugName}" belongs to this allergen class or exhibits high cross-reactivity!`,
              suggestedAlternatives
            });
          }
        }
      }
    }

    return conflicts;
  }
}

