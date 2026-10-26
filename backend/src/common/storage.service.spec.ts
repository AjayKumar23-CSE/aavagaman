import type { Env } from '../config/env.schema';
import { StorageService } from './storage.service';

const base = {
  S3_BUCKET: 'ride-docs',
  S3_ACCESS_KEY_ID: 'AKIDEXAMPLE',
  S3_SECRET_ACCESS_KEY: 'secret',
  S3_REGION: 'auto',
} as Env;

const credentialScope = (url: string) =>
  decodeURIComponent(new URL(url).searchParams.get('X-Amz-Credential') ?? '');

describe('StorageService', () => {
  it('Cloudflare R2: path-style URL on the endpoint, region auto', async () => {
    const s = new StorageService({
      ...base,
      S3_ENDPOINT: 'https://acc.r2.cloudflarestorage.com',
    } as Env);
    const url = await s.presignPut('drivers/u1/rc/a.jpg', 'image/jpeg', 600);
    expect(url).toMatch(
      /^https:\/\/acc\.r2\.cloudflarestorage\.com\/ride-docs\/drivers\/u1\/rc\/a\.jpg\?/,
    );
    expect(credentialScope(url)).toContain('/auto/s3/');
  });

  it('Amazon S3: no endpoint, virtual-hosted URL signed for the bucket region', async () => {
    const s = new StorageService({ ...base, S3_REGION: 'ap-south-1' } as Env);
    const url = await s.presignGet('drivers/u1/rc/a.jpg', 300);
    expect(url).toMatch(
      /^https:\/\/ride-docs\.s3\.ap-south-1\.amazonaws\.com\/drivers\/u1\/rc\/a\.jpg\?/,
    );
    expect(credentialScope(url)).toContain('/ap-south-1/s3/');
  });

  it('stays disabled without an endpoint or a real region', () => {
    const s = new StorageService(base);
    expect(() => s.presignGet('k', 300)).toThrow('File storage is not configured');
  });
});
