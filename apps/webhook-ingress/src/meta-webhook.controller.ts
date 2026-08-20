import {
  BadRequestException,
  Body,
  Controller,
  ForbiddenException,
  Get,
  Header,
  Headers,
  HttpCode,
  HttpStatus,
  Inject,
  Post,
  Query,
  Req,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';

import { verifyMetaWebhookChallenge, verifyMetaWebhookSignature } from '@crm/meta-cloud-api';

import { parseMetaWebhookConfig } from './meta-webhook.config.js';

import { MetaWebhookService } from './meta-webhook.service.js';

type RequestWithRawBody = Readonly<{
  rawBody?: Buffer;
}>;

@Controller('webhooks/meta/whatsapp')
export class MetaWebhookController {
  private readonly config = parseMetaWebhookConfig();

  constructor(
    @Inject(MetaWebhookService)
    private readonly webhookService: MetaWebhookService,
  ) {}

  @Get()
  @Header('Content-Type', 'text/plain')
  verify(
    @Query('hub.mode')
    mode: string | undefined,

    @Query('hub.verify_token')
    verifyToken: string | undefined,

    @Query('hub.challenge')
    challenge: string | undefined,
  ): string {
    if (!this.config.verifyToken) {
      throw new ServiceUnavailableException({
        code: 'META_WEBHOOK_NOT_CONFIGURED',

        message: 'Meta webhook verification is not configured.',
      });
    }

    const result = verifyMetaWebhookChallenge({
      mode,

      providedToken: verifyToken,

      challenge,

      expectedToken: this.config.verifyToken,
    });

    if (result === null) {
      throw new ForbiddenException({
        code: 'META_WEBHOOK_VERIFICATION_DENIED',

        message: 'Meta webhook verification failed.',
      });
    }

    return result;
  }

  @Post()
  @HttpCode(HttpStatus.OK)
  @Header('Content-Type', 'text/plain')
  async receive(
    @Req()
    request: RequestWithRawBody,

    @Headers('x-hub-signature-256')
    signature: string | undefined,

    @Body()
    payload: unknown,
  ): Promise<string> {
    if (!this.config.appSecret) {
      throw new ServiceUnavailableException({
        code: 'META_WEBHOOK_NOT_CONFIGURED',

        message: 'Meta webhook signature validation is not configured.',
      });
    }

    const rawBody = request.rawBody;

    if (!rawBody || rawBody.length === 0) {
      throw new BadRequestException({
        code: 'META_WEBHOOK_RAW_BODY_REQUIRED',

        message: 'Raw webhook body is required.',
      });
    }

    if (!verifyMetaWebhookSignature(this.config.appSecret, rawBody, signature)) {
      throw new UnauthorizedException({
        code: 'META_WEBHOOK_SIGNATURE_INVALID',

        message: 'Invalid Meta webhook signature.',
      });
    }

    const result = await this.webhookService.ingest(payload, rawBody);

    console.log(
      JSON.stringify({
        event: 'meta.webhook.received',

        envelopeId: result.envelopeId,

        status: result.status,

        matched: result.whatsAppNumberId !== null,

        timestamp: new Date().toISOString(),
      }),
    );

    return 'EVENT_RECEIVED';
  }
}
