#!/bin/bash

# ============================================================================
# new-next.sh — Scaffold a new Next.js project with opinionated defaults
# ============================================================================

# --- Defaults ---------------------------------------------------------------

VERSION="1.0.1"
APP_NAME=""
DRY_RUN=false
WITH_PRISMA=true
WITH_SHADCN=true
STEP_NUM=0

# --- Utility functions ------------------------------------------------------

die() { echo "Error: $1" >&2; exit 1; }

print_usage() {
  cat <<'EOF'
Usage: ./new-next.sh [flags] <app-name>

Flags:
  --dry-run      Print what would be executed without running anything
  --no-prisma    Skip Prisma, Docker, and Better Auth setup
  --no-shadcn    Skip shadcn/ui initialization and component install
  -v, --version  Show version
  --help         Show this help message

Examples:
  ./new-next.sh my-app
  ./new-next.sh --dry-run my-app
  ./new-next.sh --no-prisma --no-shadcn my-app
  ./new-next.sh --dry-run --no-shadcn my-app
EOF
  exit 0
}

# Execute a command, or print it in dry-run mode
run_cmd() {
  if $DRY_RUN; then
    echo "  > $*"
  else
    "$@"
  fi
}

# Write a file from stdin (heredoc), or print the filename in dry-run mode
run_write() {
  local file="$1"
  if $DRY_RUN; then
    echo "  > write $file"
    cat > /dev/null  # consume the heredoc
  else
    cat > "$file"
  fi
}

# Append to a file, or print the action in dry-run mode
run_append() {
  local file="$1"
  local content="$2"
  if $DRY_RUN; then
    echo "  > append \"$content\" to $file"
  else
    echo "$content" >> "$file"
  fi
}

step() {
  STEP_NUM=$((STEP_NUM + 1))
  echo "[Step $STEP_NUM] $1"
}

skip() {
  STEP_NUM=$((STEP_NUM + 1))
  echo "[Step $STEP_NUM] SKIPPED: $1"
}

# --- Step functions ---------------------------------------------------------

step_create_app() {
  step "Create Next.js app"
  run_cmd pnpm create next-app "$APP_NAME" \
    --typescript \
    --eslint \
    --tailwind \
    --app \
    --turbopack \
    --no-import-alias \
    --no-react-compiler \
    --no-src-dir \
    --use-pnpm
}

step_install_dev_deps() {
  step "Install dev dependencies"
  local deps=(concurrently rimraf)
  $WITH_PRISMA && deps+=(prisma)
  run_cmd pnpm add -D "${deps[@]}"
}

step_install_deps() {
  step "Install dependencies"
  local deps=(
    @ai-sdk/react
    @ai-sdk/openai
    ai
    date-fns
    dotenv
    jotai
  )
  if $WITH_PRISMA; then
    deps+=(
      @better-fetch/fetch
      @prisma/adapter-pg
      @prisma/client
      better-auth
      pg
    )
  fi
  run_cmd pnpm add "${deps[@]}"
}

step_init_shadcn() {
  step "Initialize shadcn/ui"
  # The default base color is neutral.
  run_cmd pnpm dlx shadcn@latest init --defaults
  run_cmd pnpm dlx shadcn@latest add --all
}

step_create_dirs() {
  step "Create directories"
  local dirs=()
  $WITH_PRISMA && dirs+=(app/api/auth/\[...all\] prisma docker lib)
  if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "  (no directories needed)"
    return
  fi
  run_cmd mkdir -p "${dirs[@]}"
}

step_update_gitignore() {
  step "Update .gitignore"
  run_append .gitignore "prisma/generated"
}

step_generate_docker_compose() {
  step "Generate docker/compose.dev.yml"
  run_write docker/compose.dev.yml <<EOL
name: $APP_NAME

services:
  postgres:
    container_name: $APP_NAME-postgres
    image: postgres:18-alpine
    restart: unless-stopped
    ports:
      - "5432:5432"
    volumes:
      - $APP_NAME-postgres-data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: postgres
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
    healthcheck:
      test:
        - CMD-SHELL
        - pg_isready --dbname=postgres --username=postgres
      interval: 10s
      timeout: 5s
      retries: 3

  redis:
    container_name: $APP_NAME-redis
    image: redis:7-alpine
    restart: unless-stopped
    ports:
      - "6379:6379"
    volumes:
      - $APP_NAME-redis-data:/data
    command: redis-server --appendonly yes
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

  mailpit:
    container_name: $APP_NAME-mailpit
    image: axllent/mailpit:latest
    restart: unless-stopped
    ports:
      - "1025:1025"
      - "8025:8025"

volumes:
  $APP_NAME-postgres-data:
  $APP_NAME-redis-data:
EOL
}

