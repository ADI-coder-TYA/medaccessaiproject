# MedAccess AI — Backend Architecture Reference

> **Complete architectural reference for the Node.js/TypeScript backend:** server bootstrap sequence, modular clinical diagnostics engine, CDSS WHO ICD-11 framework, pharmacy safety pipeline, BullMQ background queues, in-process ML retraining, and medical data protection architecture.

---

## 1. System Overview & Technology Stack

The MedAccess AI backend is an enterprise-grade, event-driven medical intelligence and triage platform built on Express 5 and modern TypeScript (ESM). It orchestrates clinical computer vision, acoustic respiratory ML, camera photoplethysmography (rPPG), WHO ICD-11 decision support, and emergency copay disbursements.

| Component | Technology | Specification / Notes |
|---|---|---|
| **Runtime** | Node.js 20+ (ESM modules) | High-throughput asynchronous event loop |
| **HTTP Framework** | Express 5 / TypeScript 5 | Strict typing, robust middleware pipeline, 50MB payload capacity |
| **In-Process ML** | `@tensorflow/tfjs-node` v4.22 | Native C++ bindings for DeepRank, CoughClassifier, MultimodalFusion, Autoencoder, LSTM |
| **Edge Transformer Runtime** | `@xenova/transformers` v2.17 | In-process ONNX Runtime (WASM/CPU) for local Qwen1.5/2.5 PFA & DistilBERT |
| **Database & Vector Store** | Supabase PostgreSQL + `pgvector` | Row-Level Security (RLS) on all tables, `vector(768)` semantic embeddings |
| **Job Queue & Workers** | BullMQ v5 + Redis 7 Alpine | Distributed asynchronous claim processing, continuous retraining, notification dispatch |
| **Real-Time Engine** | Socket.io v4 | WebSocket rooms segmented per institution tenant |
| **Digital Signal Processing** | Meyda.js + Custom Butterworth | MFCC acoustic extraction & 0.75–3.5 Hz bandpass pulse filtering |
| **OCR & Imaging** | Poppler `pdftotext` + Tesseract.js + `sharp` | Handwritten Rx digitization, bill parsing, and clinical image preprocessing |

---

## 2. Directory Structure

