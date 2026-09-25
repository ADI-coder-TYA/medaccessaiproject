import { AllergenGroup, RxNormConcept } from './types.js';

/**
 * Technical Guardrail 2: Allergen Cross-Reactivity Mapping
 * Maps parent allergen groups to all child derivative chemical agents and brand formulations.
 */
export const ALLERGEN_CROSS_REACTIVITY_MAP: Record<AllergenGroup, string[]> = {
  PENICILLINS: [
    'amoxicillin',
    'ampicillin',
    'piperacillin',
    'penicillin v',
    'penicillin g',
    'amoxicillin-clavulanate',
    'amoxicillin clavulanate',
    'augmentin',
    'unasyn',
    'zosyn',
    'ticarcillin',
    'methicillin',
    'oxacillin',
    'cloxacillin',
    'dicloxacillin'
  ],
  NSAIDS: [
    'ibuprofen',
    'naproxen',
    'ketorolac',
    'aspirin',
    'acetylsalicylic acid',
    'celecoxib',
    'meloxicam',
    'diclofenac',
    'indomethacin',
    'piroxicam',
    'sulindac',
    'etodolac',
    'nabumetone',
    'ketoprofen',
    'advil',
    'motrin',
    'aleve',
    'toradol',
    'celebrex',
    'mobic',
    'voltaren'
  ],
  PENICILLIN: [
    'amoxicillin',
    'ampicillin',
    'piperacillin',
    'penicillin v',
    'penicillin g',
    'amoxicillin-clavulanate',
    'amoxicillin clavulanate',
    'augmentin',
    'unasyn',
    'zosyn',
    'ticarcillin',
    'methicillin',
    'oxacillin',
    'cloxacillin',
    'dicloxacillin'
  ],
  SULFA: [
    'sulfamethoxazole',
    'trimethoprim-sulfamethoxazole',
    'trimethoprim sulfamethoxazole',
    'bactrim',
    'septra',
    'sulfasalazine',
    'azulfidine',
    'sulfadiazine',
    'sulfisoxazole',
    'zonisamide'
  ],
  SULFONAMIDES: [
    'sulfamethoxazole',
    'trimethoprim-sulfamethoxazole',
    'trimethoprim sulfamethoxazole',
    'bactrim',
    'septra',
    'sulfasalazine',
    'azulfidine',
    'sulfadiazine',
    'sulfisoxazole',
    'zonisamide'
  ],
  OPIOIDS: [
    'codeine',
    'morphine',
    'oxycodone',
    'hydrocodone',
    'tramadol',
    'fentanyl',
    'hydromorphone',
    'dilaudid',
    'oxymorphone',
    'methadone',
    'meperidine',
    'demerol',
    'buprenorphine',
    'percocet',
    'vicodin',
    'norco',
    'ultram',
    'oxycontin'
  ],
  CEPHALOSPORINS: [
    'cephalexin',
    'keflex',
    'cefuroxime',
    'ceftriaxone',
    'rocephin',
    'cefixime',
    'cefdinir',
    'cefepime'
  ],
  MACROLIDES: [
    'azithromycin',
    'zithromax',
    'clarithromycin',
    'biaxin',
    'erythromycin'
  ],
  TETRACYCLINES: [
    'doxycycline',
    'vibramycin',
    'minocycline',
    'tetracycline'
  ],
  STATINS: [
    'atorvastatin',
    'lipitor',
    'simvastatin',
    'zocor',
    'rosuvastatin',
    'crestor',
    'pravastatin'
  ]
};

/**
 * Embedded RxNorm Concept Knowledge Base
 * Maps generic active ingredients and major brand formulations with allergen tagging.
 */
