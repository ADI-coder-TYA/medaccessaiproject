import axios from 'axios';
import { AllergenGroup, AlternativeMedicationOption } from './types.js';

/**
 * Standard evidence-based therapeutic substitution cross-reference:
 * Maps contraindicated allergen groups to safe non-cross-reactive classes
 * and primary active ingredients.
 */
const EVIDENCE_BASED_SUBSTITUTIONS: Record<string, { drugClass: string; alternatives: Array<{ ingredient: string; brand: string; rationale: string }> }> = {
  PENICILLINS: {
    drugClass: 'Macrolides / Lincosamides (Non-beta-lactam antibacterial)',
    alternatives: [
      { ingredient: 'Azithromycin', brand: 'Zithromax', rationale: 'First-line non-beta-lactam alternative for respiratory & soft-tissue infections; zero cross-reactivity with penicillin.' },
      { ingredient: 'Clarithromycin', brand: 'Biaxin', rationale: 'Effective alternative for respiratory tract infections in penicillin-allergic patients.' },
      { ingredient: 'Clindamycin', brand: 'Cleocin', rationale: 'Lincosamide class; high efficacy against Gram-positive bacteria and skin/soft-tissue infections without beta-lactam core.' }
    ]
  },
  NSAIDS: {
    drugClass: 'Analgesics / Antipyretics (Non-NSAID)',
    alternatives: [
      { ingredient: 'Acetaminophen', brand: 'Tylenol / Paracetamol', rationale: 'Central COX inhibitor without peripheral anti-inflammatory allergenicity; standard safe analgesic.' },
      { ingredient: 'Celecoxib', brand: 'Celebrex', rationale: 'Selective COX-2 inhibitor; evaluated under medical supervision if cross-reactivity is COX-1 specific.' }
    ]
  },
  SULFA: {
    drugClass: 'Non-sulfonamide Antimicrobials',
    alternatives: [
      { ingredient: 'Ciprofloxacin', brand: 'Cipro', rationale: 'Fluoroquinolone antimicrobial; safe in patients with sulfonamide hypersensitivity for urinary tract coverage.' },
      { ingredient: 'Nitrofurantoin', brand: 'Macrobid', rationale: 'Urinary antiseptic with zero cross-reactivity to sulfonamides.' }
    ]
  },
  MACROLIDES: {
    drugClass: 'Fluoroquinolones / Tetracyclines',
    alternatives: [
      { ingredient: 'Doxycycline', brand: 'Vibramycin', rationale: 'Tetracycline antibiotic; covers atypical pathogens without macrolide cross-allergenicity.' },
      { ingredient: 'Levofloxacin', brand: 'Levaquin', rationale: 'Broad spectrum respiratory fluoroquinolone alternative.' }
    ]
  },
  CEPHALOSPORINS: {
    drugClass: 'Macrolides / Fluoroquinolones',
    alternatives: [
      { ingredient: 'Azithromycin', brand: 'Zithromax', rationale: 'Safe alternative for ENT and respiratory infections avoiding cephalosporin beta-lactam rings.' },
      { ingredient: 'Levofloxacin', brand: 'Levaquin', rationale: 'Broad spectrum alternative without beta-lactam ring structure.' }
    ]
  },
  STATINS: {
    drugClass: 'Non-statin Lipid Lowering Agents',
    alternatives: [
      { ingredient: 'Ezetimibe', brand: 'Zetia', rationale: 'Cholesterol absorption inhibitor; safe in statin-intolerant or allergic patients.' },
      { ingredient: 'Bempedoic Acid', brand: 'Nexletol', rationale: 'ACL inhibitor active in the liver without muscle-statin cross-reactivity.' }
    ]
  },
  ACE_INHIBITORS: {
    drugClass: 'Angiotensin II Receptor Blockers (ARBs)',
    alternatives: [
      { ingredient: 'Losartan', brand: 'Cozaar', rationale: 'ARB does not inhibit bradykinin degradation; significantly lower risk of angioedema or dry cough.' },
      { ingredient: 'Valsartan', brand: 'Diovan', rationale: 'Standard alternative for hypertension and heart failure without ACE-related allergy.' }
    ]
  },
  FLUOROQUINOLONES: {
    drugClass: 'Cephalosporins / Macrolides (if tolerated)',
    alternatives: [
      { ingredient: 'Azithromycin', brand: 'Zithromax', rationale: 'Atypical and bacterial coverage without fluoroquinolone tendonitis/allergy risk.' },
      { ingredient: 'Amoxicillin-Clavulanate', brand: 'Augmentin', rationale: 'Broad spectrum beta-lactam (verify penicillin tolerance before prescribing).' }
    ]
  }
};

export class AlternativeMedicationService {
  private static readonly RXNAV_BASE_URL = 'https://rxnav.nlm.nih.gov/REST';
  private static readonly OPENFDA_BASE_URL = 'https://api.fda.gov/drug/label.json';
  private static readonly REQUEST_TIMEOUT_MS = 3000;

