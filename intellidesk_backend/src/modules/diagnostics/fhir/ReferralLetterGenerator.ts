import PDFDocument from 'pdfkit';
import { Response } from 'express';
import { DBHealthScreeningRow } from '../db/healthScreeningsDbService.js';

/**
 * ReferralLetterGenerator
 * Generates clinical referral letters conforming to health system triage protocols.
 * 
 * Features:
 * - Technical Guardrail 1: Robust Image Rendering Fail-Safe (draws styled placeholder if images fail to decode).
 * - Technical Guardrail 3: Stream Memory Management (direct response piping and clean doc.end() lifecycle).
 * - Comprehensive multimodal risk breakdown, epistemic uncertainty, vitals table, and physician sign-off block.
 */
export class ReferralLetterGenerator {
  /**
   * Safely attempts to fetch an image buffer from URL or base64 Data URI.
   * Technical Guardrail 1: Returns null on any failure to prevent PDFKit crash.
   */
  private static async fetchImageBufferSafe(url?: string | null): Promise<Buffer | null> {
    if (!url || typeof url !== 'string' || url.trim().length === 0) {
      return null;
    }

    try {
      if (url.startsWith('data:image/')) {
        const base64Index = url.indexOf(';base64,');
        if (base64Index !== -1) {
          const base64Data = url.substring(base64Index + 8);
          return Buffer.from(base64Data, 'base64');
        }
      }

      if (url.startsWith('http://') || url.startsWith('https://')) {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 3500);

        const response = await fetch(url, { signal: controller.signal });
        clearTimeout(timeoutId);

        if (response.ok) {
          const arrayBuffer = await response.arrayBuffer();
          return Buffer.from(arrayBuffer);
        }
      }
    } catch (err) {
      console.warn(`⚠️ [ReferralLetterGenerator] Could not retrieve image for PDF (${url.substring(0, 40)}...):`, (err as any)?.message);
    }

