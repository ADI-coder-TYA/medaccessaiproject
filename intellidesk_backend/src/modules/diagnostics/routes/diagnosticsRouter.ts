import { Router, Request, Response } from 'express';
import { ClinicalImageClassifier } from '../vision/imageClassifier.js';
import { MultimodalRiskNetwork } from '../fusion/multimodalRiskNetwork.js';
import { GradCamGenerator } from '../explainability/gradCamGenerator.js';
import { FeatureImportanceEngine } from '../explainability/featureImportance.js';
import { HealthScreeningsDbService, DBHealthScreeningRow } from '../db/healthScreeningsDbService.js';
import { SymptomInputPayload } from '../fusion/types.js';
import { AudioFeatureExtractor, CoughClassifier, CloudAudioClassifier } from '../audio/index.js';
import { FHIRConverterService } from '../fhir/FHIRConverterService.js';
import { ReferralLetterGenerator } from '../fhir/ReferralLetterGenerator.js';
import { ScreeningDeltaAnalyzer } from '../progression/ScreeningDeltaAnalyzer.js';
import { EmergencyFacilityService } from '../facilities/EmergencyFacilityService.js';
import { pharmacyRouter } from '../../pharmacy/routes/pharmacyRouter.js';
import { 
  interpretDiagnosticResult, 
  generateCounselorResponse, 
  DiagnosticSummaryContext 
} from '../../../services/crisisCounselorService.js';
import { rPPGSignalProcessor } from '../vitals/rPPGSignalProcessor.js';
import { BioSignalFrame } from '../vitals/types.js';
import { cdssRouter } from '../../cdss/routes/cdssRouter.js';
import { CDSSService } from '../../cdss/CDSSService.js';
import { PharmacyDbService } from '../../pharmacy/pharmacyDbService.js';

const router = Router();

// Mount RxSentinel Pharmacy Subsystem & CDSS
router.use('/pharmacy', pharmacyRouter);
router.use('/cdss', cdssRouter);

/**
 * POST /api/v1/diagnostics/analyze
 * End-to-end multimodal screening pipeline:
 * Vision feature extraction + Multimodal fusion + Grad-CAM heatmap + SHAP feature importance + Persistence
 */
