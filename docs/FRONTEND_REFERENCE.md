# MedAccess AI — Frontend Architecture Reference

> **Complete architectural reference for the Flutter client:** MVVM pattern, Provider state management, Clinical Diagnostics & Vision Suite, CDSS & Pharmacy Hubs, Real-Time Socket.io integration, on-device edge ML, and accessibility design system.

---

## 1. Project & Technology Overview

The MedAccess AI mobile and web frontend is engineered with Flutter, delivering hospital-grade clinical diagnostics, real-time emergency triage, and confidential Psychological First Aid (PFA) across iOS, Android, Desktop, and Web.

| Technology | Version / Package | Architectural Role |
|---|---|---|
| **Framework** | Flutter 3.29+ (Dart SDK ^3.10.7) | High-performance multi-platform UI runtime |
| **State Management** | `provider` ^6.1.5 | Reactive MVVM architecture with ChangeNotifier |
| **Edge ML Execution** | `tflite_flutter` | On-device inference for quantized clinical vision & cough models |
| **Audio Capture** | `record` ^5.2.1 | High-fidelity 16kHz uncompressed acoustic capture for respiratory cough analysis |
| **Camera & Video** | `camera` ^0.11.0 + `image_picker` | High-resolution capture for dermatology, wounds, and 30Hz rPPG vitals |
| **Real-Time Telemetry** | `socket_io_client` ^3.1.6 | Low-latency bi-directional WebSocket connection with institution rooms |
| **Data Visualization** | `fl_chart` ^1.2.0 | ESI triage distribution, fund liquidity, and longitudinal health risk charts |
| **Offline Resilience** | `shared_preferences` ^2.5.5 | Local persistent storage with `OfflineSyncEngine` caching |
| **Local Alerts** | `flutter_local_notifications` ^22.2.0 | Device push notifications for emergent ESI-1 triage updates |
| **Networking** | `http` ^1.6.0 | RESTful HTTP client with token injection & tenant scoping |
| **Typography** | `google_fonts` ^8.2.1 | Clean, high-legibility clinical typography (Outfit / Inter) |

---

## 2. MVVM Architecture Pattern

