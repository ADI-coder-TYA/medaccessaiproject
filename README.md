# 🏥 MedAccess AI

> **AI-Powered Multimodal Clinical Diagnostics, CDSS Triage & Emergency Health Platform** — on-device computer vision, WHO ICD-11 clinical decision support, acoustic respiratory screening, contactless rPPG vitals, pharmacy safety intelligence, psychological first aid, and emergency medical welfare.

---

## 📑 Table of Contents

1. [What is MedAccessAI?](#1-what-is-medaccessai)
2. [Real-World Clinical Scenarios](#2-real-world-clinical-scenarios)
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

**MedAccess AI** is a full-stack, AI-first clinical diagnostic and medical triage platform engineered for campus health centers and university populations. It accelerates patient care by placing hospital-grade diagnostic intelligence directly in students' and clinicians' hands — combining multimodal computer vision, WHO ICD-11 clinical decision support, acoustic cough analysis, contactless camera vitals, and pharmacy safety with an integrated emergency welfare relief rail.

| Role | Portal | Core Clinical Workflow |
|---|---|---|
| **Patient / Student** | Mobile (Flutter) | Submit clinical images/audio/vitals → receive differential AI assessment → chat with PFA counselor → access emergency copay relief |
| **Clinical Admin / Triage Officer** | Mobile (Flutter) | Review AI diagnostic findings & Grad-CAM heatmaps → triage ESI emergency queue → verify ICD-11 differential pathways → disburse copay relief |

### Core Clinical Principles

- **Diagnostic Rigor & Clinical Decision Support (CDSS)** — powered by a WHO ICD-11 concept graph with temperature-scaled logit scoring, calibrated differential diagnosis probabilities, and HL7 FHIR R4 Bundle exports.
- **Multimodal Medical Sensing** — ingests visual (dermatology, ocular, wounds), acoustic (16-d MFCC respiratory audio), physiological (contactless rPPG video vitals), and pharmacological signals into a unified late-fusion neural network.
- **AI-First, Human-in-the-Loop** — every ML prediction serves as a clinical decision-support tool. Clinicians retain full autonomy with documented justification for all diagnostic and ESI triage overrides.
- **Explainability & Transparency** — Grad-CAM visual attention overlays generate heatmaps on clinical images, ensuring clinicians see exactly what regions prompted the AI classification.
- **Offline-Resilient Edge Fallbacks** — every cloud diagnostic model (Qwen2.5-VL 72B, Qwen2.5-72B CDSS) pairs with a local on-device or deterministic fallback (Clinical MobileNet-V3, TFLite Cough Classifier, ICD-11 logit engine, local Qwen ONNX PFA chat), ensuring zero clinical downtime.
- **Patient Privacy & Safety Safeguards** — immutable clinical activity logs, automated PHI redaction via Gemini 1.5 Flash, FERPA-compliant communications, and physiological red-flag triggers for emergent vitals.

---

## 2. Real-World Clinical Scenarios

| Clinical Scenario | MedAccess AI Diagnostic & Care Workflow |
|---|---|
| **Dermatological Rash or Lesion Evaluation** | Patient photographs skin rash → Qwen2.5-VL 72B vision model classifies lesion type, severity, and anatomical site → local MobileNet-V3 fallback ensures edge resilience → Grad-CAM generates saliency heatmap highlighting localized inflammation. |
| **Complex Symptom Presentation & Differential Diagnosis** | Patient inputs multi-system symptoms → WHO ICD-11 concept store evaluates clinical priors → Qwen2.5-72B CDSS engine outputs differential diagnoses, urgency tiers, and evidence-based care pathways → exports HL7 FHIR R4 DiagnosticReport. |
| **Acoustic Cough & Respiratory Screening** | Patient records 5-second cough sample → Meyda.js DSP extracts 16-d MFCC acoustic vector → on-device CoughClassifier NN identifies wet, dry, or whooping patterns → physiological sentinel flags wheeze anomalies. |
| **Contactless Vitals Monitoring via Front Camera** | Student holds smartphone camera to face → rPPG signal processor decomposes green/RGB channel absorption at 30 Hz → Butterworth bandpass filter (0.75–3.5 Hz) isolates cardiac pulse wave → estimates HR (BPM) and SpO2 with bradycardia/tachycardia red-flag alerts. |
| **Prescription Parsing & Drug Interaction Safety** | Student uploads handwritten prescription → Poppler/Tesseract OCR extracts text with character error correction → fuzzy RxNorm matcher maps active ingredients → DrugInteractionEngine cross-checks 8,000+ contraindication pairs and patient allergy profile. |
| **Acute Mental Health & Crisis Intervention** | Student expresses acute distress or self-harm ideation → Regex and DistilBERT NLP detect critical crisis markers → local Qwen ONNX model delivers empathetic Psychological First Aid (PFA) → automatically injects one-tap 24/7 crisis hotline cards. |
| **Emergency Copay & Medical Welfare Relief** | When an acute clinical condition requires hospital care → DeepRank assigns ESI triage level (1–5) based on severity → Grant Optimizer suggests emergency copay relief with Bayesian uncertainty bounds → clinical admin disburses emergency funds via UPI or Stripe. |
| **Longitudinal Patient Health Risk Tracking** | Student presents repeated clinical encounters over the semester → Temporal Attrition LSTM analyzes multi-encounter trajectories → flags compounding academic/health burnout risk for proactive outreach. |

---

## 3. Feature Overview

### 🩺 Clinical Diagnostics & Vision Suite
- **Dermatology & Lesion Vision AI** — Qwen2.5-VL 72B multimodal vision classifier for rashes, burns, wounds, ocular redness, and oral lesions with automated severity grading.
- **Local Clinical MobileNet-V3** — on-device quantized TFLite classifier acting as a zero-latency, offline fallback for visual triage.
- **Grad-CAM Saliency Heatmaps** — gradient-weighted class activation mapping superimposed on clinical images to visualize areas of pathological concern.
- **Longitudinal Screening Delta Analyzer** — tracks visual progression or healing of skin lesions and burns across follow-up consultations.

### 🔬 Clinical Decision Support System (CDSS)
- **WHO ICD-11 Knowledge Graph** — curated concept store with clinical condition priors, symptom linkages, and evidence-based guideline references.
- **Differential Diagnosis Engine** — Qwen2.5-72B inference combined with temperature-scaled logit scoring ($T=1.25$) and $[-20, 20]$ logit clipping to produce calibrated probabilities for top differential candidates.
- **Subjective Clinical Notes Synthesis** — deeply scrutinizes free-text patient narratives, duration, triggers, and clinician observations within the Qwen2.5 prompt to refine differential diagnostic reasoning.
- **Urgency Classification** — categorizes presentations into `ROUTINE`, `PROMPT_EVALUATION`, and `IMMEDIATE_EMERGENCY`.
- **HL7 FHIR R4 Bundle Export** — transforms diagnostic encounters, observations, and recommendations into standardized clinical FHIR JSON bundles.

### 🫁 Acoustic Respiratory Diagnostics
- **Meyda MFCC DSP Pipeline** — extracts 16-dimensional Mel-Frequency Cepstral Coefficients from raw audio streams.
- **On-Device Cough Classifier** — multi-layer neural network classifying cough audio into 4 distinct clinical categories: dry, wet/productive, whooping, or normal.
- **Acoustic Red-Flag Sentinel** — triggers immediate clinical escalation upon detecting stridor, wheezing, or whoop signatures.

### 💓 Contactless rPPG Camera Vitals & Dual-Channel DSP
- **Dual-Channel Adaptive Optical Selection** — dynamically evaluates both Green (contactless facial capillary absorption) and Red (contact fingertip photoplethysmography) channels via Normalized Power Spectral Density (PSD) to choose the optical carrier with highest pulsatile SNR.
- **Butterworth Bandpass Filtering** — 4th-order bandpass filter ($0.75–3.5\text{ Hz}$, corresponding to 45–210 BPM) isolating cardiac pulsatile frequencies.
- **Harmonic Peak Tracking & SNR** — sums fundamental cardiac peak ($\pm 0.22\text{ Hz}$) and first harmonic ($\pm 0.22\text{ Hz}$) against the spectral noise floor to compute linear SNR and SNR in dB.
- **Physiological Red-Flag Sentinel** — automated boundary monitoring detecting acute tachycardia ($>110\text{ BPM}$), bradycardia ($<50\text{ BPM}$), and hypoxia indicators.

### 🚑 Emergency Medical Facilities & Dynamic Capability Deduction
- **Real-Time Geolocation Facility Discovery** — searches surrounding emergency departments, trauma centers, urgent cares, and student health clinics.
- **Dynamic Clinical Capability Deduction** — dynamically evaluates patient diagnostic findings and maps them against certified facility capabilities (e.g. Burn Care Unit, Comprehensive Stroke Center, Level 1 Trauma, 24/7 Acute Psychiatric Crisis, Pediatric ER, Advanced Ophthalmic Care).
- **Direct Dispatch & Calling Rail** — integrates one-tap emergency calling, travel time estimation, distance calculation, and native navigation dispatch.

### 📄 Automated Clinical Referral Letter (PDF) & LOINC Vitals
- **PDFKit Medical Referral Generator** — programmatically compiles a standardized, hospital-ready clinical referral letter for downstream attending physicians.
- **Standardized LOINC Medical Observation Coding** — formats vital signs with international LOINC identifiers: Body Temperature (8310-5), Heart Rate (8867-4), Blood Pressure (8480-6 / 8462-4), Oxygen Saturation SpO2 (2708-6), and Pain Severity Score (72514-3).
- **Bayesian Risk & Evidence Confidence Intervals** — embeds multimodal risk score with 95% confidence intervals and epistemic standard deviation.
- **Dynamic Clinical Directives & Sign-off** — generates urgent stabilization directives and clinician sign-off block with medical license verification.
- **Native Flutter Download & Share Sheet** — direct PDF download, share sheet fallback, and native file saving with visual confirmation.

### 💊 Pharmacy Safety & RxSentinel
- **Handwritten Prescription Open-ML OCR** — hybrid architecture combining open-weight Vision-Language Models (`GLM-4.6V-Flash`, `Qwen2.5-VL-72B`, `DeepSeek-V4-Flash-Vision` via Hugging Face router) with localized Poppler `pdftotext` and Tesseract.js sanitization fallback (correcting clinical token swaps like O/0, I/1).
- **RxNorm Semantic Normalizer** — fuzzy string matcher resolving brand names and colloquial spellings to standardized RxNorm Concept Unique Identifiers (RxCUIs).
- **8,000+ Drug-Drug Interaction Matrix** — instant cross-referencing of multi-drug regimens classifying interactions as `CONTRAINDICATED`, `MAJOR`, `MODERATE`, or `MINOR`.
- **Dynamic Evidence-Based Alternative Prescribing** — integrated with the **NIH National Library of Medicine (NLM) RxNav & RxClass REST API** to resolve active RxCUIs and anatomical therapeutic classes (ATC). When allergy contraindications occur, dynamically fetches and recommends safe, non-cross-reactive alternatives with clinical rationale.
- **Allergy Safety Sentinel** — cross-checks newly prescribed substances against patient allergy records with allergen cross-reactivity tree analysis to prevent anaphylaxis.

### 🧠 Psychological First Aid (PFA), Clinical Chatbots & Patient-RAG
- **Clinical Patient-RAG Architecture (`PatientClinicalRagService`)** — retrieves and synthesizes multi-entity clinical dossiers from Supabase (patient demographics & canonical roster mapping, active medications, recorded allergies, recent screening vitals with BP/Temp/RR, CDSS evaluations with first-line pathways, and emergency copay claims) to supply deep, clinically-tailored context to chatbots without privacy compromise.
- **Personalized Mental Health Counselor (`/api/v1/chat/mental-health`)** — combines Gemini Flash with Patient-RAG retrieval, empathetically addressing patient emotional distress while taking active medications, allergies, and recent screening vitals into account.
- **Emergency Copay & Medical Claim Assistant (`/api/v1/claims/:id/messages`)** — injects live claim amounts, copay relief allocations, and clinical category into multi-turn dialogue with token throttling and memory caching.
- **Local ONNX Qwen Chat Engine** — runs `Xenova/Qwen1.5-0.5B-Chat` completely on-device without network transmission, ensuring absolute privacy for sensitive mental health conversations.
- **Life-Safety & Crisis Regex** — instant pattern matching detecting suicide and self-harm keywords, overriding conversation flow to present immediate 24/7 hotlines (Tele-MANAS 14416, 988 Lifeline, Vandrevala).
- **Rogerian PFA Fallback** — deterministic, non-judgmental reflective listening engine providing continuous availability under zero-memory constraints.

### 📱 Patient Clinical Dashboard & Emergency Medical Passport
- **Emergency Medical Passport** — interactive patient health passport card displaying verified allergen profile (or NKDA), active medication counts, emergency contact telephone, and immediate care plan status.
- **Diagnostic Report & CDSS Review Launchpad** — direct navigation from health screening history into the clinical diagnostic report and CDSS decision drawer with full assessment overrides.
- **Longitudinal Trend Tracking** — historical health screening timeline tracking risk levels, vital sign changes, and clinical recommendations across consultations.

### 📋 Clinical ESI Triage & Emergency Copay Support
- **DeepRank Emergency Severity Index (ESI)** — assigns Crisis Severity Index (CSI $\in [0, 1]$) and triage tiers (ESI-1 Resuscitation down to ESI-5 Routine).
- **Clinical Admin War Room** — real-time WebSocket dashboard enabling clinicians to review diagnostic telemetry, inspect Grad-CAM heatmaps, and override AI recommendations.
- **Emergency Copay Grant Optimizer** — Monte Carlo Dropout neural regression assessing fund allocations for urgent prescriptions and emergency room copays.
- **Fraud Sentinel** — 3-layer claim integrity check (SHA-256 receipt hashing, velocity monitoring, Autoencoder anomaly scoring) protecting student health funds.
- **Multi-Rail Instant Payout** — disburses approved emergency health copays via UPI (RazorpayX), bank transfer, Stripe, or campus clinic vouchers.

---

## 4. 🤖 ML & AI Systems — Deep Dive

MedAccess AI implements **21 distinct ML and AI components**. The core of the system is anchored around clinical diagnostic intelligence, with integrated triage and welfare rails.

---

### 4.1 Cloud Vision Classifier — Qwen2.5-VL 72B (Dermatology & Ocular)

**Clinical Role:** Evaluates patient-submitted imagery (rashes, skin lesions, ocular redness, burns, and wounds) using a 72-billion parameter Vision-Language Model.

| Attribute | Detail |
|---|---|
| **Cloud Model** | `Qwen/Qwen2.5-VL-72B-Instruct` via Hugging Face Inference Router |
| **Local Fallback** | Clinical MobileNet-V3 (quantized TFLite running on-device) |
| **Preprocessing** | `sharp` image pipeline (resizing, normalization, orientation fix) |
| **Clinical Schema** | `condition`, `anatomicalSite`, `severity`, `confidence`, `findings[]`, `differentialDiagnoses[]`, `recommendedAction`, `isEmergencyAlert` |
| **Emergency Trigger** | `severity: critical` immediately generates an ESI-1 notification |
| **File** | `intellidesk_backend/src/modules/diagnostics/vision/CloudVisionClassifier.ts` |

```
Cloud:    Clinical Photo → sharp → Qwen2.5-VL 72B → Structured Clinical JSON
Fallback: Clinical Photo → MobileNet-V3 TFLite → 10-Class Top-K Probabilities
```

---

### 4.2 CDSS — Clinical Decision Support System (WHO ICD-11 + Qwen2.5-72B)

**Clinical Role:** Formulates evidence-based differential diagnoses, clinical urgency categorization, and treatment pathway guidance mapped directly to the WHO ICD-11 catalog.

| Attribute | Detail |
|---|---|
| **Primary Cloud Model** | `Qwen/Qwen2.5-72B-Instruct` via Hugging Face Inference Router |
| **Subjective History Synthesis** | Deep clinical narrative scrutiny ingesting patient-reported progression, prior exposures, triggers, and clinician notes directly into the Qwen LLM prompt |
| **Local Engine Fallback** | `DifferentialDiagnosisEngine` — deterministic ICD-11 probability calculator |
| **Knowledge Base** | `ICD11ConceptStore` — graph of ICD-11 codes, priors, and cardinal symptoms |
| **Logit Calibration** | Temperature-scaled logit scoring ($T=1.25$) with $[-20, 20]$ boundary clipping |
| **Serialization Resilience** | Case-invariant DTO schema supporting both camelCase and snake_case representations across cloud and offline records |
| **Urgency Grades** | `ROUTINE`, `PROMPT_EVALUATION`, `IMMEDIATE_EMERGENCY` |
| **Institutional Governance** | `CDSSDecisionDrawer` Flutter interface routes findings to assigned Medical Centers; records licensed clinician approvals, cryptographic signatures, and clinical overrides |
| **Interoperability** | `FHIRConverterService` outputs HL7 FHIR R4 `DiagnosticReport` Bundles |
| **Files** | `intellidesk_backend/src/modules/cdss/CDSSService.ts`, `QwenInferenceService.ts`, `intellidesk_app/lib/modules/cdss/ui/cdss_decision_drawer.dart` |

---

### 4.3 Multimodal Clinical Fusion Model — Late-Fusion Deep Neural Network

**Clinical Role:** Synthesizes multimodal patient streams (visual embeddings, structured symptoms, demographic factors) into a calibrated clinical risk index and care tier.

| Attribute | Detail |
|---|---|
| **Architecture** | Multi-head Late-Fusion DNN (TensorFlow.js Functional API) |
| **Input Representation** | 168-dimensional concatenated feature vector: 128 visual + 32 clinical symptoms + 8 demographics |
| **Head 1 (Continuous)** | Dense(1, sigmoid) → Continuous Clinical Risk Score $\in [0, 1]$ |
| **Head 2 (Categorical)** | Dense(3, softmax) → [Low Risk, Moderate Need, Critical Referral] |
| **Uncertainty Bounds** | Monte Carlo Dropout (active inference) yields epistemic standard deviation & 95% CI |
| **Hidden Layers** | Dense(128, ReLU) → BatchNorm → Dropout(0.30) → Dense(64, ReLU) → Dropout(0.25) |
| **File** | `intellidesk_backend/src/modules/diagnostics/fusion/MultimodalFusionModel.ts` |

---

### 4.4 Grad-CAM Visual Explainability Engine

**Clinical Role:** Generates gradient-weighted class activation heatmaps overlaying clinical images to highlight specific regions driving model predictions, building clinician trust.

| Attribute | Detail |
|---|---|
| **Method** | Saliency backpropagation through final convolutional feature maps |
| **Output** | 2D colorized heatmap superimposed on the original medical photograph |
| **Clinical Utility** | Allows physicians to inspect whether classification focused on genuine pathology or background artifacts |
| **File** | `intellidesk_backend/src/modules/diagnostics/explainability/gradCamGenerator.ts` |

---

### 4.5 Cough Classifier — On-Device Acoustic Respiratory ML

**Clinical Role:** Passive screening and characterization of respiratory illness via patient cough audio samples.

| Attribute | Detail |
|---|---|
| **Architecture** | Dense(48, BN, Dropout) → Dense(24, Dropout) → Dense(4, Softmax) + L2 Regularization |
| **Feature Extraction** | 16-dimensional MFCC acoustic vector extracted via Meyda.js DSP |
| **Output Classes** | `dry cough`, `wet/productive cough`, `whooping cough`, `normal/non-pathological` |
| **Acoustic Red Flag** | High-frequency wheeze detection triggers automatic respiratory alert |
| **Cloud Alternative** | `CloudAudioClassifier` Hugging Face audio inference endpoint |
| **File** | `intellidesk_backend/src/modules/diagnostics/audio/CoughClassifier.ts` |

---

### 4.6 rPPG Vital Sign Processor — Dual-Channel Contactless & Contact DSP

**Clinical Role:** Non-invasive physiological monitoring extracting heart rate (BPM), respiratory rate, SpO2, and HRV RMSSD from ordinary camera streams using adaptive optical channel selection.

| Attribute | Detail |
|---|---|
| **Adaptive Channel Selection** | Simultaneously evaluates **Green Channel** (contactless facial capillary light absorption) and **Red Channel** (contact fingertip photoplethysmography), dynamically selecting the optimal optical carrier with highest pulsatile SNR |
| **Temporal Resampling** | Uniform 30.0 Hz time-series interpolation across variable device camera frame rates |
| **DSP Filtering** | 4th-order Butterworth bandpass filter ($0.75–3.5\text{ Hz}$, corresponding to $45–210\text{ BPM}$) isolating cardiac pulse waves |
| **FFT Spectral Estimation** | 2048-point power spectrum with parabolic peak interpolation for sub-bin frequency accuracy |
| **Harmonic Peak Tracking & SNR** | Integrates fundamental pulse power ($f_0 \pm 0.22\text{ Hz}$) and first harmonic power ($2f_0 \pm 0.22\text{ Hz}$) relative to noise floor via Normalized Power Spectral Density (PSD) |
| **Safety Sentinel** | `PhysiologicalRedFlagSentinel` alerts on acute tachycardia ($>110\text{ BPM}$), bradycardia ($<50\text{ BPM}$), and hypoxia |
| **File** | `intellidesk_backend/src/modules/diagnostics/vitals/rPPGSignalProcessor.ts` |

---

### 4.7 Prescription OCR Parser & Open ML Vision Pipeline

**Clinical Role:** Digitize handwritten and typed prescriptions, resolving medication names to canonical clinical drug databases.

| Attribute | Detail |
|---|---|
| **Primary Cloud ML Model** | Open-weight Vision-Language Models (`zai-org/GLM-4.6V-Flash`, `Qwen/Qwen2.5-VL-72B-Instruct`, `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` via Hugging Face Router) |
| **Secondary Engine (PDF)** | Poppler `pdftotext -layout` for native electronic prescriptions |
| **Local Offline Fallback** | Tesseract.js v7.0 with localized English language training weights |
| **Character Correction** | Heuristic sanitization swapping OCR token confusions (e.g. `5O0mg` → `500mg`, `I-0-1` → `1-0-1`) |
| **Knowledge Base** | Fuzzy Levenshtein matching against `rxNormDataset.ts` (8,000+ clinical formulations) |
| **Parsed Fields** | Medication name, dosage strength, administration frequency, duration, RxCUI identifier |
| **File** | `intellidesk_backend/src/modules/pharmacy/PrescriptionOCRParser.ts` |

---

### 4.8 Drug Interaction Engine & Dynamic Evidence-Based Alternative Prescribing

**Clinical Role:** Protects patients from adverse drug events, flags cross-reactive allergen contraindications, and dynamically generates safe alternative medications backed by live clinical APIs.

| Attribute | Detail |
|---|---|
| **Live Clinical API** | **NIH NLM RxNav REST API** (`https://rxnav.nlm.nih.gov/REST/`) & **RxClass API** |
| **Dynamic Alternative Engine** | `AlternativeMedicationService.ts` queries live RxCUIs and ATC classes to generate safe, non-cross-reactive substitutes for contraindicated medications |
| **Interaction Matrix** | Multi-index graph of 8,000+ known clinical drug-drug pairs |
| **Allergy Scanner** | `AllergySafetySentinel.ts` evaluates prescribed substances against patient allergy records using an allergen cross-reactivity tree |
| **Severity Hierarchy** | `CONTRAINDICATED_SEVERE` (hard block), `MAJOR`, `MODERATE_MONITOR`, `MINOR`, `SAFE` |
| **Orchestration** | `RxSentinelService.ts` coordinates prescription parsing, DDI check, allergy conflicts, and patient notifications |
| **Files** | `intellidesk_backend/src/modules/pharmacy/AlternativeMedicationService.ts`, `AllergySafetySentinel.ts`, `DrugInteractionEngine.ts` |

---

### 4.9 Clinical Patient-RAG Architecture (Retrieval-Augmented Generation)

**Clinical Role:** Aggregates and synthesizes longitudinal multi-entity patient dossiers from Supabase to provide deep, safe, and context-aware intelligence to clinical chatbots.

| Attribute | Detail |
|---|---|
| **Retriever Service** | `PatientClinicalRagService.ts` |
| **Data Entities Retrieved** | `profiles` (demographics & canonical roster resolution e.g. Priya Sharma `PAT-2026-002`), `patient_medications` (active therapy & dosages), `patient_allergies` (verified hypersensitivities), `health_screenings` (multimodal risk scores, full rPPG vitals including BP/Temp/RR, subjective notes), `cdss_evaluations` (ICD-11 codes, primary titles, first-line treatment pathways), `claims` (emergency copay status & approved amounts) |
| **Prompt Synthesis** | Dual domain modes: `MENTAL_HEALTH` (empathetic counseling) and `CLAIM_TRIAGE` (copay assistance) with token throttling |
| **Clinical Privacy** | Zero data leakage; context strictly scoped to authenticated patient sessions with strict FERPA compliance |
| **Files** | `intellidesk_backend/src/services/patientClinicalRagService.ts`, `intellidesk_backend/src/routes/chat.ts` |

---

### 4.10 PFA Crisis Counselor — Local ONNX Psychological First Aid

**Clinical Role:** Provides instantaneous, 100% confidential Psychological First Aid for students experiencing acute emotional crises.

| Attribute | Detail |
|---|---|
| **Primary Model** | `Xenova/Qwen1.5-0.5B-Chat` (quantized ONNX running on CPU via WASM) |
| **Secondary Model** | `onnx-community/Qwen2.5-0.5B-Instruct` (quantized ONNX) |
| **Tertiary Fallback** | Deterministic Rogerian active-listening engine (zero-latency guarantee) |
| **Crisis Detection** | `CRITICAL_SELF_HARM_REGEX` flags suicidal ideation or self-harm triggers |
| **Emergency Injection** | Injects one-tap calling cards for 24/7 helplines (Tele-MANAS 14416, 988 Lifeline) |
| **Privacy Guarantee** | Local inference ensures zero text payload is transmitted to third-party cloud APIs |
| **File** | `intellidesk_backend/src/services/crisisCounselorService.ts` |

---

### 4.11 Emergency Medical Facilities & Dynamic Capability Deduction

**Clinical Role:** Geolocation-based emergency medical facility routing dynamically matching diagnosed patient conditions with hospital certifications and clinical capabilities.

| Attribute | Detail |
|---|---|
| **Matching Algorithm** | Evaluates diagnostic clinical findings, ICD-11 differential impressions, and acuity tiers against facility specialty taxonomy (e.g. `Burn Care Unit`, `Comprehensive Stroke Center`, `Level 1 Trauma`, `24/7 Acute Psychiatric Crisis`, `Pediatric Emergency`) |
| **Scoring & Routing** | Haversine distance calculation, estimated travel time, operating status verification, and direct hotlines |
| **Flutter Interface** | `EmergencyFacilitySheet` bottom sheet with interactive navigation dispatch, direct calling, and facility capability tags |
| **Files** | `intellidesk_backend/src/modules/diagnostics/facilities/EmergencyFacilityService.ts`, `intellidesk_app/lib/modules/diagnostics/services/HospitalLocatorService.dart`, `intellidesk_app/lib/modules/diagnostics/ui/EmergencyFacilitySheet.dart` |

---

### 4.12 Automated Clinical Referral Letter Generator (PDF & LOINC Standard)

**Clinical Role:** Automatically compiles and signs an official, standardized clinical referral document in PDF format for downstream emergency departments and attending physicians.

| Attribute | Detail |
|---|---|
| **PDF Rendering Engine** | Server-side vector PDF generation via `pdfkit` |
| **Standardized LOINC Coding** | Vital signs mapped to international clinical observation codes: Body Temperature (8310-5), Heart Rate (8867-4), Blood Pressure (8480-6 / 8462-4), Oxygen Saturation SpO2 (2708-6), Pain Severity (72514-3) |
| **Bayesian Evidence Summary** | Renders continuous Multimodal Risk Score, 95% Confidence Interval range, and epistemic standard deviation |
| **Dynamic Clinical Directives** | Recommends triage priority, urgent stabilization steps, and diagnostic workup recommendations |
| **Physician Attestation** | Attending physician title, license verification block, and signature attestation line |
| **Client Download Rail** | `ClinicalReportShareSheet.dart` provides direct in-app PDF downloading, native share intent fallback, and offline saving |
| **Files** | `intellidesk_backend/src/modules/diagnostics/fhir/ReferralLetterGenerator.ts`, `intellidesk_app/lib/modules/diagnostics/ui/ClinicalReportShareSheet.dart` |

---

### 4.13 NLP Clinical Sentiment & Medical Entity Pipeline

**Clinical Role:** Ingests unstructured patient messages to extract emotional distress metrics and urgent clinical entities.

| Attribute | Detail |
|---|---|
| **Transformer Model** | `Xenova/distilbert-base-uncased-finetuned-sst-2-english` (ONNX) |
| **Heuristic Fallback** | Regex-driven clinical keyword density scoring |
| **Extracted Metrics** | `sentimentScore`, `negativeScore`, `isCriticalDistress`, `extractedKeywords[]` |
| **Clinical Lexicon** | Detects 40+ acute medical markers (seizure, anaphylaxis, overdose, hemorrhage, trauma) |
| **File** | `intellidesk_backend/src/services/nlpPipeline.ts` |

---

### 4.14 Clinical Counselor — Real-Time Conversational AI

**Clinical Role:** Real-time conversational triage assistant answering medical policy and symptom questions.

| Attribute | Detail |
|---|---|
| **Cloud Model** | `gemini-flash-lite-latest` (Google Gemini API) |
| **Token Budget** | Capped at 50 output tokens to ensure sub-500ms conversational latency |
| **Safety Interceptor** | Emergency regex triggers bypass LLM generation to display urgent care instructions |
| **Caching** | 10-minute in-memory LRU response cache for repetitive queries |
| **File** | `intellidesk_backend/src/services/clinicalCounselorService.ts` |

---

### 4.15 DeepRank — Crisis Severity Indexer & ESI Triage

**Clinical Role:** Computes a continuous Crisis Severity Index (CSI $\in [0, 1]$) and maps the patient into standard Emergency Severity Index (ESI) tiers.

| Attribute | Detail |
|---|---|
| **Architecture** | Sequential Dense Neural Network (`@tensorflow/tfjs-node`) |
| **Input Vector** | `[word_count, urgent_keyword_count, sentiment_score, historical_ticket_count]` |
| **ESI Mapping** | $\ge 0.85 \rightarrow \text{ESI-1 (Resuscitation)}$, $\ge 0.60 \rightarrow \text{ESI-2 (Emergent)}$, $\ge 0.35 \rightarrow \text{ESI-3 (Urgent)}$, else Routine |
| **In-Process Retraining** | Fine-tuned live on resolved triage outcomes via Adam optimizer |
| **File** | `intellidesk_backend/src/services/deepRankModel.ts` |

---

### 4.16 Multimodal Medical Intake Processor — Gemini 2.0 Flash

**Clinical Role:** Comprehensive multimodal parsing of patient text narratives paired with medical bills or clinical photographs.

| Attribute | Detail |
|---|---|
| **Cloud Model** | `gemini-2.0-flash` (Google Gemini API) |
| **Output Schema** | Validated Zod object: `category`, `urgency`, `plainTextSummary`, `requestedAmount`, `isCritical` |
| **Resilience** | Strict JSON schema enforcement with fallback to structured default intake object |
| **File** | `intellidesk_backend/src/services/gemini.ts` |

---

### 4.17 Medical Privacy & PHI Redaction Filter

**Clinical Role:** Redacts protected health information (PHI) before generating external notifications or faculty leave letters.

| Attribute | Detail |
|---|---|
| **Cloud Model** | `gemini-1.5-flash` |
| **Action** | Replaces sensitive medical diagnoses with FERPA-compliant phrasing ("a documented medical emergency") |
| **Verification** | Post-redaction regex scan; throws `PrivacyViolationError` if diagnostic terms remain |
| **File** | `intellidesk_backend/src/services/gemini.ts` $\rightarrow$ `redactSensitiveInfo()` |

---

### 4.18 Fraud Sentinel — Multi-Layer Claim Integrity Detection

**Welfare Role:** Safeguards institutional medical relief funds from fraudulent exploitation.

| Layer | Method | Trigger |
|---|---|---|
| **Layer A** | SHA-256 cryptographic image hashing | Matches identical submitted medical bills |
| **Layer B** | 7-day velocity tracking per phone identity | Flags $\ge 2$ claims within 7 days |
| **Threshold Gaming** | Identifies repeated micro-claims in high-frequency bands | Pattern of repetitive sub-limit claims |
| **Layer C** | Autoencoder feature reconstruction MSE | Flags feature vectors exceeding $0.75$ MSE threshold |

*Emergency life-safety claims bypass non-critical velocity blocks to guarantee immediate patient access to care.*

---

### 4.19 Anomaly Autoencoder — Feature Reconstruction NN

**Welfare Role:** Learns legitimate claim manifold; high reconstruction error signals anomalous submissions.

| Attribute | Detail |
|---|---|
| **Architecture** | Symmetrical Encoder-Decoder Dense Neural Network (TensorFlow.js) |
| **Input** | 4-feature normalized vector of intake metadata |
| **Output** | Mean Squared Error (MSE) anomaly score |
| **File** | `intellidesk_backend/src/services/anomalyModel.ts` |

---

### 4.20 Temporal Attrition LSTM — Longitudinal Health Risk

**Clinical Role:** Evaluates time-series trajectories across consecutive health center visits to detect escalating dropout or health burnout risk.

| Attribute | Detail |
|---|---|
| **Architecture** | Recurrent LSTM Neural Network (`@tensorflow/tfjs-node`) |
| **Input Shape** | Sequential time-series `[batch=1, timeSteps=1, features=4]` |
| **File** | `intellidesk_backend/src/services/attritionModel.ts` |

---

### 4.21 Grant Optimizer — Monte Carlo Dropout Neural Regression

**Welfare Role:** Calculates optimal emergency medical copay disbursement amount with Bayesian uncertainty quantification.

| Attribute | Detail |
|---|---|
| **Architecture** | Dense Neural Network with active Dropout layers |
| **Uncertainty Quantification** | 20 Monte Carlo forward passes calculate predictive variance and confidence interval |
| **File** | `intellidesk_backend/src/services/grantOptimizerModel.ts` |

---

### 4.22 Policy Adjudicator & Semantic Search — Gemini RAG

**Welfare Role:** Semantic matching and Chain-of-Thought policy adjudication for institutional health insurance copays.

| Attribute | Detail |
|---|---|
| **Embeddings** | `gemini-embedding-001` (768-dimensional vectors) stored in Supabase `pgvector` |
| **Search Method** | Reciprocal Rank Fusion (RRF) combining vector cosine distance + keyword full-text search |
| **Adjudicator** | `gemini-1.5-pro` reasoning engine with mandatory policy citation constraints |
| **File** | `intellidesk_backend/src/services/gemini.ts` |

---

### 4.20 ML Retraining Worker — Continuous In-Process Learning

**Role:** Background worker fine-tuning production models using verified clinical outcomes.

| Attribute | Detail |
|---|---|
| **Queue Engine** | BullMQ on Redis |
| **Retrained Models** | DeepRank CSI and Grant Optimizer (5 epochs each on resolved Supabase tickets) |
| **File** | `intellidesk_backend/src/workers/mlRetrainingWorker.ts` |

---

### Cloud vs Local Model Fallback Map

| Capability | Cloud Primary | Local Edge Fallback |
|---|---|---|
| **Clinical Image Vision** | Qwen2.5-VL 72B (Hugging Face) | Clinical MobileNet-V3 (TFLite, On-Device) |
| **CDSS Differential Dx** | Qwen2.5-72B (Hugging Face) | ICD-11 Deterministic Scoring Engine |
| **Acoustic Cough Screening** | HF Audio Inference Endpoint | Local CoughClassifier NN (MFCC + TF.js) |
| **Camera Vitals (rPPG)** | — *(Local Only)* | Butterworth Filter + Video Photoplethysmography |
| **Prescription Parsing** | Poppler `pdftotext` | Tesseract.js OCR + RxNorm Fuzzy Matcher |
| **Pharmacy Safety / DDI** | — *(Local Only)* | 8,000+ Drug Pair Contraindication Matrix |
| **PFA Crisis Chat** | — *(Local-First for Privacy)* | Qwen1.5-0.5B ONNX → Qwen2.5-0.5B ONNX → Rogerian Engine |
| **Clinical Triage Chat** | Gemini Flash Lite | Deterministic Rogerian Engine |
| **Clinical Entity & Sentiment** | DistilBERT SST-2 (ONNX) | Clinical Urgent Keyword Regex Heuristics |
| **Emergency Severity (CSI)** | Local DeepRank NN (TF.js) | Safe Baseline (CSI = 0.5) |
| **Intake Parsing** | Gemini 2.0 Flash | Structured Default Triage Payload |
| **PHI / Privacy Redaction** | Gemini 1.5 Flash | Manual Review Escalation Flag |
| **Copay Grant Optimization** | Local MC Dropout NN (TF.js) | Standard Capped Grant Function |
| **Fraud Anomaly Detection** | Local Autoencoder (TF.js) | SHA-256 Hash + Velocity Filter |
| **Policy Search & RAG** | Gemini Embedding-001 + 1.5 Pro | Manual Administrative Escalation |

---

## 5. System Architecture

```
+---------------------------------------------------------------------------------------+
|                         MedAccess AI -- Flutter Mobile Client                         |
|                                                                                       |
|  +-------------------------------------+   +---------------------------------------+  |
|  |       Patient Clinical Portal       |   |        Admin Clinical War Room        |  |
|  |  Camera Dermatology / Lesion Scan   |   |  Real-Time ESI Triage Queue (1-5)     |  |
|  |  Cough Audio Recording (Meyda DSP)  |   |  Grad-CAM Saliency Heatmap Review     |  |
|  |  Contactless rPPG Vitals Monitor    |   |  CDSS Differential Diagnostic Review  |  |
|  |  Prescription OCR & DDI Checker     |   |  Clinical ESI Override & Telemetry    |  |
|  |  PFA Crisis Chat (Qwen ONNX Local)  |   |  Health Fund Liquidity Telemetry      |  |
|  |  Emergency Copay Status Tracker     |   |  One-Tap Instant Payout Modal         |  |
|  +-------------------------------------+   +---------------------------------------+  |
+-------------------------------------------^-------------------------------------------+
                                            |  REST + WebSocket (Socket.io)
+-------------------------------------------v-------------------------------------------+
|               MedAccess Backend API (Express 5 / TypeScript / ESM)                    |
|  Auth + RBAC (JWT / Supabase)            Clinical Diagnostics & Vision Ingestion      |
|  CDSS ICD-11 Differential Engine         Acoustic Cough Analysis Pipeline             |
|  Pharmacy Safety & RxNorm Matcher        Contactless rPPG Signal Processor            |
|  PFA Counselor AI (Local ONNX CPU)       FHIR R4 DiagnosticReport Converter           |
|  Async Triage Pipeline (BullMQ)          FHIR R4 DiagnosticReport Converter           |
+---------------------+-------------------------------------+---------------------------+
                      |                                     |
+---------------------v-------------+         +-------------v---------------------+
|    BullMQ Workers (Redis)         |         |  Supabase PostgreSQL + pgvector   |
|  Clinical Intake Worker           |         |  institutions (multi-tenancy)     |
|    Poppler / Tesseract.js OCR     |         |  profiles (RBAC: Student/Admin)   |
|    SHA-256 Receipt Integrity      |         |  tickets / clinical encounters    |
|    DeepRank CSI & ESI Triage      |         |  ticket_messages (PFA chat)       |
|    Multimodal Fusion Assessment   |         |  health_funds / emergency copays  |
|    CDSS Diagnostic Ingestion      |         |  system event & triage logs           |
|    Socket.io Real-Time Broadcast  |         |  policies (vector(768) pgvector)  |
|  ML Retraining Worker (TF.js)     |         |  RLS Row-Level Security Enforced  |
|  Notification Worker (Email/SMS)  |         +-----------------------------------+
+-----------------------------------+
                      |
+---------------------v-----------------------------------------------------------------+
|                                     ML / AI Layer                                     |
|                                                                                       |
|  +------------------------+  +------------------------+  +--------------------------+ |
|  |   Local TF.js Node     |  |   ONNX Runtime (WASM)  |  |   Cloud AI APIs          | |
|  |  Multimodal Fusion NN  |  |  Qwen1.5-0.5B PFA Chat |  |  Qwen2.5-VL 72B Vision   | |
|  |  Cough Classifier NN   |  |  Qwen2.5-0.5B Instruct |  |  Qwen2.5-72B CDSS Engine | |
|  |  DeepRank CSI Model    |  |  DistilBERT Sentiment  |  |  Gemini 2.0 Flash Intake | |
|  |  Anomaly Autoencoder   |  +------------------------+  |  Gemini 1.5 Pro Policy   | |
|  |  Temporal LSTM Risk    |                              |  Gemini Flash Lite Chat  | |
|  |  Grant Optimizer NN    |                              |  Gemini Embedding-001    | |
|  +------------------------+                              +--------------------------+ |
+---------------------------------------------------------------------------------------+
                      |
+---------------------v-----------------------------------+
|               External Health & Payment Rails           |
|  RazorpayX (Instant UPI / IMPS Copay Disbursement)      |
|  Stripe (USD International Medical Aid)                 |
|  Twilio (Emergency SMS for ESI-1 Life-Safety Alerts)   |
|  Nodemailer / Resend (Clinical Encounter Summaries)     |
|  Google Places API (Nearest Emergency Clinic Locator)   |
|  Firebase FCM (Urgent Diagnostic Push Notifications)    |
+---------------------------------------------------------+
```

---

## 6. Folder Structure

```
intellidesk/
├── intellidesk_app/                     # Flutter Mobile Client
│   ├── lib/
│   │   ├── main.dart                    # Entry point, Provider tree, route table
│   │   ├── models/
│   │   │   ├── claim.dart               # Clinical ticket & claim entity
│   │   │   ├── claim_message.dart       # PFA chat turn model
│   │   │   ├── health_fund.dart         # Copay fund model
│   │   │   └── emergency_helpline.dart  # Crisis hotlines
│   │   ├── services/
│   │   │   ├── clinical_api_service.dart     # Diagnostic & REST API client
│   │   │   ├── socket_service.dart           # Real-time WebSocket manager
│   │   │   └── offline_sync_manager.dart     # On-device offline cache
│   │   ├── providers/
│   │   │   ├── auth_provider.dart            # Session, JWT, RBAC
│   │   │   ├── claims_provider.dart          # Clinical triage queue & filters
│   │   │   ├── clinical_chat_provider.dart   # PFA conversational state
│   │   │   ├── war_room_provider.dart        # Clinical telemetry & ESI stats
│   │   │   └── ticket_provider.dart          # Patient status tracker
│   │   ├── screens/
│   │   │   ├── patient/
│   │   │   │   ├── claim_intake_screen.dart       # Photo, audio, bill upload
│   │   │   │   ├── clinical_chat_screen.dart      # PFA chat interface
│   │   │   │   ├── claim_status_screen.dart       # ESI tier & copay tracker
│   │   │   │   ├── emergency_hub_screen.dart      # 24/7 crisis hotlines
│   │   │   │   ├── health_records_screen.dart     # Longitudinal medical history
│   │   │   │   ├── pharmacy_hub_screen.dart       # Rx parser & interaction checker
│   │   │   │   └── patient_clinical_dashboard.dart
│   │   │   └── admin/
│   │   │       ├── admin_war_room_screen.dart           # Triage queue & payout
│   │   │       ├── admin_clinical_diagnoses_screen.dart # Diagnostic AI & Grad-CAM
│   │   │       ├── admin_health_funds_screen.dart       # Fund management
│   │   │       ├── admin_knowledge_base_screen.dart     # Policy RAG search
│   │   │       └── admin_main_screen.dart
│   │   └── theme/app_theme.dart        # Clinical design system & ESI tokens
│   └── pubspec.yaml
│
├── intellidesk_backend/                 # Node.js Diagnostic & Triage Backend
│   ├── src/
│   │   ├── server.ts                    # Bootstrap, Express & ML init
│   │   ├── modules/
│   │   │   ├── cdss/                    # Clinical Decision Support System
│   │   │   │   ├── CDSSService.ts                  # CDSS coordinator
│   │   │   │   ├── DifferentialDiagnosisEngine.ts  # ICD-11 logit scoring
│   │   │   │   ├── ICD11ConceptStore.ts            # WHO ICD-11 knowledge base
│   │   │   │   ├── QwenInferenceService.ts         # Qwen2.5-72B cloud service
│   │   │   │   └── TreatmentPathwayAdvisor.ts      # Clinical pathway advisor
│   │   │   ├── diagnostics/
│   │   │   │   ├── vision/
│   │   │   │   │   ├── CloudVisionClassifier.ts    # Qwen2.5-VL 72B vision
│   │   │   │   │   ├── clinicalMobileNet.ts        # Local MobileNet-V3 fallback
│   │   │   │   │   └── VisionDiagnosticService.ts
│   │   │   │   ├── audio/
│   │   │   │   │   ├── CoughClassifier.ts          # Cough neural network
│   │   │   │   │   ├── AudioFeatureExtractor.ts    # Meyda.js MFCC pipeline
│   │   │   │   │   └── CloudAudioClassifier.ts     # HF audio endpoint
│   │   │   │   ├── vitals/
│   │   │   │   │   ├── rPPGSignalProcessor.ts      # Camera heart rate extraction
│   │   │   │   │   ├── ButterworthFilter.ts        # Bandpass filter (0.75-3.5 Hz)
│   │   │   │   │   └── PhysiologicalRedFlagSentinel.ts
│   │   │   │   ├── fusion/
│   │   │   │   │   ├── MultimodalFusionModel.ts    # 168-d late-fusion DNN
│   │   │   │   │   ├── diseasePredictionModel.ts
│   │   │   │   │   └── vectorAssembler.ts
│   │   │   │   ├── explainability/
│   │   │   │   │   ├── gradCamGenerator.ts         # Grad-CAM heatmaps
│   │   │   │   │   ├── featureImportance.ts
│   │   │   │   │   └── uncertaintyEngine.ts
│   │   │   │   ├── fhir/
│   │   │   │   │   ├── FHIRConverterService.ts     # HL7 FHIR R4 Bundle generator
│   │   │   │   │   └── ReferralLetterGenerator.ts
│   │   │   │   └── progression/
│   │   │   │       └── ScreeningDeltaAnalyzer.ts   # Lesion healing tracker
│   │   │   └── pharmacy/
│   │   │       ├── PrescriptionOCRParser.ts        # Handwritten Rx OCR
│   │   │       ├── DrugInteractionEngine.ts        # 8,000+ drug pair DDI
│   │   │       ├── AllergySafetySentinel.ts        # Allergy contraindication
│   │   │       ├── fuzzyMatcher.ts                 # Levenshtein RxNorm matcher
│   │   │       └── rxNormDataset.ts                # RxNorm local database
│   │   ├── services/
│   │   │   ├── crisisCounselorService.ts    # Local Qwen ONNX PFA chat
│   │   │   ├── clinicalCounselorService.ts  # Gemini Flash Lite chat
│   │   │   ├── deepRankModel.ts             # DeepRank ESI / CSI model
│   │   │   ├── nlpPipeline.ts               # DistilBERT clinical sentiment
│   │   │   ├── gemini.ts                    # Gemini multimodal APIs & RAG
│   │   │   ├── receiptParser.ts             # PDF / bill OCR parser
│   │   │   ├── disbursementService.ts       # RazorpayX payout service
│   │   │   ├── payoutService.ts             # Stripe & voucher engine
│   │   │   ├── fraudSentinel.ts             # 3-layer claim integrity check
│   │   │   ├── anomalyModel.ts              # Autoencoder anomaly model
│   │   │   ├── attritionModel.ts            # Temporal LSTM risk model
│   │   │   └── grantOptimizerModel.ts       # MC Dropout copay optimizer
│   │   ├── workers/
│   │   │   ├── intakeWorker.ts              # 10-step BullMQ intake pipeline
│   │   │   ├── mlRetrainingWorker.ts        # In-process TF.js continuous retraining
│   │   │   └── notificationWorker.ts        # Email + Twilio SMS dispatch
│   │   ├── ml/                              # Training scripts
│   │   │   ├── deep_rank.ts
│   │   │   ├── lstm.ts
│   │   │   ├── autoencoder.ts
│   │   │   └── train_all.ts
│   │   └── models/                          # Generated TF.js model weights
│   ├── eng.traineddata                      # Tesseract English weights
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── package.json
│
├── models/cdss/                             # CDSS knowledge graph artifacts
├── supabase_core_schema.sql                 # PostgreSQL tables + RLS
├── supabase_setup.sql                       # Extensions & vector setup
├── train_cdss_model.py                      # Offline CDSS training script
└── ARCHITECTURE.md                          # Architecture specification
```

---

## 7. Technology Stack

### Clinical & Diagnostic AI Stack

| Component | Framework / Library | Role & Justification |
|---|---|---|
| **VLM Vision Classifier** | `Qwen/Qwen2.5-VL-72B-Instruct` | Hospital-grade multimodal classification of dermatology, lesions, and ocular conditions |
| **Local Vision Fallback** | Clinical MobileNet-V3 (TFLite) | Zero-latency, on-device edge fallback when network connection is severed |
| **CDSS Diagnostic LLM** | `Qwen/Qwen2.5-72B-Instruct` | WHO ICD-11 evidence-based differential diagnosis and clinical triage recommendations |
| **Deterministic CDSS Engine** | `DifferentialDiagnosisEngine` | Logit scoring ($T=1.25$) over calibrated ICD-11 disease priors |
| **Acoustic Cough ML** | `@tensorflow/tfjs-node` + Meyda.js | 16-d MFCC feature extraction + 4-class neural network respiratory screening |
| **Contactless Vitals** | Node.js + Butterworth DSP | 30 Hz RGB video decomposition isolating heart rate (BPM) and SpO2 |
| **Prescription OCR** | Poppler `pdftotext` + Tesseract.js | Dual-engine OCR with character sanitization and 8,000+ entry RxNorm fuzzy matcher |
| **Drug Safety Engine** | `DrugInteractionEngine` | In-memory 8,000+ drug pair contraindication and interaction lookup matrix |
| **Local Crisis Chat (PFA)** | `@xenova/transformers` (ONNX) | CPU-quantized Qwen1.5-0.5B running on-device for 100% confidential mental health triage |
| **Clinical Sentiment NLP** | DistilBERT SST-2 (ONNX) | Distress quantification and medical urgency regex entity extraction |
| **Clinical ESI Triage** | `@tensorflow/tfjs-node` | DeepRank Crisis Severity Index (CSI) neural network mapping to ESI tiers 1–5 |
| **Visual Explainability** | Grad-CAM | Gradient backpropagation generating visual saliency overlays for diagnostic transparency |
| **Interoperability** | HL7 FHIR R4 Converter | Exports clinical encounters to standard FHIR `DiagnosticReport` Bundles |

### Frontend (Flutter Client)

| Category | Technology | Usage |
|---|---|---|
| **Framework** | Flutter (Dart SDK ^3.10.7) | Cross-platform client (Android, iOS, Web, Desktop) |
| **State Management** | Provider + ChangeNotifier | Clean MVVM architecture separating clinical UI from API logic |
| **Edge ML** | `tflite_flutter` | Local on-device execution of quantized TFLite models |
| **Acoustic Capture** | `record` | 16kHz uncompressed audio recording for cough screening |
| **Camera & Media** | `camera`, `image_picker` | High-resolution capture for dermatology and rPPG vitals |
| **Real-Time** | `socket_io_client` | Real-time bi-directional clinical war room telemetry |
| **Offline Cache** | `shared_preferences` | Offline symptom logging with automatic sync on reconnection |

### Backend & Cloud Infrastructure

| Category | Technology | Usage |
|---|---|---|
| **Runtime & Framework** | Node.js (ESM) + Express 5 | High-throughput asynchronous backend service |
| **Database** | Supabase PostgreSQL + `pgvector` | Relational clinical records with Row-Level Security and vector search |
| **Queue & Workers** | BullMQ + Redis 7 | 10-step asynchronous intake pipeline and continuous ML retraining |
| **Document Processing** | `sharp`, `pdf-parse` | Image preprocessing, PDF layout extraction & OCR |
| **Copay Disbursement** | RazorpayX (UPI/IMPS), Stripe | Multi-rail emergency copay and medical welfare disbursement |
| **Emergency Alerts** | Twilio, Nodemailer, Resend | Instant SMS dispatch for ESI-1 life-safety alerts and email reports |

---

## 8. API Reference

### Clinical Diagnostics & CDSS

| Method | Route | Description |
|---|---|---|
| `POST` | `/api/v1/diagnostics/vision` | Upload clinical image $\rightarrow$ Qwen2.5-VL 72B / MobileNet assessment + Grad-CAM |
| `POST` | `/api/v1/diagnostics/audio` | Ingest cough audio $\rightarrow$ 16-d MFCC extraction $\rightarrow$ 4-class cough classification |
| `POST` | `/api/v1/diagnostics/vitals` | Ingest facial/fingertip video frames $\rightarrow$ dual-channel rPPG pulse extraction & vitals red flags |
| `POST` | `/api/v1/diagnostics/facilities/emergency` | Search nearby emergency facilities with dynamic clinical capability deduction |
| `POST` | `/api/v1/diagnostics/referral-letter/pdf` | Generate standardized clinical referral letter (PDF) with LOINC vitals & clinician signature |
| `GET` | `/api/v1/diagnostics/screenings/patient/:patientId` | Retrieve longitudinal multimodal health screening records |
| `POST` | `/api/v1/cdss/evaluate` | Ingest symptom payload $\rightarrow$ WHO ICD-11 differential diagnosis & FHIR R4 bundle |
| `POST` | `/api/v1/cdss/predict-qwen` | Differential disease prediction via Qwen2.5-72B with subjective clinical notes synthesis |
| `POST` | `/api/v1/cdss/approve` | Attending clinician sign-off or diagnostic override with cryptographic signature hash |
| `GET` | `/api/v1/cdss/evaluation/:screeningId` | Retrieve cached or persisted CDSS evaluation by health screening ID |

### Pharmacy & Medication Safety

| Method | Route | Description |
|---|---|---|
| `POST` | `/api/v1/pharmacy/parse` | Ingest prescription image $\rightarrow$ OCR extraction $\rightarrow$ RxNorm canonical matching |
| `POST` | `/api/v1/pharmacy/interactions` | Ingest medication list $\rightarrow$ check 8,000+ drug-drug interactions & allergy profile |

### Psychological First Aid (PFA), Clinical Chatbots & Patient-RAG

| Method | Route | Description |
|---|---|---|
| `POST` | `/api/v1/chat` | Send message $\rightarrow$ on-device Qwen PFA reply + self-harm crisis interception |
| `POST` | `/api/v1/chat/mental-health` | Patient-RAG augmented empathetic PFA counselor with full patient dossier context |
| `GET` | `/api/v1/chat/:ticketId/messages` | Retrieve confidential PFA chat history for a clinical claim |

### Clinical Triage & Intake

| Method | Route | Description |
|---|---|---|
| `POST` | `/api/v1/intake/web` | Submit clinical request (narrative + photos/bills) $\rightarrow$ BullMQ 10-step pipeline |
| `GET` | `/api/v1/claims` | List clinical claims (filter by ESI tier, status, keyword) |
| `GET` | `/api/v1/claims/:id` | Fetch complete clinical claim + diagnostic scores + triage tier |

### Clinical Admin War Room

| Method | Route | Description |
|---|---|---|
| `POST` | `/api/v1/claims/:id/override` | Override AI-assigned ESI tier with documented clinical justification |
| `POST` | `/api/v1/claims/:id/disburse` | Disburse approved emergency copay relief via RazorpayX or Stripe |
| `GET` | `/api/v1/admin/telemetry` | Telemetry dashboard: ESI distribution, diagnostic volume, fund liquidity |

---

## 9. Database Schema

All database tables are governed by strict **Row-Level Security (RLS)** in PostgreSQL to maintain patient privacy and FERPA isolation.

### `tickets` — Primary Clinical & Welfare Encounter Record
| Column | Type | Description |
|---|---|---|
| `id` | UUID (PK) | Unique encounter identifier |
| `urgency_level` | TEXT | ESI triage level (ESI-1 to ESI-5) computed by DeepRank |
| `crisis_severity_index` | NUMERIC (0–1) | Continuous severity score generated by DeepRank |
| `dropout_risk_score` | NUMERIC (0–1) | Longitudinal health burnout/attrition risk |
| `recommended_grant_amount`| NUMERIC | Emergency copay relief amount calculated by Grant Optimizer |
| `fraud_risk_score` | NUMERIC (0–1) | Multi-layer fraud sentinel score |
| `receipt_image_hash` | TEXT | SHA-256 hash for medical bill deduplication |
| `anomaly_reconstruction_score`| NUMERIC | Autoencoder feature reconstruction MSE |
| `embedding` | vector(768) | Gemini Embedding-001 vector representation |
| `payout_method` | TEXT | UPI / BANK / VOUCHER |

### `ticket_messages` — Confidential PFA & Triage Log
| Column | Type | Description |
|---|---|---|
| `id` | UUID (PK) | Message identifier |
| `sender` | TEXT | `STUDENT`, `COUNSELOR_AI`, or `HUMAN_ADMIN` |
| `is_crisis_response` | BOOLEAN | True if self-harm or acute distress detected |
| `suggested_resources` | JSONB | Immediate emergency helpline cards |

### `activity_logs` — System Event Logs
| Column | Type | Description |
|---|---|---|
| `id` | UUID (PK) | Event record identifier |
| `action_type` | TEXT | `ESI_OVERRIDE`, `DISBURSEMENT`, `FRAUD_FLAG` |
| `actor_type` | TEXT | `CLINICIAN`, `ADMIN`, or `AI_SYSTEM` |
| `details` | JSONB | Complete payload including clinical override justification |

---

## 10. Background Workers

### Clinical Intake Worker (`intakeWorker.ts`)
Processes all submitted clinical requests through a 10-step asynchronous queue:
1. **Multimodal Extraction** — parses uploaded medical bills/prescriptions using Poppler and Tesseract.js.
2. **Clinical NLP Analysis** — extracts sentiment and medical emergency entities using DistilBERT ONNX.
3. **Integrity Sentinel** — runs SHA-256 hash verification and Autoencoder anomaly scoring.
4. **DeepRank CSI Scoring** — calculates continuous severity and assigns ESI triage level (1–5).
5. **Attrition Risk Scoring** — evaluates longitudinal health burnout via Temporal LSTM.
6. **Copay Optimization** — computes recommended emergency copay relief with MC Dropout confidence bounds.
7. **Multimodal Intake Parsing** — structures narrative via Gemini 2.0 Flash with clinical category tags.
8. **Policy Adjudication** — performs RRF hybrid vector search for institutional copay guidelines.
9. **Record Persistence** — updates Supabase ticket with full diagnostic telemetry.
10. **WebSocket Broadcast** — pushes real-time ESI-sorted encounter to the clinician war room.

### ML Retraining Worker (`mlRetrainingWorker.ts`)
- Runs continuously on a scheduled BullMQ interval.
- Fetches verified clinical outcomes from Supabase.
- Performs in-process fine-tuning for DeepRank CSI and Grant Optimizer (5 epochs each using Adam).
- Persists updated neural network weights directly to disk.

---

## 11. Security Architecture

```
Client Request → CORS → JWT Auth (requireAuth)
                              |
                     Role Check (requireRole(['ADMIN', 'CLINICIAN']))
                              |
                     Tenant Middleware (injects institution_id from JWT)
                              |
                     Supabase Row-Level Security (enforces data isolation)
```

- **Clinical Decision Logging** — every clinical decision, diagnosis confirmation, and copay disbursement is logged with structured JSONB telemetry.
- **Automated PHI De-Identification** — Gemini 1.5 Flash strips protected health information before generating notifications or external leave letters.
- **Emergency Life-Safety Bypass** — acute life-safety and mental health crisis triggers bypass all non-critical rate limits and fraud checks.

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

### ML Training & Model Weights
```bash
cd intellidesk_backend
npm run train:ml   # Trains DeepRank, LSTM, Autoencoder, Grant Optimizer, Cough Classifier, Fusion
npm run seed:all   # Seeds institutional policies, health funds, and ICD-11 priors
```

---

## 13. Environment Variables

| Variable | Service | Description |
|---|---|---|
| `SUPABASE_URL` | Supabase | Project API endpoint |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase | Service role key for backend operations |
| `SUPABASE_ANON_KEY` | Supabase | Anon key for Flutter client |
| `GEMINI_API_KEY` | Google AI Studio | Gemini 2.0 Flash / 1.5 Pro / Embedding-001 |
| `HF_TOKEN` | Hugging Face | Qwen2.5-VL 72B vision & Qwen2.5-72B CDSS |
| `REDIS_URL` | Redis | BullMQ asynchronous queue connection |
| `RAZORPAY_KEY_ID` | RazorpayX | Instant UPI / IMPS copay payout key |
| `RAZORPAY_KEY_SECRET` | RazorpayX | RazorpayX account secret |
| `STRIPE_SECRET_KEY` | Stripe | International medical aid payment key |
| `TWILIO_ACCOUNT_SID` | Twilio | SMS notification account SID |
| `TWILIO_AUTH_TOKEN` | Twilio | SMS authentication token |
| `TWILIO_PHONE_NUMBER` | Twilio | Sender phone number for ESI-1 alerts |
| `GOOGLE_PLACES_API_KEY` | Google Places | Nearest emergency hospital and clinic locator |
| `JWT_SECRET` | Backend | Secret used for signing authentication tokens |
| `PORT` | Backend | Server port (default: 3000) |

---

## 14. Getting Started

### Prerequisites
- Node.js 20+ with npm
- Flutter SDK 3.10+
- Redis 7 (local or Docker container)
- Supabase account with PostgreSQL instance
- Google Gemini API key
- Hugging Face API token (for 72B vision and CDSS features)

### Quick Start

```bash
# 1. Clone repository
git clone <repo-url> && cd intellidesk

# 2. Configure & initialize backend
cd intellidesk_backend
cp .env.example .env
# Set SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GEMINI_API_KEY, HF_TOKEN, REDIS_URL
npm install

# 3. Apply database schema
# Run supabase_core_schema.sql in your Supabase SQL editor

# 4. Train local ML models & seed initial clinical data
npm run train:ml
npm run seed:all

# 5. Launch backend server
npm run dev

# 6. Launch Flutter mobile client (in a new terminal)
cd ../intellidesk_app
flutter pub get
flutter run
```

---

## WebSocket Events

| Event | Direction | Payload |
|---|---|---|
| `join-institution` | Client $\rightarrow$ Server | `{ institutionId }` |
| `ticket-created` | Server $\rightarrow$ Client | Full clinical encounter object |
| `ticket-updated` | Server $\rightarrow$ Client | `{ ticketId, status, esiLevel, csi }` |
| `payout-completed` | Server $\rightarrow$ Client | `{ ticketId, txnRef, amount }` |
| `fraud-flagged` | Server $\rightarrow$ Client | `{ ticketId, flagReasons }` |

---

*Built with clinical rigor, engineering excellence, and patient-first care.*
