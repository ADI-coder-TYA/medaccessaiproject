import { Router, Request, Response } from 'express';
import { supabase } from '../config/supabase.js';

const router = Router();

/**
 * GET /api/v1/patients/profile
 * Retrieves patient profile by phone, email, or user id
 */
router.get('/profile', async (req: Request, res: Response) => {
  const patientPhone = (req.query.phone || req.query.patientPhone || req.headers['x-patient-phone']) as string;
  const patientEmail = (req.query.email || req.query.patientEmail || req.headers['x-patient-email']) as string;
  const patientId = (req.query.id || req.query.patientId || req.headers['x-patient-id']) as string;

  try {
    let query = supabase.from('profiles').select('*');
    if (patientId) {
      query = query.eq('id', patientId);
    } else if (patientEmail) {
      query = query.eq('email', patientEmail);
    } else if (patientPhone) {
      query = query.eq('phone', patientPhone);
    } else {
      return res.status(400).json({ error: 'Patient email or phone required' });
    }

    const { data: profile, error } = await query.maybeSingle();

    if (profile && !error) {
      return res.json(profile);
    }

    // Fallback: check patient_rosters table
    let rosterQuery = supabase.from('patient_rosters').select('*');
    if (patientEmail) rosterQuery = rosterQuery.eq('email', patientEmail);
    else if (patientPhone) rosterQuery = rosterQuery.eq('phone', patientPhone);

    const { data: rosterEntry } = await rosterQuery.maybeSingle();
    if (rosterEntry) {
      return res.json({
        id: rosterEntry.patient_id,
        full_name: rosterEntry.name || 'Verified Patient',
        email: rosterEntry.email,
        phone: rosterEntry.phone,
        role: 'PATIENT',
        institution_id: rosterEntry.institution_id || 'nano123',
      });
    }

    return res.status(404).json({ error: 'Patient profile not found' });
  } catch (error: any) {
    return res.status(500).json({ error: error.message });
  }
});

/**
 * POST /api/v1/patients/register
 * Registers or updates a patient profile
 */
router.post('/register', async (req: Request, res: Response) => {
  const { full_name, name, email, phone, emergency_contact, institution_id } = req.body;

  try {
    const patientName = full_name || name || 'Patient Member';
    const patientEmail = email || `${phone || Date.now()}@campushealth.edu`;

    const { data, error } = await supabase
      .from('profiles')
      .upsert({
        full_name: patientName,
        email: patientEmail,
        phone,
        role: 'PATIENT',
        emergency_contact,
        institution_id: institution_id || 'hosp-stanford-01',
      })
      .select()
      .maybeSingle();

    if (error) {
      return res.status(400).json({ error: error.message });
    }

    return res.status(201).json({
      success: true,
      patient: data,
    });
  } catch (error: any) {
    return res.status(500).json({ error: error.message });
  }
});

/**
 * GET /api/v1/patients/:id/claims
 * Lists all claims for a given patient
 */
router.get('/:id/claims', async (req: Request, res: Response) => {
  const { id } = req.params;
  try {
    const { data: claims, error } = await supabase
      .from('claims')
      .select('*')
      .or(`patient_id.eq.${id},patient_phone.eq.${id}`)
      .order('created_at', { ascending: false });

    if (error) {
      return res.status(400).json({ error: error.message });
    }

    return res.json(claims || []);
  } catch (error: any) {
    return res.status(500).json({ error: error.message });
  }
});

export default router;
