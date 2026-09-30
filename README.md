# 🏥 MedAccess AI

> **AI-powered student health emergency & welfare platform** — clinical triage, multimodal diagnostics, psychological first aid, pharmacy safety, and emergency fund disbursement, all in one system.

---

## 📑 Table of Contents

1. [What is MedAccessAI?](#1-what-is-medaccessai)
2. [Real-World Use Cases](#2-real-world-use-cases)
3. [Feature Overview](#3-feature-overview)
4. [🤖 ML & AI Systems — Deep Dive](#4--ml--ai-systems--deep-dive)
5. [System Architecture](#5-system-architecture)
6. [Folder Structure](#6-folder-structure)
7. [Technology Stack](#7-technology-stack)
8. [API Reference](#8-api-reference)
9. [Database Schema](#9-database-schema)
10. [Background Workers](#10-background-workers)
11. [Security Architecture](#11-security-architecture)
12. [Deployment](#12-deployment)
13. [Environment Variables](#13-environment-variables)
14. [Getting Started](#14-getting-started)

---

## 1. What is MedAccessAI?

**MedAccess AI** is a full-stack, AI-first medical welfare platform built for university campuses. It bridges the gap between a student experiencing a health or financial crisis and institutional support — using cutting-edge on-device ML models, cloud LLMs, and real-time infrastructure.

| Role | Portal | Core Workflow |
|---|---|---|
| **Student / Patient** | Mobile (Flutter) | Submit health claim → chat with PFA AI → track payout status |
| **Clinical Admin** | Mobile (Flutter) | Triage ESI queue → approve/disburse grants → monitor fund liquidity |

### Core Principles

- **AI-First, Human-in-the-Loop** — every ML prediction is a decision-support tool; clinicians can override with documented justification.
- **Privacy by Design** — HIPAA-aligned audit trail, FERPA-compliant professor notification redaction, Row-Level Security on all data.
- **Offline-Resilient** — every cloud ML call has a local on-device or deterministic fallback, ensuring zero downtime.
- **Multi-Rail Disbursement** — funds reach students via UPI (RazorpayX), IMPS, Stripe (USD), or campus voucher codes.

---

## 2. Real-World Use Cases

| Scenario | How MedAccess Handles It |
|---|---|
| Student has a hospital bill and needs ER copay relief | PDF bill → OCR extracts total → DeepRank assigns ESI tier → Grant Optimizer calculates amount → admin disburses via UPI |
| Student messages about self-harm and rent crisis | Crisis regex detects self-harm → Qwen PFA model responds empathetically → emergency hotline cards displayed → welfare ticket created |
| Student uploads a photo of a skin rash | Qwen2.5-VL 72B cloud vision classifier diagnoses condition → local MobileNet-V3 fallback → Grad-CAM heatmap highlights affected area |
| Student submits a prescription for medication refill | Tesseract OCR parses handwritten prescription → fuzzy RxNorm matcher normalizes drug names → DrugInteractionEngine checks 8,000+ interaction pairs |
| Admin reviews compliance at end of month | HIPAA audit PDF → ESI distribution, fund utilization, disbursement ledger → tamper-evident SHA-256 checksum |
| Student has repeated high-urgency tickets | LSTM attrition model detects dropout risk → flags student for proactive outreach |
| Student submits a suspicious duplicate receipt | SHA-256 image hash matches previous → Autoencoder detects anomalous feature pattern → claim flagged DUPLICATE_RECEIPT_DETECTED |

---

## 3. Feature Overview

### 🔷 Patient Portal

- **Claim Intake** — submit a medical request as free text + attach PDF bill or receipt photo
- **Multimodal Receipt Parsing** — automatic extraction of bill total from PDF (Poppler `pdftotext`) or scanned image (Tesseract.js OCR)
- **Real-Time Status Tracking** — WebSocket push updates on ESI tier, triage status, and payout completion
- **PFA Chat (Psychological First Aid)** — multi-turn AI chat with local Qwen ONNX model, full crisis detection, hardship confirmation flow, and ticket auto-creation
- **Clinical Dashboard** — symptom logger, health record viewer, screening history
- **Emergency Hub** — one-tap access to 24/7 crisis hotlines (Tele-MANAS 14416, 988 Lifeline, Vandrevala Foundation)
- **Pharmacy Hub** — prescription OCR parser, drug interaction checker, allergy safety scanner
- **Offline Sync** — SharedPreferences caching with graceful recovery on reconnection
- **QR Voucher** — campus welfare voucher code for pharmacy/clinic redemption
- **rPPG Vitals Monitor** — camera-based contactless heart rate measurement (no wearable required)

### 🔷 Admin Clinical War Room

- **ESI Triage Queue** — real-time sorted list ordered by Crisis Severity Index (CSI)
- **One-Tap Payout** — execute RazorpayX UPI/bank or Stripe disbursement from the mobile app
- **ESI Override** — override AI-assigned triage tier with documented clinical justification (full audit trail)
- **Fraud Flag Management** — review Fraud Sentinel decisions, mark false positives
- **Health Fund Liquidity Panel** — monitor budget utilization, remaining balance, allocation history
- **Knowledge Base (RAG Search)** — semantic search over institutional policy documents
- **HIPAA Compliance Audit PDF** — downloadable report with ESI distribution, disbursement ledger, fund utilization, tamper-evident SHA-256 checksum
- **Clinical Diagnostics Screen** — review AI-generated multimodal diagnostic results

---

## 4. 🤖 ML & AI Systems — Deep Dive

This section covers every ML model, AI pipeline, and cloud/local fallback pair in the system.

---

### 4.1 DeepRank — Crisis Severity Indexer

**Purpose:** Assigns a Crisis Severity Index (CSI in [0, 1]) and ESI triage tier to every incoming claim.

| Attribute | Detail |
|---|---|
| **Architecture** | Dense Neural Network (TensorFlow.js Sequential) |
| **Input Features** | `word_count`, `urgent_keyword_count`, `sentiment_score`, `historical_ticket_count` (4-d) |
| **Output** | CSI → ESI tier (ESI-1 >= 0.85, ESI-2 >= 0.60, ESI-3 >= 0.35, ROUTINE) |
| **Training** | Offline via `npm run train:ml`, synthetic + real-outcome labeled data |
| **Fine-Tuning** | `fineTuneDeepRankModel()` — 5 epochs on resolved tickets, Adam optimizer |
| **Fallback** | CSI = 0.5 (neutral) if model weights not found on disk |
| **File** | `intellidesk_backend/src/services/deepRankModel.ts` |

```
Input: [word_count=180, urgent_kw=4, sentiment=0.87, hist_count=2]
  Dense(hidden) → relu → sigmoid
  CSI = 0.91  →  ESI_1 (CRITICAL)
```

---

### 4.2 TemporalAttrition LSTM — Dropout Risk Predictor

**Purpose:** Analyzes a student's longitudinal ticket history to predict likelihood of dropping out.

| Attribute | Detail |
|---|---|
| **Architecture** | LSTM Neural Network (TensorFlow.js) |
| **Input Shape** | `[1, 1, 4]` — batch=1, timeSteps=1, features=4 |
| **Features** | Aggregated `word_count`, `urgent_keyword_count`, `sentiment_score`, `historical_ticket_count` |
| **Output** | Dropout risk score in [0, 1] |
| **Data Source** | Last 10 tickets from Supabase per student phone |
| **Fallback** | 0.0 (safe) if model not loaded |
| **File** | `intellidesk_backend/src/services/attritionModel.ts` |

---

### 4.3 Fraud Sentinel — Multi-Layer Anomaly Detection

**Purpose:** Detects fraudulent or duplicate emergency fund claims using a 3-layer detection stack.

| Layer | Method | Risk Contribution |
|---|---|---|
| **Layer A** | SHA-256 receipt image hash lookup in DB | +0.50 if duplicate found |
| **Layer B** | 7-day claim velocity check per phone number | +0.35 if >= 2 claims in 7 days |
| **Threshold Gaming** | Repeated micro-requests in $150–$200 band | +0.30 if pattern detected |
| **Layer C** | Autoencoder MSE anomaly score | +0.40 if score >= 0.75 |

Life-safety critical claims bypass velocity/threshold checks — only hard fraud (duplicate receipt) can flag them.

| Attribute | Detail |
|---|---|
| **File** | `intellidesk_backend/src/services/fraudSentinel.ts` |
| **Anomaly Dependency** | Calls `anomalyModel.ts` (Autoencoder) for Layer C |

---

### 4.4 Anomaly Autoencoder — Reconstruction-Based Fraud Detection

**Purpose:** Learns the normal feature distribution of legitimate claims. High MSE = anomalous/fraudulent submission.

| Attribute | Detail |
|---|---|
| **Architecture** | Autoencoder (Encoder-Decoder) Neural Network (TensorFlow.js) |
| **Input** | 4-feature normalized vector `[word_count_norm, urgent_kw_norm, sentiment, hist_count_norm]` |
| **Output** | Reconstruction MSE as anomaly score |
| **Training** | `npm run train:ml` → `train_all.ts` |
| **Fallback** | 0.0 (no anomaly) if model not found |
| **File** | `intellidesk_backend/src/services/anomalyModel.ts` |

---

### 4.5 Grant Optimizer — MC Dropout Neural Regression

**Purpose:** Recommends the optimal emergency grant amount with Bayesian uncertainty quantification.

| Attribute | Detail |
|---|---|
| **Architecture** | Dense Sequential NN with Dropout layers (TensorFlow.js) |
| **Input Features** | `dropout_risk_score`, `requested_amount`, `historical_grant_total`, `fund_remaining_ratio`, `urgency_level_numeric` (5-d) |
| **Output** | `recommendedAmount`, `confidenceScore`, `variance` |
| **Uncertainty** | Monte Carlo Dropout (20 forward passes with dropout active) → epistemic variance |
| **Fine-Tuning** | `fineTuneGrantOptimizerModel()` on resolved historical tickets |
| **Fallback** | min(requested, $200) if model not loaded |
| **File** | `intellidesk_backend/src/services/grantOptimizerModel.ts` |

```
MC Dropout (20 passes) → mean grant ratio ± epistemic std dev
confidence = 1.0 - min(variance x 10, 1.0)
```

---

### 4.6 NLP Sentiment Pipeline — Clinical Text Analysis

**Purpose:** Extracts sentiment, distress magnitude, and urgent medical keywords from patient submissions.

| Attribute | Detail |
|---|---|
| **Primary Model** | `Xenova/distilbert-base-uncased-finetuned-sst-2-english` (ONNX via `@xenova/transformers`) |
| **Fallback** | Keyword heuristic scoring using `CLINICAL_URGENT_REGEX` |
| **Output** | `sentimentScore`, `negativeScore`, `isCriticalDistress`, `extractedKeywords`, `medicalEntityCount` |
| **Clinical Keywords** | hospital, emergency, icu, ambulance, seizure, overdose, suicide, stroke, cardiac, unconscious, burn, etc. |
| **File** | `intellidesk_backend/src/services/nlpPipeline.ts` |

---

### 4.7 PFA Counselor — Local ONNX Chat AI (Crisis Response)

**Purpose:** Real-time Psychological First Aid using locally-running quantized LLMs. Detects crisis messages and triggers emergency resource cards.

| Attribute | Detail |
|---|---|
| **Primary Model** | `Xenova/Qwen1.5-0.5B-Chat` (quantized ONNX, 100% CPU, no internet required) |
| **Secondary Fallback** | `onnx-community/Qwen2.5-0.5B-Instruct` (quantized ONNX) |
| **Tertiary Fallback** | Rogerian PFA deterministic response engine (zero-latency, 100% uptime) |
| **Crisis Detection** | `CRITICAL_SELF_HARM_REGEX` → suicide/self-harm keywords → immediate emergency resource injection |
| **Hardship Detection** | `RELIEF_HARDSHIP_REGEX` → financial hardship → ticket creation confirmation flow |
| **Multi-Turn** | Last 4 messages included in ChatML prompt for conversational coherence |
| **Inference Timeout** | 2.5s safety timeout, falls back instantly if local model is slow |
| **File** | `intellidesk_backend/src/services/crisisCounselorService.ts` |

```
Student: "I can't pay my rent and I feel like giving up"
  RELIEF_HARDSHIP_REGEX hit → requiresConfirmation = true
Counselor: "I hear how stressful this is. Would you like me to submit an Emergency Grant ticket?"
  Student confirms → ticket created → PFA response generated
```

---

### 4.8 Clinical Counselor — Gemini Flash Lite (Real-Time Chat)

| Attribute | Detail |
|---|---|
| **Cloud Model** | `gemini-flash-lite-latest` (Google Gemini API) |
| **Max Output Tokens** | 50 (optimized for real-time chat latency) |
| **Response Cache** | In-memory 10-minute TTL cache |
| **Rate Limiting** | Per-claim throttle to prevent spam |
| **Life-Safety Detection** | `LIFE_SAFETY_REGEX` → bypasses throttle, injects emergency helplines |
| **File** | `intellidesk_backend/src/services/clinicalCounselorService.ts` |

---

### 4.9 Multimodal Intake Processor — Gemini 2.0 Flash

| Attribute | Detail |
|---|---|
| **Cloud Model** | `gemini-2.0-flash` (Google Gemini API) |
| **Input** | Free-text message + optional medical invoice/receipt URL |
| **Output Schema** | `category`, `urgency`, `plainTextSummary`, `requestedAmount`, `sentimentNegativeScore`, `multiDepartmentInvolvement`, `policyAmbiguityScore` |
| **Validation** | Zod schema validation on every response |
| **Fallback** | Safe default `General Health / Routine` object if Gemini fails |
| **File** | `intellidesk_backend/src/services/gemini.ts` |

---

### 4.10 Policy Adjudicator — Gemini 1.5 Pro (Chain-of-Thought RAG)

| Attribute | Detail |
|---|---|
| **Cloud Model** | `gemini-1.5-pro` (Google Gemini API) |
| **Reasoning** | Chain-of-Thought — must cite exact policy clause before deciding |
| **Decisions** | `Auto-Approved`, `Escalated`, `Denied` |
| **Anti-Hallucination** | If policy context irrelevant → output `Escalated / Out of Scope` |
| **Response Format** | Structured JSON via native Gemini `responseSchema` |
| **File** | `intellidesk_backend/src/services/gemini.ts` → `evaluatePolicyMatch()` |

---

### 4.11 Semantic Policy Search — Gemini Embeddings + pgvector RAG

| Attribute | Detail |
|---|---|
| **Embedding Model** | `gemini-embedding-001` (768-d, Google Gemini API) |
| **Vector Database** | Supabase `pgvector` extension, `vector(768)` column |
| **Search Method** | Hybrid RRF (Reciprocal Rank Fusion) — vector similarity + keyword search |
| **RPC Function** | `hybrid_match_policies()` PostgreSQL RPC |
| **Low-Confidence Warning** | Logs warning if top RRF score < 0.015 |
| **File** | `intellidesk_backend/src/services/gemini.ts` → `searchMatchingPolicies()` |

---

### 4.12 Cloud Vision Classifier — Qwen2.5-VL 72B (Dermatology & Ocular)

**Purpose:** Classifies clinical images (rashes, skin lesions, ocular conditions, wounds, burns, oral infections) via a 72B-parameter VLM.

| Attribute | Detail |
|---|---|
| **Cloud Model** | `Qwen/Qwen2.5-VL-72B-Instruct` via Hugging Face Inference Router |
| **Local Fallback** | Clinical MobileNet-V3 (TFLite, on-device, quantized) |
| **Input** | Raw image buffer (preprocessed by `sharp`) |
| **Output** | `condition`, `anatomicalSite`, `severity`, `confidence`, `findings[]`, `differentialDiagnoses[]`, `recommendedAction`, `isEmergencyAlert` |
| **Emergency Override** | severity = critical → immediate ER alert |
| **File** | `intellidesk_backend/src/modules/diagnostics/vision/CloudVisionClassifier.ts` |

```
Cloud (HF_TOKEN set):  Image → sharp → Qwen2.5-VL 72B → structured JSON
Offline fallback:      Image → Local MobileNet-V3 → 10-class classification
```

---

### 4.13 Multimodal Fusion Model — Late-Fusion Deep Neural Network

**Purpose:** Fuses visual, symptom, and demographic signals into a unified clinical risk score with uncertainty bounds.

| Attribute | Detail |
|---|---|
| **Architecture** | Multi-head Late-Fusion DNN (TensorFlow.js Functional API) |
| **Input Dimension** | 168-d concatenated vector [128 visual + 32 symptoms + 8 demographics] |
| **Head 1** | Dense(1, sigmoid) → continuous risk score in [0, 1] |
| **Head 2** | Dense(3, softmax) → [Low Risk, Moderate Need, Critical Referral] |
| **Uncertainty** | Monte Carlo Dropout → epistemic std dev + 95% CI bounds |
| **Architecture Detail** | Dense(128, relu) → BatchNorm → Dropout(0.3) → Dense(64, relu) → Dropout(0.25) |
| **File** | `intellidesk_backend/src/modules/diagnostics/fusion/MultimodalFusionModel.ts` |

---

### 4.14 CDSS — Clinical Decision Support System (ICD-11 + Qwen2.5-72B)

**Purpose:** WHO ICD-11 differential diagnosis, urgency classification, and evidence-based treatment pathways.

| Attribute | Detail |
|---|---|
| **Cloud Model** | `Qwen/Qwen2.5-72B-Instruct` via Hugging Face Router |
| **Local Fallback** | `DifferentialDiagnosisEngine` — deterministic ICD-11 scoring algorithm |
| **Knowledge Base** | `ICD11ConceptStore` — curated WHO ICD-11 concept graph with probability priors |
| **Differential Engine** | Temperature-scaled logit scoring (T=1.25), [-20, 20] logit clipping (Guardrail 2) |
| **Urgency Levels** | `ROUTINE`, `PROMPT_EVALUATION`, `IMMEDIATE_EMERGENCY` |
| **Idempotency** | Results cached by `screeningId` to prevent duplicate DB writes |
| **FHIR Export** | `FHIRConverterService` converts result to HL7 FHIR R4 Bundle |
| **File** | `intellidesk_backend/src/modules/cdss/CDSSService.ts` |

---

### 4.15 Cough Classifier — On-Device Acoustic ML

**Purpose:** Passive respiratory disease screening via cough audio classification.

| Attribute | Detail |
|---|---|
| **Architecture** | Dense(48, BN, Dropout) → Dense(24, Dropout) → Dense(4, softmax) with L2 regularization |
| **Input** | 16-d MFCC acoustic feature vector (extracted by AudioFeatureExtractor / Meyda.js) |
| **Output** | 4-class probability [dry cough, wet/productive, whooping, normal] |
| **Red Flag** | Wheeze confidence >= threshold → immediate clinical alert |
| **Cloud Option** | `CloudAudioClassifier` → Hugging Face Audio Inference (fallback to local) |
| **File** | `intellidesk_backend/src/modules/diagnostics/audio/CoughClassifier.ts` |

---

### 4.16 rPPG Vital Sign Processor — Camera-Based Heart Rate

**Purpose:** Extracts heart rate and SpO2 estimate from facial video frames — no wearable hardware required.

| Attribute | Detail |
|---|---|
| **Method** | RGB channel decomposition + Butterworth bandpass filter (0.75–3.5 Hz) |
| **Resampling** | Uniform 30.0 Hz time-series resampling (Guardrail 1) |
| **Alert System** | `PhysiologicalRedFlagSentinel` → tachycardia, bradycardia, low SpO2 alerts |
| **Output** | Heart rate (BPM), confidence interval, physiological alerts |
| **File** | `intellidesk_backend/src/modules/diagnostics/vitals/rPPGSignalProcessor.ts` |

---

### 4.17 Prescription OCR Parser — Handwritten Rx Recognition

| Attribute | Detail |
|---|---|
| **Primary OCR** | Poppler `pdftotext -layout` for structured PDFs |
| **Secondary OCR** | Tesseract.js v7.0 (`eng.traineddata`, 5 MB, English) |
| **OCR Sanitization** | Guardrail 3: O→0 in numeric tokens, I/l→1 in frequency patterns |
| **Drug Normalization** | Fuzzy matcher against local `rxNormDataset.ts` (8,000+ drug entries) |
| **Output** | `ExtractedMedication[]` — drug name, dosage, frequency, route, RxNorm concept |
| **File** | `intellidesk_backend/src/modules/pharmacy/PrescriptionOCRParser.ts` |

---

### 4.18 Drug Interaction Engine & Allergy Sentinel

| Attribute | Detail |
|---|---|
| **Interaction DB** | `DrugInteractionEngine.ts` — 8,000+ drug pair interactions |
| **Allergy Check** | `AllergySafetySentinel.ts` — cross-checks patient allergy list |
| **RxSentinel** | `RxSentinelService.ts` — orchestrates both checks, severity scoring |
| **Severity Levels** | `CONTRAINDICATED`, `MAJOR`, `MODERATE`, `MINOR` |
| **Files** | `intellidesk_backend/src/modules/pharmacy/` |

---

### 4.19 Grad-CAM Visual Explainability

| Attribute | Detail |
|---|---|
| **Method** | Gradient backpropagation through final convolutional layer |
| **Output** | Per-pixel saliency heatmap overlay on original image |
| **Use Case** | "Our visual attention heatmap highlighted localized inflammation" |
| **File** | `intellidesk_backend/src/modules/diagnostics/explainability/gradCamGenerator.ts` |

---

### 4.20 HIPAA-Compliant Privacy Filter — Gemini 1.5 Flash

| Attribute | Detail |
|---|---|
| **Cloud Model** | `gemini-1.5-flash` |
| **Action** | Replaces specific diagnoses with generic phrasing ("a documented medical emergency") |
| **Validation** | Post-redaction scan — throws `PrivacyViolationError` if sensitive terms persist |
| **File** | `intellidesk_backend/src/services/gemini.ts` → `redactSensitiveInfo()` |

---

### 4.21 ML Retraining Worker — Continuous Learning Pipeline

| Attribute | Detail |
|---|---|
| **Trigger** | BullMQ scheduled job (or manual admin trigger) |
| **Data Source** | Resolved tickets from Supabase |
| **Models Updated** | DeepRank (5 epochs), Grant Optimizer (5 epochs) |
| **Persistence** | Updated weights saved back to `./models/` directory |
| **File** | `intellidesk_backend/src/workers/mlRetrainingWorker.ts` |

---

### Cloud vs Local Model Fallback Map

| Feature | Cloud (Primary) | Local Fallback |
|---|---|---|
| PFA Counselor Chat | (local-first for privacy) | Qwen1.5-0.5B ONNX → Qwen2.5-0.5B ONNX → Rogerian PFA engine |
| Clinical Chat | Gemini Flash Lite | Rogerian deterministic engine |
| Claim Intake Parsing | Gemini 2.0 Flash | Safe default triage object |
| Policy Adjudication | Gemini 1.5 Pro | Escalated (safe default) |
| Semantic Embeddings | Gemini Embedding-001 | Zero vector (768-d) |
| Clinical Image Vision | Qwen2.5-VL 72B (HF) | Clinical MobileNet-V3 (TFLite) |
| CDSS / Differential Dx | Qwen2.5-72B (HF) | ICD-11 Deterministic Engine |
| Cough Classification | HF Audio Inference | Local TFLite Cough Classifier |
| NLP Sentiment | DistilBERT ONNX (Xenova) | Keyword regex heuristics |
| DeepRank CSI | Local TF.js (trained weights) | CSI = 0.5 (neutral) |
| LSTM Attrition | Local TF.js (trained weights) | Risk = 0.0 (safe) |
| Anomaly Autoencoder | Local TF.js (trained weights) | Score = 0.0 (no anomaly) |
| Grant Optimizer | Local TF.js (MC Dropout) | min(requested, $200) |
| Fraud Sentinel | Local (SHA-256 + DB + Autoencoder) | Hash + velocity only |
| Privacy Redaction | Gemini 1.5 Flash | Manual review flag |

---

## 5. System Architecture

```
+-----------------------------------------------------------------------------+
|                    MedAccess AI -- Flutter Mobile Client                     |
|                                                                              |
|  +---------------------------+     +------------------------------------+    |
|  |      Patient Portal        |     |      Admin Clinical War Room       |    |
|  |  Claim Intake (PDF/img)   |     |  ESI Queue (DeepRank sorted)      |    |
|  |  PFA Chat (Qwen AI)       |     |  Health Fund Liquidity Panel      |    |
|  |  Copay Status Tracker     |     |  One-Tap Payout Modal             |    |
|  |  Pharmacy Hub             |     |  Clinical Diagnostics Review      |    |
|  |  Emergency Helpline Hub   |     |  HIPAA Audit PDF Export           |    |
|  |  rPPG Vitals Monitor      |     |  Knowledge Base (RAG Search)      |    |
|  +---------------------------+     +------------------------------------+    |
+-----------------------------------------------^------------------------------+
                                                |  REST + WebSocket (Socket.io)
+-----------------------------------------------v------------------------------+
|           MedAccess Backend API (Express 5 / TypeScript / ESM)               |
|  Auth + RBAC (JWT / Supabase)       Claim CRUD + ESI + Status Updates        |
|  Async Intake -> BullMQ Queue       Multi-Rail Payout Execution               |
|  PFA Counselor AI (Qwen/Gemini)     Clinical Admin Overrides + Telemetry      |
|  CDSS Differential Dx Routes        Pharmacy Safety Routes                    |
|  FHIR R4 Conversion                 HIPAA Audit PDF (PDFKit + SHA-256)        |
+----------+-------------------------------------------+------------------------+
           |                                           |
+----------v-----------------+         +---------------v--------------------+
|  BullMQ Workers (Redis)    |         |  Supabase PostgreSQL + pgvector    |
|  Intake Worker             |         |  institutions (multi-tenancy)      |
|    Poppler PDF OCR         |         |  profiles (RBAC / JWT)             |
|    Tesseract.js img        |         |  tickets / claims                  |
|    SHA-256 hashing         |         |  ticket_messages (PFA chat)        |
|    Fraud Sentinel          |         |  health_funds / vouchers           |
|    DeepRank CSI            |         |  patient_rosters                   |
|    LSTM Attrition          |         |  audit_logs (HIPAA trail)          |
|    Grant Optimizer         |         |  policies (vector(768) embeddings) |
|    Policy RAG (Gemini)     |         |  RLS enabled on all tables         |
|    Socket.io emit          |         +------------------------------------+
|  ML Retraining Worker      |
|  Notification Worker       |
|    Email (Nodemailer)      |
|    SMS (Twilio)            |
+----------------------------+
           |
+----------v-----------------------------------------------------------------+
|                          ML / AI Layer                                      |
|                                                                             |
|  +------------------+  +------------------+  +---------------------------+ |
|  |   Local TF.js     |  |  ONNX (Xenova)   |  |   Cloud APIs              | |
|  |  DeepRank DNN     |  |  Qwen1.5-0.5B    |  |  Gemini 2.0 Flash         | |
|  |  LSTM Attrition   |  |  Qwen2.5-0.5B    |  |  Gemini 1.5 Pro (CoT)    | |
|  |  Autoencoder      |  |  DistilBERT SST2 |  |  Gemini Flash Lite        | |
|  |  Grant Optimizer  |  +------------------+  |  Gemini Embedding-001     | |
|  |  Cough Classifier |                         |  Qwen2.5-VL 72B (HF)     | |
|  |  Fusion Model     |                         |  Qwen2.5-72B (HF CDSS)   | |
|  |  MobileNet-V3     |                         +---------------------------+ |
|  +------------------+                                                        |
+-----------------------------------------------------------------------------+
           |
+----------v-----------------------------------------+
|   External Services                                  |
|  RazorpayX (UPI/IMPS INR disbursement)             |
|  Stripe (USD international payout)                  |
|  Twilio (SMS for ESI-1 critical alerts)             |
|  Nodemailer / Resend (email dispatch)               |
|  Google Places API (nearest facility finder)        |
|  Firebase FCM (push notifications)                  |
+------------------------------------------------------+
```

### Claim Intake Pipeline (BullMQ — 10 Steps)

```
Job Received (claim_id, raw_message, media_url)
  Step 1: Receipt Parsing
          pdftotext → pdf-parse → Tesseract.js OCR fallback
          extractInvoiceTotal() with INR/USD currency detection
  Step 2: NLP Feature Extraction
          word_count, urgent_keyword_count (regex), sentiment_score (DistilBERT ONNX)
  Step 3: Fraud Sentinel (3-layer)
          SHA-256 receipt hash → duplicate detection
          7-day velocity check per patient_phone
          Autoencoder anomaly score (MSE threshold = 0.75)
  Step 4: DeepRank CSI Inference
          predict([word_count, urgent_kw, sentiment, hist_count]) → CSI in [0,1]
  Step 5: ESI Tier Assignment
          CSI >= 0.85 → ESI_1 | >= 0.60 → ESI_2 | >= 0.35 → ESI_3 | else ROUTINE
  Step 6: LSTM Attrition Risk
          predict(student_history) → dropout_risk_score in [0,1]
  Step 7: Grant Optimizer (MC Dropout)
          predictOptimalGrant(metrics) → recommended_amount ± confidence
  Step 8: Gemini Multimodal Intake (cloud)
          processMultimodalIntake(text, mediaUrl) → structured triage JSON
  Step 9: Policy Match (RAG)
          gemini-embedding-001 → vector search → hybrid_match_policies RPC
          evaluatePolicyMatch() (Gemini 1.5 Pro CoT) → Auto-Approved / Escalated / Denied
  Step 10: Supabase Update + Socket.io Broadcast
           ticket.status = 'Triage Active' + real-time push to admin dashboard
```

---

## 6. Folder Structure

```
intellidesk/
├── intellidesk_app/                     # Flutter Mobile Application
│   ├── lib/
│   │   ├── main.dart                    # App entry, Provider tree, route table
│   │   ├── models/
│   │   │   ├── claim.dart               # Medical claim (fromJson/toJson)
│   │   │   ├── claim_message.dart       # PFA chat turn entity
│   │   │   ├── health_fund.dart         # Welfare fund balance
│   │   │   └── emergency_helpline.dart  # Crisis hotline directory
│   │   ├── services/
│   │   │   ├── clinical_api_service.dart     # REST client
│   │   │   ├── socket_service.dart           # Socket.io room manager
│   │   │   └── offline_sync_manager.dart     # SharedPreferences fallback
│   │   ├── providers/                   # ViewModels (ChangeNotifier MVVM)
│   │   │   ├── auth_provider.dart       # Session, role, JWT
│   │   │   ├── claims_provider.dart     # Triage queue + ESI filter
│   │   │   ├── clinical_chat_provider.dart   # PFA conversation state
│   │   │   ├── war_room_provider.dart   # KPI telemetry
│   │   │   └── ticket_provider.dart     # Patient-side tracking
│   │   ├── screens/
│   │   │   ├── patient/
│   │   │   │   ├── claim_intake_screen.dart       # PDF/image upload
│   │   │   │   ├── clinical_chat_screen.dart      # PFA chat UI
│   │   │   │   ├── claim_status_screen.dart       # ESI badge + payout tracker
│   │   │   │   ├── emergency_hub_screen.dart      # Crisis hotlines
│   │   │   │   ├── health_records_screen.dart     # Medical history
│   │   │   │   ├── pharmacy_hub_screen.dart       # Prescription & Rx safety
│   │   │   │   └── patient_clinical_dashboard.dart
│   │   │   └── admin/
│   │   │       ├── admin_war_room_screen.dart           # Triage queue + payout
│   │   │       ├── admin_health_funds_screen.dart       # Fund management
│   │   │       ├── admin_knowledge_base_screen.dart     # Policy RAG search
│   │   │       ├── admin_clinical_diagnoses_screen.dart # AI diagnostic review
│   │   │       └── admin_main_screen.dart
│   │   └── theme/app_theme.dart        # Clinical design system, ESI color tokens
│   └── pubspec.yaml
│
├── intellidesk_backend/                 # Node.js Backend (Express 5 / TypeScript)
│   ├── src/
│   │   ├── server.ts                    # Express bootstrap + ML model init
│   │   ├── services/                    # Core ML & business service layer
│   │   │   ├── deepRankModel.ts         # DeepRank CSI Neural Network
│   │   │   ├── attritionModel.ts        # LSTM Dropout Risk
│   │   │   ├── anomalyModel.ts          # Autoencoder Fraud Detection
│   │   │   ├── grantOptimizerModel.ts   # MC Dropout Grant Predictor
│   │   │   ├── fraudSentinel.ts         # 3-layer Fraud Detection
│   │   │   ├── crisisCounselorService.ts    # Qwen ONNX + Rogerian PFA
│   │   │   ├── clinicalCounselorService.ts  # Gemini Flash Lite Chat
│   │   │   ├── gemini.ts                # All Gemini API integrations
│   │   │   ├── nlpPipeline.ts           # DistilBERT sentiment analysis
│   │   │   ├── receiptParser.ts         # PDF/OCR receipt extraction
│   │   │   ├── disbursementService.ts   # RazorpayX payouts
│   │   │   ├── payoutService.ts         # Stripe + voucher engine
│   │   │   ├── pdfReportService.ts      # HIPAA audit PDF (PDFKit)
│   │   │   ├── socketManager.ts         # Socket.io room management
│   │   │   └── voucherEngine.ts         # Campus voucher generation
│   │   ├── modules/
│   │   │   ├── cdss/                    # Clinical Decision Support System
│   │   │   │   ├── CDSSService.ts           # Main orchestrator
│   │   │   │   ├── DifferentialDiagnosisEngine.ts  # ICD-11 scoring
│   │   │   │   ├── ICD11ConceptStore.ts     # WHO ICD-11 knowledge base
│   │   │   │   ├── QwenInferenceService.ts  # Qwen2.5-72B cloud inference
│   │   │   │   └── TreatmentPathwayAdvisor.ts
│   │   │   ├── diagnostics/
│   │   │   │   ├── vision/
│   │   │   │   │   ├── CloudVisionClassifier.ts  # Qwen2.5-VL 72B
│   │   │   │   │   ├── clinicalMobileNet.ts      # Local MobileNet-V3
│   │   │   │   │   └── VisionDiagnosticService.ts
│   │   │   │   ├── audio/
│   │   │   │   │   ├── CoughClassifier.ts         # TFLite cough detection
│   │   │   │   │   ├── AudioFeatureExtractor.ts   # MFCC features (Meyda.js)
│   │   │   │   │   └── CloudAudioClassifier.ts    # HF Audio API
│   │   │   │   ├── fusion/
│   │   │   │   │   ├── MultimodalFusionModel.ts   # 168-d late-fusion DNN
│   │   │   │   │   ├── diseasePredictionModel.ts
│   │   │   │   │   └── vectorAssembler.ts
│   │   │   │   ├── explainability/
│   │   │   │   │   ├── gradCamGenerator.ts        # Grad-CAM heatmaps
│   │   │   │   │   ├── featureImportance.ts
│   │   │   │   │   └── uncertaintyEngine.ts
│   │   │   │   ├── vitals/
│   │   │   │   │   ├── rPPGSignalProcessor.ts     # Camera-based heart rate
│   │   │   │   │   ├── ButterworthFilter.ts
│   │   │   │   │   └── PhysiologicalRedFlagSentinel.ts
│   │   │   │   ├── fhir/
│   │   │   │   │   ├── FHIRConverterService.ts    # HL7 FHIR R4 export
│   │   │   │   │   └── ReferralLetterGenerator.ts
│   │   │   │   └── progression/
│   │   │   │       └── ScreeningDeltaAnalyzer.ts  # Longitudinal tracking
│   │   │   └── pharmacy/
│   │   │       ├── PrescriptionOCRParser.ts       # Handwritten Rx OCR
│   │   │       ├── DrugInteractionEngine.ts        # 8,000+ drug pairs
│   │   │       ├── AllergySafetySentinel.ts
│   │   │       ├── fuzzyMatcher.ts                # RxNorm fuzzy matching
│   │   │       └── rxNormDataset.ts               # Local drug database
│   │   ├── workers/
│   │   │   ├── intakeWorker.ts          # 10-step BullMQ claim pipeline
│   │   │   ├── mlRetrainingWorker.ts    # Continuous model fine-tuning
│   │   │   └── notificationWorker.ts    # Email + SMS dispatch
│   │   ├── controllers/
│   │   ├── routes/
│   │   ├── middleware/                  # Auth, RBAC, tenant scoping
│   │   ├── config/                      # Supabase client config
│   │   └── ml/                          # Training scripts
│   │       ├── deep_rank.ts
│   │       ├── lstm.ts
│   │       ├── autoencoder.ts
│   │       └── train_all.ts
│   ├── models/                          # Trained model weights (auto-generated)
│   │   ├── deep_rank/model.json
│   │   ├── lstm/model.json
│   │   ├── autoencoder/model.json
│   │   ├── grant_optimizer/model.json
│   │   ├── cough_classifier/model.json
│   │   └── multimodal_fusion/model.json
│   ├── eng.traineddata                  # Tesseract English model (5 MB)
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── package.json
│
├── models/cdss/                         # CDSS model artifacts
├── screenshots/                         # App screenshots + architecture diagrams
├── supabase_core_schema.sql             # Full PostgreSQL schema with RLS
├── supabase_setup.sql                   # Initial setup + extensions
├── train_cdss_model.py                  # Python CDSS training script
├── sample_policies/                     # Sample institutional policy PDFs
└── ARCHITECTURE.md                      # Detailed architecture reference
```

---

## 7. Technology Stack

### Frontend

| Category | Technology | Notes |
|---|---|---|
| **Framework** | Flutter (Dart) SDK ^3.10.7 | Cross-platform (Android, iOS, Web, Desktop) |
| **State Management** | Provider + ChangeNotifier | MVVM architecture |
| **HTTP Client** | `http` | REST API calls |
| **Real-Time** | `socket_io_client` | WebSocket rooms per institution |
| **On-Device ML** | `tflite_flutter` | Local TFLite model inference |
| **Charts** | `fl_chart` | ESI distribution, fund utilization |
| **Camera & Media** | `camera`, `image_picker`, `file_picker` | Claim photo + PDF upload |
| **Audio Recording** | `record` | Cough audio capture |
| **QR Code** | `qr_flutter` | Campus voucher display |
| **Geolocation** | `geolocator` | Nearest facility finder |
| **Notifications** | `flutter_local_notifications` | Push alerts for ESI-1 claims |
| **Offline Storage** | `shared_preferences` | Claim data caching |
| **Fonts** | `google_fonts` | Modern clinical typography |
| **URL Launch** | `url_launcher` | Crisis hotline tel: links |
| **Connectivity** | `connectivity_plus` | Network state detection |
| **Permissions** | `permission_handler` | Camera, microphone, storage |

### Backend

| Category | Technology | Notes |
|---|---|---|
| **Runtime** | Node.js (ESM modules) | — |
| **Framework** | Express 5 / TypeScript v7.0.2 | Strict mode |
| **Database** | Supabase PostgreSQL + pgvector | Row-Level Security, vector(768) |
| **DB Client** | `@supabase/supabase-js` v2 | Direct DB client |
| **Queue System** | BullMQ + Redis | Async claim processing pipeline |
| **Redis Client** | ioredis v6 | BullMQ job store |
| **Real-Time** | Socket.io v4 | Bi-directional WebSocket |
| **File Upload** | Multer v2 | PDF/image multipart upload |
| **PDF Parsing** | pdf-parse + Poppler pdftotext | Layout-preserving extraction |
| **OCR** | Tesseract.js v7 + eng.traineddata | 5MB English language model |
| **PDF Generation** | PDFKit | HIPAA audit reports |
| **Image Processing** | sharp | Clinical image preprocessing |
| **Email** | Nodemailer + Resend | Claim status notifications |
| **SMS** | Twilio v6 | Critical ESI-1 SMS alerts |
| **Validation** | Zod v4 | API request/response schema |
| **Auth** | Supabase Auth + JWT | RBAC (STUDENT / ADMIN / AUDITOR) |
| **Containerization** | Docker + docker-compose | Redis + backend services |
| **ORM Tooling** | Prisma v7 | Schema migrations |

### ML & AI

| Model / Framework | Type | Role |
|---|---|---|
| **TensorFlow.js + tfjs-node** v4.22 | Local Neural Network | DeepRank, LSTM, Autoencoder, Grant Optimizer, Cough Classifier, Multimodal Fusion |
| **@xenova/transformers** v2.17 | ONNX Runtime (Node.js) | DistilBERT sentiment, Qwen1.5/2.5 PFA chat |
| **Qwen1.5-0.5B-Chat** | Quantized ONNX LLM | Primary PFA counselor (on-device CPU) |
| **Qwen2.5-0.5B-Instruct** | Quantized ONNX LLM | Secondary PFA counselor fallback |
| **Qwen/Qwen2.5-VL-72B-Instruct** | Cloud VLM (Hugging Face Router) | Clinical image classification |
| **Qwen/Qwen2.5-72B-Instruct** | Cloud LLM (Hugging Face Router) | CDSS differential diagnosis |
| **DistilBERT SST-2** | ONNX Transformer | Clinical NLP sentiment analysis |
| **Gemini 2.0 Flash** | Cloud LLM (Google) | Multimodal claim intake parsing |
| **Gemini 2.5 Flash** | Cloud LLM (Google) | Multimodal voice/image input |
| **Gemini 1.5 Pro** | Cloud LLM (Google) | Policy adjudication (Chain-of-Thought) |
| **Gemini Flash Lite** | Cloud LLM (Google) | Real-time clinical chat (50 tokens/call) |
| **Gemini Embedding-001** | Cloud Embeddings (Google) | 768-d semantic policy embeddings |
| **Clinical MobileNet-V3** | Local TFLite | Vision fallback (10-class clinical) |
| **Meyda.js** | Audio DSP Library | MFCC feature extraction for cough analysis |
| **tflite_flutter** | Flutter TFLite Plugin | On-device mobile inference |
| **Grad-CAM** | XAI Method | Visual saliency heatmaps for clinical transparency |
| **Monte Carlo Dropout** | Uncertainty Quantification | Epistemic variance in predictions |
| **pgvector** | PostgreSQL Extension | Semantic policy RAG vector search |
| **Butterworth Filter** | DSP Algorithm | rPPG signal bandpass filtering (0.75–3.5 Hz) |

### Payment & External APIs

| Service | Purpose |
|---|---|
| **RazorpayX** | UPI + IMPS INR disbursement |
| **Stripe** | USD international payout |
| **Twilio** | SMS for ESI-1 critical alerts |
| **Google Places API** | Nearest emergency facility lookup |
| **Firebase FCM** | Push notification delivery |
| **Hugging Face Inference Router** | Cloud Qwen model hosting |
| **Supabase** | Managed PostgreSQL + Auth + Storage + pgvector |

### DevOps & Infrastructure

| Tool | Purpose |
|---|---|
| Docker + docker-compose | Containerized backend + Redis |
| Redis 7 Alpine | BullMQ job queue store |
| Prisma v7 | Database schema tooling |
| tsx | TypeScript execution (dev) |
| Nodemon | Hot-reload dev server |

---

## 8. API Reference

### Auth
| Method | Route | Description |
|---|---|---|
| `POST` | `/api/v1/auth/signup` | Register student or admin |
| `POST` | `/api/v1/auth/login` | Authenticate, receive JWT |
| `GET` | `/api/v1/auth/profile` | Get authenticated user profile |

### Claim Intake
| Method | Route | Description |
|---|---|---|
| `POST` | `/api/v1/intake/web` | Submit new claim (multipart: text + PDF/image) → BullMQ |
| `GET` | `/api/v1/claims` | List claims (filter: ESI, status, keyword) |
| `GET` | `/api/v1/claims/:id` | Full claim + all ML scores + triage breakdown |

### Clinical Admin (ADMIN role)
| Method | Route | Description |
|---|---|---|
| `POST` | `/api/v1/claims/:id/disburse` | Execute RazorpayX / Stripe payout |
| `POST` | `/api/v1/claims/:id/override` | ESI or fraud flag override with notes |
| `GET` | `/api/v1/admin/telemetry` | KPI dashboard: fund liquidity, ESI distribution |
| `GET` | `/api/v1/admin/reports` | Download HIPAA compliance audit PDF |
| `GET` | `/api/v1/admin/knowledge` | Institutional policy knowledge base (RAG) |

### PFA Chat
| Method | Route | Description |
|---|---|---|
| `POST` | `/api/v1/chat` | Send message → Qwen PFA AI reply |
| `GET` | `/api/v1/chat/:ticketId/messages` | Full PFA chat history for a claim |

### Clinical Diagnostics
| Method | Route | Description |
|---|---|---|
| `POST` | `/api/v1/diagnostics/vision` | Upload clinical image → Qwen2.5-VL / MobileNet |
| `POST` | `/api/v1/diagnostics/audio` | Audio recording → cough classification |
| `POST` | `/api/v1/diagnostics/vitals` | rPPG frame sequence → heart rate analysis |
| `POST` | `/api/v1/cdss/evaluate` | Symptom payload → ICD-11 differential diagnosis |

### Pharmacy
| Method | Route | Description |
|---|---|---|
| `POST` | `/api/v1/pharmacy/parse` | Prescription → OCR + drug extraction + RxNorm |
| `POST` | `/api/v1/pharmacy/interactions` | Check drug-drug interaction for a medication list |

### Health
| Method | Route | Description |
|---|---|---|
| `GET` | `/health` | Service status + DB + all ML model load status |

---

## 9. Database Schema

All tables have **Row-Level Security (RLS)** enabled.

### `institutions` — Multi-Tenancy Root
| Column | Type | Notes |
|---|---|---|
| `id` | TEXT (PK) | Slug e.g. `campus-health-001` |
| `name` | TEXT | Display name |
| `domain` | TEXT | Email domain whitelist |
| `currency` | TEXT | `INR` or `USD` |

### `profiles` — Auth & RBAC
| Column | Type | Notes |
|---|---|---|
| `id` | UUID (PK) | References `auth.users.id` |
| `role` | TEXT | `STUDENT` or `ADMIN` or `AUDITOR` |
| `institution_id` | TEXT (FK) | Tenant scoping |

### `tickets` — Core Clinical Claim Record
| Column | Type | Notes |
|---|---|---|
| `urgency_level` | TEXT | ESI level assigned by DeepRank |
| `crisis_severity_index` | NUMERIC (0-1) | DeepRank output |
| `dropout_risk_score` | NUMERIC (0-1) | LSTM Attrition output |
| `recommended_grant_amount` | NUMERIC | Grant Optimizer output |
| `fraud_risk_score` | NUMERIC (0-1) | Fraud Sentinel score |
| `receipt_image_hash` | TEXT | SHA-256 for deduplication |
| `anomaly_reconstruction_score` | NUMERIC | Autoencoder MSE |
| `embedding` | vector(768) | Gemini Embedding-001 for RAG |
| `payout_method` | TEXT | UPI / BANK / VOUCHER |

### `ticket_messages` — PFA Chat History
| Column | Type | Notes |
|---|---|---|
| `sender` | TEXT | STUDENT or COUNSELOR_AI or HUMAN_ADMIN |
| `is_crisis_response` | BOOLEAN | True if self-harm keywords detected |
| `suggested_resources` | JSONB | Emergency hotline cards array |

### `audit_logs` — HIPAA Audit Trail
| Column | Type | Notes |
|---|---|---|
| `action_type` | TEXT | DISBURSEMENT, ESI_OVERRIDE, FRAUD_FLAG |
| `actor_type` | TEXT | SYSTEM / ADMIN / AI |
| `details` | JSONB | Full structured audit payload |

---

## 10. Background Workers

### Intake Worker (`intakeWorker.ts`) — `clinical-intake-queue`
Primary 10-step ML processing pipeline executed asynchronously for every submitted claim (see Section 5 diagram).

### ML Retraining Worker (`mlRetrainingWorker.ts`)
- Fetches resolved tickets from Supabase as labeled training data
- Fine-tunes DeepRank (5 epochs) and Grant Optimizer (5 epochs)
- Saves updated weights to `./models/` — enables continuous learning from real outcomes

### Notification Worker (`notificationWorker.ts`) — `notification-queue`
- Email via Nodemailer + Resend for claim status changes
- SMS via Twilio for critical ESI-1 alerts
- Queued asynchronously — does not block claim processing

---

## 11. Security Architecture

```
Request → CORS → JWT Middleware (requireAuth)
                        |
              requireRole(['ADMIN']) -- blocks non-admin routes
                        |
              tenantScopeMiddleware -- injects institution_id from JWT
                        |
              Supabase RLS -- enforces data isolation at the database level
```

| Feature | Implementation |
|---|---|
| **HIPAA Audit Trail** | Every disbursement, override, fraud decision in `audit_logs` with full JSONB payload |
| **Receipt Integrity** | SHA-256 hash stored at intake time, checked on every new submission |
| **Tamper-Evident PDF** | SHA-256 checksum of report content printed on every HIPAA audit PDF |
| **FERPA Compliance** | AI-powered diagnosis redaction (Gemini 1.5 Flash) before professor email dispatch |
| **Life-Safety Bypass** | Crisis claims exempt from velocity/threshold fraud checks |
| **RLS Isolation** | Every DB table has per-institution Row-Level Security policies |

---

## 12. Deployment

### Docker Compose
```yaml
services:
  backend:
    build: ./intellidesk_backend
    ports: ["3000:3000"]
    environment:
      - SUPABASE_URL
      - SUPABASE_SERVICE_ROLE_KEY
      - GEMINI_API_KEY
      - HF_TOKEN
      - REDIS_URL
      - RAZORPAY_KEY_ID
      - RAZORPAY_KEY_SECRET
    depends_on: [redis]
  redis:
    image: redis:7-alpine
    ports: ["6379:6379"]
```

### ML Model Training (One-Time Setup)
```bash
cd intellidesk_backend
npm run train:ml   # Train DeepRank, LSTM, Autoencoder, Grant Optimizer, Cough, Fusion
npm run seed:all   # Seed institutional policies, funds, and audit logs
```

### Development
```bash
cd intellidesk_backend && npm install && npm run dev   # Backend on :3000
cd intellidesk_app && flutter pub get && flutter run   # Flutter App
```

---

## 13. Environment Variables

| Variable | Service | Description |
|---|---|---|
| `SUPABASE_URL` | Supabase | Project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase | Backend service role key (bypasses RLS) |
| `SUPABASE_ANON_KEY` | Supabase | Flutter client anon key |
| `GEMINI_API_KEY` | Google Gemini | Gemini 2.0 Flash / 1.5 Pro / Embedding-001 |
| `HF_TOKEN` | Hugging Face | Qwen2.5-VL 72B vision + Qwen2.5-72B CDSS |
| `REDIS_URL` | Redis | BullMQ connection string |
| `RAZORPAY_KEY_ID` | RazorpayX | INR UPI / IMPS payout key |
| `RAZORPAY_KEY_SECRET` | RazorpayX | RazorpayX secret |
| `RAZORPAYX_ACCOUNT_NUMBER` | RazorpayX | Fund account number |
| `STRIPE_SECRET_KEY` | Stripe | USD international payout |
| `TWILIO_ACCOUNT_SID` | Twilio | SMS account SID |
| `TWILIO_AUTH_TOKEN` | Twilio | SMS auth token |
| `TWILIO_PHONE_NUMBER` | Twilio | Sender phone number |
| `GOOGLE_PLACES_API_KEY` | Google Places | Nearest clinic/hospital lookup |
| `FIREBASE_PROJECT_ID` | Firebase | FCM push notifications |
| `FIREBASE_CLIENT_EMAIL` | Firebase | Service account email |
| `FIREBASE_PRIVATE_KEY` | Firebase | Service account private key |
| `JWT_SECRET` | Backend | JWT signing secret |
| `PORT` | Backend | HTTP port (default: 3000) |

---

## 14. Getting Started

### Prerequisites
- Node.js 20+ with npm
- Flutter SDK 3.10+
- Redis 7 (or Docker)
- Supabase project (free tier sufficient)
- Gemini API key (Google AI Studio — free tier available)
- Hugging Face token (free tier — for cloud vision/CDSS features)

### Quick Start
```bash
git clone <repo-url> && cd intellidesk

# Backend setup
cd intellidesk_backend
cp .env.example .env
# Fill in: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GEMINI_API_KEY, REDIS_URL
npm install

# Database migrations
# Execute supabase_core_schema.sql in your Supabase SQL editor

# Train local ML models
npm run train:ml
npm run seed:all

# Start backend
npm run dev

# Flutter App (new terminal)
cd ../intellidesk_app
flutter pub get && flutter run
```

> **Note:** Local ONNX models (Qwen1.5-0.5B-Chat, DistilBERT) are downloaded automatically on first run via `@xenova/transformers`. Internet required on first launch only.

---

## WebSocket Events

| Event | Direction | Payload |
|---|---|---|
| `join-institution` | Client → Server | `{ institutionId }` |
| `ticket-created` | Server → Client | Full ticket object |
| `ticket-updated` | Server → Client | `{ ticketId, status, esiLevel, csi }` |
| `payout-completed` | Server → Client | `{ ticketId, txnRef, amount }` |
| `fraud-flagged` | Server → Client | `{ ticketId, flagReasons }` |

---

*Built with patience, perseverance and dedication.*
