# MedAccess AI — Clinical & User Operational Guide

> **Real-world operational manual for patients, students, and clinical practitioners.**  
> Step-by-step clinical workflows covering multimodal computer vision diagnostics, acoustic cough screening, contactless rPPG vitals, WHO ICD-11 clinical decision support (CDSS), pharmacy safety intelligence, confidential Psychological First Aid (PFA), and emergency copay triage.

---

## 📑 User Roles & Permissions

| Role | Access Level | Primary Clinical & Operational Capabilities |
|---|---|---|
| **Patient / Student** | `STUDENT` | Camera dermatology scans, cough audio analysis, contactless rPPG vitals, prescription OCR & DDI checks, confidential PFA chat, emergency copay relief |
| **Clinician / Triage Officer** | `ADMIN` | Real-time ESI emergency triage queue, Grad-CAM visual explainability reviews, WHO ICD-11 CDSS evaluation, prescription approval, copay disbursement |
| **Medical Auditor / CMO** | `AUDITOR` | Read-only compliance review, immutable HIPAA audit trail analysis, cryptographic SHA-256 report verification |

---

## Workflow 1: Patient Performs a Dermatology & Lesion Vision Scan

### Clinical Context
Sarah notices a rapidly spreading erythematous skin rash on her forearm accompanied by localized itching and mild heat. She wants an immediate preliminary assessment before visiting the health center.

### Step-by-Step Instructions

**1. Open Patient Clinical Dashboard**
- Launch the MedAccess AI app on your smartphone.
- Sign in with your university credentials.
- In the top action bar, tap **"Scan Lesion / Rash"** (or open the **Dermatology Vision** tile).

**2. Capture Clinical Image**
- Hold the phone camera 10–15 cm from the skin under good lighting.
- Ensure the rash is in clear focus without glare or motion blur.
- Tap the capture button (or select an existing photo from your gallery).
- Select the anatomical site: **"Forearm / Arm"**.

**3. Automated Multimodal Processing**
The app automatically performs:
- Image normalization and orientation correction via `sharp`.
- Dispatch to **Qwen2.5-VL 72B** multimodal cloud vision classifier (or on-device **Clinical MobileNet-V3** if offline).
- Generation of a **Grad-CAM Saliency Heatmap**.

**4. View Diagnostic Evaluation**
Within 2–4 seconds, the diagnostic results screen displays:
```
Condition:               Contact Dermatitis (Moderate Severity)
Primary Site:            Forearm (Right)
Confidence:              92.4%
Pathological Findings:   Well-demarcated erythematous plaque, micro-vesicles, mild edema

Differential Diagnoses:
  1. Acute Contact Dermatitis (82.1%)
  2. Nummular Eczema (11.3%)
  3. Tinea Corporis (6.6%)

Recommended Action:      Cold compress, topical hydrocortisone 1%, avoid allergen contact.
                         Flagged for clinical consultation at campus health.
```

**5. Inspect Grad-CAM Heatmap**
- Tap **"View Visual Explainability"**.
- A false-color heatmap overlays the image: bright red and yellow highlights pinpoint the concentrated inflammatory boundary, confirming the model focused on genuine cutaneous pathology rather than background skin or lighting artifacts.
- Tap **"Save to Health Records"** to automatically attach the encounter to your permanent longitudinal profile.

---

## Workflow 2: Patient Conducts Acoustic Cough Respiratory Screening

### Clinical Context
Marcus has had a persistent nocturnal cough for 4 days and feels mild chest tightness. He wants to know if his cough exhibits wet, dry, or whooping characteristics.

### Step-by-Step Instructions

**1. Access Acoustic Screening**
- From the **Patient Clinical Dashboard**, tap **"Acoustic Cough Check"**.
- Position the phone microphone approximately 20 cm from your mouth.
- Ensure the surrounding room is quiet.

**2. Record Cough Sample**
- Tap the red **"Record Cough"** microphone button.
- Cough naturally 2 to 3 times over a 5-second window.
- The app visualizes the incoming 16kHz uncompressed acoustic waveform in real time.

