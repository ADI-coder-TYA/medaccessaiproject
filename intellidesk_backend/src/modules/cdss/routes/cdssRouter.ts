import { Router, Request, Response } from 'express';
import { CDSSService } from '../CDSSService.js';
import { ICD11ConceptStore } from '../ICD11ConceptStore.js';
import { CDSSInputPayload } from '../types.js';

export const cdssRouter = Router();

/**
 * POST /api/v1/cdss/evaluate
 * Ingests multimodal screening payload, performs ICD-11 coding,
 * computes DDx probabilities with temperature scaling, and returns recommended pathway.
 */
cdssRouter.post('/evaluate', async (req: Request, res: Response) => {
  try {
    const {
      screeningId,
      patientId = 'anonymous',
      multimodalRiskScore = 0.5,
      symptoms,
      visionFindings,
      audioClassification,
      temperature = 1.25
    } = req.body;

    const payload: CDSSInputPayload = {
      screeningId,
      patientId,
      multimodalRiskScore: Number(multimodalRiskScore) || 0.5,
      symptoms,
      visionFindings,
      audioClassification,
      temperature: Number(temperature) || 1.25
    };

    const evaluation = await CDSSService.evaluateScreening(payload);

    return res.status(200).json({
      success: true,
      evaluation
    });
  } catch (err: any) {
    console.error('❌ [CDSS Router] Error evaluating clinical decision support:', err);
    return res.status(500).json({
      success: false,
      error: err.message || 'CDSS evaluation failed'
    });
  }
});

/**
 * POST /api/v1/cdss/approve/:evaluationId
 * Clinician approval or ICD-11 diagnostic code override.
 * Preserves medico-legal provenance (Guardrail 3).
 */
cdssRouter.post('/approve/:evaluationId', async (req: Request, res: Response) => {
  try {
    const evaluationId = String(req.params.evaluationId);
    const {
      clinicianId = 'cmo-admin-1',
      clinicianName = 'Dr. Attending Physician, MD',
      isOverridden = false,
      overriddenCode,
      overrideNotes
    } = req.body;

    const result = await CDSSService.approveEvaluation(evaluationId, {
      clinicianId,
      clinicianName,
      isOverridden: Boolean(isOverridden),
      overriddenCode,
      overrideNotes
    });

    return res.status(200).json({
      success: true,
      evaluation: result
    });
  } catch (err: any) {
    console.error('❌ [CDSS Router] Error approving CDSS evaluation:', err);
    return res.status(500).json({
      success: false,
      error: err.message || 'CDSS approval failed'
    });
  }
});

/**
 * GET /api/v1/cdss/evaluation/:id
 */
cdssRouter.get('/evaluation/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const evaluation = await CDSSService.getEvaluationById(id);
    if (!evaluation) {
      return res.status(404).json({ success: false, error: 'CDSS evaluation not found' });
    }
    return res.status(200).json({ success: true, evaluation });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/cdss/screening/:screeningId
 */
cdssRouter.get('/screening/:screeningId', async (req: Request, res: Response) => {
  try {
    const screeningId = String(req.params.screeningId);
    const evaluation = await CDSSService.getEvaluationByScreeningId(screeningId);
    if (!evaluation) {
      return res.status(404).json({ success: false, error: 'No CDSS evaluation for screening' });
    }
    return res.status(200).json({ success: true, evaluation });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

/**
 * GET /api/v1/cdss/concepts
 * Returns the embedded ICD-11 knowledge base.
 */
cdssRouter.get('/concepts', (_req: Request, res: Response) => {
  return res.status(200).json({
    success: true,
    concepts: ICD11ConceptStore.getAllConcepts()
  });
});