router.post('/analyze', async (req: Request, res: Response) => {
  try {
    const {
      patientId,
      patientName,
      previousScreeningId,
      institutionId = (req.headers['x-institution-id'] as string) || 'nano123',
      imageUrl,
      imageBase64,
      symptoms,
      audioBase64,
      audioFeatures
    } = req.body;

    const effectiveImageUrl = imageUrl || (imageBase64 ? (imageBase64.startsWith('data:') ? imageBase64 : `data:image/jpeg;base64,${imageBase64}`) : undefined);

    if (!symptoms || !symptoms.symptoms || !Array.isArray(symptoms.symptoms)) {
      return res.status(400).json({
        error: 'Invalid payload: "symptoms" with an array of symptom strings is required.'
      });
    }

    const resolvedPatientName = patientName || symptoms.patientName || symptoms.patient_name || undefined;
    const extractedNotes = symptoms.clinicalNotes || symptoms.clinical_notes || symptoms.additionalNotes || symptoms.notes || req.body.clinicalNotes || req.body.clinical_notes || req.body.notes || '';

    const symptomPayload: SymptomInputPayload = {
      bodyLocation: symptoms.bodyLocation || 'General / Unspecified',
      durationDays: Number(symptoms.durationDays) || 1,
      painScale: Number(symptoms.painScale) || 0,
      symptoms: symptoms.symptoms,
      vitals: symptoms.vitals,
      demographics: symptoms.demographics,
      additionalNotes: extractedNotes,
      clinicalNotes: extractedNotes,
      clinical_notes: extractedNotes,
      notes: extractedNotes,
      patient_name: resolvedPatientName,
    };

    // 1. Clinical Computer Vision Pipeline (if image provided)
    let visionResult;
    let gradCamResult;
    if (effectiveImageUrl) {
      console.log(`\n🩺 [Diagnostics API] Clinical Image Attached for patient: "${resolvedPatientName || 'Anonymous'}"`);
      console.log(`   Image payload type: ${effectiveImageUrl.startsWith('data:') ? 'Base64 Data URI' : effectiveImageUrl.startsWith('http') ? 'Remote URL' : 'Raw string'}`);
      console.log(`   Category hint: ${symptoms.categoryHint || 'None specified (Auto-detection enabled)'}`);
      if (extractedNotes) {
        console.log(`   Forwarding Clinical Notes to Vision Classifier: "${extractedNotes.length > 60 ? extractedNotes.substring(0, 60) + '...' : extractedNotes}"`);
      }
      const vStart = Date.now();
      visionResult = await ClinicalImageClassifier.extractEmbeddings({
        imageUrl: effectiveImageUrl,
        categoryHint: symptoms.categoryHint,
        clinicalNotes: extractedNotes,
        symptoms: symptomPayload.symptoms,
        anatomicalLocation: symptomPayload.bodyLocation,
      });
      console.log(`🩺 [Diagnostics API] Vision extraction completed in ${Date.now() - vStart}ms:`);
      console.log(`   Condition: "${visionResult.predictedCondition}" | Severity: ${visionResult.severity || 'N/A'} | Source: ${visionResult.source || 'Local'}`);

      // Generate Grad-CAM Heatmap
      gradCamResult = GradCamGenerator.generateHeatmap(
        visionResult.predictedCondition,
        visionResult.featureVector,
        visionResult.featureMapDimensions
      );
      console.log(`🔥 [Diagnostics API] Grad-CAM Visual Focus Heatmap generated for condition: "${visionResult.predictedCondition}"`);
    } else {
      console.log(`ℹ️ [Diagnostics API] No clinical photo attached -> Running screening with text/audio priors.`);
    }


    // 2. Audio Biomarker Buffer (if audio provided)
    let audioBuffer: Buffer | undefined;
    if (audioBase64 && typeof audioBase64 === 'string') {
      const b64Data = audioBase64.startsWith('data:') ? audioBase64.split(',')[1] : audioBase64;
      audioBuffer = Buffer.from(b64Data, 'base64');
      console.log(`🎙️ [Diagnostics API] Received audio biomarker in multimodal screening payload: ${audioBuffer.length} bytes`);
    } else if (audioFeatures && Array.isArray(audioFeatures)) {
      console.log(`🎙️ [Diagnostics API] Received pre-computed 16-D audio features: [${audioFeatures.map((f: number) => f.toFixed(2)).join(', ')}]`);
    } else {
      console.log(`ℹ️ [Diagnostics API] No audio provided in multimodal screening (using neutral acoustic prior)`);
    }

    // 3. Multimodal Fusion Engine (Vision + Symptoms + Demographics + Audio)
    const riskResult = await MultimodalRiskNetwork.assessRisk(symptomPayload, visionResult, {
      audioBuffer,
      audioFeatures
    });

    // 3. Explainability & Feature Importance (SHAP/LIME)
    const shapResult = FeatureImportanceEngine.calculateShapValues(symptomPayload, riskResult, visionResult);

    // 4. Persistence into Supabase `health_screenings`
    let rppgPayload = symptomPayload.vitals?.rppgResult || null;
    if (!rppgPayload && symptomPayload.vitals) {
      const v = symptomPayload.vitals;
      const hr = v.heartRateBpm ?? v.heartRate ?? 74;
      const spo2 = v.oxygenSaturationSpo2 ?? v.oxygenSaturation ?? 98;
      const sys = v.bloodPressureSystolicMmHg ?? v.systolicBP ?? 120;
      const dia = v.bloodPressureDiastolicMmHg ?? v.diastolicBP ?? 80;
      const rr = v.respiratoryRateBpm ?? v.respiratoryRate ?? 16;
      const temp = v.temperatureCelsius ?? v.temperature ?? 37.0;

      rppgPayload = {
        heartRateBpm: hr,
        heartRate: hr,
        oxygenSaturationSpo2: spo2,
        oxygenSaturation: spo2,
        bloodPressureSystolicMmHg: sys,
        systolicBP: sys,
        bloodPressureDiastolicMmHg: dia,
        diastolicBP: dia,
        respiratoryRateBpm: rr,
        respiratoryRate: rr,
        temperatureCelsius: temp,
        signalQuality: 0.95,
        alerts: [],
        source: v.source || 'manual_input'
      };
    }
    const physiologicalAlerts = rppgPayload?.alerts || [];

    const derivedFindings = (riskResult.differentialDiagnoses && riskResult.differentialDiagnoses.length > 0)
      ? riskResult.differentialDiagnoses.map((d: any, idx: number) => ({
          diagnosis: d.condition,
          condition: d.condition,
          icd11Code: d.icd11Code || d.code,
          code: d.icd11Code || d.code,
          riskLevel: d.urgency || riskResult.riskLevel,
          probability: d.probability,
          differentialRank: idx + 1,
          recommendation: riskResult.clinicalRecommendations?.[idx] || riskResult.clinicalRecommendations?.[0] || 'Targeted clinical management and close monitoring',
          evidence: ['Multimodal ML prediction', 'Physical examination corroboration'],
        }))
      : [
          {
            diagnosis: riskResult.primaryDiagnosis || 'Multimodal Clinical Checkup',
            condition: riskResult.primaryDiagnosis || 'Multimodal Clinical Checkup',
            icd11Code: 'MG40',
            code: 'MG40',
            riskLevel: riskResult.riskLevel,
            probability: 0.85,
            differentialRank: 1,
            recommendation: riskResult.clinicalRecommendations?.[0] || 'Periodic routine wellness screening recommended',
            evidence: ['Multimodal sensor presentation'],
          }
        ];

    const savedScreening = await HealthScreeningsDbService.createScreening({
      patientId,
      previousScreeningId,
      institutionId,
      imageUrl: imageUrl || (effectiveImageUrl && !effectiveImageUrl.startsWith('data:') ? effectiveImageUrl : null),
      symptomPayload,
      multimodalRiskScore: riskResult.riskScore,
      uncertaintyBounds: riskResult.uncertaintyBounds as any,
      xaiHeatmapUrl: gradCamResult?.overlaySvgDataUri || null,
      clinicalFindings: derivedFindings,
      riskLevel: riskResult.riskLevel,
      status: 'COMPLETED',
      rppgVitalsPayload: rppgPayload,
      physiologicalAlerts
    });

    // 5. Generate and Persist CDSS Report ONCE during health checkup with vision model findings
    const cdssVisionFindings: any[] = [];
    if (visionResult?.predictedCondition) {
      cdssVisionFindings.push({
        condition: visionResult.predictedCondition,
        confidence: visionResult.confidence ?? 0.92,
        anatomicalSite: visionResult.anatomicalSite || symptomPayload.bodyLocation,
        severity: visionResult.severity || 'Moderate',
        description: visionResult.clinicalDescription || visionResult.predictedCondition,
        source: visionResult.source || 'Qwen2.5-VL-72B-Instruct',
      });
      if (Array.isArray(visionResult.findings)) {
        for (const f of visionResult.findings) {
          if (f && f !== visionResult.predictedCondition) {
            cdssVisionFindings.push({
              condition: f,
              confidence: 0.65,
              anatomicalSite: visionResult.anatomicalSite || symptomPayload.bodyLocation,
              source: visionResult.source || 'Qwen2.5-VL-72B-Instruct',
            });
          }
        }
      }
    } else {
      cdssVisionFindings.push({
        condition: riskResult.primaryDiagnosis || 'Multimodal Clinical Checkup',
        confidence: 0.80,
        anatomicalSite: symptomPayload.bodyLocation,
      });
    }

    const cdssSymptoms: Record<string, any> = {
      ...symptomPayload,
      additionalNotes: extractedNotes,
      clinicalNotes: extractedNotes,
      clinical_notes: extractedNotes,
      notes: extractedNotes,
      anatomicalLocation: symptomPayload.bodyLocation,
      primaryDiagnosis: visionResult?.predictedCondition || riskResult.primaryDiagnosis,
      clinicalImageDiagnosis: visionResult?.predictedCondition,
      clinicalImageAnatomicalSite: visionResult?.anatomicalSite || symptomPayload.bodyLocation,
      clinicalImageSeverity: visionResult?.severity,
      recommendations: riskResult.clinicalRecommendations,
      riskLevel: riskResult.riskLevel,
      clinicalSummary: `${visionResult?.predictedCondition || riskResult.primaryDiagnosis}. ${(riskResult.clinicalRecommendations || []).join('; ')}`,
    };
    if (symptomPayload.vitals) {
      cdssSymptoms.vitals = symptomPayload.vitals;
    }

    let cdssEvaluation = null;
    try {
      console.log(`🧠 [Diagnostics API] Automatically evaluating CDSS report for screening ${savedScreening.id} with vision output & clinical notes...`);
      cdssEvaluation = await CDSSService.evaluateScreening({
        screeningId: savedScreening.id,
        patientId: patientId || 'PATIENT-ANON',
        institutionId,
        institutionName: symptoms.institutionName,
        multimodalRiskScore: riskResult.riskScore,
        symptoms: cdssSymptoms,
        clinicalNotes: extractedNotes,
        visionFindings: cdssVisionFindings,
        temperature: 1.25,
        useCloudModel: true,
      });
      console.log(`✅ [Diagnostics API] CDSS report generated: ${cdssEvaluation.primaryICD11Code} - ${cdssEvaluation.primaryICD11Title}`);
      await HealthScreeningsDbService.attachCdssEvaluation(savedScreening.id, cdssEvaluation);
    } catch (cdssErr: any) {
      console.error('⚠️ [Diagnostics API] Inline CDSS evaluation error:', cdssErr);
    }

    // 6. Compute Longitudinal Progression Delta if previous screening is linked
    let longitudinalDelta = null;
    if (savedScreening.previous_screening_id) {
      try {
        longitudinalDelta = await ScreeningDeltaAnalyzer.analyzeDelta(
          savedScreening.previous_screening_id,
          savedScreening
        );
      } catch (deltaErr) {
        console.warn('⚠️ [Diagnostics API] Could not compute inline longitudinal delta:', deltaErr);
      }
    }

    return res.status(200).json({
      success: true,
      screeningId: savedScreening.id,
      riskAssessment: riskResult,
      visionAnalysis: visionResult,
      cdssEvaluation,
      explainability: {
        gradCam: gradCamResult,
        shap: shapResult
      },
      longitudinalDelta,
      persistedRecord: savedScreening
    });
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error processing health screening:', err);
    return res.status(500).json({
      success: false,
      error: err.message || 'Internal screening failure'
    });
  }
});

