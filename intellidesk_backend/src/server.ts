import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import http from 'http';
import { initializeSocket } from './services/socketManager.js';
import asyncIntakeRouter from './routes/asyncIntake.js';
import chatRouter from './routes/chat.js';
import adminRouter from './routes/admin.js';
import knowledgeRouter from './routes/knowledge.js';
import workflowDispatchRouter from './routes/workflow_dispatch.js';
import telemetryRouter from './routes/telemetry.js';
import reportsRouter from './routes/reports.js';
import simulationRouter from './routes/simulation.js';
import claimsRouter from './routes/claims.js';
import patientsRouter from './routes/patients.js';
import { tenantScopeMiddleware } from './middleware/tenant.js';
import { loadOrTrainLSTMModel } from './services/attritionModel.js';
import { loadOrTrainGrantOptimizerModel } from './services/grantOptimizerModel.js';
import { loadOrTrainDeepRankModel } from './services/deepRankModel.js';
import { loadOrTrainAnomalyModel } from './services/anomalyModel.js';
import { startWorkers } from './workers/index.js';

import { ensureStorageBucketsExist } from './services/storageBootstrap.js';
import { DatabaseService } from './services/dbService.js';

import authRouter, { getInstitutionDetails } from './routes/auth.js';
import { requireAuth, requireRole } from './middleware/authMiddleware.js';
import diagnosticsRouter from './modules/diagnostics/routes/diagnosticsRouter.js';
import { ClinicalImageClassifier } from './modules/diagnostics/vision/imageClassifier.js';
import { CoughClassifier } from './modules/diagnostics/audio/CoughClassifier.js';
import { MultimodalRiskNetwork } from './modules/diagnostics/fusion/multimodalRiskNetwork.js';
import { pharmacyRouter } from './modules/pharmacy/routes/pharmacyRouter.js';
import { cdssRouter } from './modules/cdss/routes/cdssRouter.js';

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ limit: '50mb', extended: true }));

const server = http.createServer(app);

initializeSocket(server);

app.use('/api/v1/auth', authRouter);
app.get('/api/v1/institutions/:id', async (req, res) => {
  const inst = await getInstitutionDetails(String(req.params.id || ''));
  res.status(200).json({ success: true, institution: inst });
});
app.get('/institutions/:id', async (req, res) => {
  const inst = await getInstitutionDetails(String(req.params.id || ''));
  res.status(200).json({ success: true, institution: inst });
});
app.use('/api/v1/chat', chatRouter);
app.use('/chat', chatRouter);
app.use('/api/v1/intake', asyncIntakeRouter);
app.use('/api/v1/diagnostics', diagnosticsRouter);
app.use('/diagnostics', diagnosticsRouter);
app.use('/api/v1/pharmacy', pharmacyRouter);
app.use('/pharmacy', pharmacyRouter);
app.use('/api/v1/cdss', cdssRouter);
app.use('/cdss', cdssRouter);
app.use('/api/v1/patients', patientsRouter);
app.use('/api/v1/students', patientsRouter);
app.use('/api/v1/claims', tenantScopeMiddleware, claimsRouter);
app.use('/api/v1/admin/claims', requireAuth, requireRole(['ADMIN']), tenantScopeMiddleware, claimsRouter);
app.use('/api/v1/admin/knowledge', requireAuth, requireRole(['ADMIN']), tenantScopeMiddleware, knowledgeRouter);
app.use('/api/v1/admin/telemetry', requireAuth, requireRole(['ADMIN']), tenantScopeMiddleware, telemetryRouter);
app.use('/api/v1/admin/reports', requireAuth, requireRole(['ADMIN']), tenantScopeMiddleware, reportsRouter);
app.use('/api/v1/admin', requireAuth, requireRole(['ADMIN']), tenantScopeMiddleware, adminRouter);
app.use('/api/v1/reports', reportsRouter);
app.use('/api/v1/workflow', requireAuth, requireRole(['ADMIN']), tenantScopeMiddleware, workflowDispatchRouter);
app.use('/api/v1/simulation', requireAuth, requireRole(['ADMIN']), tenantScopeMiddleware, simulationRouter);

app.get('/health', async (req, res) => {
  const dbHealth = await DatabaseService.checkDatabaseHealth();
  res.status(200).json({
    status: 'ok',
    service: 'MedAccess AI Clinical Triage & Copay Engine',
    database: dbHealth,
  });
});

app.use((err: any, req: express.Request, res: express.Response, next: express.NextFunction) => {
  if (err?.type === 'entity.too.large') {
    console.error(`⚠️ [PayloadTooLarge] Request entity exceeded limit: ${err.message}`);
    return res.status(413).json({
      success: false,
      error: 'Payload Too Large',
      message: 'The submitted audio, image, or diagnostic payload exceeds the maximum allowed size (50MB).',
    });
  }
  next(err);
});

const PORT = process.env.PORT || 3000;

async function bootstrapServer() {
  // 1. Ensure storage buckets exist
  await ensureStorageBucketsExist();

  // 2. Verify Database Layer & Schema Telemetry
  try {
    const dbHealth = await DatabaseService.checkDatabaseHealth();
    console.log(`🩺 [MedAccess AI] Database Telemetry: status=${dbHealth.status} | Claims ready=${dbHealth.claimsReady} | Health Funds ready=${dbHealth.fundsReady}`);
  } catch (dbErr) {
    console.warn('⚠️ [MedAccess AI] Database health check warning:', dbErr);
  }

  // 3. Load Triage & Claims ML Models
  try {
    console.log('🤖 [MedAccess AI] Bootstrapping Triage & Financial ML Models...');
    await Promise.all([
      loadOrTrainLSTMModel(),
      loadOrTrainGrantOptimizerModel(),
      loadOrTrainDeepRankModel(),
      loadOrTrainAnomalyModel()
    ]);
  } catch (err) {
    console.error('Failed to initialize Triage ML models on startup:', err);
  }

  // 4. Load Multimodal Clinical Diagnostics Neural Networks (Vision, Cough, Fusion)
  try {
    console.log('🩺 [MedAccess AI] Bootstrapping Multimodal Clinical Diagnostics Neural Networks...');
    await Promise.all([
      ClinicalImageClassifier.initialize(),
      CoughClassifier.loadOrBootstrapModel(),
      MultimodalRiskNetwork.initialize()
    ]);
    console.log('✅ [MedAccess AI] Multimodal Clinical Diagnostics Models (Vision MobileNetV3, Acoustic Cough, Late Fusion) online & ready.');
  } catch (err) {
    console.error('Failed to initialize Multimodal Clinical Diagnostics ML models on startup:', err);
  }

  // 5. Start HTTP server and background workers
  server.listen(PORT as number, '0.0.0.0', () => {
    console.log(`🏥 [MedAccess AI] Clinical Triage & Emergency Copay Engine running on port ${PORT}`);
    console.log(`🏥 [MedAccess War Room] Admin routes, payout rails & PDF report engine initialized successfully.`);
    startWorkers();
  });
}

bootstrapServer();

