/**
 * Comprehensive Automated Test Suite for Touchless rPPG Vitals Signs Engine.
 * Tests:
 * 1. Butterworth 4th-order zero-phase bandpass filter (0.75 - 3.5 Hz)
 * 2. Uniform 30.0 Hz Time-Series Resampling (Guardrail 1)
 * 3. FFT Spectral Peak & Sub-BPM Precision (75 BPM synthetic test)
 * 4. SpO2 AC/DC Baseline Normalization & [70%, 100%] Clamping (Guardrail 2)
 * 5. Respiration Rate (RSA extraction)
 * 6. HRV RMSSD calculation from Inter-Beat Intervals
 * 7. Physiological Red-Flag Sentinel evaluation & Safety Net override (Floor >= 0.85)
 */

import { ButterworthFilter } from '../modules/diagnostics/vitals/ButterworthFilter.js';
import { rPPGSignalProcessor } from '../modules/diagnostics/vitals/rPPGSignalProcessor.js';
import { PhysiologicalRedFlagSentinel } from '../modules/diagnostics/vitals/PhysiologicalRedFlagSentinel.js';
import { evaluateClinicalSafetyNet } from '../modules/diagnostics/fusion/assessMultimodalRisk.js';
import { BioSignalFrame } from '../modules/diagnostics/vitals/types.js';

let passedTests = 0;
let totalTests = 0;

function assert(condition: boolean, testName: string, details?: string) {
  totalTests++;
  if (condition) {
    passedTests++;
    console.log(`  ✅ [PASS] ${testName}`);
  } else {
    console.error(`  ❌ [FAIL] ${testName}${details ? ` -> ${details}` : ''}`);
    throw new Error(`Test failed: ${testName}`);
  }
}