/**
 * GET /api/v1/diagnostics/screenings/patient/:patientId
 */
router.get('/screenings/patient/:patientId', async (req: Request, res: Response) => {
  try {
    const patientId = String(req.params.patientId);
    const screenings = await HealthScreeningsDbService.getScreeningsByPatient(patientId);
    return res.status(200).json({ success: true, screenings });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/diagnostics/screenings/:id
 */
router.get('/screenings/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const screening = await HealthScreeningsDbService.getScreeningById(id);
    if (!screening) {
      return res.status(404).json({ success: false, error: 'Screening not found' });
    }
    return res.status(200).json({ success: true, screening });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/diagnostics/screenings/:id/fhir
 * Returns standard HL7 FHIR Release 4 (v4.0.1) Observation & DiagnosticReport bundle.
 * Technical Guardrails 2 & 4: Strict LOINC/UCUM alignment and patient fallback.
 */
router.get('/screenings/:id/fhir', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const screening = await HealthScreeningsDbService.getScreeningById(id);
    if (!screening) {
      return res.status(404).json({
        resourceType: 'OperationOutcome',
        issue: [
          {
            severity: 'error',
            code: 'not-found',
            diagnostics: `Health screening record "${id}" not found.`
          }
        ]
      });
    }

    const fhirBundle = FHIRConverterService.buildFHIRDiagnosticReport(screening);
    res.setHeader('Content-Type', 'application/fhir+json');
    return res.status(200).json(fhirBundle);
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error generating FHIR R4 export:', err);
    return res.status(500).json({
      resourceType: 'OperationOutcome',
      issue: [
        {
          severity: 'fatal',
          code: 'exception',
          diagnostics: err.message || 'Internal failure generating FHIR representation.'
        }
      ]
    });
  }
});

/**
 * GET /api/v1/diagnostics/screenings/:id/referral
 * Streams a formal Clinical Referral Letter PDF generated via PDFKit.
 * Technical Guardrail 3: Direct response stream piping.
 */
router.get(['/screenings/:id/referral', '/screenings/:id/referral-letter'], async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const screening = await HealthScreeningsDbService.getScreeningById(id);
    if (!screening) {
      return res.status(404).json({ success: false, error: 'Screening not found' });
    }

    await ReferralLetterGenerator.generateReferralPdfStream(screening, res);
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error generating Referral Letter PDF:', err);
    if (!res.headersSent) {
      return res.status(500).json({ success: false, error: err.message || 'Failed to generate referral letter' });
    }
  }
});