```
intellidesk_backend/
├── src/
│   ├── server.ts                       # HTTP bootstrap, ML weight loading, route registration
│   ├── config/                         # Supabase client credentials & environment validation
│   ├── middleware/
│   │   ├── authMiddleware.ts           # Supabase JWT authentication & RBAC guards
│   │   └── tenant.ts                   # Multi-tenant institution scoping middleware
│   ├── modules/                        # Domain-driven clinical diagnostic engines
│   │   ├── cdss/                       # Clinical Decision Support System
│   │   │   ├── CDSSService.ts                  # Central CDSS coordinator & cache
│   │   │   ├── DifferentialDiagnosisEngine.ts  # Temperature-scaled ICD-11 logit scorer
│   │   │   ├── ICD11ConceptStore.ts            # Curated WHO ICD-11 knowledge graph
│   │   │   ├── QwenInferenceService.ts         # Cloud Qwen2.5-72B inference client
│   │   │   ├── TreatmentPathwayAdvisor.ts      # Clinical evidence guideline generator
│   │   │   └── routes/cdssRouter.ts            # /api/v1/cdss endpoints
│   │   ├── diagnostics/                # Multimodal diagnostic sensing suite
│   │   │   ├── vision/
│   │   │   │   ├── CloudVisionClassifier.ts    # Qwen2.5-VL 72B dermatology & lesion VLM
│   │   │   │   ├── clinicalMobileNet.ts        # Local 10-class MobileNet-V3 fallback
│   │   │   │   └── imageClassifier.ts          # Vision service orchestrator
│   │   │   ├── audio/
│   │   │   │   ├── CoughClassifier.ts          # 4-class respiratory neural network
│   │   │   │   ├── AudioFeatureExtractor.ts    # 16-d MFCC extraction (Meyda DSP)
│   │   │   │   └── CloudAudioClassifier.ts     # Hugging Face audio inference client
│   │   │   ├── vitals/
│   │   │   │   ├── rPPGSignalProcessor.ts      # Dual-channel video pulse & optical SNR extractor
│   │   │   │   ├── ButterworthFilter.ts        # 4th-order 0.75-3.5 Hz bandpass filter
│   │   │   │   └── PhysiologicalRedFlagSentinel.ts # Tachycardia/bradycardia alerts
│   │   │   ├── facilities/
│   │   │   │   └── EmergencyFacilityService.ts # Geolocation discovery & clinical capability deduction
│   │   │   ├── fusion/
│   │   │   │   ├── MultimodalFusionModel.ts    # 168-d late-fusion DNN (visual+symptom+vitals)
│   │   │   │   ├── multimodalRiskNetwork.ts    # Fusion coordinator & uncertainty engine
│   │   │   │   └── vectorAssembler.ts          # Concatenates multimodal sub-vectors
│   │   │   ├── explainability/
│   │   │   │   ├── gradCamGenerator.ts         # Grad-CAM saliency heatmaps for clinical trust
│   │   │   │   └── uncertaintyEngine.ts        # Monte Carlo Dropout confidence bounds
│   │   │   ├── fhir/
│   │   │   │   ├── FHIRConverterService.ts     # HL7 FHIR R4 DiagnosticReport generator
│   │   │   │   └── ReferralLetterGenerator.ts  # Compiles PDF referral letters with LOINC vitals
│   │   │   ├── progression/
│   │   │   │   └── ScreeningDeltaAnalyzer.ts   # Tracks lesion healing over time
│   │   │   └── routes/diagnosticsRouter.ts     # /api/v1/diagnostics endpoints
│   │   └── pharmacy/                   # Medication intelligence & safety
│   │       ├── PrescriptionOCRParser.ts        # Poppler & Tesseract OCR engine
│   │       ├── DrugInteractionEngine.ts        # 8,000+ drug pair DDI lookup matrix
│   │       ├── AllergySafetySentinel.ts        # Patient allergen contraindication scanner
│   │       ├── fuzzyMatcher.ts                 # Levenshtein RxNorm concept matcher
│   │       ├── rxNormDataset.ts                # In-memory RxNorm clinical formulation store
│   │       ├── RxSentinelService.ts            # Pharmacy safety coordinator
│   │       └── routes/pharmacyRouter.ts        # /api/v1/pharmacy endpoints
│   ├── services/                       # Triage, Welfare & Foundation Services
│   │   ├── patientClinicalRagService.ts # Multi-entity patient dossier aggregator for clinical AI
│   │   ├── deepRankModel.ts            # DeepRank Crisis Severity Index (CSI) NN
│   │   ├── crisisCounselorService.ts   # On-device Qwen ONNX PFA counselor
│   │   ├── clinicalCounselorService.ts # Gemini Flash Lite clinical triage chat
│   │   ├── gemini.ts                   # Multimodal intake, RAG search & PHI redaction
│   │   ├── fraudSentinel.ts            # 3-layer claim integrity check (Hash/Velocity/Autoencoder)
│   │   ├── anomalyModel.ts             # Autoencoder feature reconstruction NN
│   │   ├── attritionModel.ts           # Temporal LSTM longitudinal risk NN
│   │   ├── grantOptimizerModel.ts      # MC Dropout copay optimizer NN
│   │   ├── disbursementService.ts      # RazorpayX UPI & IMPS payouts
│   │   ├── payoutService.ts            # Stripe international & campus vouchers
│   │   ├── receiptParser.ts            # Bill total extraction & currency detection
│   │   ├── socketManager.ts            # Socket.io room broadcaster
│   │   ├── dbService.ts                # Database health & telemetry check
│   │   └── storageBootstrap.ts         # Supabase storage bucket auto-provisioning
│   ├── routes/                         # Core HTTP API route controllers
│   │   ├── auth.ts                     # Signup, login, institution profile
│   │   ├── asyncIntake.ts              # Multipart submission enqueuing to BullMQ
│   │   ├── claims.ts                   # Claim CRUD & triage queue endpoints
│   │   ├── chat.ts                     # PFA crisis counseling chat endpoints
│   │   ├── admin.ts                    # Admin overrides, telemetry, payouts
│   │   ├── telemetry.ts                # Real-time ESI & fund analytics
│   │   └── knowledge.ts                # Institutional policy RAG semantic search
│   ├── workers/                        # Distributed BullMQ background workers
│   │   ├── intakeWorker.ts             # 10-step asynchronous intake pipeline
│   │   ├── mlRetrainingWorker.ts       # Continuous in-process fine-tuning for TF.js models
│   │   └── notificationWorker.ts       # Asynchronous email & SMS dispatch
│   └── ml/                             # Training scripts for local TF.js models
│       ├── deep_rank.ts                # DeepRank training pipeline
│       ├── lstm.ts                     # Attrition LSTM training pipeline
│       ├── autoencoder.ts              # Anomaly Autoencoder training pipeline
│       └── train_all.ts                # Master training orchestration script
├── models/                             # Persistent weights (model.json + binary shards)
├── eng.traineddata                     # 5MB Tesseract English language OCR model
├── Dockerfile & docker-compose.yml     # Containerized production runtime
└── package.json                        # Dependencies & npm scripts
```

