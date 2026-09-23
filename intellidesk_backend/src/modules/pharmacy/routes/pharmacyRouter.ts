import { Router, Request, Response } from 'express';
import multer from 'multer';
import { RxSentinelService } from '../RxSentinelService.js';
import { PharmacyDbService } from '../pharmacyDbService.js';
import { PatientAllergy, PatientMedication } from '../types.js';

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 15 * 1024 * 1024 } // 15MB limit
});

export const pharmacyRouter = Router();

/**
 * POST /api/v1/pharmacy/parse-prescription
 * Accepts multipart prescription file or JSON payload (imageUrl, bufferBase64, rawText).
 * Runs RxSentinel parsing, DDI check, allergy conflicts, and returns safety alerts.
 */
pharmacyRouter.post(
  '/parse-prescription',
  upload.single('file'),
  async (req: Request, res: Response) => {
    try {
      const file = req.file;
      const {
        patientId,
        claimId,
        imageUrl,
        bufferBase64,
        rawText,
        activeMedicationsOverride,
        allergiesOverride
      } = req.body;

      let input: Buffer | string | null = null;

      if (file && file.buffer) {
        input = file.buffer;
      } else if (bufferBase64) {
        input = Buffer.from(bufferBase64, 'base64');
      } else if (imageUrl) {
        input = imageUrl;
      } else if (rawText) {
        input = rawText;
      }

      if (!input) {
        return res.status(400).json({
          error: 'No prescription input provided. Upload a file or supply imageUrl, bufferBase64, or rawText.'
        });
      }

      const activeMeds = activeMedicationsOverride
        ? (Array.isArray(activeMedicationsOverride) ? activeMedicationsOverride : [activeMedicationsOverride])
        : undefined;

      const allergies = allergiesOverride
        ? (Array.isArray(allergiesOverride) ? allergiesOverride : [allergiesOverride])
        : undefined;

      const summary = await RxSentinelService.analyzePrescription({
        input,
        patientId,
        claimId,
        imageUrl,
        activeMedicationsOverride: activeMeds,
        allergiesOverride: allergies
      });

      return res.status(200).json({
        success: true,
        summary
      });
    } catch (err: any) {
      console.error('❌ [Pharmacy Router] Error parsing prescription:', err);
      return res.status(500).json({
        error: 'Failed to process prescription scan',
        details: err?.message || String(err)
      });
    }
  }
);

/**
 * GET /api/v1/pharmacy/allergies/:patientId
 * Retrieves recorded drug allergies for a patient.
 */
pharmacyRouter.get('/allergies/:patientId', async (req: Request, res: Response) => {
  try {
    const patientId = String(req.params.patientId);
    const allergies = await PharmacyDbService.getPatientAllergies(patientId);
    return res.status(200).json({
      patientId,
      allergies
    });
  } catch (err: any) {
    return res.status(500).json({
      error: 'Failed to retrieve patient allergies',
      details: err?.message || String(err)
    });
  }
});

/**
 * POST /api/v1/pharmacy/allergies
 * Adds a new allergy to a patient's medical profile.
 */
pharmacyRouter.post('/allergies', async (req: Request, res: Response) => {
  try {
    const { patientId, allergenGroup, reactionDescription } = req.body;
    if (!patientId || !allergenGroup) {
      return res.status(400).json({
        error: 'patientId and allergenGroup are required.'
      });
    }

    const allergy: PatientAllergy = {
      patientId,
      allergenGroup: String(allergenGroup).toUpperCase(),
      reactionDescription
    };

    const saved = await PharmacyDbService.addPatientAllergy(allergy);
    return res.status(201).json({
      success: true,
      allergy: saved
    });
  } catch (err: any) {
    return res.status(500).json({
      error: 'Failed to record allergy',
      details: err?.message || String(err)
    });
  }
});

/**
 * GET /api/v1/pharmacy/medications/:patientId
 * Retrieves active medications for a patient.
 */
pharmacyRouter.get('/medications/:patientId', async (req: Request, res: Response) => {
  try {
    const patientId = String(req.params.patientId);
    const medications = await PharmacyDbService.getPatientMedications(patientId, true);
    return res.status(200).json({
      patientId,
      medications
    });
  } catch (err: any) {
    return res.status(500).json({
      error: 'Failed to retrieve patient medications',
      details: err?.message || String(err)
    });
  }
});

/**
 * POST /api/v1/pharmacy/medications
 * Adds an active medication to a patient's roster.
 */
pharmacyRouter.post('/medications', async (req: Request, res: Response) => {
  try {
    const { patientId, medicationName, activeIngredient, dosage, isActive = true } = req.body;
    if (!patientId || !medicationName || !activeIngredient) {
      return res.status(400).json({
        error: 'patientId, medicationName, and activeIngredient are required.'
      });
    }

    const med: PatientMedication = {
      patientId,
      medicationName,
      activeIngredient,
      dosage,
      isActive: Boolean(isActive)
    };

    const saved = await PharmacyDbService.addPatientMedication(med);
    return res.status(201).json({
      success: true,
      medication: saved
    });
  } catch (err: any) {
    return res.status(500).json({
      error: 'Failed to record medication',
      details: err?.message || String(err)
    });
  }
});

/**
 * GET /api/v1/pharmacy/scans/:id
 * Retrieves prescription scan results by ID.
 */
pharmacyRouter.get('/scans/:id', async (req: Request, res: Response) => {
  try {
    const id = String(req.params.id);
    const scan = await PharmacyDbService.getPrescriptionScan(id);
    if (!scan) {
      return res.status(404).json({ error: 'Prescription scan not found' });
    }
    return res.status(200).json(scan);
  } catch (err: any) {
    return res.status(500).json({
      error: 'Failed to retrieve scan',
      details: err?.message || String(err)
    });
  }
});
