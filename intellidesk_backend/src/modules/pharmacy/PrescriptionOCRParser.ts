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
 * Runs Tesseract OCR on image buffer (PNG, JPEG, WebP).
 */
export async function extractTextFromImageBuffer(buffer: Buffer): Promise<string> {
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
    console.warn('[Prescription OCR] Tesseract OCR warning:', ocrErr?.message || ocrErr);
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
 * Line parser: extracts drug candidate, dosage, frequency, and duration from a sanitized line.
 */
export function parseMedicationLine(rawLine: string): ExtractedMedication | null {
  const line = rawLine.trim();
  if (!line || line.length < 3) return null;

  // Ignore header/footer metadata lines
  const ignorePatterns = [
    /^(doctor|dr\.|patient|name|age|gender|sex|date|rx\s*#|reg\s*no|clinic|hospital|signature|address|phone|email)\b/i,
    /^(diagnosis|instructions|notes|bp:|pulse:|temp:|vitals:)/i,
    /^[-=_*#\s]{3,}$/
  ];
  for (const pattern of ignorePatterns) {
    if (pattern.test(line)) return null;
  }

  // 1. Extract Dosage (e.g., 500mg, 500 mg, 10mg, 250mg/5ml, 0.5mg, 5ml)
  const dosageRegex = /\b(\d+(?:\.\d+)?\s*(?:mg|mcg|ml|g|gm|iu|mEq)(?:\s*\/\s*\d+(?:\.\d+)?\s*(?:ml|mg))?)\b/i;
  const dosageMatch = line.match(dosageRegex);
  const dosage = dosageMatch ? dosageMatch[1].replace(/\s+/g, '') : '';

  // 2. Extract Frequency (e.g., BID, TID, QD, QID, 1-0-1, 1-1-1, once daily, PRN)
  const freqRegex = /\b(1-0-1|1-1-1|0-0-1|1-0-0|0-1-0|BID|TID|QID|QD|QAM|QPM|QHS|PRN|STAT|ONCE\s+DAILY|TWICE\s+DAILY|THRICE\s+DAILY|EVERY\s+\d+\s*(?:HOURS|HRS)|Q\d+H|DAILY)\b/i;
  const freqMatch = line.match(freqRegex);
  const frequency = freqMatch ? freqMatch[1].toUpperCase() : 'QD';

  // 3. Extract Duration (e.g., for 5 days, 5 days, 10 d, 2 weeks)
  const durationRegex = /\b(?:FOR\s+)?(\d+\s*(?:DAYS|DAY|WEEKS|WEEK|MONTHS|MONTH|D|W))\b/i;
  const durationMatch = line.match(durationRegex);
  const duration = durationMatch ? durationMatch[1] : undefined;

  // 4. Extract Drug Name Candidate
  // Clean line of matched dosage, frequency, duration, and common prefix symbols
  let cleanedDrugCandidate = line
    .replace(/^(?:Rx|Tab\.?|Tablet|Cap\.?|Capsule|Syp\.?|Syrup|Inj\.?|Injection|Drop|Drops)\s+/i, '')
    .replace(dosageRegex, '')
    .replace(freqRegex, '')
    .replace(durationRegex, '')
    .replace(/[-–—,:;()#*]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  // Pick first 1-3 words representing the drug name
  const words = cleanedDrugCandidate.split(' ').filter(w => w.length > 2);
  if (words.length === 0) return null;

  const candidate = words.slice(0, 3).join(' ');

  // 5. Fuzzy match against RxNorm dataset
  const matchResult = findBestRxNormMatch(candidate, 0.75);

  return {
    brandName: matchResult.brandName || candidate,
    activeIngredient: matchResult.activeIngredient || candidate,
    dosage: dosage || 'Standard Dose',
    frequency: frequency,
    duration: duration,
    rawText: line,
    confidence: matchResult.confidence,
    matchedRxNormTerm: matchResult.matchedTerm,
    allergenGroup: matchResult.concept?.allergenGroup
  };
}

/**
 * Main parser entrypoint: sanitizes OCR text, splits lines, and extracts medications.
 */
export async function parsePrescriptionDocument(input: Buffer | string): Promise<{
  extractedText: string;
  medications: ExtractedMedication[];
}> {
  const rawText = await extractRawPrescriptionText(input);
  const sanitizedText = sanitizeOcrText(rawText);

  const lines = sanitizedText.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
  const medications: ExtractedMedication[] = [];
  const seenIngredients = new Set<string>();

  for (const line of lines) {
    const med = parseMedicationLine(line);
    if (med) {
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
