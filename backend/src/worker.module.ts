import { Module } from '@nestjs/common';
import { CoreModule } from './core.module';
import { ProcessorsModule } from './modules/matching/processors.module';

@Module({ imports: [CoreModule, ProcessorsModule] })
export class WorkerModule {}
