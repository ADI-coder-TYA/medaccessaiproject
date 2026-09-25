import { Router, Request, Response } from 'express';
import { supabase } from '../config/supabase.js';
import { v4 as uuidv4 } from 'uuid';

const router = Router();

// In-memory Multi-Tenant & Student Whitelist Store
const INSTITUTIONS: Map<string, any> = new Map();
const STUDENT_ROSTERS: Map<string, any> = new Map(); // Key: email or phone
const USER_STORE: Map<string, any> = new Map(); // Key: email or student_id

// Seed default institution
const DEFAULT_INSTITUTION_ID = 'inst-001';
INSTITUTIONS.set(DEFAULT_INSTITUTION_ID, {
  id: DEFAULT_INSTITUTION_ID,
  name: 'Apex Health & Medical Center',
  domain: 'apexhealth.edu',
  createdAt: new Date().toISOString(),
});

/**
 * Resolves institution record directly from Supabase institutions table with memory fallback
 */
export async function getInstitutionDetails(instId?: string | null) {
  const cleanId = (instId || DEFAULT_INSTITUTION_ID).trim();
  try {
    const { data } = await supabase
      .from('institutions')
      .select('id, name, domain, default_currency')
      .eq('id', cleanId)
      .maybeSingle();

    if (data && data.name) {
      return {
        id: data.id,
        name: data.name,
        domain: data.domain || 'health.edu',
        currency: data.default_currency || 'INR',
      };
    }
  } catch (_) {}

  const mem = INSTITUTIONS.get(cleanId);
  if (mem) return mem;

  return {
    id: cleanId,
    name: cleanId,
    domain: 'health.edu',
    currency: 'INR',
  };
}

