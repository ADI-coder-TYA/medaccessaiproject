import { ICD11Concept, WHO_ICD11_URI_STEM } from './types.js';

export class ICD11ConceptStore {
  private static _concepts: Map<string, ICD11Concept> = new Map();

  static {
    this._initializeConcepts();
  }

  /**
   * Technical Guardrail 1: WHO ICD-11 URI & Subsumption Matching
   * Standardizes concept coding against http://id.who.int/icd/release/11/mms
   */
  public static buildUri(code: string): string {
    return `${WHO_ICD11_URI_STEM}/${encodeURIComponent(code)}`;
  }

  /**
   * Retrieves an ICD-11 concept by code (e.g., '1B10.0' or '1B10').
   */
  public static getConceptByCode(code: string): ICD11Concept | undefined {
    const clean = code.trim().toUpperCase();
    if (this._concepts.has(clean)) {
      return this._concepts.get(clean);
    }
    // Subsumption check (e.g. '1B10.0' matches '1B10')
    for (const [key, concept] of this._concepts.entries()) {
      if (clean.startsWith(key) || key.startsWith(clean)) {
        return concept;
      }
    }
    return undefined;
  }

  /**
   * Technical Guardrail 1: URI Stem Matching for clean HAPI-FHIR / EHR interoperability.
   */
  public static getConceptByUri(uri: string): ICD11Concept | undefined {
    if (!uri) return undefined;
    const cleanUri = uri.trim();
    if (cleanUri.startsWith(WHO_ICD11_URI_STEM)) {
      const codePart = cleanUri.replace(`${WHO_ICD11_URI_STEM}/`, '');
      return this.getConceptByCode(decodeURIComponent(codePart));
    }
    return undefined;
  }

  /**
   * Returns all embedded clinical concepts.
   */
  public static getAllConcepts(): ICD11Concept[] {
    return Array.from(this._concepts.values());
  }

  /**
   * Registers or updates a concept.
   */
  public static registerConcept(concept: ICD11Concept): void {
    this._concepts.set(concept.code.toUpperCase(), concept);
  }

