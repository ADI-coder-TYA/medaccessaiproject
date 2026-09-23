import { AllergenGroup, AllergyConflictResult, PatientAllergy } from './types.js';
import { ALLERGEN_CROSS_REACTIVITY_MAP } from './rxNormDataset.js';
import { findBestRxNormMatch } from './fuzzyMatcher.js';

export class AllergySafetySentinel {
  /**
   * Technical Guardrail 2: Cross-Reactivity Allergen Evaluation
   * Evaluates newly prescribed medications against patient allergy records.
   */
  public static evaluateAllergies(
    prescribedDrugs: string[],
    patientAllergies: PatientAllergy[] = []
  ): AllergyConflictResult[] {
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

        // Check if rawGroup is one of our mapped AllergenGroups
        const normalizedGroup = rawGroup.replace(/[^A-Z]/g, '') as AllergenGroup;
        const crossReactivityList = ALLERGEN_CROSS_REACTIVITY_MAP[normalizedGroup] || [];

        // 1. Direct cross-reactivity list check
        const isCrossReactive = crossReactivityList.some(child => 
          activeIng.includes(child) || child.includes(activeIng) ||
          matchedTerm.includes(child) || child.includes(matchedTerm)
        );

        // 2. Direct name matching against allergen description or group name
        const groupLower = rawGroup.toLowerCase();
        const isDirectGroupMatch = activeIng.includes(groupLower) || groupLower.includes(activeIng);

        // 3. Tagged concept allergenGroup match
        const isConceptGroupMatch = match.concept?.allergenGroup === normalizedGroup;

        if (isCrossReactive || isDirectGroupMatch || isConceptGroupMatch) {
          const conflictKey = `${normalizedGroup}::${match.activeIngredient}`.toLowerCase();
          if (!seenConflicts.has(conflictKey)) {
            seenConflicts.add(conflictKey);

            conflicts.push({
              allergenGroup: rawGroup,
              matchedDrug: rawDrug,
              activeIngredient: match.activeIngredient || rawDrug,
              patientReaction: reaction,
              severity: 'HIGH_RISK_ALLERGY',
              alertMessage: `CRITICAL ALLERGY ALERT: Patient has documented allergy to "${rawGroup}" (${reaction}). Prescribed medication "${match.activeIngredient || rawDrug}" belongs to this allergen class or exhibits high cross-reactivity!`
            });
          }
        }
      }
    }

    return conflicts;
  }
}