---

## 3. Server Bootstrap Sequence (`src/server.ts`)

The backend initializes sequentially to ensure zero-crash resilience:

```
1. Storage Bucket Provisioning (ensureStorageBucketsExist())
   • Verifies 'claim-receipts', 'prescriptions', and 'diagnostic-images' exist in Supabase.

2. Database Health & Schema Telemetry (DatabaseService.checkDatabaseHealth())
   • Pings Supabase PostgreSQL, verifies RLS status, claims table readiness, and fund liquidity.

3. Triage & Financial ML Models Initialization
   • Concurrently bootstraps in-process TF.js models:
     - loadOrTrainLSTMModel()
     - loadOrTrainGrantOptimizerModel()
     - loadOrTrainDeepRankModel()
     - loadOrTrainAnomalyModel()
   • If weights are missing, initializes baseline fallbacks gracefully.

4. Multimodal Clinical Diagnostics Models Initialization
   • Concurrently bootstraps clinical neural networks:
     - ClinicalImageClassifier.initialize() (loads MobileNet-V3 weights)
     - CoughClassifier.loadOrBootstrapModel() (loads TF.js 4-class respiratory weights)
     - MultimodalRiskNetwork.initialize() (loads 168-d late-fusion weights)

5. HTTP & Socket.io Listen
   • Binds to 0.0.0.0 on PORT (default 3000).
   • Spins up BullMQ intakeWorker, mlRetrainingWorker, and notificationWorker.
```

---

## 4. Clinical Modules Architecture

### 4.1 CDSS — Clinical Decision Support System (`src/modules/cdss/`)
- **`CDSSService.ts`**: Coordinates clinical evaluations. Validates incoming symptoms, applies in-memory caching keyed by `screeningId` to ensure idempotency, and routes to either cloud Qwen2.5-72B or local deterministic algorithms. Features case-invariant normalization supporting both camelCase and snake_case DTO schemas across cloud and offline records.
- **`QwenInferenceService.ts`**: Cloud VLM/LLM inference client for Qwen2.5-72B. Seamlessly extracts and scrutinizes patient clinical notes and subjective history narratives, synthesizing patient-reported symptoms, triggers, prior exposures, and duration into the diagnostic prompt.
- **`DifferentialDiagnosisEngine.ts`**: Evaluates symptom vectors against the WHO ICD-11 graph. Applies temperature-scaled logit transformation ($T=1.25$) with clipping to $[-20, 20]$ to prevent numerical overflow and calculate calibrated probability distributions.
- **`ICD11ConceptStore.ts`**: In-memory knowledge base containing cardinal ICD-11 codes, baseline prevalence priors, severity weights, and contraindications.
- **`FHIRConverterService.ts`**: Transforms CDSS outputs into HL7 FHIR R4 `Bundle` containing `DiagnosticReport`, `Observation`, and `Condition` resources.

