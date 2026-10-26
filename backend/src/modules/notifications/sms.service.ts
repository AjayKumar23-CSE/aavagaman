import { Inject, Injectable, Logger } from '@nestjs/common';
import { APP_CONFIG } from '../../config/config.module';
import type { Env } from '../../config/env.schema';
import { maskPhone } from '../../common/phone';

/** Provider interface so MSG91 can be swapped for a fallback (SPEC §2). */
export interface SmsProvider {
  sendOtp(phone: string, code: string): Promise<void>;
  /** Free-text operational alert (SOS to admins, SPEC §14). */
  sendAlert(phone: string, message: string): Promise<void>;
}

const MSG91_FLOW_URL = 'https://control.msg91.com/api/v5/flow';

class Msg91Provider implements SmsProvider {
  private readonly logger = new Logger('Msg91');

  constructor(
    private readonly authKey: string,
    private readonly templateId: string,
    private readonly alertTemplateId?: string,
  ) {}

  /** MSG91 Flow API; DLT template variables are passed per recipient, mobiles without "+". */
  private async flow(templateId: string, phone: string, vars: Record<string, string>) {
    const res = await fetch(MSG91_FLOW_URL, {
      method: 'POST',
      headers: {
        authkey: this.authKey,
        'content-type': 'application/json',
        accept: 'application/json',
      },
      body: JSON.stringify({
        template_id: templateId,
        short_url: '0',
        recipients: [{ mobiles: phone.replace(/^\+/, ''), ...vars }],
      }),
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) throw new Error(`MSG91 responded ${res.status}`);
  }

  sendOtp(phone: string, code: string) {
    return this.flow(this.templateId, phone, { otp: code });
  }

  async sendAlert(phone: string, message: string) {
    if (!this.alertTemplateId) {
      this.logger.warn('MSG91_ALERT_TEMPLATE_ID not set; alert SMS skipped');
      return;
    }
    await this.flow(this.alertTemplateId, phone, { message });
  }
}

/** Development only: writes the code to the log instead of sending an SMS. */
class LogProvider implements SmsProvider {
  private readonly logger = new Logger('SmsLog');

  constructor(private readonly showCode: boolean) {}

  async sendOtp(phone: string, code: string) {
    this.logger.warn(`OTP for ${maskPhone(phone)}: ${this.showCode ? code : '[hidden]'}`);
  }

  async sendAlert(phone: string, message: string) {
    this.logger.warn(`ALERT SMS to ${maskPhone(phone)}: ${message}`);
  }
}

@Injectable()
export class SmsService implements SmsProvider {
  private readonly provider: SmsProvider;

  constructor(@Inject(APP_CONFIG) config: Env) {
    this.provider =
      config.MSG91_AUTH_KEY && config.MSG91_TEMPLATE_ID
        ? new Msg91Provider(
            config.MSG91_AUTH_KEY,
            config.MSG91_TEMPLATE_ID,
            config.MSG91_ALERT_TEMPLATE_ID,
          )
        : new LogProvider(config.NODE_ENV === 'development');
  }

  sendOtp(phone: string, code: string) {
    return this.provider.sendOtp(phone, code);
  }

  sendAlert(phone: string, message: string) {
    return this.provider.sendAlert(phone, message);
  }
}
