# MedAccess AI — Machine Learning Architecture Reference

> **Complete technical reference for the MedAccess AI machine learning ecosystem:** 21 hybrid diagnostic, triage, and welfare models spanning on-device computer vision, WHO ICD-11 clinical decision support, acoustic respiratory screening, contactless rPPG vitals, pharmacy safety, local ONNX PFA counselors, and continuous in-process neural retraining.

---

## 1. Machine Learning Ecosystem Overview

MedAccess AI employs a **hybrid edge-cloud machine learning architecture**. It prioritizes zero-downtime offline clinical safety by pairing high-capacity cloud models with on-device or deterministic fallbacks:

| Category | Primary Cloud Model | Local / Edge Fallback Model | Framework |
|---|---|---|---|
| **Clinical Image Vision** | Qwen2.5-VL 72B VLM (Hugging Face) | Clinical MobileNet-V3 (Quantized TFLite) | Hugging Face Router / TFLite |
| **CDSS Differential Dx** | Qwen2.5-72B LLM (Hugging Face) | `DifferentialDiagnosisEngine` (ICD-11 Logits) | Hugging Face Router / TypeScript |
| **Acoustic Cough Screening**| Hugging Face Audio Inference | Local CoughClassifier NN (16-d MFCC) | Meyda.js DSP / `@tensorflow/tfjs-node` |
| **Contactless Vitals** | — *(100% On-Device / Local)* | rPPG Video Decomposition + Butterworth Filter | Node.js DSP (0.75–3.5 Hz) |
| **Multimodal Fusion** | — *(100% Local Neural Network)* | 168-d Late-Fusion Multi-Head DNN | `@tensorflow/tfjs-node` Functional API |
| **Visual Explainability** | — *(100% Local Inference)* | Grad-CAM Saliency Backpropagation | Saliency Gradient Engine |
| **Prescription OCR** | Poppler `pdftotext -layout` | Tesseract.js v7.0 + RxNorm Fuzzy Matcher | OCR Engine / Levenshtein Matcher |
| **Pharmacy Safety & DDI** | — *(100% In-Memory)* | 8,000+ Drug Pair Contraindication Matrix | In-Memory Graph / Concept Hash |
| **PFA Crisis Chat** | — *(Local-First for Absolute Privacy)* | Xenova Qwen1.5-0.5B ONNX $\rightarrow$ Rogerian PFA | `@xenova/transformers` (WASM) |
| **Clinical Sentiment NLP** | DistilBERT SST-2 (ONNX) | Clinical Urgent Keyword Regex Heuristics | `@xenova/transformers` / RegEx |
| **Clinical ESI Triage (CSI)**| Local DeepRank NN (TF.js) | Safe Baseline Model (CSI = 0.5) | `@tensorflow/tfjs-node` Sequential |
| **Copay Grant Optimization**| Local MC Dropout NN (TF.js) | Standard Capped Grant Function | `@tensorflow/tfjs-node` (MC Dropout) |
| **Longitudinal Health Risk**| Local Temporal Attrition LSTM (TF.js)| Safe Baseline Model (Risk = 0.0) | `@tensorflow/tfjs-node` Recurrent |
| **Fraud Anomaly Detection** | Local Autoencoder (TF.js) | SHA-256 Hash + Velocity Filter | `@tensorflow/tfjs-node` Autoencoder |
| **Multimodal Claim Intake** | Google Gemini 2.0 Flash | Structured Default Triage Payload | Google Gemini API (Zod Validated) |
| **Policy Adjudication (RAG)**| Google Gemini 1.5 Pro (Chain-of-Thought)| Escalated / Manual Administrative Flag | Gemini API + pgvector (768-d) |
| **Medical Privacy & PHI Redaction** | Google Gemini 1.5 Flash | Manual Redaction Escalation Flag | Gemini API + Post-Redaction Regex |

---

## 2. Clinical Diagnostics & Vision Suite

### 2.1 Cloud Vision Classifier — Qwen2.5-VL 72B & Clinical MobileNet-V3
**Source Files:**
- Cloud VLM: `intellidesk_backend/src/modules/diagnostics/vision/CloudVisionClassifier.ts`
- Local Fallback: `intellidesk_backend/src/modules/diagnostics/vision/clinicalMobileNet.ts`
- Orchestration: `intellidesk_backend/src/modules/diagnostics/vision/imageClassifier.ts`

