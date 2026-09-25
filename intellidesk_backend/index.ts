import express from 'express';
import cors from 'cors';
import { PrismaClient } from '@prisma/client';
import { GoogleGenAI } from '@google/genai';

const prisma = new PrismaClient();
const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));

// Initialize Gemini Client
const ai = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY || 'dummy_key' });

app.post('/api/intake', async (req, res) => {
  try {
    const { studentName = 'Anonymous Student', studentContact = '555-0000', message } = req.body;
    
    if (!message) {
      return res.status(400).json({ error: 'message is required' });
    }

    // Find or create student
    let student = await prisma.student.findFirst({ where: { contact: studentContact } });
    if (!student) {
      student = await prisma.student.create({
        data: { name: studentName, contact: studentContact }
      });
    }

    // Call Gemini API to parse the message
    let urgency = 'Routine';
    let category = 'General';
    let aiAssessment = 'General inquiry, no immediate risk identified.';

    if (process.env.GEMINI_API_KEY) {
      const prompt = `
        Analyze the following student crisis message.
        Determine the urgency (Critical, High, Routine) and category (Financial, Academic, Medical, General).
        Provide a short assessment summary detailing the core issue and any potential risks.
        Message: "${message}"
        Format strictly as JSON: { "urgency": "...", "category": "...", "assessment": "..." }
      `;
      
      const response = await ai.models.generateContent({
        model: 'gemini-2.5-flash',
        contents: prompt,
      });

      const text = response.text || '';
      try {
        const jsonMatch = text.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          const parsed = JSON.parse(jsonMatch[0]);
          urgency = parsed.urgency || urgency;
          category = parsed.category || category;
          aiAssessment = parsed.assessment || aiAssessment;
        }
      } catch (e) {
        console.error('Failed to parse Gemini JSON', e);
      }
    } else {
      // Mock logic if no API key
      const msg = message.toLowerCase();
      if (msg.includes('accident') || msg.includes('hospital') || msg.includes('concussion')) {
        urgency = 'Critical';
        category = 'Medical';
        aiAssessment = 'Student reported a medical emergency or hospitalization.';
      } else if (msg.includes('eviction') || msg.includes('rent') || msg.includes('homeless')) {
        urgency = 'High';
        category = 'Financial';
        aiAssessment = 'Student is facing housing insecurity and requires immediate financial assistance.';
      } else if (msg.includes('extension') || msg.includes('test')) {
        urgency = 'Routine';
        category = 'Academic';
        aiAssessment = 'Student is requesting an academic accommodation.';
      }
    }

    const newCase = await prisma.case.create({
      data: {
        studentId: student.id,
        description: message,
        urgency,
        category,
        aiAssessment,
      }
    });

    res.json(newCase);
  } catch (error) {
    console.error('Error in intake:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.get('/api/cases', async (req, res) => {
  try {
    const cases = await prisma.case.findMany({
      include: {
        student: true
      },
      orderBy: {
        createdAt: 'desc'
      }
    });
    res.json(cases);
  } catch (error) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/cases/:id/approve', async (req, res) => {
  try {
    const { id } = req.params;
    const updatedCase = await prisma.case.update({
      where: { id },
      data: { status: 'Approved' }
    });
    res.json(updatedCase);
  } catch (error) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.post('/api/cases/:id/deny', async (req, res) => {
  try {
    const { id } = req.params;
    const updatedCase = await prisma.case.update({
      where: { id },
      data: { status: 'Denied' }
    });
    res.json(updatedCase);
  } catch (error) {
    res.status(500).json({ error: 'Internal server error' });
  }
});

app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
});