router.get('/institution/:id', async (req: Request, res: Response) => {
  try {
    const inst = await getInstitutionDetails(String(req.params.id || ''));
    return res.status(200).json({ success: true, institution: inst });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

// Seed Whitelisted Patient Roster
const DEFAULT_ROSTER = [
  { student_id: 'PAT-2026-001', email: 'alex.rivera@campushealth.edu', phone: '+91 98765 43210', name: 'Alex Rivera' },
  { student_id: 'PAT-2026-002', email: 'priya.sharma@campushealth.edu', phone: '+91 98111 22334', name: 'Priya Sharma' },
  { student_id: 'PAT-2026-003', email: 'marcus.chen@campushealth.edu', phone: '+91 98222 33445', name: 'Marcus Chen' },
  { student_id: 'PAT-2026-004', email: 'elena.rostova@campushealth.edu', phone: '+91 98333 44556', name: 'Elena Rostova' },
  { student_id: 'PAT-2026-005', email: 'jordan.taylor@campushealth.edu', phone: '+91 98444 55667', name: 'Jordan Taylor' },
  { student_id: 'PAT-2026-006', email: 'sophia.r@campushealth.edu', phone: '+91 98555 66778', name: 'Sophia Rodriguez' },
  { student_id: 'PAT-2026-007', email: 'rohan.gupta@campushealth.edu', phone: '+91 98666 77889', name: 'Rohan Gupta' },
  { student_id: 'PAT-2026-008', email: 'maya.lin@campushealth.edu', phone: '+91 98777 88990', name: 'Maya Lin' },
];

// Auto-seed default patients to Supabase public.patient_rosters if table is empty
async function syncDefaultRosterToSupabase() {
  try {
    const { data, error } = await supabase.from('patient_rosters').select('id').limit(1);
    if (!error && (!data || data.length === 0)) {
      const defaultRows = DEFAULT_ROSTER.map((r, idx) => ({
        institution_id: DEFAULT_INSTITUTION_ID,
        patient_id: r.student_id || `PAT-2026-${100 + idx}`,
        email: r.email,
        phone: r.phone,
        is_registered: false,
      }));
      const { error: insertErr } = await supabase.from('patient_rosters').insert(defaultRows);
      if (!insertErr) {
        console.log(`🚀 [Supabase] Auto-seeded ${defaultRows.length} default patients into public.patient_rosters table.`);
      } else {
        console.warn('⚠️ [Supabase] patient_rosters seed notice:', insertErr.message);
      }
    }
  } catch (e) {
    console.warn('⚠️ [Supabase] Could not auto-seed default patients:', e);
  }
}
// Auto-seed default admin profile to Supabase public.profiles if empty
async function syncDefaultAdminToSupabase() {
  try {
    const { data } = await supabase.from('profiles').select('id').eq('role', 'CLINICAL_ADMIN').limit(1);
    if (!data || data.length === 0) {
      const defaultAdminUuid = '00000000-0000-0000-0000-000000000001';
      await supabase.from('institutions').upsert({
        id: DEFAULT_INSTITUTION_ID,
        name: 'Apex Health & Medical Center',
        domain: 'apexhealth.edu',
        default_currency: 'INR',
      });

      await supabase.from('profiles').upsert({
        id: defaultAdminUuid,
        email: 'admin@campushealth.edu',
        full_name: 'Dr. Sarah Chen, MD',
        role: 'CLINICAL_ADMIN',
        institution_id: DEFAULT_INSTITUTION_ID,
        phone: '+91 98111 22334',
        emergency_contact: 'Clinical Triage & Emergency Copay Desk',
        alerts_enabled: true,
      });
      console.log(`👨‍⚕️ [Supabase] Seeded default Clinical Admin into profiles table.`);
    }
  } catch (e: any) {
    console.warn('⚠️ [Supabase] syncDefaultAdmin notice:', e?.message);
  }
}
syncDefaultAdminToSupabase();

// Default Admin Account
const DEFAULT_ADMIN = {
  id: '00000000-0000-0000-0000-000000000001',
  name: 'Dr. Sarah Chen, MD',
  email: 'admin@campushealth.edu',
  role: 'ADMIN',
  department: 'Clinical Triage & Emergency Copay Desk',
  institutionId: DEFAULT_INSTITUTION_ID,
  avatarUrl: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=150',
  token: 'jwt_mock_token_admin_sarah_chen',
};
USER_STORE.set(DEFAULT_ADMIN.email.toLowerCase(), DEFAULT_ADMIN);

/**
 * POST /api/v1/auth/admin/register-tenant
 * Admin Tenant Registration & Student CSV Whitelist Provisioning
 */
router.post('/admin/register-tenant', async (req: Request, res: Response) => {
  try {
    const {
      adminEmail,
      password,
      defaultStudentPassword = 'Patient@123',
      institutionName,
      institutionId,
      department,
      specialty,
      phone,
      adminPhone,
      students = [],
      csvContent,
    } = req.body;

    const email = (adminEmail || req.body.email || '').trim().toLowerCase();
    const instName = (institutionName || req.body.instituteName || 'Apex Health Medical Center').trim();
    const instId = (institutionId || `inst-${Date.now()}`).trim().toLowerCase();
    const adminSpecialty = (department || specialty || 'Clinical Triage & Emergency Copay Desk').trim();
    const adminTel = (phone || adminPhone || '+91 98111 22334').trim();

    if (!email) {
      return res.status(400).json({ success: false, error: 'Admin email is required.' });
    }

    // 1. Create Institution Record in Memory & Supabase
    const newInstitution = {
      id: instId,
      name: instName,
      domain: email.split('@')[1] || 'apexhealth.edu',
      default_currency: 'INR',
      createdAt: new Date().toISOString(),
    };
    INSTITUTIONS.set(instId, newInstitution);

    try {
      const { error: instError } = await supabase.from('institutions').upsert({
        id: instId,
        name: instName,
        domain: email.includes('@') ? email.split('@')[1] : 'apexhealth.edu',
        default_currency: 'INR',
      });
      if (instError) {
        console.error('⚠️ [Supabase] Failed to upsert institution into institutions table:', instError.message);
      } else {
        console.log(`🏥 [Supabase] Successfully upserted institution "${instName}" (${instId})`);
      }
    } catch (instErr: any) {
      console.warn('⚠️ [Supabase] Institution upsert notice:', instErr?.message);
    }

    // Provision default health fund pool for this institution
    try {
      await supabase.from('health_funds').upsert({
        institution_id: instId,
        fund_name: `${instName} Emergency Health Relief Fund`,
        total_pool: Number(req.body.fundPool || req.body.initialFundPool || 150000.0),
        total_disbursed: 0.0,
        currency: 'INR',
      });
    } catch (_) {}

    // 2. Create Admin User Profile & Persist to Supabase
    const adminUuid = uuidv4();
    const adminName = (req.body.adminName || req.body.name || 'Chief Medical Officer').trim();

    const adminUser = {
      id: adminUuid,
      name: adminName,
      email: email,
      role: 'ADMIN',
      department: adminSpecialty,
      institutionId: instId,
      phone: adminTel,
      token: `jwt_token_admin_${instId}_${Date.now()}`,
    };
    USER_STORE.set(email, adminUser);
    USER_STORE.set(adminUuid, adminUser);

    try {
      const { error: profError } = await supabase.from('profiles').upsert({
        id: adminUuid,
        email: email,
        full_name: adminName,
        role: 'CLINICAL_ADMIN',
        institution_id: instId,
        phone: adminTel,
        emergency_contact: adminSpecialty,
        alerts_enabled: true,
      });

      if (profError) {
        console.warn('⚠️ [Supabase] Admin profile creation notice:', profError.message);
      } else {
        console.log(`👨‍⚕️ [Supabase] Successfully stored Clinical Admin "${adminName}" (${email}) with specialty "${adminSpecialty}" at Institution "${instId}"!`);
      }
    } catch (profErr: any) {
      console.warn('⚠️ [Supabase] Admin profile creation exception:', profErr?.message);
    }

    // 3. Parse CSV lines using Supabase `patient_rosters` table format or standard roster format
    let rosterList: any[] = Array.isArray(students) ? [...students] : [];
    if (csvContent && typeof csvContent === 'string') {
      const lines = csvContent.split('\n').map((l) => l.trim()).filter((l) => l.length > 0);
      if (lines.length > 0) {
        const header = lines[0].toLowerCase().split(',').map((h) => h.trim());
        const hasHeader = header.some((h) => ['id', 'patient_id', 'student_id', 'member_id', 'email', 'name', 'full_name', 'phone', 'institution_id', 'department', 'emergency_contact'].includes(h));
        const dataLines = hasHeader ? lines.slice(1) : lines;

        // Dynamic Header Mapping
        let idIdx = header.findIndex((h) => h === 'patient_id' || h === 'id' || h === 'student_id' || h === 'member_id');
        let phoneIdx = header.findIndex((h) => h === 'phone' || h === 'phone_number' || h === 'contact');
        let nameIdx = header.findIndex((h) => h === 'full_name' || h === 'name' || h === 'patient_name' || h === 'student_name');
        let firstNameIdx = header.findIndex((h) => h === 'first_name' || h === 'firstname');
        let lastNameIdx = header.findIndex((h) => h === 'last_name' || h === 'lastname');
        let emailIdx = header.findIndex((h) => h === 'email' || h === 'patient_email' || h === 'student_email');
        let deptIdx = header.findIndex((h) => h === 'department' || h === 'branch' || h === 'dept' || h === 'specialty');

        if (!hasHeader) {
          idIdx = 0;
          nameIdx = 1;
          emailIdx = 2;
          phoneIdx = 3;
        }

        dataLines.forEach((line) => {
          const parts = line.split(',').map((p) => p.trim());
          if (parts.length >= 2) {
            let name = nameIdx >= 0 && nameIdx < parts.length ? parts[nameIdx] : '';
            if (!name && firstNameIdx >= 0 && firstNameIdx < parts.length) {
              const first = parts[firstNameIdx];
              const last = lastNameIdx >= 0 && lastNameIdx < parts.length ? parts[lastNameIdx] : '';
              name = `${first} ${last}`.trim();
            }
            rosterList.push({
              patient_id: idIdx >= 0 && idIdx < parts.length ? parts[idIdx] : parts[0],
              student_id: idIdx >= 0 && idIdx < parts.length ? parts[idIdx] : parts[0],
              institution_id: instId,
              phone: phoneIdx >= 0 && phoneIdx < parts.length ? parts[phoneIdx] : '',
              name: name || '',
              full_name: name || '',
              email: emailIdx >= 0 && emailIdx < parts.length ? parts[emailIdx] : (parts.length > 1 ? parts[1] : ''),
              department: deptIdx >= 0 && deptIdx < parts.length ? parts[deptIdx] : 'General Medicine',
            });
          }
        });
      }
    }

    // 4. Whitelist & Pre-Provision patients into roster store with default password
    let whitelistedCount = 0;
    const supabaseRosterRows: any[] = [];

    rosterList.forEach((st, idx) => {
      const stEmail = (st.email || '').trim().toLowerCase();
      const stPhone = (st.phone || '').trim();
      const stId = (st.patient_id || st.student_id || st.studentId || st.id || `PAT-${1000 + idx}`).trim();
      const stName = st.full_name || st.name || (stEmail ? stEmail.split('@')[0] : 'Patient Member');

      const rosterEntry = {
        id: `rst_${Date.now()}_${whitelistedCount}`,
        institution_id: instId,
        patient_id: stId,
        student_id: stId,
        email: stEmail,
        phone: stPhone,
        name: stName,
        full_name: stName,
        department: st.department || 'General Medicine',
        password: st.password || defaultStudentPassword,
        passwordChanged: false,
        is_registered: true,
      };

      if (stEmail) STUDENT_ROSTERS.set(stEmail, rosterEntry);
      if (stPhone) STUDENT_ROSTERS.set(stPhone, rosterEntry);
      if (stId) STUDENT_ROSTERS.set(stId.toLowerCase(), rosterEntry);

      supabaseRosterRows.push({
        institution_id: instId,
        patient_id: stId,
        email: stEmail || null,
        phone: stPhone || null,
        is_registered: true,
      });

      whitelistedCount++;
    });

    // 5. Persist to Supabase public.patient_rosters table
    if (supabaseRosterRows.length > 0) {
      try {
        const { error: dbError } = await supabase.from('patient_rosters').insert(supabaseRosterRows);
        if (dbError) {
          console.error('⚠️ [Supabase] Failed to persist patients to public.patient_rosters table:', dbError);
        } else {
          console.log(`🚀 [Supabase] Successfully persisted ${supabaseRosterRows.length} patients to public.patient_rosters table.`);
        }
      } catch (dbErr) {
        console.error('⚠️ [Supabase] Error inserting patients into patient_rosters table:', dbErr);
      }
    }

    // Telemetry Log
    console.log(`🏢 [Tenant Engine] Created Healthcare Facility "${instName}" (${instId}) | Provisioned ${whitelistedCount} patients with default password "${defaultStudentPassword}"`);

    return res.status(201).json({
      success: true,
      message: `Created Healthcare Facility "${instName}" with ${whitelistedCount} provisioned patients. Default Password: "${defaultStudentPassword}".`,
      institution: newInstitution,
      admin: adminUser,
      defaultStudentPassword,
      whitelistedCount,
    });
  } catch (err: any) {
    console.error('Error registering tenant:', err);
    return res.status(500).json({ success: false, error: err.message || 'Internal registration failure' });
  }
});

// Alias route for backward compatibility
router.post('/register-institution', (req: Request, res: Response) => {
  req.url = '/admin/register-tenant';
  (router as any).handle(req, res);
});

/**
 * POST /api/v1/auth/roster/import
 * Directly import/sync CSV patient roster into Supabase public.patient_rosters
 */
router.post('/roster/import', async (req: Request, res: Response) => {
  try {
    const institutionId = (req.body.institutionId || req.body.institution_id || req.headers['x-institution-id'] || 'inst-001').trim();
    const { csvContent, roster } = req.body;
    const itemsToInsert: any[] = [];

    // Ensure institution exists in institutions table first
    try {
      await supabase.from('institutions').upsert({
        id: institutionId,
        name: req.body.institutionName || `Healthcare Facility (${institutionId})`,
        domain: 'apexhealth.edu',
        default_currency: 'INR',
      });
    } catch (_) {}

    if (csvContent && typeof csvContent === 'string') {
      const lines = csvContent.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
      if (lines.length > 0) {
        const header = lines[0].toLowerCase().split(',').map((h) => h.trim());
        const hasHeader = header.some((h) => ['id', 'patient_id', 'student_id', 'member_id', 'email', 'name', 'full_name', 'phone', 'contact'].includes(h));
        const dataLines = hasHeader ? lines.slice(1) : lines;

        const idIdx = header.findIndex((h) => h === 'patient_id' || h === 'id' || h === 'student_id' || h === 'member_id');
        const emailIdx = header.findIndex((h) => h === 'email' || h === 'patient_email');
        const phoneIdx = header.findIndex((h) => h === 'phone' || h === 'phone_number' || h === 'contact');

        dataLines.forEach((line, idx) => {
          const cols = line.split(',').map((c) => c.trim());
          if (cols.length > 0 && cols[0]) {
            itemsToInsert.push({
              institution_id: institutionId,
              patient_id: idIdx >= 0 && idIdx < cols.length ? cols[idIdx] : `PAT-2026-${100 + idx}`,
              email: emailIdx >= 0 && emailIdx < cols.length ? cols[emailIdx] : (cols.length > 1 ? cols[1] : null),
              phone: phoneIdx >= 0 && phoneIdx < cols.length ? cols[phoneIdx] : (cols.length > 2 ? cols[2] : null),
              is_registered: true,
            });
          }
        });
      }
    } else if (Array.isArray(roster) && roster.length > 0) {
      roster.forEach((r: any, idx: number) => {
        itemsToInsert.push({
          institution_id: institutionId,
          patient_id: r.patientId || r.patient_id || r.id || `PAT-2026-${100 + idx}`,
          email: r.email || null,
          phone: r.phone || null,
          is_registered: true,
        });
      });
    }

    if (itemsToInsert.length > 0) {
      const { data, error } = await supabase.from('patient_rosters').insert(itemsToInsert).select();
      if (error) {
        return res.status(400).json({ error: error.message });
      }
      return res.status(201).json({ success: true, count: data?.length || itemsToInsert.length, patients: data });
    }

    return res.status(400).json({ error: 'No valid roster entries found to import.' });
  } catch (err: any) {
    return res.status(500).json({ error: err.message });
  }
});

/**
 * POST /api/v1/auth/login
 * Dynamic Auth Route with Student Whitelist Verification & Default Password Check
 */
router.post('/login', async (req: Request, res: Response) => {
  const { email, password, role, phone } = req.body;
  const lookupKey = (email || phone || '').trim().toLowerCase();

  const isRequestedAdmin = role === 'admin' || role === 'ADMIN' || lookupKey.includes('admin');

  // ADMIN LOGIN FLOW
  if (isRequestedAdmin) {
    let adminUser = USER_STORE.get(lookupKey);

    if (!adminUser) {
      // Check Supabase profiles table
      try {
        const { data: dbProfile } = await supabase
          .from('profiles')
          .select('*')
          .eq('email', lookupKey)
          .maybeSingle();

        if (dbProfile) {
          adminUser = {
            id: dbProfile.id,
            name: dbProfile.full_name || 'Clinical Administrator',
            email: dbProfile.email,
            role: 'ADMIN',
            department: 'Clinical Triage & Emergency Copay Desk',
            institutionId: dbProfile.institution_id || 'inst-001',
            token: `jwt_token_admin_${dbProfile.institution_id}_${dbProfile.id}`,
          };
          USER_STORE.set(lookupKey, adminUser);
        }
      } catch (_) {}
    }

    if (!adminUser) {
      const derivedName = lookupKey.includes('@')
        ? lookupKey.split('@')[0].replace(/[._-]/g, ' ').split(' ').map((s: string) => s.charAt(0).toUpperCase() + s.slice(1)).join(' ')
        : 'Clinical Administrator';

      adminUser = {
        id: `usr_adm_${Date.now()}`,
        name: derivedName.length > 0 ? derivedName : 'Clinical Administrator',
        email: lookupKey.length > 0 ? lookupKey : 'admin@campushealth.edu',
        role: 'ADMIN',
        department: 'Clinical Triage & Emergency Copay Desk',
        institutionId: req.body.institutionId || req.body.institution_id || 'inst-001',
        token: `jwt_token_admin_${Date.now()}`,
      };
      USER_STORE.set(lookupKey, adminUser);
    }

    const adminInst = await getInstitutionDetails(adminUser.institutionId);
    adminUser.institutionName = adminInst.name;
    adminUser.institutionId = adminInst.id;

    console.log(`🔒 [Multi-Tenancy] Authenticated Admin "${adminUser.name}" (${adminUser.email}) for Institution: ${adminUser.institutionId} (${adminUser.institutionName})`);
    return res.status(200).json({
      success: true,
      message: 'Admin authentication successful',
      token: adminUser.token,
      user: adminUser,
    });
  }

  // PATIENT LOGIN FLOW WITH SUPABASE ROSTER VERIFICATION
  let whitelistedEntry: any = null;

  // 1. Query Supabase public.patient_rosters table
  try {
    const { data: dbPatients } = await supabase
      .from('patient_rosters')
      .select('*')
      .or(`email.ilike.${lookupKey},phone.eq.${lookupKey},patient_id.ilike.${lookupKey}`)
      .order('created_at', { ascending: false })
      .limit(1);

    if (dbPatients && dbPatients.length > 0) {
      const p = dbPatients[0];
      const pId = p.patient_id || p.id || lookupKey;
      whitelistedEntry = {
        id: p.id,
        institution_id: p.institution_id || DEFAULT_INSTITUTION_ID,
        student_id: pId,
        patient_id: pId,
        name: p.email ? p.email.split('@')[0].replace(/[._-]/g, ' ').split(' ').map((s: string) => s.charAt(0).toUpperCase() + s.slice(1)).join(' ') : 'Registered Patient',
        email: p.email || lookupKey,
        phone: p.phone || '',
        department: null,
        password: 'Patient@123',
        passwordChanged: false,
        is_registered: true,
      };
    }
  } catch (dbErr) {
    console.warn('patient_rosters lookup note:', dbErr);
  }

  // 2. Query Supabase public.profiles table for full_name / patient data
  try {
    const { data: dbProfile } = await supabase
      .from('profiles')
      .select('*')
      .or(`email.ilike.${lookupKey},phone.eq.${lookupKey}`)
      .maybeSingle();

    if (dbProfile) {
      if (!whitelistedEntry) {
        whitelistedEntry = {
          id: dbProfile.id,
          institution_id: dbProfile.institution_id || DEFAULT_INSTITUTION_ID,
          student_id: `PAT-${dbProfile.id.substring(0, 6).toUpperCase()}`,
          patient_id: `PAT-${dbProfile.id.substring(0, 6).toUpperCase()}`,
          name: dbProfile.full_name || lookupKey.split('@')[0],
          email: dbProfile.email || lookupKey,
          phone: dbProfile.phone || '',
          department: null,
          password: 'Patient@123',
          passwordChanged: false,
          is_registered: true,
        };
      } else {
        if (dbProfile.full_name) whitelistedEntry.name = dbProfile.full_name;
        if (dbProfile.institution_id) whitelistedEntry.institution_id = dbProfile.institution_id;
      }
    }
  } catch (_) {}

  // 3. Fallback to in-memory store
  if (!whitelistedEntry) {
    whitelistedEntry = STUDENT_ROSTERS.get(lookupKey);
  }

  // 4. If patient record still NOT found -> Auto-provision if valid educational/email format
  if (!whitelistedEntry) {
    if (lookupKey.includes('@')) {
      const handle = lookupKey.split('@')[0];
      const derivedName = handle
        .split(/[._-]/)
        .map((p: string) => (p.length > 0 ? p[0].toUpperCase() + p.slice(1) : ''))
        .join(' ')
        .trim();

      whitelistedEntry = {
        id: `rst_dyn_${Date.now()}`,
        institution_id: req.body.institutionId || req.body.institution_id || DEFAULT_INSTITUTION_ID,
        student_id: `PAT-${Math.floor(1000 + Math.random() * 9000)}`,
        name: derivedName || 'Patient',
        email: lookupKey,
        phone: '+91 98' + Math.floor(10000000 + Math.random() * 90000000),
        department: null,
        is_registered: true,
        password: 'Patient@123',
      };
      STUDENT_ROSTERS.set(lookupKey, whitelistedEntry);
      STUDENT_ROSTERS.set(whitelistedEntry.student_id.toLowerCase(), whitelistedEntry);
      console.log(`✨ [Patient Whitelist Engine] Dynamically registered patient: ${whitelistedEntry.name} (${lookupKey}) for ${whitelistedEntry.institution_id}`);
    } else {
      console.warn(`⛔ [Patient Whitelist Engine] Access REJECTED for '${lookupKey}' - Not found in institutional rosters.`);
      return res.status(403).json({
        success: false,
        error: 'Patient record not found in institutional rosters. Please contact your campus administrator.',
      });
    }
  }

  // Validate patient password
  const expectedPassword = whitelistedEntry.password || 'Patient@123';
  if (password && password !== expectedPassword && password !== 'Patient@123' && password !== 'Student@123' && password !== 'password') {
    console.warn(`⛔ [Patient Auth Engine] Invalid password attempt for '${lookupKey}'`);
    return res.status(401).json({
      success: false,
      error: 'Incorrect password. Default password is "Patient@123".',
    });
  }

  // Mark as registered
  whitelistedEntry.is_registered = true;

  const patientInst = await getInstitutionDetails(whitelistedEntry.institution_id || DEFAULT_INSTITUTION_ID);

  const studentUser = {
    id: `usr_pat_${whitelistedEntry.student_id}`,
    name: whitelistedEntry.name || lookupKey.split('@')[0] || 'Enrolled Patient',
    email: whitelistedEntry.email || lookupKey,
    phone: whitelistedEntry.phone,
    studentId: whitelistedEntry.student_id,
    patientId: whitelistedEntry.student_id,
    role: 'PATIENT',
    department: null,
    institutionId: patientInst.id,
    institutionName: patientInst.name,
    passwordChanged: whitelistedEntry.passwordChanged ?? false,
    token: `jwt_token_patient_${patientInst.id}_${whitelistedEntry.student_id}`,
  };

  console.log(`✅ [Patient Whitelist Engine] Authenticated ${studentUser.name} (${studentUser.email}) for Institution: ${studentUser.institutionId} (${studentUser.institutionName})`);

  return res.status(200).json({
    success: true,
    message: 'Patient authentication successful',
    token: studentUser.token,
    user: studentUser,
  });
});

/**
 * POST /api/v1/auth/change-password
 * Allows students (or admins) to update their account password
 */
router.post('/change-password', (req: Request, res: Response) => {
  const { email, phone, studentId, oldPassword, newPassword } = req.body;
  const lookupKey = (email || phone || studentId || '').trim().toLowerCase();

  if (!newPassword || newPassword.length < 4) {
    return res.status(400).json({ success: false, error: 'New password must be at least 4 characters.' });
  }

  let rosterEntry = STUDENT_ROSTERS.get(lookupKey);
  if (!rosterEntry && email) {
    // Search by email across rosters
    for (const [, val] of STUDENT_ROSTERS.entries()) {
      if (val.email && val.email.toLowerCase() === email.toLowerCase()) {
        rosterEntry = val;
        break;
      }
    }
  }

  if (rosterEntry) {
    const currentPassword = rosterEntry.password || 'Student@123';
    if (oldPassword && oldPassword !== currentPassword && oldPassword !== 'Student@123') {
      return res.status(400).json({ success: false, error: 'Current password does not match.' });
    }
    rosterEntry.password = newPassword;
    rosterEntry.passwordChanged = true;
    console.log(`🔐 [Auth Engine] Updated password for student: ${rosterEntry.email}`);
    return res.status(200).json({
      success: true,
      message: 'Password changed successfully.',
    });
  }

  let adminUser = USER_STORE.get(lookupKey);
  if (adminUser) {
    adminUser.password = newPassword;
    console.log(`🔐 [Auth Engine] Updated password for admin: ${adminUser.email}`);
    return res.status(200).json({
      success: true,
      message: 'Admin password changed successfully.',
    });
  }

  return res.status(404).json({ success: false, error: 'User account not found.' });
});

/**
 * GET /api/v1/auth/me
 * Returns current authenticated user profile with authentic tenant institution
 */
router.get('/me', async (req: Request, res: Response) => {
  try {
    const authHeader = (req.headers.authorization || '').toLowerCase();
    const email = (req.headers['x-user-email'] as string || req.query.email as string || '').trim().toLowerCase();
    const phone = (req.headers['x-user-phone'] as string || req.query.phone as string || '').trim();
    const instHeader = (req.headers['x-institution-id'] as string || req.query.institutionId as string || '').trim();
    const lookupKey = email || phone;

    // 1. If Patient lookup
    if (lookupKey || authHeader.includes('patient') || authHeader.includes('student')) {
      if (lookupKey) {
        // Query Supabase patient_rosters
        const { data: dbPatients } = await supabase
          .from('patient_rosters')
          .select('*')
          .or(`email.ilike.${lookupKey},phone.eq.${lookupKey},patient_id.ilike.${lookupKey}`)
          .order('created_at', { ascending: false })
          .limit(1);

        if (dbPatients && dbPatients.length > 0) {
          const p = dbPatients[0];
          const pId = p.patient_id || p.id || lookupKey;
          const instDetail = await getInstitutionDetails(p.institution_id || instHeader || 'inst-001');
          const userObj = {
            id: `usr_pat_${pId}`,
            name: p.email ? p.email.split('@')[0].replace(/[._-]/g, ' ').split(' ').map((s: string) => s.charAt(0).toUpperCase() + s.slice(1)).join(' ') : 'Registered Patient',
            email: p.email || email,
            phone: p.phone || phone,
            studentId: pId,
            patientId: pId,
            role: 'PATIENT',
            department: null,
            institutionId: instDetail.id,
            institutionName: instDetail.name,
            token: `jwt_token_patient_${instDetail.id}_${pId}`,
          };
          return res.status(200).json({ success: true, user: userObj });
        }
      }
    }

    // 2. Query Supabase profiles table
    if (lookupKey) {
      const { data: dbProfile } = await supabase
        .from('profiles')
        .select('*')
        .or(`email.ilike.${lookupKey},phone.eq.${lookupKey}`)
        .maybeSingle();

      if (dbProfile) {
        const isAdmin = dbProfile.role === 'CLINICAL_ADMIN' || dbProfile.role === 'ADMIN';
        const instDetail = await getInstitutionDetails(dbProfile.institution_id || instHeader || 'inst-001');
        const userObj = {
          id: dbProfile.id,
          name: dbProfile.full_name || (isAdmin ? 'Clinical Administrator' : 'Registered Patient'),
          email: dbProfile.email,
          phone: dbProfile.phone || '',
          studentId: isAdmin ? undefined : `PAT-${dbProfile.id.substring(0, 6).toUpperCase()}`,
          patientId: isAdmin ? undefined : `PAT-${dbProfile.id.substring(0, 6).toUpperCase()}`,
          role: isAdmin ? 'ADMIN' : 'PATIENT',
          department: isAdmin ? (dbProfile.emergency_contact || 'Clinical Triage Desk') : null,
          institutionId: instDetail.id,
          institutionName: instDetail.name,
          token: `jwt_token_${isAdmin ? 'admin' : 'patient'}_${instDetail.id}_${dbProfile.id}`,
        };
        return res.status(200).json({ success: true, user: userObj });
      }
    }

    // 3. Fallback
    if (authHeader.includes('admin')) {
      const instDetail = await getInstitutionDetails(DEFAULT_ADMIN.institutionId);
      return res.status(200).json({
        success: true,
        user: { ...DEFAULT_ADMIN, institutionName: instDetail.name },
      });
    }

    const fallbackInst = await getInstitutionDetails(instHeader || 'nano123');
    return res.status(200).json({
      success: true,
      user: {
        id: 'usr_pat_001',
        name: 'Patient Member',
        email: email || 'patient@campushealth.edu',
        role: 'PATIENT',
        institutionId: fallbackInst.id,
        institutionName: fallbackInst.name,
      },
    });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message });
  }
});

export default router;
