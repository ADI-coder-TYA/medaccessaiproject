# MedAccess AI — Complete System Architecture Specification

> **Comprehensive engineering architecture reference:** Multi-tier topology, clinical diagnostics & vision pipelines, WHO ICD-11 CDSS framework, pharmacy safety, BullMQ background processing, database schema with Row-Level Security, and Flutter MVVM architecture.

---

## 1. System Topology & Tier Architecture

MedAccess AI is architected as an offline-resilient, hybrid edge-cloud medical platform:

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                         MedAccess AI Flutter Client (Mobile & Web)                     │
│                                                                                        │
│   Patient Clinical Portal                         Admin Clinical War Room              │
│   ───────────────────────                         ───────────────────────              │
│   • Dermatology / Lesion Scan (Camera)           • ESI Triage Queue (DeepRank sorted) │
│   • Acoustic Cough Capture (16kHz Audio)          • Grad-CAM Visual Heatmap Review     │
│   • Contactless rPPG Vitals (Video Pulse)         • CDSS Differential Diagnosis Review │
│   • Prescription OCR & 8,000+ DDI Checker         • Clinician Diagnostic & ESI Override│
│   • PFA Crisis Chat (Local Qwen ONNX)             • Copay Liquidity & Payout Modal     │
│   • Emergency Copay Status Tracker                • Clinical Encounter Reports     │
└──────────────────────────────────────────▲─────────────────────────────────────────────┘
                                           │  REST + WebSocket (Socket.io)
┌──────────────────────────────────────────▼─────────────────────────────────────────────┐
│                 MedAccess Backend API (Express 5 / TypeScript / Node.js ESM)           │
│                                                                                        │
│  /api/v1/auth              JWT Authentication & Tenant Scoping                         │
│  /api/v1/diagnostics       Multimodal Vision (Qwen2.5-VL), Cough ML, rPPG Vitals       │
│  /api/v1/cdss              WHO ICD-11 Differential Engine & HL7 FHIR R4 Converter      │
│  /api/v1/pharmacy          Open-ML Prescription OCR, 8,000+ DDI & NLM RxNav Alt Engine│
│  /api/v1/chat              Patient-RAG Mental Health & Confidential PFA Chat           │
│  /api/v1/claims/:id/messages Patient-RAG Emergency Copay Dialogue & Status Assistant     │
│  /api/v1/intake/web        Asynchronous Claim Ingestion $\rightarrow$ BullMQ Processing Queue   │
│  /api/v1/claims            Clinical Triage CRUD, CSI Filtering & Encounter Telemetry   │
│  /api/v1/admin             Clinician Overrides & Real-Time Telemetry Dashboards        │
│  /api/v1/claims/:id/disburse Instant Multi-Rail Copay Disbursement (RazorpayX/Stripe) │

└──────────────┬──────────────────────────────────────────┬──────────────────────────────┘
               │                                          │
    Job Events │ BullMQ (Redis 7)                  Query  │ SQL / RLS
               ▼                                          ▼
┌──────────────────────────────────────────┐   ┌─────────────────────────────────────────┐
│       Distributed BullMQ Workers         │   │      Supabase PostgreSQL + pgvector     │
│  ────────────────────────────────        │   │  ─────────────────────────────────────  │
│  Intake Worker (10-Step Pipeline):       │   │  institutions (multi-tenancy partitioning)│
│  • Poppler pdftotext & Tesseract.js OCR  │   │  profiles (RBAC: STUDENT/ADMIN/CLINICIAN)│
│  • SHA-256 Receipt Deduplication Hash    │   │  tickets (clinical encounters & ESI)    │
│  • Fraud Sentinel & Autoencoder MSE      │   │  ticket_messages (PFA chat history)     │
│  • DeepRank CSI Prediction & ESI Tier    │   │  health_funds & vouchers (copay pools)  │
│  • Temporal Attrition LSTM Health Risk   │   │  activity_logs (clinical event records) │
│  • Grant Optimizer (MC Dropout Bounds)   │   │  policies (pgvector 768-d embeddings)   │
│  • Gemini Multimodal & RAG Matching      │   │  (Row-Level Security active on all DB)  │
│  • Socket.io Real-Time Broadcast         │   └─────────────────────────────────────────┘
│                                          │
│  ML Retraining Worker:                   │
│  • In-process Adam fine-tuning on        │
│    verified clinician outcomes (5 epochs)│
│                                          │
│  Notification Worker:                    │
│  • Transactional Email (Resend)          │
│  • Emergency Life-Safety SMS (Twilio)    │
└──────────────────────────────────────────┘
```

---

## 2. Multimodal Diagnostic Sensing & CDSS Architecture

MedAccess AI decomposes clinical decision-making into dedicated diagnostic micro-engines:

```
                                  PATIENT PRESENTATION
                                           │
         ┌─────────────────────────────────┼─────────────────────────────────┐
         │ Visual                          │ Acoustic                        │ Physiological
         ▼                                 ▼                                 ▼
