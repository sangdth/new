#!/bin/bash

# ============================================================================
# new-next.sh — Scaffold a new Next.js project with opinionated defaults
# ============================================================================

# --- Defaults ---------------------------------------------------------------

VERSION="3.0.0"
APP_NAME=""
DRY_RUN=false
STEP_NUM=0

# Invocation name, so help/version text matches how the script was actually
# called — "./new-next.sh" when run directly, "nnx" when run via a symlink.
PROG="$(basename "$0")"

# --- Utility functions ------------------------------------------------------

die() { echo "Error: $1" >&2; exit 1; }

print_usage() {
  cat <<EOF
Usage: $PROG [flags] <app-name>

Flags:
  --dry-run      Print what would be executed without running anything
  -v, --version  Show version
  --help         Show this help message

Examples:
  $PROG my-app
  $PROG --dry-run my-app

Creates the project as a subdirectory of the current working directory.
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

step() {
  STEP_NUM=$((STEP_NUM + 1))
  echo "[Step $STEP_NUM] $1"
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
  run_cmd pnpm add -D \
    concurrently \
    rimraf \
    graphile-migrate \
    kysely-codegen \
    @types/pg
}

step_install_deps() {
  step "Install dependencies"
  # Nothing here is pinned. The apiKey plugin ships as its own package
  # (@better-auth/api-key) rather than in the better-auth barrel export, so it is
  # installed alongside better-auth instead of being pulled from it.
  run_cmd pnpm add \
    @ai-sdk/react \
    @ai-sdk/openai \
    @better-fetch/fetch \
    ai \
    better-auth \
    @better-auth/api-key \
    date-fns \
    dotenv \
    jotai \
    kysely \
    pg
}

step_init_shadcn() {
  step "Initialize shadcn/ui"
  # The default base color is neutral.
  run_cmd pnpm dlx shadcn@latest init --defaults
  run_cmd pnpm dlx shadcn@latest add --all
}

step_create_dirs() {
  step "Create directories"
  run_cmd mkdir -p \
    app/api/auth/\[...all\] \
    migrations/committed \
    docker \
    lib
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
      # Postgres 18+ stores data in a versioned subdir; mount the parent directory.
      - $APP_NAME-postgres-data:/var/lib/postgresql
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

  local secret
  if command -v openssl >/dev/null 2>&1; then
    secret=$(openssl rand -base64 32)
  else
    secret="replacewithyourverysecretstring"
  fi

  cat > .env <<EOL
BETTER_AUTH_TELEMETRY=0
BETTER_AUTH_SECRET=$secret
BETTER_AUTH_URL=http://localhost:3000

POSTGRES_PASSWORD=password
DATABASE_URL=postgresql://postgres:password@localhost:5432/postgres

# graphile-migrate uses a shadow DB (commit) and a root/maintenance DB (reset).
# All three connection strings must differ, so root points at the default template1.
SHADOW_DATABASE_URL=postgresql://postgres:password@localhost:5432/postgres_shadow
ROOT_DATABASE_URL=postgresql://postgres:password@localhost:5432/template1

# For mailpit
SMTP_USER="mailpit"
SMTP_PASS="topsecret"
SMTP_HOST="127.0.0.1"
SMTP_PORT="1025"
EOL
}

step_generate_db_files() {
  step "Generate Kysely + graphile-migrate files"

  run_write lib/db.ts <<EOL
import { Kysely, PostgresDialect } from 'kysely';
import { Pool } from 'pg';
import type { DB } from '@/lib/db-types';

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error('DATABASE_URL environment variable is not set');
}

declare global {
  // \`var\` is required here: let/const don't create properties on globalThis,
  // so the singleton below wouldn't survive a hot reload.
  var db: Kysely<DB> | undefined;
}

const db =
  global.db ||
  new Kysely<DB>({
    dialect: new PostgresDialect({
      pool: new Pool({ connectionString }),
    }),
  });

if (process.env.NODE_ENV === 'development') {
  global.db = db;
}

export { db };
EOL

  run_write lib/db-types.ts <<EOL
/**
 * Database types for Kysely.
 *
 * Auto-generated by kysely-codegen from your live database. After applying
 * migrations, regenerate with:
 *
 *   pnpm db:codegen
 *
 * The placeholder below lets the project type-check before the first codegen
 * run. Do not edit by hand — running codegen overwrites this file.
 */
export type DB = Record<string, never>;
EOL

  run_write .gmrc.js <<EOL
require('dotenv/config');

/** @type {import('graphile-migrate').Settings} */
module.exports = {
  connectionString: process.env.DATABASE_URL,
  shadowConnectionString: process.env.SHADOW_DATABASE_URL,
  rootConnectionString: process.env.ROOT_DATABASE_URL,
  pgSettings: {},
  placeholders: {},
  afterReset: [],
  afterAllMigrations: [],
  afterCurrent: [],
};
EOL

  run_write migrations/committed/.gitkeep </dev/null
}

step_generate_auth_files() {
  step "Generate Better Auth files"

  run_write lib/auth-client.ts <<EOL
import { adminClient, anonymousClient } from 'better-auth/client/plugins';
import { apiKeyClient } from '@better-auth/api-key/client';
import { createAuthClient } from 'better-auth/react';

export const authClient = createAuthClient({
	plugins: [adminClient(), apiKeyClient(), anonymousClient()],
});

export const {
	requestPasswordReset,
	resetPassword,
	signIn,
	signOut,
	signUp,
	useSession,
	verifyEmail,
} = authClient;
EOL

  run_write auth.ts <<EOL
import { admin, anonymous } from 'better-auth/plugins';
import { apiKey } from '@better-auth/api-key';
import { betterAuth } from 'better-auth';
import { Pool } from 'pg';

export const auth = betterAuth({
	database: new Pool({
		connectionString: process.env.DATABASE_URL,
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

step_add_package_scripts() {
  step "Add package.json scripts"
  run_cmd npm pkg set \
    "scripts.db:watch=graphile-migrate watch" \
    "scripts.db:migrate=graphile-migrate migrate" \
    "scripts.db:commit=graphile-migrate commit" \
    "scripts.db:reset=graphile-migrate reset" \
    "scripts.db:codegen=kysely-codegen --dialect postgres --out-file lib/db-types.ts" \
    "scripts.auth:generate=pnpm dlx @better-auth/cli@latest generate --yes --output migrations/current.sql"
}

# --- Parse arguments --------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -v|--version)
      echo "$PROG $VERSION"
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
step_init_shadcn
step_create_dirs
step_generate_env
step_generate_docker_compose
step_generate_db_files
step_generate_auth_files
step_add_package_scripts

cat <<EOF

Done! Next steps:

  cd $APP_NAME

  # 1. Start Postgres, Redis, and Mailpit (waits until healthy)
  docker compose -f docker/compose.dev.yml --env-file .env up -d --wait

  # 2. Generate the Better Auth schema into migrations/current.sql
  #    (needs the database running — the pg adapter introspects it)
  pnpm auth:generate

  # 3. Apply the migration to your dev database
  pnpm db:watch --once

  # 4. Generate Kysely types from the database
  pnpm db:codegen

  # 5. Start the dev server
  pnpm dev

When the schema is stable, freeze it as a committed migration: pnpm db:commit
EOF