**3. Digital Signal Processing (DSP) & Inference**
The app instantly extracts 16 Mel-Frequency Cepstral Coefficients (MFCCs) using Meyda.js DSP and executes the **CoughClassifier Neural Network**:
```
Cough Classification Breakdown:
  • Wet / Productive Cough:   74.2%  ███████████████░░░░░
  • Dry / Irritative Cough:   18.1%  ████░░░░░░░░░░░░░░░░
  • Normal / Non-Pathologic:   5.4%  █░░░░░░░░░░░░░░░░░░░
  • Whooping Signature:        2.3%  ░░░░░░░░░░░░░░░░░░░░

Acoustic Alert Status:       HIGH-FREQUENCY WHEEZE DETECTED
Clinical Interpretation:     Acoustic signatures suggest lower respiratory tract secretions.
                             Wheeze indicator indicates mild bronchial constriction.
```

**4. Next Steps**
- If high-frequency wheeze or whooping signatures are identified, the app surfaces an **"Escalate to Urgent Care"** prompt.
- With one tap, Marcus routes the acoustic findings directly to the campus health center triage queue.

---

## Workflow 3: Contactless Camera Vitals (rPPG Photoplethysmography)

### Clinical Context
Priya feels dizzy and lightheaded after intense exertion and wants to check her resting heart rate and physiological stability without a smartwatch or cuff.

### Step-by-Step Instructions

**1. Open rPPG Vitals Monitor**
- In the **Patient Clinical Dashboard**, tap **"Camera Vitals (rPPG)"**.
- Position your face inside the on-screen oval guide.
- Sit still and avoid talking for 15 seconds under steady ambient lighting.

**2. Video Photoplethysmography Extraction**
- The app camera samples micro-vascular green-channel light absorption at 30 Hz.
- A 4th-order zero-phase **Butterworth Bandpass Filter** ($0.75–3.5\text{ Hz}$) removes motion drift and isolates the arterial pulse wave.

**3. Real-Time Physiological Output**
```
Heart Rate:              108 BPM (Mild Tachycardia)
Confidence Score:        94.8%
Signal Quality Index:    HIGH (Uniform 30.0 Hz Resampled)
Estimated SpO2:          98%

Physiological Sentinel:  ⚠️ ELEVATED RESTING HEART RATE DETECTED (>100 BPM)
Guidance:                Rest seated for 5 minutes, hydrate, and re-test.
```

---

## Workflow 4: Prescription OCR & Drug-Drug Interaction (DDI) Safety

### Clinical Context
David is taking an SSRI antidepressant (Sertraline) and receives a new handwritten prescription from an external clinic for migraine relief (Sumatriptan). He wants to verify that the combination is safe before taking both.

### Step-by-Step Instructions

**1. Open Pharmacy Hub**
- In the app bottom navigation, tap **"Pharmacy Hub"**.
- Tap **"Scan New Prescription"**.

**2. Photograph Prescription**
- Capture a clear photo of the physician's handwritten or typed prescription script.
- The hybrid Poppler/Tesseract OCR engine extracts the text and applies character error sanitization (correcting common OCR confusions like O/0, I/1).
- The **fuzzy RxNorm matcher** maps the medication to standardized identifiers:
  - Extracted: `Sumatriptan 50mg oral tablet` $\rightarrow$ **RxCUI: 313146**

**3. Automated Drug-Drug Interaction (DDI) Cross-Check**
The **DrugInteractionEngine** checks David's active medication list (Sertraline) against the newly scanned prescription (Sumatriptan) across 8,000+ interaction pairs:

```
🚨 PHARMACY SAFETY CONTRAINDICATION DETECTED

Severity:       MAJOR INTERACTION (SEROTONIN SYNDROME HAZARD)
Drug 1:         Sertraline (SSRI Antidepressant)
Drug 2:         Sumatriptan (5-HT1 Receptor Agonist)

Clinical Mechanism:
Both medications elevate central nervous system serotonergic activity. Concomitant
administration increases the risk of Serotonin Toxicity (tremor, hyperthermia, rigidity).

Recommendation:
DO NOT INGEST TOGETHER without direct physician consultation.
Alternative migraine abortive therapies (e.g., NSAIDs, acetaminophen) recommended.
```