  private static _initializeConcepts(): void {
    const defaultConcepts: ICD11Concept[] = [
      // 1. Respiratory: 1B10.0 Acute Upper Respiratory Infection
      {
        code: '1B10.0',
        title: 'Acute Upper Respiratory Tract Infection',
        category: 'Respiratory Diseases',
        uri: this.buildUri('1B10.0'),
        clinicalCriteria: {
          requiredKeywords: ['cough', 'rhinorrhea', 'congestion', 'sore throat', 'sneezing'],
          anatomicalLocations: ['Throat / Oral Cavity', 'Chest / Thorax', 'Face / Head'],
          vitalsTriggers: {
            feverMinCelsius: 37.5,
            tachycardiaMinBpm: 90
          },
          coughCategories: ['Normal Respiratory', 'Wet/Productive Cough'],
          minRiskScore: 0.15
        },
        firstLinePathway: {
          recommendedRx: [
            {
              genericName: 'Acetaminophen',
              dosage: '500 mg',
              frequency: 'Q6H PRN',
              duration: '3 - 5 days',
              clinicalNotes: 'Antipyretic and analgesic for pharyngeal discomfort and fever.'
            },
            {
              genericName: 'Dextromethorphan / Guaifenesin',
              dosage: '10mg / 100mg per 5mL',
              frequency: 'Q4H PRN',
              duration: '5 days',
              clinicalNotes: 'Expectorant and cough suppressant for daytime relief.'
            }
          ],
          labOrders: ['Rapid Influenza A/B Antigen', 'SARS-CoV-2 RT-PCR / Rapid Antigen'],
          imagingOrders: ['Chest X-Ray (AP/Lateral) only if dyspnea or hypoxia develops'],
          monitoringFrequency: 'Daily symptom self-monitoring',
          followUpDays: 5,
          urgentRedFlags: [
            'Stridor or barking cough at rest',
            'Inability to swallow secretions or fluids',
            'Respiratory rate >= 24 breaths/min'
          ]
        }
      },

      // 2. Respiratory: CA00 Acute Bronchitis
      {
        code: 'CA00',
        title: 'Acute Bronchitis',
        category: 'Respiratory Diseases',
        uri: this.buildUri('CA00'),
        clinicalCriteria: {
          requiredKeywords: ['bronchitis', 'wheezing', 'chest tightness', 'productive cough', 'sputum'],
          anatomicalLocations: ['Chest / Thorax'],
          vitalsTriggers: {
            feverMinCelsius: 37.8,
            tachypneaMinBreathsPerMin: 20
          },
          coughCategories: ['Wheeze/Stridor', 'Wet/Productive Cough'],
          minRiskScore: 0.35
        },
        firstLinePathway: {
          recommendedRx: [
            {
              genericName: 'Albuterol Inhaler (HFA)',
              dosage: '90 mcg/actuation (2 puffs)',
              frequency: 'Q4H - Q6H PRN',
              duration: '7 days',
              clinicalNotes: 'Short-acting beta-2 agonist for acute bronchospasm and audible wheezing.'
            },
            {
              genericName: 'Benzonatate',
              dosage: '100 mg',
              frequency: 'TID PRN',
              duration: '5 days',
              clinicalNotes: 'Non-narcotic peripheral stretch-receptor cough suppressant.'
            }
          ],
          labOrders: ['Complete Blood Count (CBC) with Differential', 'Peak Expiratory Flow (PEF) Spirometry'],
          imagingOrders: ['Portable Chest Radiography (Rule out focal lobar consolidation)'],
          monitoringFrequency: 'Every 8 hours pulse oximetry',
          followUpDays: 3,
          urgentRedFlags: [
            'SpO2 < 92% on ambient air',
            'Accessory respiratory muscle retractions',
            'Hemoptysis'
          ]
        }
      },

      // 3. Respiratory / Critical: CA40 Pneumonia
      {
        code: 'CA40',
        title: 'Community-Acquired Pneumonia',
        category: 'Infectious Diseases',
        uri: this.buildUri('CA40'),
        clinicalCriteria: {
          requiredKeywords: ['pneumonia', 'chills', 'dyspnea', 'fever / chills', 'pleuritic', 'shortness of breath'],
          anatomicalLocations: ['Chest / Thorax'],
          vitalsTriggers: {
            feverMinCelsius: 38.5,
            hypoxiaMaxSpo2: 92.0,
            tachypneaMinBreathsPerMin: 24,
            tachycardiaMinBpm: 105
          },
          coughCategories: ['Wet/Productive Cough', 'Wheeze/Stridor'],
          minRiskScore: 0.65
        },
        firstLinePathway: {
          recommendedRx: [
            {
              genericName: 'Amoxicillin / Clavulanate',
              dosage: '875mg / 125mg',
              frequency: 'BID',
              duration: '7 days',
              clinicalNotes: 'First-line empiric coverage for community-acquired bacterial pneumonia.'
            },
            {
              genericName: 'Azithromycin',
              dosage: '500 mg Day 1, then 250 mg Days 2-5',
              frequency: 'QD',
              duration: '5 days',
              clinicalNotes: 'Atypical pathogen macrolide coverage.'
            }
          ],
          labOrders: [
            'Complete Blood Count (CBC) with Differential',
            'C-Reactive Protein (CRP) Quantitative',
            'Serum Procalcitonin',
            'Sputum Gram Stain & Culture'
          ],
          imagingOrders: ['Chest Radiography (PA & Lateral Views) or Low-Dose CT Chest'],
          monitoringFrequency: 'Continuous pulse oximetry and Q4H vital signs',
          followUpDays: 2,
          urgentRedFlags: [
            'CURB-65 score >= 2 (Confusion, BUN > 19, RR >= 30, BP < 90/60, Age >= 65)',
            'SpO2 <= 90%',
            'Hypotension / Septic physiology'
          ]
        }
      },

      // 4. Dermatology: FB80 Allergic Contact Dermatitis
      {
        code: 'FB80',
        title: 'Allergic Contact Dermatitis / Eczematous Eruption',
        category: 'Dermatological Diseases',
        uri: this.buildUri('FB80'),
        clinicalCriteria: {
          requiredKeywords: ['pruritus / itching', 'erythema / redness', 'swelling / edema', 'rash', 'crusting'],
          anatomicalLocations: ['Skin / Epidermis', 'Arms / Hands', 'Legs / Feet', 'Face / Head'],
          visionPatterns: ['Dermatological Rash', 'Erythema', 'Eczema / Atopic', 'Superficial Lesion'],
          minRiskScore: 0.10
        },
        firstLinePathway: {
          recommendedRx: [
            {
              genericName: 'Hydrocortisone Butyrate Topical Cream',
              dosage: '0.1% Cream',
              frequency: 'BID',
              duration: '7 - 10 days',
              clinicalNotes: 'Medium-potency topical corticosteroid applied thinly to affected dermal areas.'
            },
            {
              genericName: 'Cetirizine',
              dosage: '10 mg',
              frequency: 'QD PO',
              duration: '7 days',
              clinicalNotes: 'Second-generation H1-antihistamine to quell nocturnal pruritus.'
            }
          ],
          labOrders: ['Serum IgE Level (if recurrent)', 'Skin Scraping for KOH (Rule out Tinea)'],
          imagingOrders: ['Dermoscopy high-resolution clinical imaging'],
          monitoringFrequency: 'Bi-daily dermal inspection',
          followUpDays: 7,
          urgentRedFlags: [
            'Rapidly advancing facial cellulitis / orbital edema',
            'Signs of secondary bacterial superinfection with purulence',
            'Targetoid or mucosal bullous skin sloughing (SJS/TEN signs)'
          ]
        }
      },

      // 5. ENT / Oral: EK02 Acute Pharyngitis / Tonsillitis
      {
        code: 'EK02',
        title: 'Acute Pharyngitis & Tonsillitis',
        category: 'Ear, Nose & Throat',
        uri: this.buildUri('EK02'),
        clinicalCriteria: {
          requiredKeywords: ['throat irritation', 'difficulty swallowing', 'sore throat', 'tonsillar', 'exudate'],
          anatomicalLocations: ['Throat / Oral Cavity'],
          vitalsTriggers: {
            feverMinCelsius: 38.0,
            tachycardiaMinBpm: 95
          },
          minRiskScore: 0.25
        },
        firstLinePathway: {
          recommendedRx: [
            {
              genericName: 'Amoxicillin',
              dosage: '500 mg',
              frequency: 'TID',
              duration: '10 days',
              clinicalNotes: 'Penicillin-class antimicrobial for confirmed Group A Strep pharyngitis.'
            },
            {
              genericName: 'Benzocaine / Menthol Lozenges',
              dosage: '15 mg',
              frequency: 'Q2H PRN',
              duration: '3 days',
              clinicalNotes: 'Topical anesthetic lozenges for acute odynophagia.'
            }
          ],
          labOrders: ['Rapid Strep Antigen Test (RADT)', 'Throat Swab Bacterial Culture'],
          imagingOrders: ['Soft Tissue Neck X-Ray / CT if peritonsillar abscess suspected (hot potato voice)'],
          monitoringFrequency: 'Daily temperature and oral intake check',
          followUpDays: 4,
          urgentRedFlags: [
            'Trismus (inability to open mouth)',
            'Uvular deviation indicating peritonsillar phlegmon',
            'Stridor or drooling'
          ]
        }
      },

      // 6. Cardiovascular: BA00 Essential Hypertension with Hypertensive Urgency
      {
        code: 'BA00',
        title: 'Essential Hypertension & Hemodynamic Urgency',
        category: 'Cardiovascular Diseases',
        uri: this.buildUri('BA00'),
        clinicalCriteria: {
          requiredKeywords: ['headache', 'dizziness', 'chest tightness', 'palpitations'],
          vitalsTriggers: {
            hypertensionMinSystolic: 160,
            tachycardiaMinBpm: 110
          },
          minRiskScore: 0.50
        },
        firstLinePathway: {
          recommendedRx: [
            {
              genericName: 'Amlodipine',
              dosage: '5 mg',
              frequency: 'QD',
              duration: '30 days',
              clinicalNotes: 'Dihydropyridine calcium channel blocker for systemic peripheral vascular resistance reduction.'
            },
            {
              genericName: 'Lisinopril',
              dosage: '10 mg',
              frequency: 'QD',
              duration: '30 days',
              clinicalNotes: 'ACE-inhibitor for renal hemodynamic protection.'
            }
          ],
          labOrders: [
            'Basic Metabolic Panel (BMP) - Serum Creatinine & BUN',
            'Urinalysis for Microalbuminuria',
            'Serum Electrolytes (Sodium, Potassium)'
          ],
          imagingOrders: ['12-Lead Electrocardiogram (ECG) for LVH / ischemia signs'],
          monitoringFrequency: 'Twice daily blood pressure logging',
          followUpDays: 3,
          urgentRedFlags: [
            'Systolic BP >= 180 mmHg or Diastolic >= 120 mmHg',
            'Acute visual changes or papilledema',
            'New neurological deficit (stroke alert)'
          ]
        }
      },

      // 7. General Clinical / Pain: QC10 Acute Pain
      {
        code: 'QC10',
        title: 'Acute Unspecified Pain with Physiological Stress',
        category: 'Symptoms & Clinical Findings',
        uri: this.buildUri('QC10'),
        clinicalCriteria: {
          requiredKeywords: ['acute sharp pain', 'pain scale', 'discomfort', 'distress'],
          minRiskScore: 0.20
        },
        firstLinePathway: {
          recommendedRx: [
            {
              genericName: 'Ibuprofen',
              dosage: '400 mg',
              frequency: 'Q6H PO with food',
              duration: '3 days',
              clinicalNotes: 'Non-steroidal anti-inflammatory drug (NSAID) for inflammatory pain.'
            }
          ],
          labOrders: ['Basic Metabolic Panel', 'Erythrocyte Sedimentation Rate (ESR)'],
          imagingOrders: ['Focal ultrasound or plain film radiography guided by anatomical tenderness'],
          monitoringFrequency: 'Pain score re-assessment at 2 hours post-analgesia',
          followUpDays: 4,
          urgentRedFlags: [
            'Pain score 10/10 unresponsive to non-opioid analgesia',
            'Sudden severe "thunderclap" headache',
            'Acute surgical abdomen with involuntary guarding'
          ]
        }
      }
    ];

    for (const concept of defaultConcepts) {
      this.registerConcept(concept);
    }
  }
}