#### Architecture & Inference Pipeline
The clinical vision system ingests medical photographs of rashes, skin lesions, burns, ocular redness, and oral conditions:
1. **Preprocessing:** Image buffer passed through `sharp`:
   - Resized to $1024 \times 1024$ maintaining aspect ratio.
   - Normalized RGB color channels.
   - EXIF orientation automatically corrected.
2. **Cloud Path (Primary):** Dispatched to `Qwen/Qwen2.5-VL-72B-Instruct` via Hugging Face Inference Router.
   - Structured JSON prompt with schema: `condition`, `anatomicalSite`, `severity`, `confidence`, `findings[]`, `differentialDiagnoses[]`, `recommendedAction`, `isEmergencyAlert`.
3. **Local Fallback (Offline):** If network or API timeout occurs, passes to quantized Clinical MobileNet-V3:
   - Evaluates image against 10 common triage classes: Eczema, Psoriasis, Cellulitis, Dermatitis, Fungal Infection, Thermal Burn, Conjunctivitis, Urticaria, Herpes Zoster, Normal Skin.
   - Yields Top-3 class probabilities and severity rating.

---

### 2.2 CDSS — Clinical Decision Support System (WHO ICD-11 + Qwen2.5-72B)
**Source Files:**
- Orchestrator: `intellidesk_backend/src/modules/cdss/CDSSService.ts`
- Differential Logit Scorer: `intellidesk_backend/src/modules/cdss/DifferentialDiagnosisEngine.ts`
- Knowledge Base: `intellidesk_backend/src/modules/cdss/ICD11ConceptStore.ts`
- FHIR Interoperability: `intellidesk_backend/src/modules/cdss/fhir/FHIRConverterService.ts`

#### Logit Calibration & Differential Algorithm
The CDSS combines LLM reasoning with mathematical logit bounds:
1. **Symptom Vector Encoding:** Maps patient narrative and structured inputs to cardinal clinical symptoms.
2. **Logit Transformation & Boundary Clipping:**
   $$\text{logit}(p) = \log\left(\frac{p}{1 - p}\right)$$
   Logits are strictly clipped to the $[-20, 20]$ interval to prevent float overflow.
3. **Temperature Scaling:** Logits are calibrated using $T = 1.25$ to avoid overconfident misdiagnoses:
   $$\hat{p}_i = \frac{\exp(z_i / 1.25)}{\sum_j \exp(z_j / 1.25)}$$
4. **Urgency Classification:**
   - `IMMEDIATE_EMERGENCY`: Severe red-flag criteria (anaphylaxis, chest pain, meningeal signs).
   - `PROMPT_EVALUATION`: Acute symptoms requiring clinician intervention within 12–24 hours.
   - `ROUTINE`: Self-limiting or stable conditions.
5. **HL7 FHIR R4 Bundle Export:** Formats the complete evaluation into a standard clinical FHIR JSON bundle containing `DiagnosticReport`, `Observation`, and `Condition` resources.

---

### 2.3 Multimodal Clinical Fusion Model — 168-d Late-Fusion DNN
**Source Files:**
- Network: `intellidesk_backend/src/modules/diagnostics/fusion/MultimodalFusionModel.ts`
- Coordinator: `intellidesk_backend/src/modules/diagnostics/fusion/multimodalRiskNetwork.ts`

#### Architecture
The late-fusion model fuses visual, clinical symptom, and demographic signals into a single unified representation:

```
Visual Embedding (128-d) ──┐
Symptom Vector (32-d)   ───┼──► Concatenate [168-d vector]
Demographics (8-d)       ──┘
            │
            ├── Dense(128, relu) + BatchNormalization + Dropout(0.30)
            ├── Dense(64, relu) + BatchNormalization + Dropout(0.25)
            │
            ├── Head 1: Dense(1, sigmoid) ──► Continuous Clinical Risk ∈ [0, 1]
            └── Head 2: Dense(3, softmax) ──► [Low Risk, Moderate Need, Critical Referral]
```

- **Uncertainty Quantification:** Runs 20 active forward passes using Monte Carlo Dropout to calculate epistemic variance and 95% confidence intervals for clinical risk.

---

### 2.4 Grad-CAM Visual Explainability Engine
**Source File:** `intellidesk_backend/src/modules/diagnostics/explainability/gradCamGenerator.ts`

#### Mathematical Formulation
Allows physicians to verify whether the AI's classification was driven by pathological features or incidental image artifacts:
1. Calculates the gradient of class score $y^c$ with respect to feature activation map $A^k$ of the final convolutional layer:
   $$\alpha_k^c = \frac{1}{Z} \sum_{i} \sum_{j} \frac{\partial y^c}{\partial A_{i,j}^k}$$