### 4.2 Diagnostics Sensing Suite (`src/modules/diagnostics/`)
- **Vision (`vision/`)**:
  - `CloudVisionClassifier.ts`: Sends image buffers through `sharp` preprocessing to `Qwen/Qwen2.5-VL-72B-Instruct` via Hugging Face. Returns structured JSON containing primary diagnosis, severity, anatomical location, and differential list.
  - `clinicalMobileNet.ts`: Local TFLite fallback supporting 10 common clinical categories (eczema, psoriasis, cellulitis, burn, conjunctivitis, etc.).
- **Audio (`audio/`)**:
  - `AudioFeatureExtractor.ts`: Processes 16kHz uncompressed WAV buffers via Meyda.js, extracting 16 Mel-Frequency Cepstral Coefficients (MFCCs).
  - `CoughClassifier.ts`: Dense neural network (`@tensorflow/tfjs-node`) mapping 16 MFCC features to 4 classes: dry, wet, whooping, normal.
- **Vitals (`vitals/`)**:
  - `rPPGSignalProcessor.ts`: Advanced bio-signal processor featuring **Dual-Channel Adaptive Optical Selection**. Simultaneously evaluates **Green Channel** (contactless facial capillary absorption) and **Red Channel** (contact fingertip photoplethysmography). Computes Normalized Power Spectral Density (PSD), summing fundamental pulse power ($f_0 \pm 0.22\text{ Hz}$) and first harmonic ($2f_0 \pm 0.22\text{ Hz}$) relative to noise floor to dynamically select the optical carrier with highest pulsatile SNR.
  - `ButterworthFilter.ts`: 4th-order bandpass filter ($0.75–3.5\text{ Hz}$) isolating pulse signals in the 45–210 BPM human heart rate band.
  - `PhysiologicalRedFlagSentinel.ts`: Generates real-time alerts for tachycardia ($>110\text{ BPM}$), bradycardia ($<50\text{ BPM}$), hypoxia, or signal noise.
- **Emergency Facilities (`facilities/`)**:
  - `EmergencyFacilityService.ts`: Real-time emergency medical facility discovery engine. Implements **Dynamic Clinical Capability Deduction**, matching diagnosed patient conditions, ICD-11 differentials, and triage urgency against verified facility services (Burn Units, Comprehensive Stroke Centers, Level 1 Trauma, 24/7 Psychiatric Crisis, Pediatric ER). Computes Haversine distance, travel times, and emergency telephone lines.
- **Clinical Referral Letters & FHIR (`fhir/`)**:
  - `ReferralLetterGenerator.ts`: Vector PDF generation via `pdfkit`. Formats official medical referral letters encoding vital signs with standard LOINC codes (Temperature: 8310-5, HR: 8867-4, BP: 8480-6, SpO2: 2708-6, Pain: 72514-3). Computes Bayesian uncertainty confidence intervals, urgent clinical directives, and attending physician sign-off block.
- **Fusion & Explainability (`fusion/`, `explainability/`)**:
  - `MultimodalFusionModel.ts`: Late-fusion DNN concatenating 128 visual features + 32 clinical symptom features + 8 demographic features into a 168-d vector, outputting continuous risk and categorical care tiers.
  - `gradCamGenerator.ts`: Computes gradient of the predicted class score with respect to convolutional feature maps, producing normalized 2D saliency heatmaps.

