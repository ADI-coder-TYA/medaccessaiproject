import { exec } from 'child_process';
import { promisify } from 'util';
import fs from 'fs/promises';
import * as syncFs from 'fs';
import path from 'path';
import os from 'os';
import axios from 'axios';
import { createWorker } from 'tesseract.js';
import { createRequire } from 'module';
import { ExtractedMedication } from './types.js';
import { findBestRxNormMatch } from './fuzzyMatcher.js';

const execAsync = promisify(exec);
const require = createRequire(import.meta.url);
const pdfModule = require('pdf-parse');

/**
 * Technical Guardrail 3: OCR Text Sanitization & Character Swaps
 * Corrects common OCR misreads in clinical numbers and units before parsing:
 * - Replaces 'O'/'o' with '0' inside numeric tokens (e.g., 5O0mg -> 500mg, 1OOmg -> 100mg)
 * - Replaces lower 'l' or 'I' or '|' with '1' inside frequency patterns (e.g., I-0-1 -> 1-0-1)
 */
export function sanitizeOcrText(rawText: string): string {
  if (!rawText) return '';

  let sanitized = rawText;

  // 1. Swap 'O'/'o' with '0' inside numeric tokens followed by medical units (mg, mcg, ml, g, etc.)
  // Handle cases like 5O0mg, 1O0mg, 25Omg, 5Omg, 5O0 mg
  sanitized = sanitized.replace(/\b(\d*)[oO]+(\d*)\s*(mg|mcg|ml|g|gm|iu|mEq|tab|tabs|cap|caps)\b/gi, (match, prefix, suffix, unit) => {
    const fixedPrefix = (prefix || '').replace(/[oO]/gi, '0');
    const fixedSuffix = (suffix || '').replace(/[oO]/gi, '0');
    return `${fixedPrefix || '0'}0${fixedSuffix} ${unit}`.trim();
  });

  // Handle embedded O/o between digits (e.g., 5O0, 10O, 2O5)
  sanitized = sanitized.replace(/(\d+)[oO](\d+)/g, '$10$2');
  sanitized = sanitized.replace(/(\d+)[oO]\b/g, '$10');

  // 2. Fix frequency patterns like I-0-1, l-0-1, 1-O-1, I-I-I -> 1-0-1
  sanitized = sanitized.replace(/\b([1liI|oO0])-([1liI|oO0])-([1liI|oO0])\b/g, (match, p1, p2, p3) => {
    const d1 = /[liI|]/i.test(p1) ? '1' : /[oO]/i.test(p1) ? '0' : p1;
    const d2 = /[liI|]/i.test(p2) ? '1' : /[oO]/i.test(p2) ? '0' : p2;
    const d3 = /[liI|]/i.test(p3) ? '1' : /[oO]/i.test(p3) ? '0' : p3;
    return `${d1}-${d2}-${d3}`;
  });

  sanitized = sanitized.replace(/\b([1liI|oO0])-([1liI|oO0])\b/g, (match, p1, p2) => {
    const d1 = /[liI|]/i.test(p1) ? '1' : /[oO]/i.test(p1) ? '0' : p1;
    const d2 = /[liI|]/i.test(p2) ? '1' : /[oO]/i.test(p2) ? '0' : p2;
    return `${d1}-${d2}`;
  });

  // 3. Fix frequency words like "I time", "I tablet", "Ix daily", "l tab"
  sanitized = sanitized.replace(/\b[lI|]\s*(tab|tabs|tablet|tablets|cap|caps|capsule|capsules|time|times|x\s*daily)\b/gi, '1 $1');

  return sanitized;
}

/**
 * Extracts plain text from PDF buffer using Poppler pdftotext with in-memory pdf-parse fallback.
 */