2. Computes the weighted combination followed by a ReLU non-linearity:
   $$L_{\text{Grad-CAM}}^c = \text{ReLU}\left(\sum_k \alpha_k^c A^k\right)$$
3. Normalizes heatmap values to $[0, 1]$ and generates a false-color jet heatmap superimposed on the original medical photograph.

---

### 2.5 Cough Classifier — On-Device Acoustic Respiratory ML
**Source Files:**
- Model Definition: `intellidesk_backend/src/modules/diagnostics/audio/CoughClassifier.ts`
- DSP Feature Extraction: `intellidesk_backend/src/modules/diagnostics/audio/AudioFeatureExtractor.ts`
- Training Script: `intellidesk_backend/scripts/trainCoughClassifier.ts`

#### Audio DSP & Neural Architecture
1. **Audio Feature Extraction:** Ingests 16kHz uncompressed WAV audio. Uses Meyda.js DSP to extract 16 Mel-Frequency Cepstral Coefficients (MFCCs).
2. **Neural Network Architecture:**
   ```
   Input [16-d MFCC vector]
       │
       ├── Dense(48, relu) + L2(0.001) + BatchNormalization + Dropout(0.2)
       ├── Dense(24, relu) + Dropout(0.2)
       └── Dense(4, softmax) ──► [dry, wet/productive, whooping, normal]
   ```
3. **Wheeze & Stridor Sentinel:** Spectral rolloff and high-frequency centroid analysis trigger an immediate respiratory alert if wheeze patterns are identified.

---

### 2.6 rPPG Vital Sign Processor — Contactless Photoplethysmography
**Source Files:**
- Signal Processor: `intellidesk_backend/src/modules/diagnostics/vitals/rPPGSignalProcessor.ts`
- Filter: `intellidesk_backend/src/modules/diagnostics/vitals/ButterworthFilter.ts`

#### Signal Processing Pipeline
Extracts cardiovascular metrics from standard smartphone selfie video without wearable sensors:
1. **Region of Interest (ROI):** Tracks forehead and upper cheek facial vascular beds.
2. **Channel Decomposition:** Isolates the green channel (peak absorption of oxygenated hemoglobin at ~540nm).
3. **Temporal Resampling:** Resamples incoming frame luminance timestamps to a strict uniform 30.0 Hz grid.
4. **Butterworth Bandpass Filter:** Applies 2nd-order digital Butterworth filter with passband $[0.75, 3.5\text{ Hz}]$ ($45–210\text{ BPM}$).
5. **Peak Detection:** Fast Fourier Transform (FFT) identifies dominant frequency peak:
   $$\text{BPM} = f_{\text{peak}} \times 60$$
6. **Physiological Sentinel:** Flags tachycardia ($>110\text{ BPM}$) and bradycardia ($<50\text{ BPM}$).

---

### 2.7 Prescription OCR & Open ML Vision Pipeline
**Source Files:**
- OCR Parser: `intellidesk_backend/src/modules/pharmacy/PrescriptionOCRParser.ts`
- Fuzzy Matcher: `intellidesk_backend/src/modules/pharmacy/fuzzyMatcher.ts`
- RxNorm Store: `intellidesk_backend/src/modules/pharmacy/rxNormDataset.ts`

#### Multi-Tier Extraction & Normalization
1. **Open-Weight Vision ML Router:** Primary tier evaluates prescription images using hosted Vision-Language Models (`zai-org/GLM-4.6V-Flash`, `Qwen/Qwen2.5-VL-72B-Instruct`, `deepseek-ai/DeepSeek-V4-Flash-Vision-Exp` via Hugging Face Inference Router).
2. **Local PDF & Tesseract Fallback:** Secondary parser uses Poppler `pdftotext -layout` for clean digital PDFs; falls back to localized Tesseract.js v7.0 with OCR word confidence scoring.
3. **Clinical Token Sanitization:** Heuristic regex pipeline fixes optical character confusions:
   - Alphanumeric swaps: `5O0mg` → `500mg`, `1O0mg` → `100mg`.
   - Frequency patterns: `I-0-1`, `l-0-1` → `1-0-1`.
   - Shorthand fractions: `5/7` → `5 days`.
4. **Levenshtein Fuzzy Matching:** Compares extracted drug names against 8,000+ canonical entries in `rxNormDataset.ts`. Calculates similarity ratio:
   $$\text{similarity} = 1 - \frac{\text{Levenshtein}(s_1, s_2)}{\max(|s_1|, |s_2|)}$$
   Matches with similarity $\ge 0.75$ map to canonical RxNorm Concept Unique Identifiers (RxCUIs).

