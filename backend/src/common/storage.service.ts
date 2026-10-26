import { GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import { APP_CONFIG } from '../config/config.module';
import type { Env } from '../config/env.schema';
import { AppException } from './app.exception';

/**
 * Private bucket on Cloudflare R2 (S3_ENDPOINT set, region `auto`) or Amazon
 * S3 (no endpoint, S3_REGION = the bucket's region). Objects are only
 * reachable via signed URLs.
 */
@Injectable()
export class StorageService {
  private readonly client?: S3Client;
  private readonly bucket?: string;

  constructor(@Inject(APP_CONFIG) config: Env) {
    // Amazon S3 needs the real region to sign; `auto` only works with an R2 endpoint.
    const located = Boolean(config.S3_ENDPOINT) || config.S3_REGION !== 'auto';
    if (located && config.S3_BUCKET && config.S3_ACCESS_KEY_ID && config.S3_SECRET_ACCESS_KEY) {
      this.bucket = config.S3_BUCKET;
      this.client = new S3Client({
        region: config.S3_REGION,
        ...(config.S3_ENDPOINT ? { endpoint: config.S3_ENDPOINT, forcePathStyle: true } : {}),
        // SDK v3 adds an x-amz-checksum-crc32 of the *empty* body to presigned PUTs by
        // default; R2 then rejects the real upload (BadDigest). Checksums only when required.
        requestChecksumCalculation: 'WHEN_REQUIRED',
        responseChecksumValidation: 'WHEN_REQUIRED',
        credentials: {
          accessKeyId: config.S3_ACCESS_KEY_ID,
          secretAccessKey: config.S3_SECRET_ACCESS_KEY,
        },
      });
    }
  }

  private ready() {
    if (!this.client || !this.bucket) {
      throw new AppException(
        'STORAGE_UNAVAILABLE',
        'File storage is not configured',
        HttpStatus.SERVICE_UNAVAILABLE,
      );
    }
    return { client: this.client, bucket: this.bucket };
  }

  presignPut(key: string, contentType: string, expiresInSeconds: number) {
    const { client, bucket } = this.ready();
    return getSignedUrl(
      client,
      new PutObjectCommand({ Bucket: bucket, Key: key, ContentType: contentType }),
      // Content-Type is part of the signature, so the client must upload what it declared.
      { expiresIn: expiresInSeconds, signableHeaders: new Set(['content-type']) },
    );
  }

  presignGet(key: string, expiresInSeconds: number) {
    const { client, bucket } = this.ready();
    return getSignedUrl(client, new GetObjectCommand({ Bucket: bucket, Key: key }), {
      expiresIn: expiresInSeconds,
    });
  }
}
