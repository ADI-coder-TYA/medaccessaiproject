import dotenv from 'dotenv';
dotenv.config();

import { 
  interpretDiagnosticResult, 
  generateRogerianDiagnosticInterpretation,
  buildDiagnosticInterpretationPrompt,
  DiagnosticSummaryContext,
  MANDATORY_DISCLAIMER 
} from '../services/crisisCounselorService.js';

async function runDiagnosticInterpretationTests() {
  console.log('\n======================================================');
  console.log('🧪 Starting Qwen2.5 Diagnostic Interpretation Test Suite');
  console.log('======================================================\n');

  let passed = 0;
  let failed = 0;

  function assert(condition: boolean, msg: string) {
    if (condition) {
      console.log(`  ✅ PASS: ${msg}`);
      passed++;
    } else {
      console.error(`  ❌ FAIL: ${msg}`);
      failed++;
    }
  }

  // --------------------------------------------------------------------------
  // TEST 1: Prompt Construction for Qwen2.5
  // --------------------------------------------------------------------------
  console.log('--- TEST 1: Prompt Construction for Qwen2.5 ---');
  const moderateContext: DiagnosticSummaryContext = {
    riskTier: "Moderate Need",
    riskScore: 0.72,
    uncertainty: "±0.03",
    topFeatures: ["High Pain Scale", "Localized Skin Rash"],
    heatMapGenerated: true,
    primaryDiagnosis: "Localized Contact Dermatitis"
  };

  const moderatePrompt = buildDiagnosticInterpretationPrompt(moderateContext);
  assert(moderatePrompt.system.includes(MANDATORY_DISCLAIMER), 'System prompt contains exact mandatory disclaimer');
  assert(moderatePrompt.system.includes('MODERATE NEED'), 'System prompt specifies moderate need guidance');
  assert(moderatePrompt.system.includes('48 hours'), 'System prompt advises clinic consultation within 24-48 hours');
  assert(moderatePrompt.system.includes('cool compress'), 'System prompt includes comfort measures (cool compress)');
  assert(moderatePrompt.user.includes('72%'), 'User prompt contains risk score (72%)');
  assert(moderatePrompt.user.includes('High Pain Scale, Localized Skin Rash'), 'User prompt contains top features');

  // --------------------------------------------------------------------------
  // TEST 2: Critical Urgency Prompt & Next Steps
  // --------------------------------------------------------------------------
  console.log('\n--- TEST 2: Critical Urgency Prompt & Next Steps ---');
  const criticalContext: DiagnosticSummaryContext = {
    riskTier: "Critical Referral",
    riskScore: 0.88,
    uncertainty: "±0.02",
    topFeatures: ["Severe Pain (10/10)", "Chest Discomfort"],
    heatMapGenerated: false,
    primaryDiagnosis: "Acute Cardiopulmonary Discomfort"
  };

  const criticalPrompt = buildDiagnosticInterpretationPrompt(criticalContext);
  assert(criticalPrompt.system.includes('CRITICAL'), 'System prompt specifies critical urgency instructions');
  assert(criticalPrompt.system.includes('Emergency Room (ER)'), 'System prompt directs patient to ER / emergency services');

  // --------------------------------------------------------------------------
  // TEST 3: Rogerian PFA Diagnostic Interpretation Engine
  // --------------------------------------------------------------------------
  console.log('\n--- TEST 3: Rogerian PFA Diagnostic Interpretation Engine ---');
  const moderateInterpretation = generateRogerianDiagnosticInterpretation(moderateContext);
  assert(moderateInterpretation.includes(MANDATORY_DISCLAIMER), 'Moderate interpretation includes mandatory disclaimer');
  assert(moderateInterpretation.includes('48 hours'), 'Moderate interpretation recommends clinic consultation within 48 hours');
  assert(moderateInterpretation.includes('cold compress'), 'Moderate interpretation recommends cold compress');
  assert(moderateInterpretation.includes('Localized Contact Dermatitis'), 'Moderate interpretation references primary condition');
  assert(moderateInterpretation.includes('72% ±0.03'), 'Moderate interpretation displays formatted risk score ± uncertainty');

  const criticalInterpretation = generateRogerianDiagnosticInterpretation(criticalContext);
  assert(criticalInterpretation.includes(MANDATORY_DISCLAIMER), 'Critical interpretation includes mandatory disclaimer');
  assert(criticalInterpretation.includes('Emergency Room (ER)'), 'Critical interpretation directs to Emergency Room');
  assert(criticalInterpretation.includes('emergency services'), 'Critical interpretation mentions emergency services');

  // --------------------------------------------------------------------------
  // TEST 4: End-to-End interpretDiagnosticResult Service Function
  // --------------------------------------------------------------------------
  console.log('\n--- TEST 4: End-to-End interpretDiagnosticResult Service Function ---');
  const serviceResult = await interpretDiagnosticResult(moderateContext, 'Is this rash contagious?');

  assert(serviceResult.reply.length > 50, `Generated thorough reply (length: ${serviceResult.reply.length})`);
  assert(serviceResult.reply.includes(MANDATORY_DISCLAIMER), 'Service response strictly contains mandatory disclaimer');
  assert(serviceResult.reply.toLowerCase().includes('contag') || serviceResult.reply.toLowerCase().includes('towels'), 'Service response addresses contagion question');
  assert(serviceResult.isCrisisResponse === false, 'Moderate context flagged as non-crisis');
  assert(serviceResult.latencyMs >= 0, `Recorded execution latency: ${serviceResult.latencyMs}ms`);

  const criticalResult = await interpretDiagnosticResult(criticalContext, 'I feel very dizzy and short of breath');
  assert(criticalResult.reply.includes(MANDATORY_DISCLAIMER), 'Critical service response contains mandatory disclaimer');
  assert(criticalResult.isCrisisResponse === true, 'Critical context correctly flagged isCrisisResponse = true');
  assert(criticalResult.resources !== null && criticalResult.resources.length > 0, 'Critical context includes emergency hotline cards');

  // --------------------------------------------------------------------------
  // TEST 5: Low Risk Presentation
  // --------------------------------------------------------------------------
  console.log('\n--- TEST 5: Low Risk Presentation ---');
  const lowRiskContext: DiagnosticSummaryContext = {
    riskTier: "Low Risk",
    riskScore: 0.18,
    uncertainty: "±0.04",
    topFeatures: ["Mild Redness"],
    heatMapGenerated: true,
    primaryDiagnosis: "Mild Erythema"
  };

  const lowRiskResult = await interpretDiagnosticResult(lowRiskContext);
  assert(lowRiskResult.reply.includes(MANDATORY_DISCLAIMER), 'Low risk response contains mandatory disclaimer');
  assert(lowRiskResult.reply.toLowerCase().includes('monitoring') || lowRiskResult.reply.toLowerCase().includes('mild'), 'Low risk response offers gentle reassurance and monitoring');
  assert(lowRiskResult.isCrisisResponse === false, 'Low risk not flagged as crisis');

  console.log('\n======================================================');
  console.log(`📊 Interpretation Test Summary: ${passed} passed, ${failed} failed`);
  console.log('======================================================\n');

  if (failed > 0) {
    process.exit(1);
  }
}

runDiagnosticInterpretationTests().catch((err) => {
  console.error('Fatal test error:', err);
  process.exit(1);
});