┌───────────────────┐             ┌──────────────────┐             ┌───────────────────┐
│ Dermatology Photo │             │  Cough Recording │             │  Facial Video     │
│ (Rash, Burn, Eye) │             │  (16kHz WAV)     │             │  (30 FPS Stream)  │
└────────┬──────────┘             └────────┬─────────┘             └─────────┬─────────┘
         │                                 │                                 │
         │ sharp normalization             │ Meyda.js DSP                    │ Green-Channel ROI
         ▼                                 ▼                                 ▼
┌───────────────────┐             ┌──────────────────┐             ┌───────────────────┐
│ Qwen2.5-VL 72B    │             │ 16-d MFCC Vector │             │ Butterworth Filter│
│ (Cloud VLM)       │             └────────┬─────────┘             │ (0.75 - 3.5 Hz)   │
│                   │                      │                       └─────────┬─────────┘
│ Fallback:         │                      ▼                                 │
│ MobileNet-V3      │             ┌──────────────────┐                       ▼
└────────┬──────────┘             │ CoughClassifier  │             ┌───────────────────┐
         │                        │ (4-Class TF.js)  │             │ Heart Rate (BPM)  │
         │                        └────────┬─────────┘             │ SpO2 & Red Flags  │
         │                                 │                       └─────────┬─────────┘
         └─────────────────────────────────┼─────────────────────────────────┘
                                           │
                                           ▼
                       ┌──────────────────────────────────────┐
                       │     Multimodal Fusion DNN (168-d)    │
                       │  [128 visual + 32 symptom + 8 demo]  │
                       └───────────────────┬──────────────────┘
                                           │
                                           ▼
                       ┌──────────────────────────────────────┐
                       │ CDSS & WHO ICD-11 Differential Engine│
                       │   • Qwen2.5-72B Evidence Pathway     │
                       │   • Logit Scorer (T=1.25, [-20, 20]) │
                       │   • HL7 FHIR R4 Bundle Export        │
                       └───────────────────┬──────────────────┘
                                           │
                                           ▼
                       ┌──────────────────────────────────────┐
                       │ DeepRank ESI Triage & Copay Optimizer│
                       │   • Crisis Severity Index (CSI 0-1)  │
                       │   • ESI Levels 1 to 5 Classification │
                       │   • MC Dropout Copay Grant Estimate  │
                       └──────────────────────────────────────┘