step_generate_env() {
  step "Generate .env"

  if $DRY_RUN; then
    echo "  > write .env"
    return
  fi

  # Build auth block conditionally
  local auth_block=""
  if $WITH_PRISMA; then
    local secret
    if command -v openssl >/dev/null 2>&1; then
      secret=$(openssl rand -base64 32)
    else
      secret="replacewithyourverysecretstring"
    fi
    auth_block="BETTER_AUTH_TELEMETRY=0
BETTER_AUTH_SECRET=$secret
BETTER_AUTH_URL=http://localhost:3000

"
  fi

  cat > .env <<EOL

${auth_block}POSTGRES_PASSWORD=password
DATABASE_URL=postgresql://postgres:password@localhost:5432/postgres

# For mailpit
SMTP_USER="mailpit"
SMTP_PASS="topsecret"
SMTP_HOST="127.0.0.1"
SMTP_PORT="1025"
EOL
}

step_generate_prisma_files() {
  step "Generate Prisma files"

  run_write lib/prisma.ts <<EOL
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from '@/prisma/generated/client';

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
	throw new Error('DATABASE_URL environment variable is not set');
}

const adapter = new PrismaPg({ connectionString });

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

  run_write prisma/schema.prisma <<EOL
generator client {
  provider = "prisma-client"
  output   = "./generated"
}
datasource db {
  provider = "postgresql"
}
EOL

  run_write prisma.config.ts <<EOL
import 'dotenv/config'
import { defineConfig, env } from 'prisma/config'

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
  },
  datasource: {
    url: env('DATABASE_URL'),
  },
})
EOL
}

step_generate_auth_files() {
  step "Generate Better Auth files"

  run_write lib/auth-client.ts <<EOL
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

  run_write auth.ts <<EOL
import { apiKey, admin, anonymous } from 'better-auth/plugins';
import { prismaAdapter } from 'better-auth/adapters/prisma';
import { betterAuth } from 'better-auth';
import { prisma } from '@/lib/prisma';

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

  run_write "app/api/auth/[...all]/route.ts" <<EOL
import { toNextJsHandler } from 'better-auth/next-js';
import { auth } from '@/auth';

export const { GET, POST } = toNextJsHandler(auth);
EOL
}

step_run_prisma_generate() {
  step "Run prisma generate"
  run_cmd pnpm dlx prisma generate
}

step_run_auth_generate() {
  step "Run better-auth generate"
  run_cmd pnpm dlx @better-auth/cli@latest generate --yes
}

# --- Parse arguments --------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --no-prisma)
      WITH_PRISMA=false
      shift
      ;;
    --no-shadcn)
      WITH_SHADCN=false
      shift
      ;;
    -v|--version)
      echo "new-next.sh $VERSION"
      exit 0
      ;;
    --help)
      print_usage
      ;;
    --*)
      die "Unknown flag: $1"
      ;;
    *)
      if [[ -z "$APP_NAME" ]]; then
        APP_NAME="$1"
      else
        die "Unexpected argument: $1 (app name already set to '$APP_NAME')"
      fi
      shift
      ;;
  esac
done

[[ -z "$APP_NAME" ]] && die "Missing required argument: <app-name>"

# --- Execute ----------------------------------------------------------------

step_create_app

if $DRY_RUN; then
  echo "  > cd $APP_NAME"
else
  cd "$APP_NAME" || die "Failed to cd into $APP_NAME"
fi

step_install_dev_deps
step_install_deps

if $WITH_SHADCN; then
  step_init_shadcn
else
  skip "shadcn/ui (--no-shadcn)"
fi

step_create_dirs
step_generate_env

if $WITH_PRISMA; then
  step_update_gitignore
  step_generate_docker_compose
  step_generate_prisma_files
  step_generate_auth_files
  step_run_prisma_generate
  step_run_auth_generate
else
  skip "Prisma setup (--no-prisma)"
  skip "Docker Compose (--no-prisma)"
  skip "Better Auth setup (--no-prisma)"
  skip "prisma generate (--no-prisma)"
  skip "better-auth generate (--no-prisma)"
fi

echo ""
echo "Done! cd $APP_NAME to get started."