**4. Clinical Resolution**
- David taps **"Share Contraindication Report with Clinician"**.
- An encrypted summary is pushed directly to the campus health pharmacy desk for immediate medication substitution.

---

## Workflow 5: Confidential Psychological First Aid (PFA) & Crisis Triage

### Clinical Context
Ananya is experiencing severe academic burnout, sleep deprivation, and overwhelming emotional distress. She needs a confidential space to process her feelings at 2:00 AM.

### Step-by-Step Instructions

**1. Open Clinical Chat**
- Tap **"Talk to Counselor"** in the app menu.
- Note the privacy banner: *"100% on-device AI model. No messages leave your device without your explicit permission."*

**2. Chat with PFA AI**
- Ananya begins typing:
  ```
  Ananya: "I can't take this pressure anymore. I haven't slept in three days and I feel
  like giving up completely."
  ```
- Within 800 milliseconds, the local **Qwen1.5-0.5B ONNX** model responds using Rogerian reflective listening:
  ```
  Counselor AI: "I hear how exhausted and overwhelmed you are right now. Carrying that
  kind of pressure alone for days is so draining. Let's take a slow breath together.
  You are safe here, and university support services are actively here for you."
  ```

**3. Life-Safety Crisis Protocol**
If messages contain acute self-harm triggers (e.g., *"I want to end my life"*):
- **Immediate Interception (<300ms):**
  - Conversation triggers `CRITICAL_SELF_HARM_REGEX`.
  - The local AI halts open-ended generation and displays a gentle grounding exercise.
  - A slide-up card stack displays **One-Tap 24/7 Crisis Helplines**:
    - **Tele-MANAS (India):** `14416` [Call Now]
    - **988 Suicide & Crisis Lifeline (US):** `988` [Call Now]
    - **Vandrevala Foundation:** `+91 9999 666 555` [Call Now]
    - **Campus Emergency Triage Desk:** `1800-MED-ACCESS` [Call Now]

**4. Proactive Welfare Relief**
If the conversation reveals financial hardship (e.g., medical bills, rent distress):
- The AI proactively asks: *"Would you like me to submit an Emergency Health Grant ticket for campus welfare review?"*
- Tapping **"Yes, Submit Ticket"** generates an automated emergency claim without requiring forms.

---

## Workflow 6: Emergency Copay Relief & Medical Welfare Disbursement

### Clinical Context
Alex was admitted to the hospital with a sports fracture and acute surgical copay of ₹14,000 that must be settled upon discharge.

### Step-by-Step Instructions

**1. Submit Emergency Claim**
- Open **Claim Intake Screen**.
- Enter a brief summary: *"Admitted to City Hospital for radial fracture surgery. Need emergency copay assistance for hospital discharge."*
- Attach the hospital bill PDF. Tap **"Submit Claim"**.

**2. Background Automated Triage (30 Seconds)**
The 10-step BullMQ intake worker runs:
- Tesseract.js / Poppler parses invoice total: `₹14,000`.
- Fraud Sentinel verifies receipt image hash (SHA-256) and evaluates Autoencoder reconstruction score ($	ext{MSE} = 0.11$, normal).
- **DeepRank Neural Network** evaluates narrative and medical keywords:
  - Crisis Severity Index (CSI): **0.78** $ightarrow$ **ESI-2 Emergent**.
- **Grant Optimizer** calculates recommended grant with Monte Carlo Dropout uncertainty:
  - Recommended Amount: **₹11,200** (80% coverage) $pm 	ext{₹450}$ variance.

**3. Real-Time Tracking**
- Alex's status screen updates from 🟡 `Submitted` $ightarrow$ 🔵 `Triage Active` with an orange **ESI-2 Emergent** badge.

**4. Instant Disbursement**
- Once the campus medical administrator approves the case in the War Room:
- Funds are transferred via RazorpayX (UPI/IMPS) or Stripe in under 2 minutes.
- Alex receives a push alert with transaction reference `pout_8492048` and hospital discharge receipt PDF.

---

## Workflow 7: Clinician Manages War Room, Grad-CAM & CDSS