---

### 2.8 Dynamic Alternative Prescribing & Drug Interaction Safety
**Source Files:**
- Alternative Prescribing: `intellidesk_backend/src/modules/pharmacy/AlternativeMedicationService.ts`
- DDI Matrix: `intellidesk_backend/src/modules/pharmacy/DrugInteractionEngine.ts`
- Allergy Sentinel: `intellidesk_backend/src/modules/pharmacy/AllergySafetySentinel.ts`

#### Safety & Dynamic Substitution
1. **Live Clinical API Integration:** Integrates with the **NIH National Library of Medicine (NLM) RxNav & RxClass REST API** to resolve active RxCUIs and anatomical therapeutic classes (ATC).
2. **Non-Cross-Reactive Substitution:** When an allergy contraindication is detected (e.g. Penicillin allergy), `AlternativeMedicationService` queries non-cross-reactive pharmacological classes (e.g. Macrolides, Lincosamides), verifies against patient's other allergies, and dynamically attaches verified substitutes with clinical rationale and RxCUI provenance.
3. **8,000+ Drug Interaction Graph:** Classifies multi-drug regimens into 5 calibrated severity tiers:
   - `CONTRAINDICATED_SEVERE`: Extreme clinical danger (e.g., Warfarin + Aspirin hemorrhage, Sildenafil + Nitroglycerin fatal hypotension). Hard block requiring clinical review.
   - `MAJOR`: Significant clinical hazard requiring physician override.
   - `MODERATE_MONITOR`: Physiological interaction requiring active monitoring (e.g. Ciprofloxacin + Calcium chelation).
   - `MINOR`: Slight pharmacokinetic effect.
   - `SAFE`: Zero clinical conflict detected.

---

### 2.9 Clinical Patient-RAG Architecture (Retrieval-Augmented Generation)
**Source Files:**
- RAG Retriever: `intellidesk_backend/src/services/patientClinicalRagService.ts`
- Mental Health Chat: `intellidesk_backend/src/routes/chat.ts`
- Clinical Copay Chat: `intellidesk_backend/src/services/clinicalCounselorService.ts`

#### RAG Architecture & Context Synthesis
1. **Multi-Entity Parallel Retrieval:** Dynamically pulls patient records across 5 Supabase tables:
   - Demographics & Emergency Contacts (`profiles`)
   - Active Prescriptions & Dosages (`patient_medications`)
   - Documented Allergen Groups & Reactions (`patient_allergies`)
   - Contactless rPPG Vitals & Physiological Alerts (`health_screenings`)
   - Emergency Copay Allocations & Invoice Amounts (`claims`)
2. **Domain-Tuned Prompt Synthesis:** Converts clinical vectors into concise, token-budgeted prompt blocks:
   - `MENTAL_HEALTH`: Injects physiological vitals (pulse, stress index) and current therapy so counselors provide deep, empathetic clinical responses without raw data leakage.
   - `CLAIM_TRIAGE`: Injects exact claim status, billed sums, and medical categories so copay assistants directly resolve student financial anxiety.
3. **Privacy & Crisis Guardrails:** Zero cross-tenant data leakage. Critical life-safety regex patterns (`CRITICAL_SELF_HARM_REGEX`, `LIFE_SAFETY_REGEX`) immediately bypass conversational RAG to trigger one-tap crisis hotline intervention cards.


---

## 3. Crisis Response, NLP & Triage Models

### 3.1 PFA Crisis Counselor — Local ONNX Transformer
**Source File:** `intellidesk_backend/src/services/crisisCounselorService.ts`

#### Architecture
- **Model:** `Xenova/Qwen1.5-0.5B-Chat` running in-process via ONNX Runtime (WASM / CPU).
- **Secondary Fallback:** `onnx-community/Qwen2.5-0.5B-Instruct`.
- **Tertiary Fallback:** Deterministic Rogerian active-listening engine (zero-latency, 100% uptime).
- **Crisis Interception:** Multi-pattern regex (`CRITICAL_SELF_HARM_REGEX`) matches suicidal ideation or acute self-harm. Upon a match:
  - Sets `isCrisisResponse = true`.
  - Injects one-tap calling cards for 24/7 hotlines (Tele-MANAS 14416, 988 Lifeline).
  - Conversation runs 100% locally on CPU — zero text is transmitted to external cloud servers.

---

### 3.2 DeepRank — Crisis Severity Indexer & ESI Triage NN
**Source Files:**
- Training: `intellidesk_backend/src/ml/deep_rank.ts`
- Inference: `intellidesk_backend/src/services/deepRankModel.ts`

