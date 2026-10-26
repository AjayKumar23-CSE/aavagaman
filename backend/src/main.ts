// Validates config and starts Sentry before anything else loads.
import './instrument';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { Logger } from 'nestjs-pino';
import { AppModule } from './app.module';
import { configureApp } from './app.setup';
import { loadConfig } from './config/config.module';

async function bootstrap() {
  const env = loadConfig();

  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    bufferLogs: true,
    bodyParser: false,
  });
  app.useLogger(app.get(Logger));
  configureApp(app, env);

  if (env.NODE_ENV !== 'production' || env.ENABLE_DOCS) {
    const doc = SwaggerModule.createDocument(
      app,
      new DocumentBuilder().setTitle('Ride Platform API').setVersion('1.0').addBearerAuth().build(),
    );
    SwaggerModule.setup('docs', app, doc);
  }

  await app.listen(env.PORT, '0.0.0.0');
}

bootstrap().catch((err: unknown) => {
  // Config errors land here with a readable list of missing variables.
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
});