The application strictly separates visual presentation, UI state/business logic, and network/edge infrastructure:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                               VIEW LAYER                                │
│                     (lib/screens/patient & admin/*.dart)                │
│   • Renders diagnostic camera previews, acoustic waveforms, heatmaps    │
│   • Subscribes reactively via context.watch<T>()                        │
│   • Dispatches user events via context.read<T>()                        │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ ChangeNotifier updates
┌────────────────────────────────────▼────────────────────────────────────┐
│                             VIEWMODEL LAYER                             │
│                         (lib/providers/*.dart)                          │
│   • AuthProvider: Session lifecycle, JWT tokens, RBAC routing           │
│   • ClaimsProvider: ESI-sorted triage queue, status filters, search     │
│   • ClinicalChatProvider: PFA multi-turn conversation, crisis cards     │
│   • WarRoomProvider: Real-time clinical telemetry & ESI statistics      │
│   • TicketProvider: Patient-side encounter tracking & FHIR records      │
│   • JobTrackingManager: Async BullMQ queue polling with step progress    │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ async service invocations
┌────────────────────────────────────▼────────────────────────────────────┐
│                          INFRASTRUCTURE LAYER                           │
│                          (lib/services/*.dart)                          │
│   • ClinicalApiService: REST routes for Vision, CDSS, Audio, Vitals     │
│   • SocketService: WebSocket event subscription & push notifications    │
│   • OfflineSyncEngine: Local storage caching & network reconnection sync│
│   • Edge TFLite Plugins: In-app inference for offline MobileNet-V3      │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Provider Tree (`main.dart`)

The application root configures dependency injection through a global `MultiProvider` tree wrapping the `MaterialApp`:

```dart
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AuthProvider()),
    ChangeNotifierProvider(create: (_) => ClaimsProvider()),
    ChangeNotifierProvider(create: (_) => ClinicalChatProvider()),
    ChangeNotifierProvider(create: (_) => WarRoomProvider()),
    ChangeNotifierProvider(create: (_) => TicketProvider()),
    ChangeNotifierProvider(create: (_) => PreferencesProvider()),
    ChangeNotifierProvider(create: (_) => AccessibilityProvider()),
    ChangeNotifierProvider(create: (_) => JobTrackingManager()),
  ],
  child: MaterialApp(
    title: 'MedAccess AI',
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    home: const AuthGatekeeper(),
  ),
);
```

---

## 4. State Management (ViewModels)

### `AuthProvider` — Authentication & RBAC Guard
**File:** `lib/providers/auth_provider.dart`
- Manages Supabase JWT lifecycle, user profile metadata, and tenant partition (`institutionId`).
- Exposes computed getters: `bool get isAuthenticated`, `bool get isAdmin`, `bool get isStudent`.
- Directs routing to either `PatientMainScreen` or `AdminMainScreen`.

### `ClaimsProvider` — Clinical Triage Queue State
**File:** `lib/providers/claims_provider.dart`
- Stores the active list of clinical claims/encounters for the current institution.
- Automatically maintains descending sort order by Crisis Severity Index (`crisis_severity_index`).
- Provides filter predicates: `filterByEsi(String level)`, `filterByStatus(String status)`, and text query search.
- Reacts to real-time WebSocket `ticket-updated` events by performing in-place state replacement.

### `ClinicalChatProvider` — Confidential PFA Conversation State
**File:** `lib/providers/clinical_chat_provider.dart`
- Orchestrates multi-turn Psychological First Aid chat with the local/edge Qwen ONNX counselor.
- Tracks turn-by-turn chat history, typing indicators, and hardship confirmation dialogs.
- **Crisis Interceptor:** When the API returns `isCrisisResponse: true`, the provider activates `resources`, triggering the emergency 24/7 hotline card overlay and grounding guidance.

### `WarRoomProvider` — Clinician Telemetry & Analytics
**File:** `lib/providers/war_room_provider.dart`
- Aggregates operational metrics: pending ESI-1 critical cases, diagnostic review queues, fund liquidity, and disbursement history.
- Automatically refreshes every 30 seconds or immediately upon receiving Socket.io broadcast signals.

### `JobTrackingManager` — Asynchronous Pipeline Polling
**File:** `lib/providers/job_tracking_manager.dart`
- Tracks 10-step asynchronous BullMQ intake jobs: `Submitted` $\rightarrow$ `Processing` $\rightarrow$ `Triage Active` $\rightarrow$ `Approved` / `Flagged`.
- Polls `/api/v1/intake/status/:jobId` on a 2-second interval with progressive visual feedback.

---

## 5. Client Services & Infrastructure Layer

### `ClinicalApiService`
**File:** `lib/services/clinical_api_service.dart`
Dedicated client for all clinical diagnostic endpoints:
- `evaluateVision({required File image, required String anatomicalSite})`: Uploads dermatology/lesion photo to `/api/v1/diagnostics/vision`. Returns condition, severity, findings, and Grad-CAM heatmap base64.
- `evaluateCough({required File audioFile})`: Uploads 16kHz audio sample to `/api/v1/diagnostics/audio`. Returns 4-class probabilities and wheeze alert status.
- `evaluateVitals({required List<String> frameData})`: Posts 30Hz facial video frames to `/api/v1/diagnostics/vitals` to calculate heart rate and SpO2.
- `evaluateCDSS({required Map<String, dynamic> clinicalPayload})`: Dispatches structured symptom payload to `/api/v1/cdss/evaluate`, returning WHO ICD-11 differential candidates and FHIR R4 Bundle.
- `parsePrescription({required File prescriptionImage})`: Uploads prescription to `/api/v1/pharmacy/parse` for OCR extraction and RxNorm mapping.
- `checkInteractions({required List<String> medications})`: Cross-references drug lists against the 8,000+ DDI matrix via `/api/v1/pharmacy/interactions`.

### `SocketService`
**File:** `lib/services/socket_service.dart`
- Maintains persistent bi-directional connection to the backend Socket.io server.
- Emits `join-institution` room scoping upon user authentication.
- Listens for server events: `ticket-created`, `ticket-updated`, `payout-completed`, and `fraud-flagged`.

### `OfflineSyncEngine`
**File:** `lib/services/offline_sync_engine.dart`
- Persists diagnostic reports, symptom logs, and emergency offline contacts in `shared_preferences`.
- Automatically queues offline submissions and flushes them sequentially upon network restoration.

---

## 6. Screen Catalog & Clinical Navigation

### 🔷 Patient Portal Screens (`lib/screens/patient/`)

#### 1. `PatientClinicalDashboard`
**File:** `patient_clinical_dashboard.dart` (38 KB)
The central clinical hub for patients:
- **Diagnostic Launchpad:** One-tap navigation to Dermatology Vision Scan, Cough Acoustic Screening, and Contactless Vitals Monitor.
- **Symptom Tracker:** Interactive body map and symptom severity selector.
- **Active Prescriptions:** Current medications with quick links to Pharmacy Hub for interaction checking.
- **Recent Screenings:** Summary cards showing latest diagnostic risk scores and follow-up guidance.

#### 2. `PharmacyHubScreen`
**File:** `pharmacy_hub_screen.dart` (35 KB)
Comprehensive medication safety center:
- **Prescription Upload:** Dual camera/PDF capture for handwritten prescriptions.
- **OCR Review Panel:** Displays digitized medications with editable dosage, frequency, and canonical RxCUI tags.
- **Drug-Drug Interaction Matrix:** Visual traffic-light indicators (`Contraindicated`, `Major`, `Moderate`, `Minor`) explaining physiological risks.
- **Allergy Scanner:** Alerts patients if active ingredients conflict with their medical profile.

#### 3. `HealthRecordsScreen`
**File:** `health_records_screen.dart` (32 KB)
Patient health summary and clinical documentation:
- Historical diagnostic reports with Grad-CAM image comparisons over time.
- Standardized HL7 FHIR R4 JSON viewer and export utility for external clinicians.
- Verified medical leave letters and institutional excuse notes with redaction tags.

#### 4. `ClaimIntakeScreen`
**File:** `claim_intake_screen.dart` (23 KB)
Multimodal intake screen supporting narrative text, hospital bills (PDF/JPG), and clinical imagery.

#### 5. `ClinicalChatScreen`
**File:** `clinical_chat_screen.dart` (13 KB)
Confidential, on-device Psychological First Aid chat with local Qwen ONNX model, conversational grounding animations, and emergency resource triggers.

#### 6. `ClaimStatusScreen`
**File:** `claim_status_screen.dart` (28 KB)
Visual progress tracker displaying assigned ESI triage level, CSI severity meter, copay relief calculation, and live payout status.

#### 7. `EmergencyHubScreen`
**File:** `emergency_hub_screen.dart` (10 KB)
One-tap access to 24/7 crisis hotlines (Tele-MANAS, 988 Lifeline, campus emergency contacts) with immediate `tel:` intent dispatch.

---

### 🔷 Admin Clinical War Room Screens (`lib/screens/admin/`)

#### 1. `AdminClinicalDiagnosesScreen`
**File:** `admin_clinical_diagnoses_screen.dart` (75 KB)
The primary diagnostic evaluation workbench for clinical officers:
- **Multimodal Visualizer:** Side-by-side comparison of original patient medical photograph and Grad-CAM saliency heatmap overlay.
- **CDSS Differential Panel:** Calibrated probability bars for WHO ICD-11 differential candidates with logit confidence scores.
- **Acoustic Spectrogram & Waveform:** Visual player for cough audio samples with 4-class model probabilities and wheeze detection.
- **Contactless Vitals Inspector:** Real-time pulse waveform curve with calculated BPM, SpO2 estimate, and physiological red flags.
- **Clinician Override Action:** One-tap mechanism to accept, modify, or reject AI diagnostic suggestions with mandatory audit comments.

#### 2. `AdminWarRoomScreen`
**File:** `admin_war_room_screen.dart` (22 KB)
- Real-time clinical triage queue sorted by Crisis Severity Index (CSI).
- ESI badge indicators (ESI-1 Critical to ESI-5 Routine) with instant filtering chips.
- Slide-up bottom sheet with complete multimodal claim breakdown, fraud sentinel analysis, and one-tap RazorpayX / Stripe payout execution.

#### 3. `AdminHealthFundsScreen`
**File:** `admin_health_funds_screen.dart` (38 KB)
Fund pool liquidity monitoring, historical disbursement ledgers, and emergency voucher generator.

#### 4. `AdminKnowledgeBaseScreen`
**File:** `admin_knowledge_base_screen.dart` (39 KB)
Institutional medical policy management with Gemini semantic vector search (RAG) and PDF policy ingestion.

#### 5. `AdminMainScreen`
**File:** `admin_main_screen.dart` (17 KB)
Master navigation shell providing responsive drawer navigation on desktop/tablet and bottom navigation on mobile devices.

---

## 7. Clinical Design System & Theme Architecture

**File:** `lib/theme/app_theme.dart`

### Clinical Color Palette
- **ESI-1 Resuscitation:** Crimson Red (`#DC2626`) — Immediate life-safety emergency.
- **ESI-2 Emergent:** High-Risk Amber/Orange (`#EA580C`) — High urgency, rapid physician evaluation required.
- **ESI-3 Urgent:** Warm Ochre (`#D97706`) — Moderate severity, stable vitals.
- **ESI-4 Semi-Urgent / ESI-5 Routine:** Medical Teal / Emerald (`#059669`) — Non-emergent care.
- **Clinical Primary Brand:** Deep Clinical Cyan (`#0EA5E9`) paired with Hospital Navy (`#0F172A`).

### Accessibility Standards
- Contrast ratios exceed WCAG 2.1 AAA for clinical text and diagnostic indicators.
- Minimum touch targets of $48 \times 48\text{ dp}$ across all clinical action buttons.
- Full dynamic type support via `AccessibilityProvider`, scaling typography for visually impaired users.