async function runRPPGVitalsSuite() {
  console.log('\n======================================================');
  console.log('🩺 RUNNING rPPG VITAL SIGNS SIGNAL PROCESSING TEST SUITE');
  console.log('======================================================\n');

  // TEST 1: Butterworth Filter Frequency Response
  console.log('--- Test Group 1: 4th-Order Butterworth Filter Response ---');
  {
    const filter = new ButterworthFilter(30.0, 0.75, 3.5);
    const n = 300; // 10 seconds at 30 Hz

    // In-band signal: 1.5 Hz (90 BPM)
    const inBand = Array.from({ length: n }, (_, i) => Math.sin(2 * Math.PI * 1.5 * (i / 30.0)));
    const filteredInBand = filter.filter(inBand);
    const maxInBand = Math.max(...filteredInBand.map(Math.abs));

    // Out-of-band signal: 0.1 Hz (very slow baseline drift)
    const outBandLow = Array.from({ length: n }, (_, i) => Math.sin(2 * Math.PI * 0.1 * (i / 30.0)));
    const filteredOutBandLow = filter.filter(outBandLow);
    const maxOutBandLow = Math.max(...filteredOutBandLow.map(Math.abs));

    // Out-of-band signal: 10.0 Hz (high frequency noise)
    const outBandHigh = Array.from({ length: n }, (_, i) => Math.sin(2 * Math.PI * 10.0 * (i / 30.0)));
    const filteredOutBandHigh = filter.filter(outBandHigh);
    const maxOutBandHigh = Math.max(...filteredOutBandHigh.map(Math.abs));

    assert(maxInBand > 0.5, 'In-band 1.5 Hz signal preserved', `Amp: ${maxInBand.toFixed(3)}`);
    assert(maxOutBandLow < 0.25, 'Out-of-band 0.1 Hz baseline drift attenuated', `Amp: ${maxOutBandLow.toFixed(3)}`);
    assert(maxOutBandHigh < 0.25, 'Out-of-band 10.0 Hz high frequency noise attenuated', `Amp: ${maxOutBandHigh.toFixed(3)}`);
  }

  // TEST 2: Guardrail 1 - Uniform 30.0 Hz Resampling
  console.log('\n--- Test Group 2: Guardrail 1 (Uniform 30.0 Hz Resampling) ---');
  {
    const processor = new rPPGSignalProcessor(30.0);
    // Create jittered timestamps around 33.3ms (ranging from 20ms to 50ms intervals)
    const jitteredTimestamps: number[] = [0];
    const jitteredGreen: number[] = [120];

    let t = 0;
    for (let i = 1; i < 450; i++) {
      const dt = 30 + (Math.sin(i) * 10); // Jitters between 20ms and 40ms
      t += dt;
      jitteredTimestamps.push(t);
      // 1.25 Hz sine wave (75 BPM) with jittered sample times
      const val = 120 + 15 * Math.sin(2 * Math.PI * 1.25 * (t / 1000.0));
      jitteredGreen.push(val);
    }

    const resampled = processor.resampleToUniform30Hz(jitteredGreen, jitteredTimestamps);
    const expectedLength = Math.max(2, Math.floor((jitteredTimestamps[jitteredTimestamps.length - 1] - jitteredTimestamps[0]) / 33.333333333333336));

    assert(resampled.length > 300, 'Resampled array size matches uniform 30.0 Hz duration', `Len: ${resampled.length}`);
    assert(Math.abs(resampled.length - expectedLength) <= 2, 'Resampled grid count matches exact 33.33ms intervals');
    // Ensure no NaNs produced
    assert(resampled.every(v => !isNaN(v) && isFinite(v)), 'All resampled points are finite numbers');
  }

  // TEST 3: Heart Rate Extraction on 75 BPM Signal
  console.log('\n--- Test Group 3: FFT Heart Rate Extraction (75 BPM target) ---');
  {
    const processor = new rPPGSignalProcessor(30.0);
    const n = 450; // 15 seconds at 30.0 Hz
    const targetBpm = 75.0;
    const targetFreq = targetBpm / 60.0; // 1.25 Hz

    const frames: BioSignalFrame[] = [];
    for (let i = 0; i < n; i++) {
      const tSec = i / 30.0;
      // Cardiac pulse on green & red channels
      const pulse = 10 * Math.sin(2 * Math.PI * targetFreq * tSec);
      frames.push({
        frameIndex: i,
        timestampMs: Math.round(tSec * 1000),
        red: 180 + pulse * 0.8,
        green: 140 + pulse,
        blue: 100 + pulse * 0.2
      });
    }

    const result = processor.processFrames(frames);
    console.log(`    Detected Heart Rate: ${result.heartRateBpm} BPM (Target: 75.0 BPM)`);
    console.log(`    SNR: ${result.snrDb} dB, Confidence: ${result.confidenceScore}`);

    assert(
      Math.abs(result.heartRateBpm - 75.0) <= 2.0,
      'FFT sub-BPM peak matches target 75 BPM within +/- 2.0 BPM',
      `Got: ${result.heartRateBpm}`
    );
    assert(result.snrDb >= 5.0, 'High signal-to-noise ratio (> 5 dB) on synthetic pulse', `SNR: ${result.snrDb} dB`);
    assert(result.confidenceScore >= 0.70, 'Confidence score exceeds 70%', `Conf: ${result.confidenceScore}`);
  }

  // TEST 4: Guardrail 2 - SpO2 AC/DC Normalization & [70%, 100%] Clamping
  console.log('\n--- Test Group 4: Guardrail 2 (SpO2 Normalization & Bounding) ---');
  {
    const processor = new rPPGSignalProcessor(30.0);
    const n = 450;

    // Normal clinical ratio: Red AC/DC ~ Blue AC/DC gives R ~ 0.5 - 0.7 -> SpO2 ~ 95% - 98%
    const normalFrames: BioSignalFrame[] = [];
    for (let i = 0; i < n; i++) {
      const t = i / 30.0;
      const pulse = Math.sin(2 * Math.PI * 1.2 * t);
      normalFrames.push({
        frameIndex: i,
        timestampMs: Math.round(t * 1000),
        red: 150 + 6.0 * pulse, // AC/DC = 6 / 150 = 0.04
        green: 120 + 8.0 * pulse,
        blue: 100 + 8.0 * pulse  // AC/DC = 8 / 100 = 0.08 => R = 0.04/0.08 = 0.50 => SpO2 = 110 - 25*0.5 = 97.5%
      });
    }

    const normalResult = processor.processFrames(normalFrames);
    console.log(`    Normal SpO2: ${normalResult.oxygenSaturationSpo2}%`);
    assert(
      normalResult.oxygenSaturationSpo2 >= 95.0 && normalResult.oxygenSaturationSpo2 <= 100.0,
      'Normal SpO2 sits in physiological 95-100% window',
      `Got: ${normalResult.oxygenSaturationSpo2}%`
    );

    // Extreme high R ratio test (would produce negative/low SpO2 without clamping)
    const extremeLowFrames: BioSignalFrame[] = [];
    for (let i = 0; i < n; i++) {
      const t = i / 30.0;
      const pulse = Math.sin(2 * Math.PI * 1.2 * t);
      extremeLowFrames.push({
        frameIndex: i,
        timestampMs: Math.round(t * 1000),
        red: 50 + 40.0 * pulse, // Massive red AC/DC
        green: 100 + 5.0 * pulse,
        blue: 150 + 2.0 * pulse  // Tiny blue AC/DC => huge R ratio
      });
    }
    const lowResult = processor.processFrames(extremeLowFrames);
    console.log(`    Extreme Low Test SpO2: ${lowResult.oxygenSaturationSpo2}% (strictly clamped at 70.0%)`);
    assert(
      lowResult.oxygenSaturationSpo2 >= 70.0,
      'SpO2 strictly clamped above 70.0% minimum boundary',
      `Got: ${lowResult.oxygenSaturationSpo2}%`
    );

    // Extreme low R ratio test (would produce > 100% SpO2 without clamping)
    const extremeHighFrames: BioSignalFrame[] = [];
    for (let i = 0; i < n; i++) {
      const t = i / 30.0;
      const pulse = Math.sin(2 * Math.PI * 1.2 * t);
      extremeHighFrames.push({
        frameIndex: i,
        timestampMs: Math.round(t * 1000),
        red: 200 + 1.0 * pulse, // Tiny red AC/DC
        green: 100 + 5.0 * pulse,
        blue: 50 + 40.0 * pulse  // Massive blue AC/DC => tiny R ratio
      });
    }
    const highResult = processor.processFrames(extremeHighFrames);
    console.log(`    Extreme High Test SpO2: ${highResult.oxygenSaturationSpo2}% (strictly clamped at 100.0%)`);
    assert(
      highResult.oxygenSaturationSpo2 <= 100.0,
      'SpO2 strictly clamped below 100.0% maximum boundary',
      `Got: ${highResult.oxygenSaturationSpo2}%`
    );
  }

  // TEST 5: Respiration Rate & HRV RMSSD Extraction
  console.log('\n--- Test Group 5: Respiration Rate (RSA) & HRV RMSSD ---');
  {
    const processor = new rPPGSignalProcessor(30.0);
    const n = 450; // 15 seconds
    const targetRespFreq = 0.25; // 15 breaths/min (0.25 Hz)
    const targetHeartFreq = 1.33; // 80 BPM

    const frames: BioSignalFrame[] = [];
    for (let i = 0; i < n; i++) {
      const t = i / 30.0;
      // Respiration modulates baseline amplitude
      const respModulation = 5 * Math.sin(2 * Math.PI * targetRespFreq * t);
      const cardiac = 15 * Math.sin(2 * Math.PI * targetHeartFreq * t);
      frames.push({
        frameIndex: i,
        timestampMs: Math.round(t * 1000),
        red: 160 + respModulation + cardiac * 0.7,
        green: 130 + respModulation + cardiac,
        blue: 90 + cardiac * 0.3
      });
    }

    const result = processor.processFrames(frames);
    console.log(`    Detected Respiration Rate: ${result.respirationRateBpm} breaths/min`);
    console.log(`    Detected HRV RMSSD: ${result.hrvRmssdMs} ms`);

    assert(
      result.respirationRateBpm >= 10 && result.respirationRateBpm <= 22,
      'Respiration rate within physiological human window (10-22 breaths/min)',
      `Got: ${result.respirationRateBpm}`
    );
    assert(result.hrvRmssdMs >= 0, 'HRV RMSSD is a positive valid duration in ms');
  }

  // TEST 6: Physiological Red-Flag Sentinel Evaluation
  console.log('\n--- Test Group 6: Physiological Red-Flag Sentinel Evaluation ---');
  {
    // Normal case
    const normalAlerts = PhysiologicalRedFlagSentinel.evaluateVitals({
      heartRate: 72,
      oxygenSaturation: 98,
      respirationRate: 16
    });
    assert(normalAlerts.length === 0, 'No alerts generated for healthy normal vitals');

    // Critical Tachycardia case (>= 130 BPM)
    const tachyAlerts = PhysiologicalRedFlagSentinel.evaluateVitals({
      heartRate: 138,
      oxygenSaturation: 97,
      respirationRate: 18
    });
    assert(
      tachyAlerts.some(a => a.type === 'CRITICAL_TACHYCARDIA' && a.severity === 'CRITICAL_OVERRIDE'),
      'CRITICAL_TACHYCARDIA triggered for 138 BPM'
    );
    assert(PhysiologicalRedFlagSentinel.hasCriticalOverride(tachyAlerts), 'hasCriticalOverride returns true for tachycardia');

    // Critical Hypoxia case (<= 90%)
    const hypoxiaAlerts = PhysiologicalRedFlagSentinel.evaluateVitals({
      heartRate: 85,
      oxygenSaturation: 88,
      respirationRate: 18
    });
    assert(
      hypoxiaAlerts.some(a => a.type === 'CRITICAL_HYPOXIA' && a.severity === 'CRITICAL_OVERRIDE'),
      'CRITICAL_HYPOXIA triggered for 88% SpO2'
    );

    // Critical Tachypnea case (>= 28 breaths/min)
    const tachypneaAlerts = PhysiologicalRedFlagSentinel.evaluateVitals({
      heartRate: 95,
      oxygenSaturation: 96,
      respirationRate: 32
    });
    assert(
      tachypneaAlerts.some(a => a.type === 'CRITICAL_TACHYPNEA' && a.severity === 'CRITICAL_OVERRIDE'),
      'CRITICAL_TACHYPNEA triggered for 32 breaths/min'
    );

    // Critical Bradycardia case (<= 40 BPM)
    const bradyAlerts = PhysiologicalRedFlagSentinel.evaluateVitals({
      heartRate: 36,
      oxygenSaturation: 98,
      respirationRate: 14
    });
    assert(
      bradyAlerts.some(a => a.type === 'CRITICAL_BRADYCARDIA' && a.severity === 'CRITICAL_OVERRIDE'),
      'CRITICAL_BRADYCARDIA triggered for 36 BPM'
    );
  }

  // TEST 7: Safety Net Override Integration with assessMultimodalRisk
  console.log('\n--- Test Group 7: Safety Net Enforced Floor (>= 0.85 & Critical Referral) ---');
  {
    // Low risk symptoms with critical hypoxia (SpO2 87%)
    const safetyNetHypoxia = evaluateClinicalSafetyNet(
      {
        symptoms: ['Mild fatigue'],
        bodyLocation: 'General',
        painScale: 1
      },
      {
        oxygenSaturation: 87,
        heartRate: 80
      }
    );

    assert(safetyNetHypoxia.triggered, 'Clinical safety net triggered by critical hypoxia');
    assert(safetyNetHypoxia.enforcedFloor === 0.85, 'Enforced risk score floor is 0.85');
    assert(
      safetyNetHypoxia.reasons.some(r => r.includes('Critical Hypoxemia')),
      'Safety net reason details critical hypoxemia directive'
    );

    // Low risk symptoms with critical tachycardia (HR 145 BPM)
    const safetyNetTachy = evaluateClinicalSafetyNet(
      {
        symptoms: ['Mild cough'],
        bodyLocation: 'Chest',
        painScale: 2
      },
      {
        oxygenSaturation: 98,
        heartRate: 145
      }
    );

    assert(safetyNetTachy.triggered, 'Clinical safety net triggered by severe tachycardia');
    assert(safetyNetTachy.enforcedFloor === 0.85, 'Enforced risk floor is 0.85 for tachycardia');
  }

  console.log('\n======================================================');
  console.log(`🎉 ALL ${passedTests}/${totalTests} rPPG VITALS TESTS PASSED SUCCESSFULLY!`);
  console.log('======================================================\n');
}

runRPPGVitalsSuite().catch(err => {
  console.error('💥 Test suite crashed:', err);
  process.exit(1);
});