export async function extractTextFromPdfBuffer(buffer: Buffer): Promise<string> {
  const tempPath = path.join(os.tmpdir(), `rx_pdf_${Date.now()}_${Math.random().toString(36).substring(7)}.pdf`);
  try {
    await fs.writeFile(tempPath, buffer);
    const { stdout } = await execAsync(`pdftotext -layout "${tempPath}" -`);
    if (stdout && stdout.trim().length > 0) {
      return stdout;
    }
  } catch {
    // pdftotext not available; continue to in-memory parser
  } finally {
    await fs.unlink(tempPath).catch(() => {});
  }

  try {
    const PDFParse = pdfModule.PDFParse || pdfModule.default?.PDFParse || (typeof pdfModule === 'function' ? pdfModule : null);
    if (PDFParse && typeof PDFParse === 'function') {
      try {
        const uint8 = new Uint8Array(buffer);
        const parser = new PDFParse(uint8);
        if (typeof parser.load === 'function') {
          await parser.load();
          const parsed = await parser.getText();
          if (parsed && typeof parsed === 'object' && parsed.text) return parsed.text;
          if (typeof parsed === 'string') return parsed;
        }
      } catch {
        const res = await (PDFParse as any)(buffer);
        if (res?.text) return res.text;
      }
    }
    if (typeof pdfModule === 'function') {
      const data = await pdfModule(buffer);
      return data.text || '';
    }
  } catch (err) {
    console.warn('[Prescription OCR] In-memory PDF parsing warning:', err);
  }

  return '';
}

/**
 * Open ML Model OCR via Hugging Face Vision router (e.g. Qwen2.5-VL / GLM-4.6V-Flash).
 * Gracefully times out or falls back to local Tesseract OCR on rate limits.
 */
export async function extractTextViaHuggingFaceVision(buffer: Buffer): Promise<string> {
  const hfToken = process.env.HF_TOKEN || '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';
  if (!hfToken) return '';

  const visionModels = [
    'zai-org/GLM-4.6V-Flash',
    'Qwen/Qwen2.5-VL-72B-Instruct',
    'deepseek-ai/DeepSeek-V4-Flash-Vision-Exp'
  ];

  const base64Data = buffer.toString('base64');
  const mimeType = buffer.slice(0, 4).toString('hex') === '89504e47' ? 'image/png' : 'image/jpeg';
  const dataUrl = `data:${mimeType};base64,${base64Data}`;

  for (const model of visionModels) {
    try {
      const response = await axios.post(
        'https://router.huggingface.co/v1/chat/completions',
        {
          model,
          messages: [
            {
              role: 'user',
              content: [
                {
                  type: 'text',
                  text: 'You are an expert clinical pharmacist and medical OCR system. Read and extract all handwritten and printed text from this doctor prescription image accurately. Transcribe all medication names, dosages, strengths, frequencies, durations, and clinical instructions exactly as written. Return ONLY the extracted text lines.'
                },
                {
                  type: 'image_url',
                  image_url: { url: dataUrl }
                }
              ]
            }
          ],
          max_tokens: 500,
          temperature: 0.1
        },
        {
          headers: {
            Authorization: `Bearer ${hfToken}`,
            'Content-Type': 'application/json'
          },
          timeout: 10000
        }
      );

      const content = response.data?.choices?.[0]?.message?.content;
      if (content && typeof content === 'string' && content.trim().length > 5) {
        console.log(`[Prescription OCR] ML Vision OCR Success using HuggingFace (${model})`);
        return content.trim();
      }
    } catch (err: any) {
      // If 429 or timeout, proceed to next or fallback
      console.warn(`[Prescription OCR] HuggingFace ML model ${model} unavailable:`, err?.response?.status || err?.message);
    }
  }

  return '';
}

/**
 * Universal image text extractor:
 * 1. Primary: HuggingFace Open Vision ML Model (cloud AI)
 * 2. Fallback: Local Tesseract OCR engine
 */
export async function extractTextFromImageBuffer(buffer: Buffer): Promise<string> {
  // 1. Try Hugging Face Open ML Vision Model first
  try {
    const mlText = await extractTextViaHuggingFaceVision(buffer);
    if (mlText && mlText.length > 10) {
      return mlText;
    }
  } catch (mlErr) {
    console.warn('[Prescription OCR] HF ML Vision primary extractor caught error:', mlErr);
  }

  // 2. Fallback to local Tesseract OCR engine
  const tempPath = path.join(os.tmpdir(), `rx_img_${Date.now()}_${Math.random().toString(36).substring(7)}.png`);
  try {
    await fs.writeFile(tempPath, buffer);
    const worker = await createWorker('eng');
    try {
      const ret = await worker.recognize(tempPath);
      return ret.data.text || '';
    } finally {
      await worker.terminate().catch(() => {});
    }
  } catch (ocrErr: any) {
    console.warn('[Prescription OCR] Local Tesseract OCR fallback warning:', ocrErr?.message || ocrErr);
    return '';
  } finally {
    await fs.unlink(tempPath).catch(() => {});
  }
}


