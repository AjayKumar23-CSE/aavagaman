import { Controller, Get, Header } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import { Public } from '../../common/auth/decorators';
import { privacyPolicyHtml } from './privacy.page';

/** Public legal pages: `GET /v1/legal/privacy` (linked from the apps and the Play listing). */
@ApiExcludeController()
@Public()
@Controller('legal')
export class LegalController {
  @Get('privacy')
  @Header('Content-Type', 'text/html; charset=utf-8')
  @Header('Cache-Control', 'public, max-age=3600')
  privacy() {
    return privacyPolicyHtml();
  }
}
