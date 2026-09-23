import * as tf from '@tensorflow/tfjs';
import * as tfNode from '@tensorflow/tfjs-node';
import sharp from 'sharp';
import {
  ClinicalMobileNetBuilder,
  CLINICAL_VISION_CLASSES,
  ClinicalVisionClass,
  INPUT_IMAGE_SIZE,
  BOTTLENECK_EMBEDDING_DIM
} from './clinicalMobileNet.js';

export interface ClinicalVisionInferenceResult {
  classProbabilities: Record<ClinicalVisionClass, number>;
  predictedCategory: ClinicalVisionClass;
  confidence: number;
  bottleneckEmbedding: number[]; // 128-dimensional L2-normalized vector
  embeddingDimension: number;
  processingTimeMs: number;
}

export class VisionDiagnosticService {
  private static model: tf.LayersModel | null = null;
  private static isInitializing = false;

  /**
   * Initializes or fetches the cached multi-output clinical vision model.
   */
  public static async getModel(): Promise<tf.LayersModel> {
    if (this.model) return this.model;

    if (this.isInitializing) {
      while (this.isInitializing) {
        await new Promise(resolve => setTimeout(resolve, 50));
      }
      if (this.model) return this.model;
    }

    this.isInitializing = true;
    try {
      this.model = await ClinicalMobileNetBuilder.loadOrBootstrapModel();
    } finally {
      this.isInitializing = false;
    }

    return this.model;
  }

  /**
   * Preprocesses raw image buffer:
   * 1. Primary: Native decode via tf.node.decodeImage(buffer, 3)
   * 2. Fallback: Sharp pipeline for zero-crash cross-platform robustness
   * 3. Resize to 224x224 RGB
   * 4. Normalize pixel dynamic range to [-1.0, 1.0]
   * 5. Reshape to [1, 224, 224, 3]
   */
  public static async preprocessImageBuffer(buffer: Buffer): Promise<tf.Tensor4D> {
    let tensor3d: tf.Tensor3D | null = null;

    // 1. Primary Decoder (Native TensorFlow C++ bindings)
    try {
      if (tfNode?.node?.decodeImage) {
        tensor3d = tfNode.node.decodeImage(buffer, 3) as tf.Tensor3D;
      }
    } catch (nativeErr) {
      // Gracefully fall back to sharp
    }

    // 2. Fallback Decoder via sharp
    if (!tensor3d) {
      try {
        const { data, info } = await sharp(buffer)
          .resize(INPUT_IMAGE_SIZE, INPUT_IMAGE_SIZE, { fit: 'fill' })
          .removeAlpha()
          .raw()
          .toBuffer({ resolveWithObject: true });

        // Build tensor directly from decoded Uint8Array
        const floatData = new Float32Array(data.length);
        for (let i = 0; i < data.length; i++) {
          floatData[i] = data[i];
        }

        tensor3d = tf.tensor3d(floatData, [info.height, info.width, 3], 'float32');
      } catch (sharpErr) {
        throw new Error(`Failed to decode image buffer via both native tf.node and sharp: ${sharpErr}`);
      }
    }

    // 3. Resize & Normalization inside tf.tidy to avoid dangling intermediate tensors
    const preprocessed4D = tf.tidy(() => {
      // Ensure exactly 224x224
      const resized = tf.image.resizeBilinear(tensor3d!, [INPUT_IMAGE_SIZE, INPUT_IMAGE_SIZE]);

      // Normalize from [0, 255] to [-1.0, 1.0] (MobileNet / Inception scale)
      // formula: (pixel / 127.5) - 1.0
      const normalized = tf.sub(tf.div(resized, 127.5), 1.0);

      // Expand to batch shape: [1, 224, 224, 3]
      return tf.expandDims(normalized, 0) as tf.Tensor4D;
    });

    // Explicitly dispose original un-normalized tensor
    tensor3d.dispose();

    return preprocessed4D;
  }

  /**
   * Executes clinical computer vision inference on raw image buffer.
   * Extracts 4-class probabilities and 128-d bottleneck embedding with strict memory safety.
   */
  public static async analyzeImage(buffer: Buffer): Promise<ClinicalVisionInferenceResult> {
    const startTime = Date.now();
    const model = await this.getModel();

    const inputTensor = await this.preprocessImageBuffer(buffer);

    let probsTensor: tf.Tensor | null = null;
    let embeddingTensor: tf.Tensor | null = null;

    try {
      // Model predict returns [classificationProbabilities, bottleneckEmbedding]
      const predictions = model.predict(inputTensor);

      if (Array.isArray(predictions)) {
        probsTensor = predictions[0];
        embeddingTensor = predictions[1];
      } else {
        throw new Error('Expected multi-output model prediction array [probs, embeddings]');
      }

      // Read tensors synchronously into CPU memory
      const probsData = Array.from(probsTensor.dataSync());
      const rawEmbedding = Array.from(embeddingTensor.dataSync());

      // 1. Structure Class Probabilities
      const classProbabilities = {} as Record<ClinicalVisionClass, number>;
      let maxProb = -1;
      let topCategory: ClinicalVisionClass = CLINICAL_VISION_CLASSES[0];

      for (let i = 0; i < CLINICAL_VISION_CLASSES.length; i++) {
        const cat = CLINICAL_VISION_CLASSES[i];
        const prob = Number((probsData[i] ?? 0.0).toFixed(4));
        classProbabilities[cat] = prob;

        if (prob > maxProb) {
          maxProb = prob;
          topCategory = cat;
        }
      }

      // 2. L2 Normalization on the 128-dimensional Bottleneck Embedding Vector
      const l2Embedding = this.applyL2Normalization(rawEmbedding);

      const processingTimeMs = Date.now() - startTime;

      return {
        classProbabilities,
        predictedCategory: topCategory,
        confidence: maxProb,
        bottleneckEmbedding: l2Embedding,
        embeddingDimension: BOTTLENECK_EMBEDDING_DIM,
        processingTimeMs
      };
    } finally {
      // Memory Safety: dispose all allocated tensors
      inputTensor.dispose();
      probsTensor?.dispose();
      embeddingTensor?.dispose();
    }
  }

  /**
   * Applies L2 Unit-Sphere Normalization: v / sqrt(sum(v_i^2)).
   */
  public static applyL2Normalization(vector: number[]): number[] {
    let sumSq = 0;
    for (let i = 0; i < vector.length; i++) {
      sumSq += vector[i] * vector[i];
    }
    const norm = Math.sqrt(sumSq) || 1.0;
    return vector.map(v => Number((v / norm).toFixed(6)));
  }
}