/**
 * Universal text extractor for files, buffers, URLs, and text strings.
 */
export async function extractRawPrescriptionText(input: Buffer | string): Promise<string> {
  if (typeof input === 'string') {
    // If it's a URL or base64 data URI or file path
    if (input.startsWith('data:')) {
      const base64Data = input.split(',')[1] || input;
      const buffer = Buffer.from(base64Data, 'base64');
      return extractRawPrescriptionText(buffer);
    }
    if (input.startsWith('http://') || input.startsWith('https://')) {
      try {
        const response = await axios.get(input, { responseType: 'arraybuffer', timeout: 15000 });
        const buffer = Buffer.from(response.data);
        return extractRawPrescriptionText(buffer);
      } catch (dlErr) {
        console.warn('[Prescription OCR] Remote file download error:', dlErr);
        return '';
      }
    }
    if (syncFs.existsSync(input)) {
      const buffer = await fs.readFile(input);
      return extractRawPrescriptionText(buffer);
    }
    // Direct raw text input
    return input;
  }

  if (Buffer.isBuffer(input)) {
    const isPdf = input.slice(0, 4).toString() === '%PDF';
    if (isPdf) {
      return extractTextFromPdfBuffer(input);
    }
    return extractTextFromImageBuffer(input);
  }

  return '';
}

/**
 * Common medical, institutional, and clinical non-drug stop words.
 * Any candidate matching these will be rejected immediately.
 */
export const COMMON_MEDICAL_STOP_WORDS = new Set([
  'fever', 'cough', 'cold', 'headache', 'pain', 'chest pain', 'back pain', 'body ache',
  'hypertension', 'htn', 'diabetes', 'dm', 't2dm', 't1dm', 'asthma', 'copd', 'bronchitis',
  'pneumonia', 'infection', 'uti', 'vomiting', 'nausea', 'diarrhea', 'constipation',
  'acidity', 'gastritis', 'gerd', 'ulcer', 'rash', 'allergy', 'itching', 'swelling',
  'edema', 'weakness', 'fatigue', 'dizziness', 'vertigo', 'insomnia', 'migraine',
  'sinusitis', 'pharyngitis', 'tonsillitis', 'arthritis', 'spondylitis',
  'doctor', 'dr', 'physician', 'patient', 'hospital', 'clinic', 'center', 'centre',
  'address', 'street', 'road', 'floor', 'suite', 'block', 'sector', 'pin', 'zip',
  'date', 'time', 'male', 'female', 'years', 'yrs', 'age', 'sex', 'gender',
  'vitals', 'pulse', 'temp', 'temperature', 'blood', 'pressure', 'weight', 'height', 'bmi',
  'diagnosis', 'provisional', 'complaint', 'complaints', 'history', 'findings', 'impression',
  'investigation', 'investigations', 'tests', 'lab', 'xray', 'ecg', 'echo', 'usg',
  'advice', 'review', 'follow', 'visit', 'referral', 'signature', 'sign', 'seal', 'stamp',
  'morning', 'evening', 'night', 'afternoon', 'food', 'meals', 'water', 'bedtime',
  'tablets', 'capsules', 'syrup', 'injection', 'drops', 'ointment', 'cream', 'rx', 'take'
]);

/**
 * Known oral solid dosage strengths (mg) commonly written without explicit unit.
 * Used to safely contextualize "Augmentin 625" or "Dolo 650" without capturing arbitrary numbers.
 */