### 4.3 Pharmacy & Medication Safety (`src/modules/pharmacy/`)
- **`PrescriptionOCRParser.ts`**: Multi-tiered prescription digitizer. Primary: Open-weight Vision-Language Models (`GLM-4.6V-Flash`, `Qwen2.5-VL-72B`, `DeepSeek-V4-Flash-Vision` via Hugging Face Router). Secondary: Poppler `pdftotext` for clean electronic PDFs. Fallback: Local Tesseract.js v7. Includes rule-based sanitization for common OCR clinical confusions (e.g., replacing 'O' with '0' in dosage numbers, 'I' with '1' in frequencies).
- **`fuzzyMatcher.ts` & `rxNormDataset.ts`**: Maps noisy drug strings to standardized RxNorm Concept Unique Identifiers (RxCUIs) using Levenshtein distance metrics.
- **`DrugInteractionEngine.ts`**: In-memory hash map indexing 8,000+ known clinical drug-drug interactions. Evaluates incoming regimens and classifies severity into `CONTRAINDICATED_SEVERE`, `MAJOR`, `MODERATE_MONITOR`, `MINOR`, or `SAFE`.
- **`AllergySafetySentinel.ts`**: Intersects extracted drug ingredients with the patient's recorded allergen profile using cross-reactivity tree analysis.
- **`AlternativeMedicationService.ts`**: Live integration with the **NIH National Library of Medicine (NLM) RxNav REST API** and **RxClass API**. Dynamically resolves RxCUIs and anatomical therapeutic classes (ATC). Generates safe, non-cross-reactive alternatives with clinical provenance tags when allergen contraindications occur.
- **`RxSentinelService.ts`**: Master orchestrator coordinating OCR extraction, fuzzy RxNorm mapping, allergy conflicts, dynamic alternative resolution, DDI warnings, and database persistence.

---

## 5. Core Services Architecture (`src/services/`)

- **`patientClinicalRagService.ts`**: Unified Clinical Patient RAG (Retrieval-Augmented Generation) Service. Aggregates multi-entity clinical dossiers from Supabase across:
  - `profiles` (demographics & canonical patient roster resolution e.g., Priya Sharma `PAT-2026-002`)
  - `patient_medications` (active medications & dosage regimens)
  - `patient_allergies` (verified hypersensitivities)
  - `health_screenings` (multimodal risk scores, full rPPG vitals with BP/Temp/RR, and subjective notes)
  - `cdss_evaluations` (ICD-11 codes, primary titles, and first-line treatment pathways)
  - `claims` (emergency copay status & approved allocations)
  Synthesizes context-rich, privacy-preserved prompt blocks tailored for both the Mental Health Counselor (`/api/v1/chat/mental-health`) and the Emergency Claim Copay Assistant.
- **`clinicalCounselorService.ts`**: Multi-turn clinical copay counselor. Injects live claim RAG context into Gemini Flash Lite prompts with per-session rate throttling, memory response caching, and local Rogerian Psychological First Aid (PFA) fallbacks.
- **`deepRankModel.ts`**: Neural network evaluating crisis text. Computes Crisis Severity Index (CSI $\in [0, 1]$) and maps to ESI triage levels:
  - $\text{CSI} \ge 0.85 \rightarrow \text{ESI-1 (Critical / Resuscitation)}$
  - $\text{CSI} \ge 0.60 \rightarrow \text{ESI-2 (Emergent)}$
  - $\text{CSI} \ge 0.35 \rightarrow \text{ESI-3 (Urgent)}$
  - $\text{CSI} < 0.35 \rightarrow \text{ESI-4 / ESI-5 (Routine)}$
- **`crisisCounselorService.ts`**: Local ONNX transformer executing `Xenova/Qwen1.5-0.5B-Chat`. Intercepts self-harm keywords via `CRITICAL_SELF_HARM_REGEX`, injecting emergency 24/7 hotline cards with 100% on-device privacy.
- **`gemini.ts`**: Wraps Google Gemini APIs for:
  - Multimodal claim intake narrative parsing (`gemini-2.0-flash`).
  - Chain-of-Thought policy adjudication with mandatory clause citations (`gemini-1.5-pro`).
  - Semantic embeddings (`gemini-embedding-001`, 768-d) for hybrid Reciprocal Rank Fusion (RRF) policy search.
  - Automated medical privacy and PHI redaction before generating official letters (`gemini-1.5-flash`).
- **`fraudSentinel.ts`**: 3-layer claim integrity check:
  - Layer A: SHA-256 cryptographic image hashing to detect duplicate receipts.
  - Layer B: 7-day claim velocity monitoring per student phone identity.
  - Layer C: Feature reconstruction anomaly detection via Autoencoder MSE (threshold = 0.75).
  - *Emergency life-safety claims automatically bypass velocity checks.*
