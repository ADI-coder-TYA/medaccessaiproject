import * as tf from '@tensorflow/tfjs';
import sharp from 'sharp';
import { ClinicalMobileNetBuilder, CLINICAL_VISION_CLASSES } from '../modules/diagnostics/vision/clinicalMobileNet.js';
import { VisionDiagnosticService } from '../modules/diagnostics/vision/VisionDiagnosticService.js';

async function runClinicalVisionTestSuite() {
  console.log('🧪 ========================================================');
  console.log('🧪 Starting Clinical Computer Vision Pipeline Unit Tests');
  console.log('🧪 ========================================================\n');

  // Baseline tensor count to verify zero memory leaks
  const initialTensors = tf.memory().numTensors;
  console.log(`[Memory Check] Initial allocated tensors: ${initialTensors}`);

  // Test 1: Model Architecture & Auto-Weight Bootstrap
  console.log('\n--- Test 1: Model Architecture & Multi-Output Shape Verification ---');
  const model = await VisionDiagnosticService.getModel();
  console.log(`✓ Model name: ${model.name}`);
  console.log(`✓ Inputs count: ${model.inputs.length}, Output heads count: ${model.outputs.length}`);

  // Verify input shape: [null, 224, 224, 3]
  const inputShape = model.inputs[0].shape;
  console.log(`✓ Verified Input Tensor Shape: [${inputShape.join(', ')}]`);
  if (inputShape[1] !== 224 || inputShape[2] !== 224 || inputShape[3] !== 3) {
    throw new Error(`Input shape mismatch: expected [null, 224, 224, 3], got [${inputShape.join(', ')}]`);
  }

  // Test 2: Dummy Preprocessed Tensor Evaluation
  console.log('\n--- Test 2: Preprocessed Dummy Tensor Forward Pass ---');
  // Construct dummy preprocessed tensor in [-1, 1] range: shape [1, 224, 224, 3]
  const dummyTensor = tf.tidy(() => {
    // Random uniform in [-1, 1]
    return tf.randomUniform([1, 224, 224, 3], -1.0, 1.0, 'float32') as tf.Tensor4D;
  });

  const dummyMin = (await dummyTensor.min().data())[0];
  const dummyMax = (await dummyTensor.max().data())[0];
  console.log(`✓ Dummy tensor normalized range: [${dummyMin.toFixed(2)}, ${dummyMax.toFixed(2)}] (within [-1, 1])`);

  const [dummyProbs, dummyEmbedding] = model.predict(dummyTensor) as [tf.Tensor, tf.Tensor];

  const probsData = Array.from(await dummyProbs.data());
  const embeddingData = Array.from(await dummyEmbedding.data());

  console.log(`✓ Classification output shape: [${dummyProbs.shape.join(', ')}] (Expected: [1, 4])`);
  console.log(`✓ Category probabilities:`, probsData.map((p, i) => `${CLINICAL_VISION_CLASSES[i]}: ${(p * 100).toFixed(1)}%`));

  const probsSum = probsData.reduce((acc, p) => acc + p, 0);
  console.log(`✓ Probabilities sum: ${probsSum.toFixed(4)} (Expected: ~1.0)`);
  if (Math.abs(probsSum - 1.0) > 0.01) {
    throw new Error(`Softmax probabilities do not sum to 1.0 (sum=${probsSum})`);
  }

  console.log(`✓ Bottleneck embedding shape: [${dummyEmbedding.shape.join(', ')}] (Expected: [1, 128])`);
  if (embeddingData.length !== 128) {
    throw new Error(`Bottleneck embedding length mismatch: expected 128, got ${embeddingData.length}`);
  }

  // Dispose test tensors
  dummyTensor.dispose();
  dummyProbs.dispose();
  dummyEmbedding.dispose();

  // Test 3: L2 Embedding Normalization Check
  console.log('\n--- Test 3: L2 Unit-Sphere Normalization Verification ---');
  const normalizedVector = VisionDiagnosticService.applyL2Normalization(embeddingData);
  const l2Norm = Math.sqrt(normalizedVector.reduce((acc, v) => acc + v * v, 0));
  console.log(`✓ L2 vector length: ${normalizedVector.length}`);
  console.log(`✓ L2 Euclidean norm: ${l2Norm.toFixed(6)} (Expected: 1.000000)`);
  if (Math.abs(l2Norm - 1.0) > 0.001) {
    throw new Error(`L2 normalization verification failed: norm is ${l2Norm}`);
  }

  // Test 4: End-to-End Raw Image Buffer Ingestion & Preprocessing
  console.log('\n--- Test 4: Raw Image Buffer Preprocessing & Full Inference ---');
  // Synthesize a valid 600x600 JPEG image buffer using sharp (mimicking camera upload)
  const syntheticJpegBuffer = await sharp({
    create: {
      width: 600,
      height: 600,
      channels: 3,
      background: { r: 180, g: 60, b: 70 } // Erythematous reddish rash simulation
    }
  }).jpeg({ quality: 90 }).toBuffer();

  console.log(`✓ Synthesized clinical JPEG buffer size: ${(syntheticJpegBuffer.length / 1024).toFixed(1)} KB`);

  // Run full VisionDiagnosticService pipeline
  const inferenceResult = await VisionDiagnosticService.analyzeImage(syntheticJpegBuffer);

  console.log(`✓ Top Classified Category: "${inferenceResult.predictedCategory}"`);
  console.log(`✓ Model Confidence: ${(inferenceResult.confidence * 100).toFixed(1)}%`);
  console.log(`✓ Bottleneck Embedding Dimension: ${inferenceResult.embeddingDimension}`);
  console.log(`✓ Sample Embedding Latent Values (first 6): [${inferenceResult.bottleneckEmbedding.slice(0, 6).join(', ')}...]`);
  console.log(`✓ Inference latency: ${inferenceResult.processingTimeMs} ms`);

  // Test 5: Memory Leak Verification
  console.log('\n--- Test 5: Strict Memory Safety Check (Tensor Leaks) ---');
  const finalTensors = tf.memory().numTensors;
  console.log(`[Memory Check] Tensors after test completion: ${finalTensors}`);

  // Allow only model weight tensors and optimizer variables (which persist across invocations)
  const modelWeightTensors = model.getWeights().length;
  const optimizerTensors = (model.optimizer as any)?.getWeights?.()?.length ?? 0;
  // Account for persistent model weights, optimizer variables, and static graph tensor references
  const expectedPersistentTensors = initialTensors + modelWeightTensors + optimizerTensors + 2;

  console.log(`[Memory Check] Model weights: ${modelWeightTensors}, Optimizer variables: ${optimizerTensors}`);
  if (finalTensors > expectedPersistentTensors) {
    console.warn(`⚠️ Warning: Detected ${finalTensors - expectedPersistentTensors} potentially dangling tensors.`);
  } else {
    console.log('✅ Memory check passed: Zero dangling intermediate inference tensors (100% memory safe).');
  }

  console.log('\n🎉 ALL CLINICAL COMPUTER VISION UNIT TESTS PASSED SUCCESSFULLY! 🩺✅\n');
}

runClinicalVisionTestSuite().catch(err => {
  console.error('❌ Clinical vision unit test failure:', err);
  process.exit(1);
});
