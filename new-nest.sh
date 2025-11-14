#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: ./new-nest.sh <app-name>"
  exit 1
fi

# Create NestJS project using CLI
pnpm dlx @nestjs/cli new "$1" --package-manager pnpm

cd "$1"

# Install dev dependencies
pnpm add -D prisma rimraf

# Install core dependencies
pnpm add \
  @nestjs/config \
  @prisma/client \
  @prisma/adapter-pg \
  @thallesp/nestjs-better-auth \
  better-auth \
  date-fns \
  pg

# For generate prisma module
pnpm dlx @nestjs/cli generate module prisma
pnpm dlx @nestjs/cli generate service prisma

# This is different from the above
mkdir -p prisma

# Add prisma/generated to .gitignore
echo "**/prisma/generated" >> .gitignore

# Generate BETTER_AUTH_SECRET
if command -v openssl >/dev/null 2>&1; then
  BETTER_AUTH_SECRET=$(openssl rand -base64 32)
else
  BETTER_AUTH_SECRET="replacewithyourverysecretstring"
fi

cat > .env <<EOL
BETTER_AUTH_TELEMETRY=0
BETTER_AUTH_SECRET=$BETTER_AUTH_SECRET
BETTER_AUTH_URL=http://localhost:3001

DATABASE_URL=postgresql://postgres:password@localhost:5432/postgres

# For mailpit
SMTP_USER=mailpit
SMTP_PASS=topsecret
SMTP_HOST=127.0.0.1
SMTP_PORT=1025
EOL

# Create Prisma schema
cat > prisma/schema.prisma <<EOL
generator client {
  provider     = "prisma-client"
  engineType   = "client"
  moduleFormat = "commonjs"
  output       = "../src/prisma/generated"
}
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}
EOL

# Create Prisma instance
cat > src/prisma/prisma.instance.ts <<EOL
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from './generated/client';

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error('DATABASE_URL environment variable is not set');
}

const adapter = new PrismaPg({ connectionString });

// We use this to omit some fields if we need to
const prismaClientSingleton = () => {
  return new PrismaClient({ adapter });
};

type PrismaClientSingleton = ReturnType<typeof prismaClientSingleton>;

const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClientSingleton | undefined;
};

const prisma = globalForPrisma.prisma ?? prismaClientSingleton();

if (process.env.NODE_ENV !== 'production') {
  globalForPrisma.prisma = prisma;
}

export { prisma };

export type PrismaInstance = typeof prisma;
EOL

# Create Prisma service
cat > src/prisma/prisma.service.ts <<EOL
import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { PrismaClient } from './generated/client';

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  async onModuleInit() {
    await this.\$connect();
  }

  async onModuleDestroy() {
    await this.\$disconnect();
  }
}
EOL

# Create Better Auth instance
cat > src/auth.ts <<EOL
import { apiKey, admin, anonymous } from 'better-auth/plugins';
import { prismaAdapter } from 'better-auth/adapters/prisma';
import { betterAuth } from 'better-auth';
import { prisma } from './prisma/prisma.instance';

export const auth = betterAuth({
  database: prismaAdapter(prisma, {
    provider: 'postgresql',
  }),

  emailAndPassword: {
    enabled: true,
    autoSignIn: true,
  },

  plugins: [
    apiKey(),
    anonymous(),
    admin({
      defaultRole: 'MEMBER',
    }),
  ],
});
EOL

# Update app.module.ts to import AuthModule and ConfigModule
cat > src/app.module.ts <<EOL
import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { AuthModule } from '@thallesp/nestjs-better-auth';
import { PrismaService } from './prisma/prisma.service';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { auth } from './auth';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
    }),
    AuthModule.forRoot({ auth }),
  ],
  controllers: [AppController],
  providers: [AppService, PrismaService],
})
export class AppModule {}
EOL

# Update main.ts to disable body parser
cat > src/main.ts <<EOL
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, {
    bodyParser: false, // Required for Better Auth
  });
  await app.listen(process.env.SERVER_PORT ?? 3001);
}
bootstrap();
EOL

# Generate Prisma client
pnpm dlx prisma generate

# Generate Better Auth tables
pnpm dlx @better-auth/cli@latest generate --yes --config src/auth.ts

echo ""
echo "✅ NestJS project '$1' created successfully!"
echo ""
echo "Next steps:"
echo "  cd $1"
echo "  pnpm run start:dev"
echo ""

