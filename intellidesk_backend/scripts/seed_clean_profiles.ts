import 'dotenv/config';
import { v4 as uuidv4 } from 'uuid';
import { supabase } from '../src/config/supabase.js';

async function seedCleanProfiles() {
  console.log('🌱 Seeding 1 Admin and 3 Empty Patient Profiles for testing...');

  const institutionId = 'nano123';

  // 1. Ensure institution exists
  const { error: instErr } = await supabase.from('institutions').upsert({
    id: institutionId,
    name: 'Nano Health Institute',
    domain: 'nano.org',
    default_currency: 'INR',
  });

  if (instErr) {
    console.error('Error inserting institution:', instErr.message);
  } else {
    console.log(`✅ Institution configured: Nano Health Institute (${institutionId})`);
  }

  // 2. Admin Profile
  const adminId = '8820aa4c-4456-46f2-a66c-c3d9948b7c70';
  const adminProfile = {
    id: adminId,
    email: 'admin@nano.org',
    full_name: 'Dr. Aditya',
    role: 'CLINICAL_ADMIN',
    institution_id: institutionId,
    phone: '+91 98111 22334',
    emergency_contact: 'Clinical Triage & Emergency Copay Desk',
    alerts_enabled: true,
  };

  const { error: adminErr } = await supabase.from('profiles').upsert(adminProfile);
  if (adminErr) {
    console.error('Error inserting admin profile:', adminErr.message);
  } else {
    console.log(`✅ Seeded Clinical Admin: ${adminProfile.full_name} (${adminProfile.email})`);
  }

  // 3. 3 Empty Patient Profiles of the same institution
  const patientProfiles = [
    {
      id: '37b0412f-f63f-4f2a-af2d-e8af00233a55',
      email: 'priya.sharma@campushealth.edu',
      full_name: 'Priya Sharma',
      role: 'PATIENT',
      institution_id: institutionId,
      phone: '+91 98111 22334',
    },
    {
      id: uuidv4(),
      email: 'patient1@nano.org',
      full_name: 'Patient Alpha',
      role: 'PATIENT',
      institution_id: institutionId,
      phone: '+91 98111 00001',
    },
    {
      id: uuidv4(),
      email: 'patient2@nano.org',
      full_name: 'Patient Beta',
      role: 'PATIENT',
      institution_id: institutionId,
      phone: '+91 98111 00002',
    },
  ];

  for (const pat of patientProfiles) {
    const { error: patErr } = await supabase.from('profiles').upsert(pat);
    if (patErr) {
      console.error(`Error inserting patient ${pat.email}:`, patErr.message);
    } else {
      console.log(`✅ Seeded Patient Profile: ${pat.full_name} (${pat.email})`);
    }
  }

  // 4. Verification
  const { data: allProfiles } = await supabase
    .from('profiles')
    .select('id, full_name, email, role, institution_id');

  console.log('\n📊 CURRENT PROFILES TABLE:');
  for (const p of allProfiles || []) {
    console.log(`   • [${p.role}] ${p.full_name.padEnd(20)} | email: ${p.email.padEnd(32)} | inst: ${p.institution_id}`);
  }

  process.exit(0);
}

seedCleanProfiles().catch(console.error);