```

---

## 3. Database Schema Specification (PostgreSQL / Supabase)

Every database table is protected by **Row-Level Security (RLS)**. Multi-tenancy is enforced by partitioning records with `institution_id`.

### 3.1 `institutions` — Multi-Tenancy Partition
| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | TEXT | PRIMARY KEY | Tenant identifier (e.g. `campus-health-001`) |
| `name` | TEXT | NOT NULL | Display name of the institution |
| `domain` | TEXT | NOT NULL | Allowed email domain whitelist |
| `currency` | TEXT | DEFAULT 'INR' | Base currency (`INR` or `USD`) |

### 3.2 `profiles` — User Identity & RBAC
| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | PRIMARY KEY, REFERENCES `auth.users.id` | User identity |
| `email` | TEXT | UNIQUE, NOT NULL | University email address |
| `role` | TEXT | NOT NULL | `STUDENT`, `ADMIN`, or `CLINICIAN` |
| `institution_id` | TEXT | REFERENCES `institutions.id` | Multi-tenant scoping |
| `name` | TEXT | | Full name |
| `phone` | TEXT | | Phone number for emergency SMS |

### 3.3 `tickets` — Clinical Encounter & Claim Record
| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | PRIMARY KEY | Unique clinical encounter ID |
| `institution_id` | TEXT | REFERENCES `institutions.id` | Tenant partition |
| `student_id` | UUID | REFERENCES `profiles.id` | Patient reference |
| `raw_message` | TEXT | NOT NULL | Narrative symptom / emergency text |
| `media_url` | TEXT | | Medical invoice or clinical photo URL |
| `parsed_category` | TEXT | | Clinical category classification |
| `urgency_level` | TEXT | | ESI tier: `ESI_1_CRITICAL` to `ROUTINE` |
| `status` | TEXT | DEFAULT 'Pending' | `Pending` $\rightarrow$ `Triage Active` $\rightarrow$ `Approved` / `Disbursed` |
| `calculated_amount` | NUMERIC | | OCR-extracted bill / copay amount |
| `crisis_severity_index`| NUMERIC | | DeepRank continuous score ($0.0–1.0$) |
| `dropout_risk_score` | NUMERIC | | Longitudinal health burnout score ($0.0–1.0$) |
| `recommended_grant_amount`| NUMERIC | | Grant Optimizer suggested copay relief |
| `fraud_risk_score` | NUMERIC | | Fraud Sentinel multi-layer composite score |
| `receipt_image_hash` | TEXT | | Cryptographic SHA-256 deduplication hash |
| `anomaly_reconstruction_score`| NUMERIC | | Autoencoder feature reconstruction MSE |
| `embedding` | vector(768) | | Semantic embedding for RAG policy retrieval |

### 3.4 `ticket_messages` — Confidential PFA Log
| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | PRIMARY KEY | Message identifier |
| `ticket_id` | UUID | REFERENCES `tickets.id` | Parent encounter |
| `sender` | TEXT | NOT NULL | `STUDENT`, `COUNSELOR_AI`, or `HUMAN_ADMIN` |
| `message` | TEXT | NOT NULL | Message content |
| `is_crisis_response`| BOOLEAN | DEFAULT FALSE | Flagged true on self-harm detection |
| `suggested_resources`| JSONB | | Array of 24/7 crisis hotline cards |

### 3.5 `activity_logs` — System Event Logs
| Column | Type | Constraints | Description |
|---|---|---|---|
| `id` | UUID | PRIMARY KEY | Event record identifier |
| `institution_id` | TEXT | NOT NULL | Tenant scoping |
| `ticket_id` | UUID | | Associated encounter ID |
| `action_type` | TEXT | NOT NULL | `ESI_OVERRIDE`, `DIAGNOSTIC_CONFIRM`, `DISBURSEMENT` |
| `actor_type` | TEXT | NOT NULL | `CLINICIAN`, `ADMIN`, or `AI_SYSTEM` |
| `details` | JSONB | NOT NULL | Structured telemetry payload & clinical rationale |
| `created_at` | TIMESTAMPTZ | DEFAULT NOW() | Tamper-evident timestamp |

---

## 4. Background Processing Pipelines (BullMQ / Redis)

### 4.1 10-Step Intake & Triage Pipeline (`intakeWorker.ts`)
```
Job Enqueued (claim_id, raw_message, media_url)
         │
         ├─ Step 1: Receipt / Document Parsing (Poppler pdftotext / Tesseract OCR)
         ├─ Step 2: Clinical NLP Extraction (DistilBERT sentiment + Urgent RegEx)
         ├─ Step 3: Fraud Sentinel Check (SHA-256 hash + 7-day velocity + Autoencoder)
         ├─ Step 4: DeepRank CSI Inference (Computes Crisis Severity Index in [0, 1])
         ├─ Step 5: ESI Tier Assignment (Maps CSI to ESI-1 through ESI-5)
         ├─ Step 6: Temporal Attrition Risk (Evaluates longitudinal health burnout via LSTM)
         ├─ Step 7: Copay Grant Optimization (MC Dropout uncertainty regression)
         ├─ Step 8: Multimodal Intake Parsing (Gemini 2.0 Flash structured triage)
         ├─ Step 9: Policy Match & RAG (pgvector 768-d search + Gemini 1.5 Pro CoT)
         └─ Step 10: Supabase Persistence & Real-Time Socket.io Broadcast