const COMMON_TABLET_STRENGTHS = new Set([
  5, 10, 20, 25, 40, 50, 75, 80, 100, 125, 150, 200, 250, 300, 375, 400, 500, 600, 625, 650, 750, 800, 850, 1000, 1200
]);

/**
 * Document-Wide Semantic Filter:
 * Detects hospital banners, clinic addresses, physician headers, patient vitals, clinical diagnoses, and notes.
 */
export function isNonMedicationLine(line: string): boolean {
  const lower = line.toLowerCase().trim();
  if (lower.length < 3) return true;

  // Institutional, administrative, and clinical note markers
  const nonMedRegexes = [
    /\b(hospital|clinic|center|centre|medical\s+center|health\s+center|nursing\s+home|infirmary|dispensary|healthcare|foundation)\b/i,
    /\b(avenue|ave\b|street|road|rd\b|lane|ln\b|blvd|boulevard|suite|ste\b|floor|fl\b|building|bldg|block|sector|plot|cross|pin\s*code|zip\s*code|postal)\b/i,
    /\b(phone|tel\b|telephone|mobile|mob\b|cell\b|fax|email|mail\b|website|web\b|www\.|https?)\b/i,
    /\b(doctor|dr\.|physician|consultant|specialist|surgeon|cardiologist|pediatrician|mbbs|md\b|ms\b|dm\b|mch\b|frcs|mrcp|facc|phd|reg\s*no|licen[sc]e|npi|dea)\b/i,
    /\b(patient\s*name|pt\s*name|patient\s*id|uhid|mrn|opd|ipd|admission|discharge|bed\s*no|room\s*no)\b/i,
    /\b(age\b|gender|sex\b|male|female|yrs|years\s*old|dob|date\s*of\s*birth|date\s*[:\=]|dated)\b/i,
    /\b(diagnosis|provisional\s*diagnosis|differential\s*diagnosis|chief\s*complaint|complaints|history|past\s*history|symptoms|findings|impression|assessment|plan|clinical\s*notes)\b/i,
    /\b(blood\s*pressure|bp\s*[:\=]|pulse\s*[:\=]|spo2|temperature|temp\s*[:\=]|weight|wt\b|height|ht\b|bmi|vitals|heart\s*rate|respiratory\s*rate)\b/i,
    /\b(investigation|investigations|advised\s*tests|lab\s*reports|x-ray|ecg|echo|usg|ct\s*scan|mri)\b/i,
    /\b(follow\s*up|next\s*visit|review\s*after|refer\s*to|referred\s*to|advice|precautions|diet|rest|warm\s*water|gargle)\b/i,
    /\b(signature|sign\b|seal|stamp|verified\s*by|pharmacist\s*signature|dispensed\s*by)\b/i,
    /^[-=_*#\s]{3,}$/
  ];

  for (const regex of nonMedRegexes) {
    if (regex.test(lower)) {
      // Exception: If line has strong medication indicators, e.g. "Rx: Amoxicillin 500mg" or "Tab Augmentin 625mg", don't reject
      const hasExplicitRx = /\b(rx\b|tab\.?|tablet|cap\.?|capsule|syp\.?|inj\.?)\b/i.test(line);
      const hasExplicitDose = /\b\d+(?:\.\d+)?\s*(?:mg|mcg|ml|iu|g)\b/i.test(line);
      if (!(hasExplicitRx && hasExplicitDose)) {
        return true;
      }
    }
  }

  // Check pure symptom/disease lines (e.g. "Fever, headache and cough for 3 days")
  if (/\b(fever|cough|cold|headache|chest\s*pain|abdominal\s*pain|vomiting|diarrhea|acidity|hypertension|diabetes|asthma|bronchitis)\b/i.test(lower)) {
    const hasMedicationForm = /\b(tab\.?|tablet|cap\.?|capsule|syp\.?|syrup|inj\.?|injection)\b/i.test(line);
    const hasExplicitDose = /\b\d+(?:\.\d+)?\s*(?:mg|mcg|ml|iu|g)\b/i.test(line);
    if (!hasMedicationForm && !hasExplicitDose) {
      return true;
    }
  }

  return false;
}

/**
 * Preprocesses and merges fragmented OCR continuation lines.
 * E.g.
 * Line 1: Tab Augmentin 625mg
 * Line 2: 1-0-1
 * Line 3: for 7 days
 * -> "Tab Augmentin 625mg 1-0-1 for 7 days"
 */
export function preprocessPrescriptionLines(rawLines: string[]): string[] {
  const merged: string[] = [];

  for (let i = 0; i < rawLines.length; i++) {
    let current = rawLines[i].trim();
    if (!current) continue;

    // Check if next line is continuation (starts with frequency, duration, or timing instruction)
    while (i + 1 < rawLines.length) {
      const next = rawLines[i + 1].trim();
      const isContinuation =
        /^(1-0-1-1|1-0-0-1|1-1-1-1|1-0-1|1-1-1|0-0-1|1-0-0|0-1-0|0-1-1|1-1-0|B\.?I\.?D\.?|T\.?I\.?D\.?|Q\.?I\.?D\.?|Q\.?D\.?|O\.?D\.?|B\.?D\.?|T\.?D\.?S\.?|Q\.?D\.?S\.?|S\.?O\.?S\.?|PRN|STAT|ONCE|TWICE|FOR|\(?\d+\s*(?:DAYS?|WEEKS?|MONTHS?|D|W)\)?|x\s*\d+|PO\b|after\s+food|before\s+food|pc\b|ac\b|at\s+bedtime)/i.test(next) &&
        !/^(rx|tab|cap|inj|syp|\d+[\.\)])/i.test(next);

      if (isContinuation) {
        current = `${current} ${next}`;
        i++;
      } else {
        break;
      }
    }

    merged.push(current);
  }

  return merged;
}