- **`disbursementService.ts` & `payoutService.ts`**: Multi-rail disbursement executing instant UPI/IMPS via RazorpayX, USD payouts via Stripe, or generating campus clinic QR vouchers.

---

## 6. Complete API Reference

### 🔷 Clinical Diagnostics & CDSS
| Method | Route | Auth / Role | Description |
|---|---|---|---|
| `POST` | `/api/v1/diagnostics/vision` | Authenticated | Upload clinical image $\rightarrow$ Qwen2.5-VL 72B / MobileNet + Grad-CAM heatmap |
| `POST` | `/api/v1/diagnostics/audio` | Authenticated | Upload cough audio $\rightarrow$ 16-d MFCC extraction $\rightarrow$ 4-class respiratory model |
| `POST` | `/api/v1/diagnostics/vitals` | Authenticated | Ingest facial/fingertip video frames $\rightarrow$ dual-channel rPPG pulse extraction & vitals red flags |
| `POST` | `/api/v1/diagnostics/facilities/emergency` | Authenticated | Search nearby emergency facilities with dynamic clinical capability deduction |
| `GET` | `/api/v1/diagnostics/facilities/capabilities` | Authenticated | List standardized emergency facility clinical capability taxonomy |
| `POST` | `/api/v1/diagnostics/referral-letter/pdf` | Authenticated | Compile standardized PDF clinical referral letter with LOINC vitals & clinician signature |
| `GET` | `/api/v1/diagnostics/screenings/patient/:patientId` | Authenticated | Retrieve longitudinal multimodal health screening records |
| `POST` | `/api/v1/diagnostics/fusion` | Authenticated | Concatenate vision + symptoms + vitals $\rightarrow$ 168-d late-fusion clinical risk score |
| `POST` | `/api/v1/cdss/evaluate` | Authenticated | Submit clinical symptoms $\rightarrow$ WHO ICD-11 differential diagnosis & FHIR R4 Bundle |
| `POST` | `/api/v1/cdss/predict-qwen` | Authenticated | Qwen2.5-72B differential disease prediction with subjective clinical notes synthesis |
| `POST` | `/api/v1/cdss/approve` | Clinician / Admin | Attending clinician sign-off or diagnostic override with cryptographic signature hash |
| `GET` | `/api/v1/cdss/evaluation/:screeningId` | Authenticated | Retrieve cached or persisted CDSS evaluation by health screening ID |

### 🔷 Psychological First Aid (PFA), Clinical Chatbots & Patient-RAG
| Method | Route | Auth / Role | Description |
|---|---|---|---|
| `POST` | `/api/v1/chat` | Authenticated | Send message $\rightarrow$ on-device Qwen PFA reply + self-harm crisis interception |
| `POST` | `/api/v1/chat/mental-health` | Authenticated | Patient-RAG augmented empathetic PFA counselor with full patient dossier context |
| `GET` | `/api/v1/chat/:ticketId/messages` | Authenticated | Retrieve confidential PFA chat history for a clinical claim |

### 🔷 Pharmacy & Medication Safety
| Method | Route | Auth / Role | Description |
|---|---|---|---|
| `POST` | `/api/v1/pharmacy/parse` | Authenticated | Ingest prescription image $\rightarrow$ OCR $\rightarrow$ RxNorm canonical matching |
| `POST` | `/api/v1/pharmacy/interactions`| Authenticated | Ingest drug list $\rightarrow$ 8,000+ DDI matrix & patient allergy contraindication check |

### 🔷 Psychological First Aid & Chat
| Method | Route | Auth / Role | Description |
|---|---|---|---|
| `POST` | `/api/v1/chat` | Authenticated | Send message $\rightarrow$ on-device Qwen PFA reply + self-harm crisis interception |
| `GET` | `/api/v1/chat/:ticketId/messages`| Authenticated | Retrieve conversation history for a given encounter |

