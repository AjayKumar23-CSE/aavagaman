import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Job } from 'bullmq';
import {
  JOB_MATCH,
  JOB_OFFER_TIMEOUT,
  MatchingService,
  MATCHING_QUEUE,
  MatchJob,
  OfferTimeoutJob,
} from './matching.service';

@Processor(MATCHING_QUEUE)
export class MatchingProcessor extends WorkerHost {
  constructor(private readonly matching: MatchingService) {
    super();
  }

  async process(job: Job) {
    switch (job.name) {
      case JOB_MATCH:
        return this.matching.runMatch(job.data as MatchJob);
      case JOB_OFFER_TIMEOUT:
        return this.matching.runOfferTimeout(job.data as OfferTimeoutJob);
    }
  }
}