#### Architecture
```
Input [4 features: word_count, urgent_kw, sentiment_score, hist_count]
    │
    ├── Dense(64, relu) + L2(0.001) + BatchNormalization + Dropout(0.2)
    ├── Dense(32, relu) + L2(0.001) + BatchNormalization + Dropout(0.2)
    ├── Dense(16, relu)
    └── Dense(1, sigmoid) ──► Crisis Severity Index (CSI) ∈ [0.0, 1.0]
```

- **Optimizer:** Adam ($lr = 0.0005$).
- **Loss:** Mean Squared Error.
- **ESI Tier Mapping:**
  - $\text{CSI} \ge 0.85 \rightarrow \text{ESI-1 (Critical / Resuscitation)}$
  - $\text{CSI} \ge 0.60 \rightarrow \text{ESI-2 (Emergent)}$
  - $\text{CSI} \ge 0.35 \rightarrow \text{ESI-3 (Urgent)}$
  - $\text{CSI} < 0.35 \rightarrow \text{ESI-4 / ESI-5 (Routine)}$

---

### 3.3 Temporal Attrition LSTM — Longitudinal Health Risk
**Source Files:**
- Training: `intellidesk_backend/src/ml/lstm.ts`
- Inference: `intellidesk_backend/src/services/attritionModel.ts`

#### Architecture
- **Input Shape:** `[batch=1, timeSteps=1, features=4]`.
- **Recurrent Layer:** LSTM(32 units, returnSequences=false) + Dropout(0.2).
- **Dense Head:** Dense(16, relu) $\rightarrow$ Dense(1, sigmoid) outputting student health burnout / attrition probability in $[0, 1]$.
- Evaluates longitudinal sequences across the patient's last 10 medical encounters.

---

### 3.4 Grant Optimizer — Monte Carlo Dropout Neural Regression
**Source Files:**
- Training: `intellidesk_backend/src/ml/lstm.ts` (grant optimizer section)
- Inference: `intellidesk_backend/src/services/grantOptimizerModel.ts`

#### Architecture & Uncertainty Quantification
- **Input Features (5-d):** `[dropout_risk_score, requested_amount, historical_grant_total, fund_remaining_ratio, urgency_level_numeric]`.
- **Layers:** Dense(64, relu) + Dropout(0.3) $\rightarrow$ Dense(32, relu) + Dropout(0.2) $\rightarrow$ Dense(1, sigmoid).
- **Monte Carlo Dropout:** Runs 20 stochastic forward passes at inference time with dropout layers kept active. Calculates mean recommended grant ratio $\mu$ and epistemic variance $\sigma^2$.

---

### 3.5 Anomaly Autoencoder — Feature Reconstruction NN
**Source Files:**
- Training: `intellidesk_backend/src/ml/autoencoder.ts`
- Inference: `intellidesk_backend/src/services/anomalyModel.ts`

#### Architecture
- **Symmetric Architecture:** Input(4) $\rightarrow$ Dense(16, relu) $\rightarrow$ Dense(8, relu) [Bottleneck] $\rightarrow$ Dense(16, relu) $\rightarrow$ Output(4, sigmoid).
- **Anomaly Scoring:** Computes Mean Squared Error (MSE) between original feature vector $x$ and reconstructed output $\hat{x}$:
  $$\text{MSE} = \frac{1}{4} \sum_{i=1}^4 (x_i - \hat{x}_i)^2$$
  Submissions with $\text{MSE} \ge 0.75$ are flagged for anomalous pattern review.

---

## 4. In-Process Model Training & Continuous Learning

### Master Training Script (`npm run train:ml`)
Executes `src/ml/train_all.ts` to build and persist all local TensorFlow.js models:
```bash
npm run train:ml
# 1. Trains DeepRank CSI Dense NN
# 2. Trains TemporalAttritionLSTM
# 3. Trains AnomalyAutoencoder
# 4. Saves model.json and binary weight shards to intellidesk_backend/models/
```

### Online Continuous Learning (`mlRetrainingWorker.ts`)
The background retraining worker runs on a scheduled BullMQ queue:
1. Queries Supabase for newly resolved claims with clinician-adjudicated triage outcomes.
2. Formulates labeled training batches.
3. Calls `fineTuneDeepRankModel()` and `fineTuneGrantOptimizerModel()`, running 5 epochs of in-memory Adam fine-tuning.
4. Serializes updated weights back to disk, completing the human-in-the-loop adaptive feedback cycle.