  /**
   * Queries NIH NLM RxNav to fetch RxCUI for a medication name.
   */
  public static async fetchRxCui(medicationName: string): Promise<string | null> {
    try {
      const cleanName = medicationName.trim().split(/\s+/)[0]; // e.g. "Amoxicillin 500mg" -> "Amoxicillin"
      const url = `${this.RXNAV_BASE_URL}/rxcui.json?name=${encodeURIComponent(cleanName)}`;
      const res = await axios.get(url, {
        headers: { Accept: 'application/json' },
        timeout: this.REQUEST_TIMEOUT_MS
      });

      const ids = res.data?.idGroup?.rxnormId;
      if (Array.isArray(ids) && ids.length > 0) {
        return ids[0];
      }
      return null;
    } catch {
      return null;
    }
  }

  /**
   * Queries NIH NLM RxClass to determine ATC pharmacological class by RxCUI.
   */
  public static async fetchAtcClass(rxcui: string): Promise<{ classId: string; className: string } | null> {
    try {
      const url = `${this.RXNAV_BASE_URL}/rxclass/class/byRxcui.json?rxcui=${encodeURIComponent(rxcui)}&relaSource=ATC`;
      const res = await axios.get(url, {
        headers: { Accept: 'application/json' },
        timeout: this.REQUEST_TIMEOUT_MS
      });

      const infoList = res.data?.rxclassDrugInfoList?.rxclassDrugInfo;
      if (Array.isArray(infoList) && infoList.length > 0) {
        const item = infoList[0]?.rxclassMinConceptItem;
        if (item?.className) {
          return {
            classId: item.classId || '',
            className: item.className
          };
        }
      }
      return null;
    } catch {
      return null;
    }
  }

  /**
   * Generates safe, non-cross-reactive alternatives for a contraindicated drug.
   * Enriches each candidate with live RxNorm RxCUI from NIH NLM API.
   */
  public static async getAlternativesForAllergy(
    allergenGroup: string,
    contraindicatedDrug: string,
    patientKnownAllergies: string[] = []
  ): Promise<AlternativeMedicationOption[]> {
    const normalizedGroup = allergenGroup.toUpperCase().trim();
    let groupKey = 'PENICILLINS';

    if (normalizedGroup.includes('PENICILLIN') || normalizedGroup.includes('AMOXICILLIN')) groupKey = 'PENICILLINS';
    else if (normalizedGroup.includes('NSAID') || normalizedGroup.includes('ASPIRIN') || normalizedGroup.includes('IBUPROFEN')) groupKey = 'NSAIDS';
    else if (normalizedGroup.includes('SULFA') || normalizedGroup.includes('SULFONAMIDE')) groupKey = 'SULFA';
    else if (normalizedGroup.includes('MACROLIDE') || normalizedGroup.includes('AZITHROMYCIN')) groupKey = 'MACROLIDES';
    else if (normalizedGroup.includes('CEPHALOSPORIN')) groupKey = 'CEPHALOSPORINS';
    else if (normalizedGroup.includes('STATIN')) groupKey = 'STATINS';
    else if (normalizedGroup.includes('ACE')) groupKey = 'ACE_INHIBITORS';
    else if (normalizedGroup.includes('FLUOROQUINOLONE') || normalizedGroup.includes('CIPRO')) groupKey = 'FLUOROQUINOLONES';

    const baseline = EVIDENCE_BASED_SUBSTITUTIONS[groupKey];
    if (!baseline) {
      return [];
    }

    const patientAllergiesUpper = patientKnownAllergies.map(a => a.toUpperCase());

    // Filter out alternatives that might conflict with another known allergy of the patient
    const candidateList = baseline.alternatives.filter(alt => {
      const ingUpper = alt.ingredient.toUpperCase();
      return !patientAllergiesUpper.some(pa => pa.includes(ingUpper) || ingUpper.includes(pa));
    });

    // Dynamically fetch live RxCUI from NIH NLM RxNav for candidates
    const enrichedAlternatives: AlternativeMedicationOption[] = await Promise.all(
      candidateList.map(async (alt) => {
        let rxcui: string | undefined = undefined;
        try {
          const fetchedCui = await this.fetchRxCui(alt.ingredient);
          if (fetchedCui) {
            rxcui = fetchedCui;
          }
        } catch {
          // Graceful network timeout fallback
        }

        return {
          activeIngredient: alt.ingredient,
          brandName: alt.brand,
          drugClass: baseline.drugClass,
          rationale: alt.rationale,
          source: rxcui ? ('NLM_RXNAV' as const) : ('CLINICAL_GUIDELINE' as const),
          rxcui
        };
      })
    );

    return enrichedAlternatives;
  }
}
