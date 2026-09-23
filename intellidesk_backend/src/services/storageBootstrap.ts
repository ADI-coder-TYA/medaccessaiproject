import { supabase } from '../config/supabase.js';

interface BucketConfig {
  name: string;
  public: boolean;
  fileSizeLimit: number; // in bytes
  allowedMimeTypes: string[];
}

const REQUIRED_BUCKETS: BucketConfig[] = [
  {
    name: 'receipts',
    public: true,
    fileSizeLimit: 15 * 1024 * 1024, // 15 MB
    allowedMimeTypes: [
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ]
  },
  {
    name: 'attachments',
    public: true,
    fileSizeLimit: 25 * 1024 * 1024, // 25 MB
    allowedMimeTypes: [
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'text/plain',
      'text/csv'
    ]
  },
  {
    name: 'voice_notes',
    public: true,
    fileSizeLimit: 25 * 1024 * 1024, // 25 MB
    allowedMimeTypes: [
      'audio/wav',
      'audio/x-wav',
      'audio/mpeg',
      'audio/mp3',
      'audio/m4a',
      'audio/mp4',
      'audio/ogg',
      'audio/webm',
      'audio/aac'
    ]
  },
  {
    name: 'clinical-diagnostics',
    public: true,
    fileSizeLimit: 30 * 1024 * 1024, // 30 MB
    allowedMimeTypes: [
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      'application/json'
    ]
  }
];

export async function ensureStorageBucketsExist(): Promise<void> {
  try {
    console.log('📦 [Storage Bootstrap] Checking Supabase storage buckets...');
    const { data: existingBuckets, error: listError } = await supabase.storage.listBuckets();

    if (listError) {
      console.warn(`⚠️ [Storage Bootstrap] Could not list buckets: ${listError.message}`);
      return;
    }

    const existingNames = new Set(existingBuckets?.map((b) => b.name) || []);

    for (const config of REQUIRED_BUCKETS) {
      if (!existingNames.has(config.name)) {
        console.log(`📦 [Storage Bootstrap] Bucket "${config.name}" not found. Creating...`);
        const { error: createError } = await supabase.storage.createBucket(config.name, {
          public: config.public,
          fileSizeLimit: config.fileSizeLimit,
          allowedMimeTypes: config.allowedMimeTypes
        });

        if (createError) {
          console.error(`🚨 [Storage Bootstrap] Failed to create "${config.name}":`, createError.message);
        } else {
          console.log(`✅ [Storage Bootstrap] Created public bucket "${config.name}" with size limit ${config.fileSizeLimit / (1024 * 1024)}MB.`);
        }
      } else {
        console.log(`✅ [Storage Bootstrap] Bucket "${config.name}" is verified and active.`);
      }
    }
  } catch (err: any) {
    console.error('🚨 [Storage Bootstrap Error]:', err.message);
  }
}