```

### 4.2 In-Process Continuous Learning (`mlRetrainingWorker.ts`)
- Queries resolved tickets with verified clinician outcomes.
- Executes 5 epochs of Adam fine-tuning on DeepRank CSI and Grant Optimizer models in Node.js.
- Persists updated weights to `intellidesk_backend/models/` without restarting the server.

### 4.3 Notification Dispatch (`notificationWorker.ts`)
- Transmits email encounter receipts via Nodemailer / Resend.
- Sends emergency SMS via Twilio for all ESI-1 Resuscitation events.

---

## 5. Flutter MVVM Architecture & Module Map

```
intellidesk_app/lib/
├── main.dart                          # App bootstrap, MultiProvider tree, routing table
├── config/                            # Environment constants & API hostnames
├── models/                            # Domain entities (Claim, Message, Fund, Helpline)
├── services/                          # Network, edge ML, and offline services
│   ├── clinical_api_service.dart      # REST client for Vision, Audio, Vitals, CDSS, Pharmacy
│   ├── socket_service.dart            # WebSocket connection with institution rooms
│   └── offline_sync_engine.dart       # SharedPreferences caching for offline triage
├── providers/                         # Reactive ViewModels (ChangeNotifier)
│   ├── auth_provider.dart             # Session lifecycle, RBAC, JWT
│   ├── claims_provider.dart           # ESI-sorted triage queue & search state
│   ├── clinical_chat_provider.dart    # Confidential PFA multi-turn conversation
│   ├── war_room_provider.dart         # Clinical telemetry & fund liquidity KPIs
│   └── ticket_provider.dart           # Patient health encounter tracker
└── screens/                           # View presentation layer
    ├── patient/
    │   ├── patient_clinical_dashboard.dart # Main hub: Vision, Cough, Vitals launchpad
    │   ├── pharmacy_hub_screen.dart        # Prescription OCR & 8,000+ DDI checker
    │   ├── health_records_screen.dart      # Longitudinal history & FHIR R4 viewer
    │   ├── claim_intake_screen.dart        # Multimodal submission (photo/bill/audio)
    │   ├── clinical_chat_screen.dart       # Local Qwen ONNX PFA chat interface
    │   ├── claim_status_screen.dart        # ESI level badge & copay progress bar
    │   └── emergency_hub_screen.dart       # One-tap 24/7 crisis hotline directory
    └── admin/
        ├── admin_clinical_diagnoses_screen.dart # Diagnostic VLM, Grad-CAM & CDSS evaluation
        ├── admin_war_room_screen.dart           # ESI triage queue & one-tap payout modal
        ├── admin_health_funds_screen.dart       # Copay pool management
        ├── admin_knowledge_base_screen.dart     # Policy RAG semantic search
        └── admin_main_screen.dart               # Responsive shell navigation
```

---

## 6. Security, Compliance & Governance

- **Data Isolation & Governance:** Row-Level Security ensures tenant isolation. Every diagnostic and override decision is written to a structured event record containing full JSONB context.
- **FERPA Redaction:** Gemini 1.5 Flash strips acute diagnostic conditions from professor notification letters, replacing them with generic medical excuse phrasing.
- **Crisis Life-Safety Bypass:** Suicidal ideation or acute life-safety keywords immediately bypass non-critical velocity and rate-limit restrictions.