/**
 * Line parser: extracts drug candidate, dosage, frequency, and duration from a sanitized line.
 */
export function parseMedicationLine(rawLine: string): ExtractedMedication | null {
  const line = rawLine.trim();
  if (!line || line.length < 3) return null;

  // Filter out headers, addresses, doctor info, patient vitals, diagnosis
  if (isNonMedicationLine(line)) return null;

  // 1. Extract Dosage (explicit units or contextual numbers like 625, 650, 500, 40)
  const explicitDosageRegex = /\b(\d+(?:\.\d+)?(?:\s*\/\s*\d+(?:\.\d+)?)*\s*(?:mg|mcg|µg|ug|ml|g|gm|iu|mEq|units?|puffs?|drops?)(?:\s*\/\s*\d+(?:\.\d+)?\s*(?:ml|mg))?)\b/i;
  const dosageMatch = line.match(explicitDosageRegex);
  let dosage = dosageMatch ? dosageMatch[1].replace(/\s+/g, '').toLowerCase() : '';

  // Contextual dosage: match known oral tablet strengths (e.g. "Augmentin 625", "Dolo 650", "Pantocid 40")
  if (!dosage) {
    const standaloneDoseRegex = /\b(\d{2,4})\b/g;
    let match: RegExpExecArray | null;
    while ((match = standaloneDoseRegex.exec(line)) !== null) {
      const numVal = parseInt(match[1], 10);
      if (COMMON_TABLET_STRENGTHS.has(numVal)) {
        dosage = `${numVal}mg`;
        break;
      }
    }
  }

  // 2. Extract Frequency (1-0-1, BID, TID, QID, OD, BD, TDS, QDS, SOS, PRN, once daily, etc.)
  const freqRegex = /\b(1-0-1-1|1-0-0-1|1-1-1-1|1-0-1|1-1-1|0-0-1|1-0-0|0-1-0|0-1-1|1-1-0|B\.?I\.?D\.?|T\.?I\.?D\.?|Q\.?I\.?D\.?|Q\.?D\.?|O\.?D\.?|B\.?D\.?|T\.?D\.?S\.?|Q\.?D\.?S\.?|S\.?O\.?S\.?|QAM|QPM|QHS|H\.?S\.?|P\.?R\.?N\.?|STAT|ONCE\s+DAILY|TWICE\s+DAILY|THRICE\s+DAILY|EVERY\s+\d+\s*(?:HOURS|HRS)|Q\d+H|DAILY)\b/i;
  const freqMatch = line.match(freqRegex);
  let rawFreq = freqMatch ? freqMatch[1].toUpperCase().replace(/\./g, '').trim() : '';

  // Standardize clinical frequency nomenclature
  let frequency = 'QD';
  if (rawFreq) {
    if (rawFreq === 'OD' || rawFreq === 'ONCE DAILY' || rawFreq === 'DAILY') frequency = 'QD';
    else if (rawFreq === 'BD' || rawFreq === 'TWICE DAILY') frequency = 'BID';
    else if (rawFreq === 'TDS' || rawFreq === 'THRICE DAILY') frequency = 'TID';
    else if (rawFreq === 'QDS') frequency = 'QID';
    else if (rawFreq === 'SOS') frequency = 'PRN';
    else if (rawFreq === 'HS') frequency = 'QHS';
    else frequency = rawFreq;
  }

  // 3. Extract Duration (for 5 days, x 5 days, x 7d, 5/7, 1/12, (7 days), 2 weeks, 1-0-1 x 5)
  let duration: string | undefined;

  // Duration Pattern A: Shorthand medical fractions (5/7 = 5 days, 2/52 = 2 weeks, 1/12 = 1 month)
  const fractionMatch = line.match(/\b(\d+)\s*\/\s*(7|52|12)\b/);
  if (fractionMatch) {
    const num = fractionMatch[1];
    const denom = fractionMatch[2];
    if (denom === '7') duration = `${num} days`;
    else if (denom === '52') duration = `${num} weeks`;
    else if (denom === '12') duration = `${num} months`;
  }

  // Duration Pattern B: Explicit duration phrases (e.g. "for 7 days", "x 5 days", "(7 days)", "x 10d")
  if (!duration) {
    const durationRegex = /(?:(?:FOR|X|\*)\s*)?\(?(\d+\s*(?:DAYS?|DAY|WEEKS?|WEEK|MONTHS?|MONTH|D|W))\)?/i;
    const durationMatch = line.match(durationRegex);
    if (durationMatch) {
      let dur = durationMatch[1].trim();
      if (/^\d+\s*d$/i.test(dur)) dur = `${dur.replace(/d/i, '').trim()} days`;
      if (/^\d+\s*w$/i.test(dur)) dur = `${dur.replace(/w/i, '').trim()} weeks`;
      duration = dur;
    }
  }

  // Duration Pattern C: Frequency followed immediately by count e.g. "1-0-1 x 5" or "BID x 7"
  if (!duration) {
    const freqFollowedRegex = /(?:1-0-1|1-1-1|1-0-0|0-0-1|BID|TID|QD|QID|OD|BD|TDS|PRN|SOS)\s*(?:x\s*|\*\s*|\bfor\s+)(\d{1,2})\b/i;
    const freqFollowedMatch = line.match(freqFollowedRegex);
    if (freqFollowedMatch) {
      duration = `${freqFollowedMatch[1]} days`;
    }
  }

  // 4. Extract Route (PO, P.O., IV, IM, SC, SL, oral)
  const routeRegex = /\b(?:PO|P\.O\.|IV|I\.V\.|IM|I\.M\.|SC|SubQ|SL|oral|orally)\b/gi;

  // 5. Extract Drug Name Candidate
  let cleanedDrugCandidate = line
    .replace(/^(?:\d+[\.\)\-\:]\s*|#\d+\s*)/, '') // Strip item numbering: 1., 2), #1
    .replace(/^(?:Rx|Tab\.?|Tablet|Cap\.?|Capsule|Syp\.?|Syrup|Inj\.?|Injection|Drop|Drops)\s+/i, '')
    .replace(explicitDosageRegex, '')
    .replace(/\b\d{2,4}\b/g, (match) => COMMON_TABLET_STRENGTHS.has(parseInt(match, 10)) ? '' : match)
    .replace(freqRegex, '')
    .replace(/(?:(?:FOR|X|\*)\s*)?\(?\d+\s*(?:DAYS?|DAY|WEEKS?|WEEK|MONTHS?|MONTH|D|W)\)?/gi, '')
    .replace(/\b\d+\s*\/\s*(?:7|52|12)\b/g, '')
    .replace(/(?:1-0-1|1-1-1|1-0-0|0-0-1|BID|TID|QD|QID|OD|BD|TDS|PRN|SOS)\s*(?:x\s*|\*\s*|\bfor\s+)\d{1,2}\b/gi, '')
    .replace(routeRegex, '')
    .replace(/\b(?:after\s+food|before\s+food|pc\b|ac\b|at\s+bedtime|daily|prn|stat)\b/gi, '')
    .replace(/[-–—,:;()#*]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  // Pick first 1-3 words representing the drug name
  const words = cleanedDrugCandidate.split(' ').filter(w => w.length >= 3);
  if (words.length === 0) return null;

  const candidate = words.slice(0, 3).join(' ');
  const candidateLower = candidate.toLowerCase();

  // Reject candidates that match medical stop words
  if (COMMON_MEDICAL_STOP_WORDS.has(candidateLower)) {
    return null;
  }
  for (const word of words) {
    if (COMMON_MEDICAL_STOP_WORDS.has(word.toLowerCase()) && words.length === 1) {
      return null;
    }
  }

  // 6. Fuzzy match against RxNorm dataset
  const matchResult = findBestRxNormMatch(candidate, 0.75);

  // STRICT CLINICAL GATEKEEPING:
  // Reject lines that are not verified in RxNorm UNLESS they meet rigorous clinical criteria
  const hasExplicitRxPrefix = /^(?:Rx|Tab\.?|Tablet|Cap\.?|Capsule|Syp\.?|Syrup|Inj\.?|Injection|Drop|Drops)\b/i.test(line);
  const hasExplicitDosage = Boolean(dosage);
  const hasClinicalFrequency = Boolean(freqMatch);

  if (!matchResult.isVerified) {
    const isStopWord = COMMON_MEDICAL_STOP_WORDS.has(candidateLower) ||
                       COMMON_MEDICAL_STOP_WORDS.has(matchResult.matchedTerm.toLowerCase());
    if (isStopWord) return null;

    // To prevent arbitrary text extraction, unverified terms MUST:
    // 1) Have an explicit medication form OR an explicit dosage with medical unit (e.g. mg, ml)
    // 2) Have an explicit clinical frequency (e.g. 1-0-1, BID)
    // 3) Have confidence >= 0.60
    const hasMedForm = hasExplicitRxPrefix;
    const hasStrictDose = hasExplicitDosage && !dosage.endsWith('mg') || Boolean(dosageMatch);
    const hasValidFrequency = hasClinicalFrequency;

    if (!((hasMedForm || hasStrictDose) && hasValidFrequency && matchResult.confidence >= 0.60)) {
      return null;
    }
  }

  return {
    brandName: matchResult.brandName || candidate,
    activeIngredient: matchResult.activeIngredient || candidate,
    dosage: dosage || (matchResult.isVerified ? 'Standard Dose' : ''),
    frequency: frequency,
    duration: duration,
    rawText: line,
    confidence: matchResult.confidence,
    matchedRxNormTerm: matchResult.matchedTerm,
    allergenGroup: matchResult.concept?.allergenGroup
  };
}

/**
 * Main parser entrypoint: sanitizes OCR text, merges multi-line blocks, and extracts verified medications.
 */
export async function parsePrescriptionDocument(input: Buffer | string): Promise<{
  extractedText: string;
  medications: ExtractedMedication[];
}> {
  const rawText = await extractRawPrescriptionText(input);
  const sanitizedText = sanitizeOcrText(rawText);

  const rawLines = sanitizedText.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
  const lines = preprocessPrescriptionLines(rawLines);

  const medications: ExtractedMedication[] = [];
  const seenIngredients = new Set<string>();

  for (const line of lines) {
    const med = parseMedicationLine(line);
    if (med && med.activeIngredient && med.activeIngredient.length > 2) {
      const key = med.activeIngredient.toLowerCase();
      if (!seenIngredients.has(key)) {
        seenIngredients.add(key);
        medications.push(med);
      }
    }
  }

  return {
    extractedText: sanitizedText,
    medications
  };
}