### Clinical Context
Dr. Chen, Chief Medical Officer, reviews active overnight emergency cases and AI diagnostic findings from the campus health center war room.

### Step-by-Step Instructions

**1. Log In to Admin War Room**
- Launch MedAccess AI and log in with clinician credentials (`role: 'ADMIN'`).
- The triage queue displays real-time encounters ordered strictly by **Crisis Severity Index (highest urgency first)**.

**2. Evaluate ESI-1 and ESI-2 Cases**
- Dr. Chen clicks the top case (Alex J., Fracture + Surgical Copay, CSI: 0.78).
- The slide-up clinical panel displays:
  - Bill Total: `₹14,000` (OCR-verified).
  - DeepRank ESI Level: `ESI_2_EMERGENT`.
  - Fraud Sentinel Risk: `0.08 (LOW)`.
  - Grant Optimizer: Recommended `₹11,200`.
- Dr. Chen taps **"Approve & Disburse"** $ightarrow$ selects Instant UPI payout $ightarrow$ confirms.

**3. Inspect Multimodal Diagnostic Encounters**
- Dr. Chen opens **"Clinical Diagnoses Review"** tab:
  - **Dermatology Review:** Views Sarah's contact dermatitis encounter. Inspects the original photo alongside the **Grad-CAM Saliency Heatmap**. Verifies the red heatmap focuses strictly on localized forearm erythema.
  - **CDSS Differential Panel:** Inspects WHO ICD-11 calibrated probabilities:
    - *L23.9 Allergic contact dermatitis:* **82.1%** ($z = 14.2$, $T = 1.25$).
  - **Acoustic Audio Player:** Listens to Marcus's cough audio; inspects the MFCC spectrogram showing wheeze frequency peaks.
- Dr. Chen confirms the AI recommendations and clicks **"Export HL7 FHIR R4 Bundle"** to sync with the university hospital EMR.

**4. Generate Monthly HIPAA Audit Report**
- Navigate to **"Compliance Audit"** in the sidebar.
- Select date range: `01 Aug 2026 - 31 Aug 2026`.
- Click **"Generate Audit PDF"**.
- System compiles an institutional report containing all ESI decisions, overrides, and fund ledgers, complete with an embedded **SHA-256 cryptographic tamper-evident checksum**.

---

## Frequently Asked Questions (FAQ)

**Q: Are camera photos and voice recordings sent to external cloud companies?**  
A: No. Privacy is prioritized by design:
- Local offline models (Clinical MobileNet-V3, TFLite CoughClassifier, and Xenova Qwen ONNX) execute **entirely on-device**.
- Cloud VLM calls (Qwen2.5-VL 72B) only execute when network is available and clinical detail requires 72B-parameter resolution. All Protected Health Information (PHI) is automatically redacted before API transmission.

**Q: Can clinicians override AI diagnosis and triage recommendations?**  
A: Yes. MedAccess AI is strictly an **AI-First, Human-in-the-Loop** system. Clinicians can override any diagnostic classification or ESI level at any time with documented clinical rationale, which is immutably logged in the HIPAA audit trail.

**Q: What happens if there is no internet connection at the health center?**  
A: The mobile client uses the **OfflineSyncEngine**:
- Clinical MobileNet-V3 evaluates dermatology images on-device.
- The 4th-order zero-phase Butterworth filter computes rPPG vitals locally.
- PFA chat uses the local on-device Qwen ONNX model.
- Screenings and notes are cached in encrypted local storage and sync to the server immediately upon reconnection.

---

## Emergency Support Contacts

| Service | Contact Information | Availability |
|---|---|---|
| **Tele-MANAS (National Mental Health, India)** | `14416` / `1800-891-4416` | 24 Hours / 7 Days |
| **988 Suicide & Crisis Lifeline (US & Canada)** | `988` (Call or Text) | 24 Hours / 7 Days |
| **Vandrevala Foundation Helplines** | `+91 9999 666 555` | 24 Hours / 7 Days |
| **MedAccess Campus Emergency Desk** | `1800-MED-ACCESS` | 24 Hours / 7 Days |
| **Technical & EMR Integration Support** | `support@medaccess.ai` | Office Hours |
