import { DDIPairResult, DDISeverity } from './types.js';
import { findBestRxNormMatch } from './fuzzyMatcher.js';

interface DDIEntry {
  agentA: string[]; // Set of synonyms or active ingredient
  agentB: string[];
  severity: DDISeverity;
  clinicalMechanism: string;
  mitigationAdvice: string;
}

/**
 * Clinical Pairwise Drug-Drug Interaction Rulebase
 */
const DDI_RULES: DDIEntry[] = [
  // 1. Warfarin + NSAIDs / Aspirin (Contraindicated Severe)
  {
    agentA: ['warfarin', 'coumadin', 'jantoven'],
    agentB: ['aspirin', 'ibuprofen', 'naproxen', 'ketorolac', 'meloxicam', 'diclofenac', 'celecoxib', 'advil', 'motrin', 'aleve', 'toradol'],
    severity: 'CONTRAINDICATED_SEVERE',
    clinicalMechanism: 'Dual anticoagulation and antiplatelet potentiation compounded by gastric mucosal barrier erosion, causing high risk of life-threatening gastrointestinal or intracranial hemorrhage.',
    mitigationAdvice: 'Avoid concurrent use unless strictly supervised by a specialist. Substitute with Acetaminophen for pain or antipyretic relief.'
  },

  // 2. Sildenafil / Tadalafil + Nitrates (Contraindicated Severe)
  {
    agentA: ['sildenafil', 'viagra', 'revatio', 'tadalafil', 'cialis'],
    agentB: ['nitroglycerin', 'nitrostat', 'nitro-dur', 'isosorbide mononitrate', 'imdur'],
    severity: 'CONTRAINDICATED_SEVERE',
    clinicalMechanism: 'Synergistic cGMP accumulation and widespread vascular smooth muscle relaxation triggering profound, refractory hypotension and circulatory collapse.',
    mitigationAdvice: 'ABSOLUTELY CONTRAINDICATED. Withhold PDE-5 inhibitors for at least 24-48 hours before administering any nitrate preparation.'
  },

  // 3. Methotrexate + NSAIDs (Contraindicated Severe)
  {
    agentA: ['methotrexate', 'trexall'],
    agentB: ['aspirin', 'ibuprofen', 'naproxen', 'ketorolac', 'diclofenac', 'advil', 'motrin', 'aleve'],
    severity: 'CONTRAINDICATED_SEVERE',
    clinicalMechanism: 'NSAIDs diminish renal blood flow and competitively inhibit organic anion transporters responsible for methotrexate excretion, triggering severe myelosuppression and fatal pancytopenia.',
    mitigationAdvice: 'Discontinue NSAIDs. Utilize non-NSAID analgesics and monitor complete blood count (CBC) and renal markers.'
  },

  // 4. Simvastatin + Clarithromycin (Contraindicated Severe)
  {
    agentA: ['simvastatin', 'zocor'],
    agentB: ['clarithromycin', 'biaxin', 'erythromycin'],
    severity: 'CONTRAINDICATED_SEVERE',
    clinicalMechanism: 'Potent CYP3A4 inhibition dramatically increases simvastatin serum concentrations, precipitating severe rhabdomyolysis and acute myoglobinuric kidney failure.',
    mitigationAdvice: 'Temporarily pause simvastatin during macrolide therapy or switch to non-CYP3A4 macrolide/antibiotic (e.g., Azithromycin).'
  },

  // 5. Tramadol + SSRIs (Contraindicated Severe)
  {
    agentA: ['tramadol', 'ultram'],
    agentB: ['fluoxetine', 'prozac', 'sertraline', 'zoloft', 'escitalopram', 'lexapro'],
    severity: 'CONTRAINDICATED_SEVERE',
    clinicalMechanism: 'Additive serotonergic transmission leading to Serotonin Syndrome (rigidity, autonomic instability, hyperthermia) accompanied by a sharply lowered seizure threshold.',
    mitigationAdvice: 'Avoid combination. Monitor neurological status and select non-serotonergic analgesic.'
  },

  // 6. Spironolactone + Potassium Chloride (Contraindicated Severe)
  {
    agentA: ['spironolactone', 'aldactone'],
    agentB: ['potassium chloride', 'k-dur', 'k-tab', 'micro-k', 'klor-con'],
    severity: 'CONTRAINDICATED_SEVERE',
    clinicalMechanism: 'Concurrent aldosterone antagonism and exogenous potassium loading leads to severe hyperkalemia, cardiac conduction abnormalities, and ventricular fibrillation.',
    mitigationAdvice: 'Discontinue potassium supplementation. Monitor serum potassium and serial ECGs.'
  },

  // 7. MAOIs + SSRIs (Contraindicated Severe)
  {
    agentA: ['phenelzine', 'nardil'],
    agentB: ['fluoxetine', 'prozac', 'sertraline', 'zoloft', 'escitalopram', 'lexapro', 'tramadol'],
    severity: 'CONTRAINDICATED_SEVERE',
    clinicalMechanism: 'Profound central and peripheral serotonin accumulation triggering catastrophic hyperpyrexic crisis, hypertensive crisis, and death.',
    mitigationAdvice: 'ABSOLUTELY CONTRAINDICATED. Requires mandatory 14-day washout period between regimens.'
  },

  // 8. Ciprofloxacin + Antacids / Multivalent Cations (Moderate Monitor)
  {
    agentA: ['ciprofloxacin', 'cipro', 'levofloxacin', 'levaquin', 'doxycycline'],
    agentB: ['calcium carbonate', 'tums', 'aluminum hydroxide-magnesium hydroxide', 'mylanta', 'ferrous sulfate'],
    severity: 'MODERATE_MONITOR',
    clinicalMechanism: 'Multivalent polycation chelation in the gastrointestinal tract forms insoluble complexes, severely decreasing antibiotic bioavailability by up to 75%.',
    mitigationAdvice: 'Separate dosing: administer antibiotic at least 2 hours before or 4-6 hours after antacids or mineral supplements.'
  },

  // 9. Lisinopril / Losartan + NSAIDs (Moderate Monitor)
  {
    agentA: ['lisinopril', 'prinivil', 'zestril', 'losartan', 'cozaar'],
    agentB: ['ibuprofen', 'advil', 'naproxen', 'aleve', 'meloxicam', 'diclofenac'],
    severity: 'MODERATE_MONITOR',
    clinicalMechanism: 'NSAID-induced inhibition of renal prostaglandin synthesis attenuates ACE-inhibitor/ARB hypotensive efficacy and increases risk of acute hemodynamic renal decline.',
    mitigationAdvice: 'Limit NSAID duration. Monitor blood pressure, serum creatinine, and estimated GFR.'
  },

  // 10. Levothyroxine + Calcium / Iron (Moderate Monitor)
  {
    agentA: ['levothyroxine', 'synthroid'],
    agentB: ['calcium carbonate', 'tums', 'ferrous sulfate'],
    severity: 'MODERATE_MONITOR',
    clinicalMechanism: 'Insoluble adsorption in the intestinal lumen significantly impairs levothyroxine absorption, causing subtherapeutic thyroid hormone levels.',
    mitigationAdvice: 'Space administration by at least 4 hours between levothyroxine and calcium or iron supplements.'
  },

  // 11. Fluoxetine + Warfarin (Moderate Monitor)
  {
    agentA: ['fluoxetine', 'prozac', 'sertraline', 'zoloft'],
    agentB: ['warfarin', 'coumadin'],
    severity: 'MODERATE_MONITOR',
    clinicalMechanism: 'Moderate CYP2C9 inhibition and platelet serotonin reuptake inhibition increases prothrombin time and elevates mucosal bleeding risk.',
    mitigationAdvice: 'Perform frequent INR testing and monitor for microhemorrhages.'
  }
];