/**
 * POST /api/v1/diagnostics/referral-letter
 * Generates and streams a formal Clinical Referral Letter PDF on demand
 * from a live client-side assessment payload or unsaved screening.
 */
router.post(['/referral-letter', '/screenings/referral-pdf'], async (req: Request, res: Response) => {
  try {
    const { screening, assessment, symptomVector, vitals, patientId, institutionId, imageUrl, patientName, institutionName } = req.body;
    let targetScreening: DBHealthScreeningRow | null = null;

    const screeningId = req.body.screeningId || screening?.id || assessment?.screeningId;
    if (screeningId && typeof screeningId === 'string' && !screeningId.startsWith('scr-live-')) {
      try {
        targetScreening = await HealthScreeningsDbService.getScreeningById(screeningId);
      } catch (err) {
        console.warn('⚠️ [Diagnostics API] Could not fetch screening by ID for referral letter:', err);
      }
    }

    if (screening && screening.id && !targetScreening) {
      targetScreening = screening;
    }

    if (!targetScreening) {
      const riskScore = Number(assessment?.riskScore ?? 0.5);
      const riskLevel = String(assessment?.riskLevel ?? 'MODERATE').toUpperCase();
      const bounds = assessment?.uncertaintyBounds ?? {
        confidence: 0.88,
        ciLower: Math.max(0, riskScore - 0.05),
        ciUpper: Math.min(1, riskScore + 0.05),
        epistemicVariance: 0.001
      };

      const findings = Array.isArray(assessment?.differentialDiagnoses) && assessment.differentialDiagnoses.length > 0
        ? assessment.differentialDiagnoses.map((d: any) => typeof d === 'object' ? `${d.condition || d.name} (${Math.round((d.confidence || d.probability || 0) * 100)}%)` : d)
        : (Array.isArray(assessment?.clinicalRecommendations) && assessment.clinicalRecommendations.length > 0
          ? assessment.clinicalRecommendations
          : [assessment?.primaryDiagnosis || 'Hypertensive Emergency Rule-Out (29%)']);

      targetScreening = {
        id: screeningId || `scr-live-${Date.now()}`,
        patient_id: patientId || 'usr_pat_PAT-37B041',
        institution_id: institutionId || 'nano123',
        image_url: imageUrl || assessment?.imageUrl || null,
        symptom_payload: {
          ...(symptomVector || req.body.symptoms || {}),
          primaryDiagnosis: assessment?.primaryDiagnosis,
          vitals: vitals || req.body.vitals || null,
        },
        multimodal_risk_score: riskScore,
        uncertainty_bounds: bounds,
        xai_heatmap_url: assessment?.xaiHeatmapUrl || null,
        clinical_findings: findings,
        risk_level: riskLevel,
        status: 'completed',
        rppg_vitals_payload: vitals || null,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      };
    }

    // Enrich targetScreening with client-provided metadata if present
    if (patientName) (targetScreening as any).patient_name = patientName;
    if (institutionName) (targetScreening as any).institution_name = institutionName;
    if (assessment?.primaryDiagnosis) (targetScreening as any).primary_diagnosis = assessment.primaryDiagnosis;
    if (assessment?.clinicalRecommendations) (targetScreening as any).clinical_recommendations = assessment.clinicalRecommendations;
    if (vitals && !targetScreening.rppg_vitals_payload) targetScreening.rppg_vitals_payload = vitals;

    const demographics = req.body.demographics || req.body.symptomVector?.demographics || req.body.symptoms?.demographics;
    if (demographics) {
      if (demographics.age) (targetScreening as any).patientAge = demographics.age;
      if (demographics.gender) (targetScreening as any).patientGender = demographics.gender;
      if (typeof targetScreening.symptom_payload === 'object' && targetScreening.symptom_payload !== null) {
        (targetScreening.symptom_payload as any).demographics = demographics;
      }
    }

    await ReferralLetterGenerator.generateReferralPdfStream(targetScreening, res);
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error generating on-demand Referral Letter PDF:', err);
    if (!res.headersSent) {
      return res.status(500).json({ success: false, error: err.message || 'Failed to generate referral letter' });
    }
  }
});