### 🔷 Triage & Intake
| Method | Route | Auth / Role | Description |
|---|---|---|---|
| `POST` | `/api/v1/intake/web` | Public / Auth | Submit clinical request (narrative + photos/bills) $\rightarrow$ enqueued to BullMQ |
| `GET` | `/api/v1/intake/status/:jobId` | Public / Auth | Poll 10-step progress of an asynchronous intake job |
| `GET` | `/api/v1/claims` | Tenant Scoped | List clinical encounters (filter by ESI tier, status, keyword) |
| `GET` | `/api/v1/claims/:id` | Tenant Scoped | Retrieve full encounter record with all ML and diagnostic telemetry |

### 🔷 Clinical Admin War Room
| Method | Route | Auth / Role | Description |
|---|---|---|---|
| `POST` | `/api/v1/claims/:id/override` | `ADMIN` | Override AI-assigned ESI tier with mandatory clinician documentation |
| `POST` | `/api/v1/claims/:id/disburse` | `ADMIN` | Execute instant emergency copay disbursement via RazorpayX or Stripe |
| `GET` | `/api/v1/admin/telemetry` | `ADMIN` | Dashboard telemetry: ESI breakdown, diagnostic counts, fund liquidity |
| `GET` | `/api/v1/admin/knowledge` | `ADMIN` | Semantic search (RAG) over institutional healthcare policies |

---

## 7. Background Workers (`src/workers/`)

### `intakeWorker.ts` — Asynchronous 10-Step Pipeline
Runs on the `clinical-intake-queue` BullMQ worker for every submitted claim:
1. **Multimodal Receipt / Document Parsing**: Poppler `pdftotext` $\rightarrow$ Tesseract.js OCR fallback.
2. **Clinical NLP Feature Extraction**: DistilBERT sentiment scoring and urgent medical keyword density calculation.
3. **Fraud Sentinel Check**: SHA-256 duplicate receipt hash lookup, 7-day velocity check, and Autoencoder anomaly scoring.
4. **DeepRank CSI Inference**: Computes continuous Crisis Severity Index ($[0, 1]$).
5. **ESI Tier Assignment**: Maps CSI to standard ESI-1 through ESI-5 triage levels.
6. **Temporal Attrition Risk**: Evaluates multi-encounter patient history via LSTM.
7. **Grant Optimization**: Computes recommended emergency copay relief with MC Dropout epistemic variance.
8. **Multimodal Intake Parsing**: Structures text narrative and clinical media using Gemini 2.0 Flash.
9. **Policy Match & RAG**: Semantic vector similarity search via pgvector and Gemini 1.5 Pro CoT adjudication.
10. **Persistence & Broadcast**: Commits record to Supabase and broadcasts real-time `ticket-created` event via Socket.io.

### `mlRetrainingWorker.ts` — Continuous In-Process Learning
- Triggers on scheduled BullMQ intervals or via admin API (`/api/v1/workflow/retrain`).
- Queries resolved tickets from Supabase containing clinician-verified outcomes.
- Executes 5 epochs of in-process retraining for DeepRank CSI and Grant Optimizer models using Adam.
- Overwrites weights directly in `./models/`, enabling continuous adaptation to clinical trends.

### `notificationWorker.ts` — Asynchronous Dispatch
- Dispatches transactional emails via Nodemailer / Resend for status milestones.
- Dispatches emergency SMS alerts via Twilio for all ESI-1 Resuscitation tickets.

---

## 8. Security & Privacy Architecture

```
Client Request ──► CORS ──► JWT Auth Middleware (requireAuth)
                                     │
                        RBAC Guard (requireRole(['ADMIN']))
                                     │
                        tenantScopeMiddleware (injects institution_id)
                                     │
                        Supabase PostgreSQL (Row-Level Security Policies)
```

- **Row-Level Security (RLS)**: Enforced across all PostgreSQL tables (`tickets`, `profiles`, `activity_logs`, `health_funds`). Queries without valid institutional tenant scoping are rejected at the database level.
- **Clinical Decision Logging**: Every clinician override, diagnosis modification, and copay disbursement generates a record in `activity_logs` containing actor ID, timestamp, and full structured JSONB payload.
- **FERPA Compliance**: Clinical diagnosis redaction replaces acute medical conditions with generalized medical necessity phrasing prior to sending notices to university faculty.