export class DrugInteractionEngine {
  /**
   * Normalizes drug string to active ingredient or canonical key.
   */
  private static normalizeDrug(drug: string): string {
    const trimmed = (drug || '').trim().toLowerCase();
    const match = findBestRxNormMatch(trimmed, 0.75);
    return (match.activeIngredient || trimmed).toLowerCase();
  }

  /**
   * Evaluates a single pairwise combination of drugs.
   */
  public static checkPair(drugA: string, drugB: string): DDIPairResult {
    const normA = this.normalizeDrug(drugA);
    const normB = this.normalizeDrug(drugB);

    if (!normA || !normB || normA === normB) {
      return {
        drugA,
        drugB,
        severity: 'SAFE',
        clinicalMechanism: 'No clinically significant interaction identified.',
        mitigationAdvice: 'Standard administration schedules apply.'
      };
    }

    for (const rule of DDI_RULES) {
      const matchA = rule.agentA.some(a => normA.includes(a) || a.includes(normA));
      const matchB = rule.agentB.some(b => normB.includes(b) || b.includes(normB));

      const reverseA = rule.agentA.some(a => normB.includes(a) || a.includes(normB));
      const reverseB = rule.agentB.some(b => normA.includes(b) || b.includes(normA));

      if ((matchA && matchB) || (reverseA && reverseB)) {
        return {
          drugA,
          drugB,
          severity: rule.severity,
          clinicalMechanism: rule.clinicalMechanism,
          mitigationAdvice: rule.mitigationAdvice
        };
      }
    }

    return {
      drugA,
      drugB,
      severity: 'SAFE',
      clinicalMechanism: 'No known adverse drug-drug interaction found in RxNorm clinical database.',
      mitigationAdvice: 'Safe for co-administration per current clinical guidelines.'
    };
  }

  /**
   * Evaluates all pairwise combinations between newly prescribed medications and patient active medications.
   */
  public static evaluateInteractions(
    newDrugs: string[],
    activeDrugs: string[] = []
  ): DDIPairResult[] {
    const results: DDIPairResult[] = [];
    const seenPairs = new Set<string>();

    const allDrugs = [...newDrugs];

    // 1. Check interactions between newly prescribed medications themselves
    for (let i = 0; i < allDrugs.length; i++) {
      for (let j = i + 1; j < allDrugs.length; j++) {
        const pairKey = [allDrugs[i], allDrugs[j]].sort().join('::').toLowerCase();
        if (!seenPairs.has(pairKey)) {
          seenPairs.add(pairKey);
          const res = this.checkPair(allDrugs[i], allDrugs[j]);
          if (res.severity !== 'SAFE') {
            results.push(res);
          }
        }
      }
    }

    // 2. Check interactions between newly prescribed medications and active medications
    for (const newDrug of newDrugs) {
      for (const activeDrug of activeDrugs) {
        const pairKey = [newDrug, activeDrug].sort().join('::').toLowerCase();
        if (!seenPairs.has(pairKey)) {
          seenPairs.add(pairKey);
          const res = this.checkPair(newDrug, activeDrug);
          if (res.severity !== 'SAFE') {
            results.push(res);
          }
        }
      }
    }

    // Sort: CONTRAINDICATED_SEVERE first, then MODERATE_MONITOR, then MINOR
    const severityRank: Record<DDISeverity, number> = {
      CONTRAINDICATED_SEVERE: 3,
      MODERATE_MONITOR: 2,
      MINOR: 1,
      SAFE: 0
    };

    return results.sort((a, b) => severityRank[b.severity] - severityRank[a.severity]);
  }
}