/**
 * POST /api/v1/diagnostics/interpret
 * Generates an empathetic Qwen2.5 explanation & next steps for screening results.
 */
router.post('/interpret', async (req: Request, res: Response) => {
  try {
    const { diagnosticContext, query } = req.body;
    if (!diagnosticContext) {
      return res.status(400).json({ success: false, error: 'diagnosticContext is required.' });
    }

    const result = await interpretDiagnosticResult(diagnosticContext as DiagnosticSummaryContext, query);
    return res.status(200).json({
      success: true,
      interpretation: result.reply,
      isCrisis: result.isCrisisResponse,
      resources: result.resources,
      latencyMs: result.latencyMs
    });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/diagnostics/audio/classify
 * Standalone Audio Biomarker Extraction & Cough Classification endpoint.
 * Accepts WAV/PCM base64 or audio feature vector.
 */
router.post('/audio/classify', async (req: Request, res: Response) => {
  try {
    const { audioBase64, audioFeatures } = req.body;
    console.log(`🎙️ [Diagnostics API] Inbound /audio/classify request: ${audioBase64 ? 'audioBase64 payload (' + (typeof audioBase64 === 'string' ? audioBase64.length + ' chars' : 'buffer') + ')' : (audioFeatures ? 'audioFeatures (' + audioFeatures.length + ' dims)' : 'none')}`);

    let features = audioFeatures;
    let extractionResult = null;
    let rawBuf: Buffer | null = null;

    if (audioBase64) {
      if (typeof audioBase64 === 'string' && audioBase64.startsWith('data:')) {
        const base64Data = audioBase64.split(',')[1];
        rawBuf = Buffer.from(base64Data, 'base64');
      } else if (typeof audioBase64 === 'string') {
        rawBuf = Buffer.from(audioBase64, 'base64');
      }
    }

    if (!features && rawBuf) {
      console.log(`🎙️ [Diagnostics API] Decoding raw audio buffer: ${rawBuf.length} bytes`);
      extractionResult = await AudioFeatureExtractor.extractFeatures(rawBuf);
      features = extractionResult.featureVector;
    }

    if (!features) {
      console.warn('⚠️ [Diagnostics API] /audio/classify missing audio payload');
      return res.status(400).json({
        success: false,
        error: 'Either "audioBase64" or "audioFeatures" (16-d array) is required.'
      });
    }

    const classification = await CloudAudioClassifier.classify(features, rawBuf);
    console.log(`🩺 [Diagnostics API] ✅ Audio classification completed: "${classification.predictedCategory}" (${(classification.confidence * 100).toFixed(1)}%) | RedFlag: ${classification.isRedFlagRespiratory}`);

    return res.status(200).json({
      success: true,
      classification,
      extraction: extractionResult
    });
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error classifying cough audio:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/diagnostics/chat
 * Multi-turn chat with local ONNX Qwen2.5 / Rogerian assistant grounded in patient screening context.
 */
router.post('/chat', async (req: Request, res: Response) => {
  try {
    const { message, diagnosticContext, history = [] } = req.body;
    if (!message) {
      return res.status(400).json({ success: false, error: 'message is required.' });
    }

    const result = await generateCounselorResponse(
      null,
      message,
      history,
      { diagnosticContext }
    );

    return res.status(200).json({
      success: true,
      reply: result.reply,
      isCrisis: result.isCrisisResponse,
      resources: result.resources,
      latencyMs: result.latencyMs
    });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/diagnostics/progression/delta
 * Calculates longitudinal progression metrics (SSIM, risk delta, vital shifts, clinical status)
 * between baseline (T0) and follow-up (T1) screenings.
 */
router.post('/progression/delta', async (req: Request, res: Response) => {
  try {
    const { baselineScreeningId, followupScreeningId, baselineScreening, followupScreening } = req.body;
    const baseline = baselineScreeningId || baselineScreening;
    const followup = followupScreeningId || followupScreening;

    if (!baseline || !followup) {
      return res.status(400).json({
        success: false,
        error: 'Both baseline (ID or object) and follow-up (ID or object) are required.'
      });
    }

    const comparison = await ScreeningDeltaAnalyzer.analyzeDelta(baseline, followup);
    return res.status(200).json({ success: true, comparison });
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error analyzing progression delta:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/diagnostics/screenings/patient/:patientId/longitudinal
 * Returns chronological longitudinal history for patient with pairwise deltas and overall trajectory.
 */
router.get('/screenings/patient/:patientId/longitudinal', async (req: Request, res: Response) => {
  try {
    const patientId = String(req.params.patientId);
    const screenings = await HealthScreeningsDbService.getScreeningsByPatientAsc(patientId);

    if (screenings.length === 0) {
      return res.status(200).json({
        success: true,
        patientId,
        screenings: [],
        timelineDeltas: [],
        overallComparison: null
      });
    }

    // Compute pairwise consecutive deltas
    const timelineDeltas = [];
    for (let i = 1; i < screenings.length; i++) {
      try {
        const delta = await ScreeningDeltaAnalyzer.analyzeDelta(screenings[i - 1], screenings[i]);
        timelineDeltas.push(delta);
      } catch (e) {
        console.warn(`⚠️ [Diagnostics API] Pairwise delta computation skipped for index ${i}:`, e);
      }
    }

    // Compute overall progression from first (T0) to last (TN)
    let overallComparison = null;
    if (screenings.length > 1) {
      try {
        overallComparison = await ScreeningDeltaAnalyzer.analyzeDelta(
          screenings[0],
          screenings[screenings.length - 1]
        );
      } catch (e) {
        console.warn('⚠️ [Diagnostics API] Overall delta computation skipped:', e);
      }
    }

    return res.status(200).json({
      success: true,
      patientId,
      totalScreenings: screenings.length,
      screenings,
      timelineDeltas,
      overallComparison
    });
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error fetching longitudinal screenings:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/diagnostics/facilities/nearby
 * Retrieves nearest emergency care facilities, trauma centers, and campus health clinics
 * within a requested radius (default 20 km) based on patient GPS coordinates.
 */
router.get('/facilities/nearby', async (req: Request, res: Response) => {
  try {
    const lat = req.query.lat ? parseFloat(String(req.query.lat)) : 40.7128;
    const lng = req.query.lng ? parseFloat(String(req.query.lng)) : -74.0060;
    const radiusKm = req.query.radiusKm ? parseFloat(String(req.query.radiusKm)) : 20.0;
    const type = req.query.type as any;

    console.log(`📍 [Diagnostics Router] GET /facilities/nearby | Lat: ${lat}, Lng: ${lng}, Radius: ${radiusKm}km, Type: ${type || 'ALL'}`);

    if (isNaN(lat) || isNaN(lng)) {
      console.warn(`⚠️ [Diagnostics Router] Rejected invalid coordinates (lat=${req.query.lat}, lng=${req.query.lng})`);
      return res.status(400).json({
        success: false,
        error: 'Invalid coordinates: "lat" and "lng" must be valid numeric floating point values.'
      });
    }

    const result = await EmergencyFacilityService.getNearbyFacilities(lat, lng, radiusKm, type);
    console.log(`🏁 [Diagnostics Router] Responded with ${result.totalFound} facilities (Closest: "${result.facilities[0]?.name || 'None'}", ${result.facilities[0]?.distanceKm ?? 0}km)`);
    return res.status(200).json({
      success: true,
      ...result
    });
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error querying nearby emergency facilities:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/diagnostics/vitals/process-rppg
 * Processes camera optical photoplethysmography (rPPG) frame stream.
 * Extracts Heart Rate, HRV (RMSSD), Respiration Rate, SpO2 (AC/DC normalized),
 * and checks physiological red-flags.
 */
router.post('/vitals/process-rppg', async (req: Request, res: Response) => {
  try {
    const { frames, red, green, blue, timestampsMs, samplingRate = 30.0 } = req.body;
    console.log(`📡 [Diagnostics API] Inbound rPPG request: ${Array.isArray(frames) ? frames.length + ' frames' : 'signal arrays'}, samplingRate=${samplingRate}`);

    const processor = new rPPGSignalProcessor(Number(samplingRate) || 30.0);
    let result;

    if (Array.isArray(frames) && frames.length > 0) {
      if (frames.length < 60) {
        console.warn(`⚠️ [Diagnostics API] Insufficient rPPG frames: received ${frames.length}, need >= 60`);
        return res.status(400).json({
          success: false,
          error: `Insufficient optical frames: received ${frames.length} frames, minimum 60 required (>= 2 seconds).`
        });
      }
      const first = frames.slice(0, 3).map((f: any) => `[#${f.frameIndex} t=${f.timestampMs}ms R=${f.red} G=${f.green} B=${f.blue}]`).join(', ');
      const last = frames.slice(-2).map((f: any) => `[#${f.frameIndex} t=${f.timestampMs}ms R=${f.red} G=${f.green} B=${f.blue}]`).join(', ');
      console.log(`📡 [Diagnostics API] Frame snapshot: Start: ${first} ... End: ${last}`);

      result = processor.processFrames(frames as BioSignalFrame[]);
    } else if (Array.isArray(green) && green.length > 0) {
      if (green.length < 60) {
        console.warn(`⚠️ [Diagnostics API] Insufficient rPPG samples: received ${green.length}, need >= 60`);
        return res.status(400).json({
          success: false,
          error: `Insufficient optical samples: received ${green.length} samples, minimum 60 required (>= 2 seconds).`
        });
      }
      result = processor.processSignals({
        red: Array.isArray(red) ? red : green,
        green,
        blue: Array.isArray(blue) ? blue : green,
        timestampsMs: Array.isArray(timestampsMs) ? timestampsMs : undefined,
        samplingRate: Number(samplingRate) || 30.0
      });
    } else {
      return res.status(400).json({
        success: false,
        error: 'Invalid payload: "frames" array or "green" signal array is required.'
      });
    }

    console.log(`🩺 [Diagnostics API] ✅ rPPG analysis computed: HR=${result.heartRateBpm} bpm | SNR=${result.snrDb} dB | Conf=${result.confidenceScore} | SpO2=${result.oxygenSaturationSpo2}% | RR=${result.respirationRateBpm} br/min | Alerts=${result.alerts?.length || 0}`);

    return res.status(200).json({
      success: true,
      vitals: result
    });
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error processing rPPG vitals:', err);
    return res.status(500).json({
      success: false,
      error: err.message || 'Signal processing error'
    });
  }
});

/**
 * GET /api/v1/diagnostics/patient/:patientId/overview
 * Unified clinical overview endpoint for patient dashboard:
 * returns latest screening, active vitals, medications count, allergies count, nearby facilities, and clinical alerts.
 */
router.get('/patient/:patientId/overview', async (req: Request, res: Response) => {
  try {
    const patientId = String(req.params.patientId);
    const lat = req.query.lat ? parseFloat(String(req.query.lat)) : 40.7128;
    const lng = req.query.lng ? parseFloat(String(req.query.lng)) : -74.0060;

    const [screenings, allergies, medications] = await Promise.all([
      HealthScreeningsDbService.getScreeningsByPatient(patientId),
      PharmacyDbService.getPatientAllergies(patientId),
      PharmacyDbService.getPatientMedications(patientId, true),
    ]);

    const latestScreening = screenings.length > 0 ? screenings[0] : null;
    // Restrict overview summary strictly to Tier 2 (Supabase) / Tier 3 (Embedded offline) without invoking Google Places API
    const facilitiesResult = await EmergencyFacilityService.getNearbyFacilities(lat, lng, 20.0, undefined, true);

    return res.status(200).json({
      success: true,
      patientId,
      latestScreening,
      totalScreenings: screenings.length,
      activeMedicationsCount: medications.length,
      activeMedications: medications.slice(0, 5),
      allergiesCount: allergies.length,
      allergies: allergies.map(a => a.allergenGroup),
      nearbyFacilitiesCount: facilitiesResult.facilities.length,
      nearestFacility: facilitiesResult.facilities.length > 0 ? facilitiesResult.facilities[0] : null,
      latestVitals: latestScreening?.rppg_vitals_payload || latestScreening?.symptom_payload?.vitals || null,
      timestamp: new Date().toISOString()
    });
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error fetching patient overview:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/diagnostics/admin/screenings
 * Returns all patient multimodal clinical diagnoses and screenings.
 */
router.get('/admin/screenings', async (req: Request, res: Response) => {
  try {
    const institutionId = (req.query.institutionId as string) || (req.headers['x-institution-id'] as string) || undefined;
    const riskLevel = req.query.riskLevel ? String(req.query.riskLevel) : undefined;
    const search = req.query.search ? String(req.query.search) : undefined;
    const limit = req.query.limit ? parseInt(String(req.query.limit), 10) : undefined;

    const screenings = await HealthScreeningsDbService.getAllScreenings({
      institutionId,
      riskLevel,
      search,
      limit,
    });

    return res.status(200).json({
      success: true,
      count: screenings.length,
      screenings,
    });
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error fetching admin screenings:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/diagnostics/admin/patients
 * Returns patient roster with aggregated clinical diagnoses, risk tier, and vital indicators.
 */
router.get('/admin/patients', async (req: Request, res: Response) => {
  try {
    const institutionId = (req.query.institutionId as string) || (req.headers['x-institution-id'] as string) || undefined;
    const patients = await HealthScreeningsDbService.getAdminPatientsOverview(institutionId);

    return res.status(200).json({
      success: true,
      count: patients.length,
      patients,
    });
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error fetching admin patients overview:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/diagnostics/admin/patients/:patientId/diagnoses
 * Returns complete list of multimodal diagnoses and clinical timeline for a specific patient.
 */
router.get('/admin/patients/:patientId/diagnoses', async (req: Request, res: Response) => {
  try {
    const patientId = String(req.params.patientId);
    const screenings = await HealthScreeningsDbService.getScreeningsByPatient(patientId);

    return res.status(200).json({
      success: true,
      patientId,
      count: screenings.length,
      screenings
    });
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error fetching patient diagnoses:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * POST /api/v1/diagnostics/assign-institution
 * Routes and directly assigns a patient's screening report to an institution admin.
 */
router.post('/assign-institution', async (req: Request, res: Response) => {
  try {
    const { screeningId, institutionId } = req.body;
    if (!screeningId || !institutionId) {
      return res.status(400).json({
        success: false,
        error: 'Both "screeningId" and "institutionId" are required to route report.'
      });
    }

    const updated = await HealthScreeningsDbService.updateScreeningInstitution(
      String(screeningId),
      String(institutionId)
    );

    return res.status(200).json({
      success: true,
      screeningId,
      institutionId,
      updated
    });
  } catch (err: any) {
    console.error('❌ [Diagnostics API] Error assigning screening to institution:', err);
    return res.status(500).json({ success: false, error: err.message });
  }
});

export default router;