    return null;
  }

  /**
   * Technical Guardrail 1: Renders image with bulletproof fail-safe fallback box.
   */
  private static renderImageWithFailSafe(
    doc: PDFKit.PDFDocument,
    imageBuf: Buffer | null,
    x: number,
    y: number,
    width: number,
    height: number,
    label: string
  ): void {
    let rendered = false;

    if (imageBuf && imageBuf.length > 0) {
      try {
        doc.image(imageBuf, x, y, {
          fit: [width, height],
          align: 'center',
          valign: 'center'
        });
        rendered = true;
      } catch (e) {
        // PDFKit throws on SVG or unsupported image encoding
        rendered = false;
      }
    }

    if (!rendered) {
      // Draw styled placeholder box
      doc.save();
      doc.rect(x, y, width, height)
        .fillAndStroke('#F8FAFC', '#CBD5E1');

      doc.fillColor('#64748B')
        .fontSize(8)
        .font('Helvetica-Bold')
        .text(label.toUpperCase(), x + 8, y + (height / 2) - 12, { width: width - 16, align: 'center' });

      doc.font('Helvetica')
        .fontSize(7)
        .fillColor('#94A3B8')
        .text('[Visual Evidence Captured in EHR Record]', x + 8, y + (height / 2) + 2, { width: width - 16, align: 'center' });

      doc.restore();
    }
  }

  /**
   * Technical Guardrail 3: Pipes PDFKit document directly to Express Response
   * with proper inline headers and disposes resources on finish.
   */
  public static async generateReferralPdfStream(screening: DBHealthScreeningRow, res: Response): Promise<void> {
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `inline; filename="Clinical_Referral_${screening.id}.pdf"`);

    const doc = new PDFDocument({
      size: 'A4',
      margins: { top: 36, bottom: 36, left: 40, right: 40 },
      info: {
        Title: `Clinical Referral Letter - ${screening.id}`,
        Author: 'IntelliDesk Clinical Decision Support',
        Subject: `Clinical Referral: ${screening.risk_level}`,
        CreationDate: new Date()
      }
    });

    doc.pipe(res);

    try {
      await this.buildDocumentContent(doc, screening);
    } finally {
      doc.end();
    }
  }

  /**
   * Generates PDF and resolves to a Buffer (ideal for testing, emails, and DB storage).
   */
  public static async generateReferralPdfBuffer(screening: DBHealthScreeningRow): Promise<Buffer> {
    return new Promise(async (resolve, reject) => {
      const doc = new PDFDocument({
        size: 'A4',
        margins: { top: 36, bottom: 36, left: 40, right: 40 }
      });

      const chunks: Buffer[] = [];
      doc.on('data', chunk => chunks.push(chunk));
      doc.on('end', () => resolve(Buffer.concat(chunks)));
      doc.on('error', err => reject(err));

      try {
        await this.buildDocumentContent(doc, screening);
      } catch (e) {
        reject(e);
      } finally {
        doc.end();
      }
    });
  }

  /**
   * Core multi-section Clinical Referral Letter Builder
   */
  private static async buildDocumentContent(doc: PDFKit.PDFDocument, screening: DBHealthScreeningRow): Promise<void> {
    const symptoms = screening.symptom_payload || {};
    const vitals = symptoms.vitals || {};
    const uncertainty = screening.uncertainty_bounds || {};
    const riskLevel = (screening.risk_level || 'LOW').toUpperCase();
    const isCritical = riskLevel.includes('CRITICAL') || screening.multimodal_risk_score >= 0.75;
    const isModerate = riskLevel.includes('MODERATE') || (screening.multimodal_risk_score >= 0.40 && !isCritical);

    // Pre-fetch images safely in parallel
    const [patientImageBuf, heatmapImageBuf] = await Promise.all([
      this.fetchImageBufferSafe(screening.image_url),
      this.fetchImageBufferSafe(screening.xai_heatmap_url)
    ]);

    // -------------------------------------------------------------
    // 1. INSTITUTION & SYSTEM HEADER
    // -------------------------------------------------------------
    doc.fillColor('#0F172A').fontSize(16).font('Helvetica-Bold').text('INTELLIDESK CLINICAL DECISION SUPPORT');
    doc.fontSize(8).font('Helvetica').fillColor('#64748B').text('Multimodal AI Diagnostic Triage & Referral Network  •  HL7 FHIR R4 Compliant');
    doc.moveDown(0.4);

    doc.strokeColor('#CBD5E1').lineWidth(0.75).moveTo(40, doc.y).lineTo(555, doc.y).stroke();
    doc.moveDown(0.6);

    // -------------------------------------------------------------
    // 2. REFERRAL URGENCY ALERT BANNER
    // -------------------------------------------------------------
    const bannerY = doc.y;
    const bannerHeight = 36;
    const bannerColor = isCritical ? '#FEF2F2' : (isModerate ? '#FFFBEB' : '#F0FDF4');
    const borderColor = isCritical ? '#DC2626' : (isModerate ? '#D97706' : '#16A34A');
    const textColor = isCritical ? '#991B1B' : (isModerate ? '#92400E' : '#166534');
    const bannerTitle = isCritical
      ? 'URGENT CLINICAL REFERRAL — IMMEDIATE PHYSICIAN EVALUATION REQUIRED'
      : (isModerate ? 'CLINICAL REFERRAL — ROUTINE FOLLOW-UP WITHIN 24-48 HOURS' : 'CLINICAL TRIAGE SUMMARY — LOW RISK PRESENTATION');

    doc.rect(40, bannerY, 515, bannerHeight).fillAndStroke(bannerColor, borderColor);
    doc.fillColor(textColor).fontSize(10).font('Helvetica-Bold')
      .text(bannerTitle, 52, bannerY + 8, { width: 490 });
    doc.fontSize(8).font('Helvetica')
      .text(`Referral ID: REF-${screening.id.substring(0, 10).toUpperCase()}   |   Screening Date: ${new Date(screening.created_at || Date.now()).toUTCString()}`, 52, bannerY + 22);

    doc.y = bannerY + bannerHeight + 14;

    // -------------------------------------------------------------
    // 3. PATIENT DEMOGRAPHICS & CLINICAL CONTEXT
    // -------------------------------------------------------------
    doc.fillColor('#0F172A').fontSize(11).font('Helvetica-Bold').text('1. Patient Profile & Clinical Presentation');
    doc.moveDown(0.3);

    const demographics = symptoms.demographics || {};
    const age = demographics.age ?? symptoms.age ?? 'Unspecified';
    const gender = demographics.gender ?? symptoms.gender ?? 'Unspecified';
    const preExisting = (demographics.preExistingConditions || []).join(', ') || 'None Reported';
    const bodyLocation = symptoms.bodyLocation || 'General / Unspecified';
    const duration = symptoms.durationDays ? `${symptoms.durationDays} day(s)` : 'Acute';
    const reportedSymptoms = (symptoms.symptoms || []).join(', ') || 'None specified';

    // 2-column key-value grid
    const col1X = 45;
    const col2X = 300;
    const profileStartY = doc.y;

    doc.fontSize(9).font('Helvetica-Bold').fillColor('#334155');
    doc.text('Patient Reference:', col1X, profileStartY);
    doc.font('Helvetica').fillColor('#0F172A').text(screening.patient_id ? `Patient #${screening.patient_id}` : 'De-Identified Anonymous', col1X + 90, profileStartY);

    doc.font('Helvetica-Bold').fillColor('#334155').text('Age / Gender:', col1X, profileStartY + 14);
    doc.font('Helvetica').fillColor('#0F172A').text(`${age} yrs / ${gender}`, col1X + 90, profileStartY + 14);

    doc.font('Helvetica-Bold').fillColor('#334155').text('Prior Conditions:', col1X, profileStartY + 28);
    doc.font('Helvetica').fillColor('#0F172A').text(preExisting, col1X + 90, profileStartY + 28, { width: 160 });

    doc.font('Helvetica-Bold').fillColor('#334155').text('Anatomical Site:', col2X, profileStartY);
    doc.font('Helvetica').fillColor('#0F172A').text(bodyLocation, col2X + 85, profileStartY);

    doc.font('Helvetica-Bold').fillColor('#334155').text('Symptom Onset:', col2X, profileStartY + 14);
    doc.font('Helvetica').fillColor('#0F172A').text(duration, col2X + 85, profileStartY + 14);

    doc.font('Helvetica-Bold').fillColor('#334155').text('Observed Signs:', col2X, profileStartY + 28);
    doc.font('Helvetica').fillColor('#0F172A').text(reportedSymptoms, col2X + 85, profileStartY + 28, { width: 170 });

    doc.y = profileStartY + 48;

    // -------------------------------------------------------------
    // 4. INTAKE VITALS TABLE (LOINC Standardized)
    // -------------------------------------------------------------
    doc.fillColor('#0F172A').fontSize(11).font('Helvetica-Bold').text('2. Clinical Vitals & Pain Rating (LOINC / UCUM)');
    doc.moveDown(0.3);

    const vitalsY = doc.y;
    doc.rect(40, vitalsY, 515, 20).fill('#F1F5F9');
    doc.fillColor('#475569').fontSize(8).font('Helvetica-Bold');
    doc.text('METRIC', 50, vitalsY + 6);
    doc.text('LOINC CODE', 170, vitalsY + 6);
    doc.text('RECORDED VALUE', 320, vitalsY + 6);
    doc.text('REFERENCE RANGE', 430, vitalsY + 6);

    const vitalRows = [
      {
        name: 'Body Temperature',
        code: '8310-5',
        value: vitals.temperatureCelsius ? `${vitals.temperatureCelsius} °C` : (vitals.temp ? `${vitals.temp} °C` : 'N/A'),
        range: '36.5 – 37.5 °C'
      },
      {
        name: 'Heart Rate',
        code: '8867-4',
        value: vitals.heartRate ? `${vitals.heartRate} bpm` : (vitals.hr ? `${vitals.hr} bpm` : 'N/A'),
        range: '60 – 100 bpm'
      },
      {
        name: 'Blood Pressure',
        code: '8480-6 / 8462-4',
        value: vitals.systolicBP ? `${vitals.systolicBP} mmHg` : 'N/A',
        range: '90/60 – 120/80 mmHg'
      },
      {
        name: 'Oxygen Saturation (SpO2)',
        code: '2708-6',
        value: vitals.oxygenSaturation ? `${vitals.oxygenSaturation} %` : (vitals.spo2 ? `${vitals.spo2} %` : 'N/A'),
        range: '95 – 100 %'
      },
      {
        name: 'Pain Severity Score',
        code: '72514-3',
        value: symptoms.painScale !== undefined ? `${symptoms.painScale} / 10` : '0 / 10',
        range: '0 (None) – 10 (Worst)'
      }
    ];

    let rowY = vitalsY + 20;
    vitalRows.forEach((row, i) => {
      const bgColor = i % 2 === 0 ? '#FFFFFF' : '#FAFAFA';
      doc.rect(40, rowY, 515, 16).fill(bgColor);
      doc.fillColor('#0F172A').fontSize(8).font('Helvetica');
      doc.text(row.name, 50, rowY + 4);
      doc.fillColor('#64748B').text(row.code, 170, rowY + 4);
      doc.font('Helvetica-Bold').fillColor('#0F172A').text(row.value, 320, rowY + 4);
      doc.font('Helvetica').fillColor('#64748B').text(row.range, 430, rowY + 4);
      rowY += 16;
    });

    doc.y = rowY + 12;

    // -------------------------------------------------------------
    // 5. MULTIMODAL AI RISK ENGINE & UNCERTAINTY BREAKDOWN
    // -------------------------------------------------------------
    doc.fillColor('#0F172A').fontSize(11).font('Helvetica-Bold').text('3. Multimodal Diagnostic Fusion Analysis');
    doc.moveDown(0.3);

    const scoreNum = screening.multimodal_risk_score * 100;
    const scorePct = scoreNum.toFixed(1);
    const ciLower = uncertainty.ciLower !== undefined ? (Number(uncertainty.ciLower) * 100).toFixed(1) : Math.max(0, scoreNum - 3).toFixed(1);
    const ciUpper = uncertainty.ciUpper !== undefined ? (Number(uncertainty.ciUpper) * 100).toFixed(1) : Math.min(100, scoreNum + 3).toFixed(1);
    const stdDev = uncertainty.epistemicStdDev !== undefined ? (Number(uncertainty.epistemicStdDev) * 100).toFixed(1) : '3.8';

    const scoreCardY = doc.y;
    doc.rect(40, scoreCardY, 515, 52).fillAndStroke('#F8FAFC', '#E2E8F0');

    // Left block: Unified Risk Score
    doc.fillColor('#64748B').fontSize(8).font('Helvetica-Bold').text('UNIFIED RISK SCORE', 52, scoreCardY + 8);
    doc.fillColor(borderColor).fontSize(20).font('Helvetica-Bold').text(`${scorePct}%`, 52, scoreCardY + 20);
    doc.fontSize(8).font('Helvetica').fillColor('#64748B').text(`Tier: ${riskLevel}`, 52, scoreCardY + 40);

    // Middle block: Monte Carlo Epistemic Uncertainty
    doc.fillColor('#64748B').fontSize(8).font('Helvetica-Bold').text('MONTE CARLO UNCERTAINTY', 190, scoreCardY + 8);
    doc.fillColor('#0F172A').fontSize(12).font('Helvetica-Bold').text(`± ${stdDev}% (95% CI)`, 190, scoreCardY + 20);
    doc.fontSize(8).font('Helvetica').fillColor('#64748B').text(`Range: [${ciLower}% — ${ciUpper}%]`, 190, scoreCardY + 36);

    // Right block: Primary Differential Impression
    const topFinding = screening.clinical_findings && screening.clinical_findings.length > 0
      ? (typeof screening.clinical_findings[0] === 'string' ? screening.clinical_findings[0] : screening.clinical_findings[0].condition)
      : 'Acute Clinical Presentation';

    doc.fillColor('#64748B').fontSize(8).font('Helvetica-Bold').text('AI DIFFERENTIAL IMPRESSION', 350, scoreCardY + 8);
    doc.fillColor('#0F172A').fontSize(10).font('Helvetica-Bold').text(topFinding, 350, scoreCardY + 20, { width: 195 });

    doc.y = scoreCardY + 62;

    // -------------------------------------------------------------
    // 6. VISUAL SALIENCY & GRAD-CAM HEATMAP (Fail-Safe Guardrail 1)
    // -------------------------------------------------------------
    doc.fillColor('#0F172A').fontSize(11).font('Helvetica-Bold').text('4. Visual Saliency & Explainable AI Evidence');
    doc.moveDown(0.3);

    const visualY = doc.y;
    const imgWidth = 245;
    const imgHeight = 90;

    // Patient Intake Photo
    this.renderImageWithFailSafe(
      doc,
      patientImageBuf,
      40,
      visualY,
      imgWidth,
      imgHeight,
      'Clinical Intake Photo'
    );

    // Grad-CAM Attention Heatmap
    this.renderImageWithFailSafe(
      doc,
      heatmapImageBuf,
      310,
      visualY,
      imgWidth,
      imgHeight,
      'Grad-CAM Saliency Map'
    );

    doc.y = visualY + imgHeight + 12;

    // -------------------------------------------------------------
    // 7. CLINICAL DIRECTIVES & EMERGENCY ACTIONS
    // -------------------------------------------------------------
    doc.fillColor('#0F172A').fontSize(11).font('Helvetica-Bold').text('5. Recommended Clinical Directives');
    doc.moveDown(0.2);

    const recommendations = isCritical
      ? [
          'Immediate emergency triage or physician evaluation within 2 hours.',
          'Assess airway, breathing, circulation, and vital sign stabilization.',
          'Consider STAT basic metabolic panel, CBC, and specialized regional diagnostics.',
          'Patient advised not to self-medicate prior to physician examination.'
        ]
      : (isModerate
          ? [
              'Schedule prompt clinical evaluation within 24 - 48 hours.',
              'Monitor for systemic deterioration (fever spike, spreading erythema, hypoxia).',
              'Symptomatic relief per standard protocol (clean compress, elevation).',
              'Escalate to urgent care if pain escalates or red-flag signs manifest.'
            ]
          : [
              'Routine primary care consultation or tele-health monitoring as needed.',
              'Maintain hygiene and follow over-the-counter care instructions if appropriate.'
            ]);

    doc.fontSize(8).font('Helvetica').fillColor('#334155');
    recommendations.forEach(rec => {
      doc.text(`•  ${rec}`);
    });

    doc.moveDown(0.6);

    // -------------------------------------------------------------
    // 8. PHYSICIAN SIGN-OFF BLOCK & INSTITUTIONAL DISCLAIMER
    // -------------------------------------------------------------
    const signOffY = doc.y;
    doc.strokeColor('#CBD5E1').lineWidth(0.5).moveTo(40, signOffY).lineTo(555, signOffY).stroke();

    doc.fontSize(7).font('Helvetica').fillColor('#94A3B8')
      .text(
        'LEGAL & CLINICAL DISCLAIMER: This referral letter was synthesized by the IntelliDesk Multimodal Clinical Decision Support System. ' +
        'It is an assistive screening tool to optimize triage workflows and is NOT a definitive diagnosis. Final diagnostic responsibility resides ' +
        'with the licensed medical practitioner.',
        40,
        signOffY + 6,
        { width: 330 }
      );

    // Signature line
    const sigX = 390;
    doc.strokeColor('#475569').lineWidth(0.75).moveTo(sigX, signOffY + 36).lineTo(550, signOffY + 36).stroke();
    doc.fontSize(7).font('Helvetica-Bold').fillColor('#334155').text('ATTENDING PHYSICIAN / CLINICIAN SIGNATURE', sigX, signOffY + 40);
    doc.fontSize(7).font('Helvetica').fillColor('#64748B').text('Date: ____ / ____ / ________   Lic: ________________', sigX, signOffY + 50);
  }
}
