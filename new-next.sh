#!/bin/bash

if [ -z "$1" ]; then
  echo "Usage: ./new-next.sh <app-name>"
  exit 1
fi

pnpm create next-app "$1" \
  --typescript \
  --eslint \
  --tailwind \
  --app \
  --turbopack \
  --no-import-alias \
  --no-react-compiler \
  --no-src-dir \
  --use-pnpm

cd "$1"

pnpm add -D concurrently prisma rimraf

pnpm add \
  @ai-sdk/react \
  @ai-sdk/openai \
  @better-fetch/fetch \
  @prisma/adapter-pg \
  @prisma/client \
  ai \
  better-auth \
  date-fns \
  jotai \
  pg

# The default base color is neutral.
pnpm dlx shadcn@latest init --defaults
pnpm dlx shadcn@latest add --all

# Create all necessary directories
mkdir -p api/auth/[...all]
mkdir -p prisma

cat > env.example <<EOL
BETTER_AUTH_TELEMETRY=0
BETTER_AUTH_SECRET=$(openssl rand -base64 32)
BETTER_AUTH_URL=http://localhost:3000

DATABASE_URL=postgresql://postgres:password@localhost:5432/postgres

# For mailpit
SMTP_USER="mailpit"
SMTP_PASS="topsecret"
SMTP_HOST="127.0.0.1"
SMTP_PORT="1025"
EOL
cp env.example .env

# Prepare Prisma setup
cat > lib/prisma.ts <<EOL
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@/prisma/generated/client';

if (!process.env.DATABASE_URL) {
	throw new Error('DATABASE_URL environment variable is not set');
}

const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL });

declare global {
  // We need var in declare global
  // eslint-disable-next-line no-var, vars-on-top
  var prisma: PrismaClient | undefined;
}

const prisma = global.prisma || new PrismaClient({ adapter });

if (process.env.NODE_ENV === 'development') {
  global.prisma = prisma;
}

export { prisma };
EOL

cat > prisma/schema.prisma <<EOL
generator client {
  provider   = "prisma-client"
  engineType = "client"
  output     = "./generated"
}
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}
EOL

# Prepare Better Auth setup
cat > lib/auth-client.ts <<EOL
import {
	adminClient,
	apiKeyClient,
	anonymousClient,
} from 'better-auth/client/plugins';
import { createAuthClient } from 'better-auth/react';

export const authClient = createAuthClient({
	plugins: [adminClient(), apiKeyClient(), anonymousClient()],
});

export const {
	forgetPassword,
	resetPassword,
	signIn,
	signOut,
	signUp,
	useSession,
	verifyEmail,
} = authClient;
EOL

cat > auth.ts <<EOL
import { apiKey, admin, anonymous } from 'better-auth/plugins';
import { prismaAdapter } from 'better-auth/adapters/prisma';
import { betterAuth } from 'better-auth';
import { prisma } from '@/lib/prisma';

export const auth = betterAuth({
	database: prismaAdapter(prisma, {
		provider: 'postgresql',
	}),

	emailAndPassword: {
		enabled: true, // Email/password authentication enabled
		autoSignIn: true, // Auto sign in after registration
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

cat > api/auth/[...all]/route.ts <<EOL
import { toNextJsHandler } from 'better-auth/next-js';
import { auth } from '@/lib/auth';

export const { GET, POST } = toNextJsHandler(auth);
EOL

pnpm prisma generate

# we need to generate the auth.ts config file first
pnpm dlx @better-auth/cli@latest generate --yes