export const RX_NORM_DATASET: RxNormConcept[] = [
  // --- Antibiotics & Beta-Lactams ---
  {
    activeIngredient: 'Amoxicillin',
    brandAliases: ['Amoxil', 'Trimox', 'Moxatag', 'Augmentin'],
    allergenGroup: 'PENICILLINS',
    category: 'Antibiotic (Penicillin / Beta-lactam)'
  },
  {
    activeIngredient: 'Amoxicillin-Clavulanate',
    brandAliases: ['Augmentin', 'Augmentin XR', 'Clavamox'],
    allergenGroup: 'PENICILLINS',
    category: 'Antibiotic (Beta-lactam + Inhibitor)'
  },
  {
    activeIngredient: 'Ampicillin',
    brandAliases: ['Omnipen', 'Principen', 'Unasyn'],
    allergenGroup: 'PENICILLINS',
    category: 'Antibiotic (Penicillin / Beta-lactam)'
  },
  {
    activeIngredient: 'Piperacillin',
    brandAliases: ['Pipracil', 'Zosyn'],
    allergenGroup: 'PENICILLINS',
    category: 'Antibiotic (Extended spectrum Penicillin)'
  },
  {
    activeIngredient: 'Penicillin V',
    brandAliases: ['Veetids', 'Pen-Vee K', 'Beepen-VK'],
    allergenGroup: 'PENICILLINS',
    category: 'Antibiotic (Penicillin)'
  },
  {
    activeIngredient: 'Cephalexin',
    brandAliases: ['Keflex', 'Keftab'],
    allergenGroup: 'CEPHALOSPORINS',
    category: 'Antibiotic (Cephalosporin 1st Gen)'
  },
  {
    activeIngredient: 'Ceftriaxone',
    brandAliases: ['Rocephin'],
    allergenGroup: 'CEPHALOSPORINS',
    category: 'Antibiotic (Cephalosporin 3rd Gen)'
  },
  {
    activeIngredient: 'Azithromycin',
    brandAliases: ['Zithromax', 'Z-Pak', 'AzaSite'],
    allergenGroup: 'MACROLIDES',
    category: 'Antibiotic (Macrolide)'
  },
  {
    activeIngredient: 'Clarithromycin',
    brandAliases: ['Biaxin', 'Biaxin XL'],
    allergenGroup: 'MACROLIDES',
    category: 'Antibiotic (Macrolide)'
  },
  {
    activeIngredient: 'Ciprofloxacin',
    brandAliases: ['Cipro', 'Cipro XR', 'Proquin XR'],
    category: 'Antibiotic (Fluoroquinolone)'
  },
  {
    activeIngredient: 'Levofloxacin',
    brandAliases: ['Levaquin', 'Quixin'],
    category: 'Antibiotic (Fluoroquinolone)'
  },
  {
    activeIngredient: 'Doxycycline',
    brandAliases: ['Vibramycin', 'Doryx', 'Oracea', 'Monodox'],
    allergenGroup: 'TETRACYCLINES',
    category: 'Antibiotic (Tetracycline)'
  },
  {
    activeIngredient: 'Sulfamethoxazole-Trimethoprim',
    brandAliases: ['Bactrim', 'Bactrim DS', 'Septra', 'Septra DS'],
    allergenGroup: 'SULFA',
    category: 'Antibiotic (Sulfonamide)'
  },
  {
    activeIngredient: 'Sulfasalazine',
    brandAliases: ['Azulfidine', 'Azulfidine EN-tabs'],
    allergenGroup: 'SULFA',
    category: 'Anti-inflammatory (Sulfonamide derivative)'
  },

  // --- Analgesics & Anti-inflammatory (NSAIDs, Acetaminophen, Opioids) ---
  {
    activeIngredient: 'Aspirin',
    brandAliases: ['Bayer Aspirin', 'Ecotrin', 'Bufferin', 'Disprin'],
    allergenGroup: 'NSAIDS',
    category: 'NSAID / Antiplatelet'
  },
  {
    activeIngredient: 'Ibuprofen',
    brandAliases: ['Advil', 'Motrin', 'Brufen', 'Nuprin', 'Midol IB'],
    allergenGroup: 'NSAIDS',
    category: 'NSAID'
  },
  {
    activeIngredient: 'Naproxen',
    brandAliases: ['Aleve', 'Naprosyn', 'Anaprox'],
    allergenGroup: 'NSAIDS',
    category: 'NSAID'
  },
  {
    activeIngredient: 'Ketorolac',
    brandAliases: ['Toradol', 'Acular', 'Sprix'],
    allergenGroup: 'NSAIDS',
    category: 'NSAID (High potency)'
  },
  {
    activeIngredient: 'Celecoxib',
    brandAliases: ['Celebrex'],
    allergenGroup: 'NSAIDS',
    category: 'NSAID (COX-2 Selective)'
  },
  {
    activeIngredient: 'Meloxicam',
    brandAliases: ['Mobic', 'Vivlodex'],
    allergenGroup: 'NSAIDS',
    category: 'NSAID'
  },
  {
    activeIngredient: 'Diclofenac',
    brandAliases: ['Voltaren', 'Cataflam', 'Zipsor'],
    allergenGroup: 'NSAIDS',
    category: 'NSAID'
  },
  {
    activeIngredient: 'Acetaminophen',
    brandAliases: ['Tylenol', 'Panadol', 'Calpol', 'Paracetamol'],
    category: 'Analgesic / Antipyretic'
  },
  {
    activeIngredient: 'Tramadol',
    brandAliases: ['Ultram', 'ConZip', 'Ryzolt'],
    allergenGroup: 'OPIOIDS',
    category: 'Opioid Analgesic / SNRI activity'
  },
  {
    activeIngredient: 'Codeine',
    brandAliases: ['Tylenol with Codeine', 'Tylenol #3'],
    allergenGroup: 'OPIOIDS',
    category: 'Opioid Analgesic'
  },
  {
    activeIngredient: 'Morphine',
    brandAliases: ['MS Contin', 'Kadian', 'Roxanol'],
    allergenGroup: 'OPIOIDS',
    category: 'Opioid Analgesic'
  },
  {
    activeIngredient: 'Oxycodone',
    brandAliases: ['OxyContin', 'Roxicodone', 'Percocet'],
    allergenGroup: 'OPIOIDS',
    category: 'Opioid Analgesic'
  },
  {
    activeIngredient: 'Hydrocodone',
    brandAliases: ['Vicodin', 'Norco', 'Lortab', 'Hysingla'],
    allergenGroup: 'OPIOIDS',
    category: 'Opioid Analgesic'
  },
  {
    activeIngredient: 'Fentanyl',
    brandAliases: ['Duragesic', 'Sublimaze', 'Actiq'],
    allergenGroup: 'OPIOIDS',
    category: 'Synthetic Opioid'
  },

  // --- Cardiovascular & Anticoagulants ---
  {
    activeIngredient: 'Warfarin',
    brandAliases: ['Coumadin', 'Jantoven'],
    category: 'Anticoagulant (Vitamin K Antagonist)'
  },
  {
    activeIngredient: 'Apixaban',
    brandAliases: ['Eliquis'],
    category: 'Anticoagulant (Factor Xa Inhibitor)'
  },
  {
    activeIngredient: 'Rivaroxaban',
    brandAliases: ['Xarelto'],
    category: 'Anticoagulant (Factor Xa Inhibitor)'
  },
  {
    activeIngredient: 'Clopidogrel',
    brandAliases: ['Plavix'],
    category: 'Antiplatelet Agent'
  },
  {
    activeIngredient: 'Nitroglycerin',
    brandAliases: ['Nitrostat', 'Nitro-Dur', 'Nitrolingual', 'Minitran'],
    category: 'Nitrate Vasodilator'
  },
  {
    activeIngredient: 'Isosorbide Mononitrate',
    brandAliases: ['Imdur', 'Ismo', 'Monoket'],
    category: 'Nitrate Vasodilator'
  },
  {
    activeIngredient: 'Sildenafil',
    brandAliases: ['Viagra', 'Revatio'],
    category: 'PDE-5 Inhibitor'
  },
  {
    activeIngredient: 'Tadalafil',
    brandAliases: ['Cialis', 'Adcirca'],
    category: 'PDE-5 Inhibitor'
  },
  {
    activeIngredient: 'Lisinopril',
    brandAliases: ['Prinivil', 'Zestril'],
    category: 'ACE Inhibitor'
  },
  {
    activeIngredient: 'Losartan',
    brandAliases: ['Cozaar'],
    category: 'Angiotensin Receptor Blocker (ARB)'
  },
  {
    activeIngredient: 'Amlodipine',
    brandAliases: ['Norvasc', 'Katerzia'],
    category: 'Calcium Channel Blocker'
  },
  {
    activeIngredient: 'Metoprolol',
    brandAliases: ['Lopressor', 'Toprol XL'],
    category: 'Beta Blocker'
  },
  {
    activeIngredient: 'Spironolactone',
    brandAliases: ['Aldactone', 'CaroSpir'],
    category: 'Potassium-Sparing Diuretic'
  },
  {
    activeIngredient: 'Potassium Chloride',
    brandAliases: ['K-Dur', 'K-Tab', 'Micro-K', 'Klor-Con'],
    category: 'Electrolyte Supplement'
  },
  {
    activeIngredient: 'Simvastatin',
    brandAliases: ['Zocor', 'Flolipid'],
    allergenGroup: 'STATINS',
    category: 'HMG-CoA Reductase Inhibitor (Statin)'
  },
  {
    activeIngredient: 'Atorvastatin',
    brandAliases: ['Lipitor'],
    allergenGroup: 'STATINS',
    category: 'HMG-CoA Reductase Inhibitor (Statin)'
  },
  {
    activeIngredient: 'Rosuvastatin',
    brandAliases: ['Crestor'],
    allergenGroup: 'STATINS',
    category: 'HMG-CoA Reductase Inhibitor (Statin)'
  },

  // --- Metabolic & Endocrine ---
  {
    activeIngredient: 'Metformin',
    brandAliases: ['Glucophage', 'Glucophage XR', 'Fortamet', 'Riomet'],
    category: 'Antidiabetic (Biguanide)'
  },
  {
    activeIngredient: 'Glipizide',
    brandAliases: ['Glucotrol', 'Glucotrol XL'],
    category: 'Antidiabetic (Sulfonylurea)'
  },
  {
    activeIngredient: 'Levothyroxine',
    brandAliases: ['Synthroid', 'Levoxyl', 'Tirosint', 'Euthyrox'],
    category: 'Thyroid Hormone'
  },
  {
    activeIngredient: 'Methotrexate',
    brandAliases: ['Trexall', 'Otrexup', 'Rasuvo'],
    category: 'Antimetabolite / Immunosuppressant'
  },

  // --- Gastrointestinal & Minerals ---
  {
    activeIngredient: 'Calcium Carbonate',
    brandAliases: ['Tums', 'Caltrate', 'Os-Cal'],
    category: 'Antacid / Mineral Supplement'
  },
  {
    activeIngredient: 'Aluminum Hydroxide-Magnesium Hydroxide',
    brandAliases: ['Mylanta', 'Maalox'],
    category: 'Antacid'
  },
  {
    activeIngredient: 'Ferrous Sulfate',
    brandAliases: ['Feosol', 'Slow Fe'],
    category: 'Iron Supplement'
  },
  {
    activeIngredient: 'Omeprazole',
    brandAliases: ['Prilosec', 'Prilosec OTC'],
    category: 'Proton Pump Inhibitor (PPI)'
  },
  {
    activeIngredient: 'Pantoprazole',
    brandAliases: ['Protonix'],
    category: 'Proton Pump Inhibitor (PPI)'
  },

  // --- Psychotropics & Neuro ---
  {
    activeIngredient: 'Fluoxetine',
    brandAliases: ['Prozac', 'Sarafem'],
    category: 'SSRI Antidepressant'
  },
  {
    activeIngredient: 'Sertraline',
    brandAliases: ['Zoloft'],
    category: 'SSRI Antidepressant'
  },
  {
    activeIngredient: 'Escitalopram',
    brandAliases: ['Lexapro'],
    category: 'SSRI Antidepressant'
  },
  {
    activeIngredient: 'Phenelzine',
    brandAliases: ['Nardil'],
    category: 'MAO Inhibitor'
  }
];

/**
 * Pre-indexed lookup sets for instant O(1) ingredient and brand resolution.
 */
export const NORMALIZED_DRUG_INDEX: Map<string, RxNormConcept> = new Map();

for (const concept of RX_NORM_DATASET) {
  NORMALIZED_DRUG_INDEX.set(concept.activeIngredient.toLowerCase(), concept);
  for (const brand of concept.brandAliases) {
    NORMALIZED_DRUG_INDEX.set(brand.toLowerCase(), concept);
  }
}
