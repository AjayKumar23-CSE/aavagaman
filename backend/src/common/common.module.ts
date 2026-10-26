import { Global, Module } from '@nestjs/common';
import { AuditService } from './audit.service';
import { PrismaService } from './prisma.service';
import { RedisService } from './redis.service';
import { StorageService } from './storage.service';

@Global()
@Module({
  providers: [PrismaService, RedisService, AuditService, StorageService],
  exports: [PrismaService, RedisService, AuditService, StorageService],
})
export class CommonModule {}
