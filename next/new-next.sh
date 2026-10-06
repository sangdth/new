#!/bin/bash

# ============================================================================
# new-next.sh — Scaffold a new Next.js project with opinionated defaults
# ============================================================================

set -euo pipefail

# --- Defaults ---------------------------------------------------------------

VERSION="4.1.0"
APP_NAME=""
PRESET="b1oVxsfY"
DRY_RUN=false
NO_AI=false
STEP_NUM=0

# Database/auth layer the project is scaffolded around: kysely (default,
# graphile-migrate) or prisma/drizzle with their own toolchains.
PROVIDER="kysely"

# Headless opencode run that writes the version-sensitive auth code.
AI_MODEL="${NNX_MODEL:-opencode-go/deepseek-v4-pro}"
AI_TIMEOUT="${NNX_AI_TIMEOUT:-1000}"

# Node release line the project runs on: "lts" or "latest". Resolved to exact
# versions at scaffold time and written to devEngines, which pnpm downloads.
NODE_CHANNEL="${NNX_NODE:-lts}"
NODE_VERSION=""
PNPM_VERSION=""

# Invocation name, so help/version text matches how the script was actually
# called — "./new-next.sh" when run directly, "nnx" when run via a symlink.
PROG="$(basename "$0")"

# --- Utility functions ------------------------------------------------------

die() { echo "Error: $1" >&2; exit 1; }
warn() { echo "Warning: $1" >&2; }

print_usage() {
  cat <<EOF
Usage: $PROG [flags] <app-name>

Flags:
  --preset <code>     shadcn preset code from the theme builder (default: $PRESET)
  --provider <db>     database/auth layer: kysely (default), prisma or drizzle
  --no-ai             Skip the opencode step that writes the auth code
  --dry-run           Print what would be executed without running anything
  -v, --version       Show version
  --help              Show this help message

Environment:
  NNX_MODEL        opencode model (default: $AI_MODEL)
  NNX_AI_TIMEOUT   Seconds before the opencode step is killed (default: $AI_TIMEOUT)
  NNX_NODE         Node release line for the project: lts or latest (default: $NODE_CHANNEL)

Examples:
  $PROG my-app
  $PROG --provider prisma my-app
  $PROG --preset b1f3nwcmmG my-app
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

# Look up the newest Node (on NODE_CHANNEL) and pnpm releases.
resolve_toolchain() {
  [[ "$NODE_CHANNEL" == lts || "$NODE_CHANNEL" == latest ]] \
    || die "NNX_NODE must be lts or latest (got '$NODE_CHANNEL')"
  NODE_VERSION="$(NNX_NODE="$NODE_CHANNEL" node -e '
fetch("https://nodejs.org/dist/index.json")
  .then((r) => r.json())
  .then((list) => {
    const release = process.env.NNX_NODE === "lts" ? list.find((v) => v.lts) : list[0];
    console.log(release.version.slice(1));
  });
' 2>/dev/null)" || true
  PNPM_VERSION="$(npm view pnpm version 2>/dev/null)" || true
  [[ -n "$NODE_VERSION" ]] || die "could not look up the $NODE_CHANNEL Node version"
  [[ -n "$PNPM_VERSION" ]] || die "could not look up the latest pnpm version"
  echo "Toolchain: Node $NODE_VERSION ($NODE_CHANNEL), pnpm $PNPM_VERSION"
}

check_prereqs() {
  command -v node >/dev/null 2>&1 || die "node not found"
  command -v pnpm >/dev/null 2>&1 || die "pnpm not found (npm i -g pnpm)"
  command -v docker >/dev/null 2>&1 || warn "docker not found; you'll need it for the post-setup steps"

  resolve_toolchain

  if ! $NO_AI; then
    # Run the binary rather than checking it exists: a broken install passes
    # `command -v` and then dies on exec with no output.
    if ! opencode --version >/dev/null 2>&1; then
      warn "opencode is missing or won't run; continuing with --no-ai"
      NO_AI=true
    fi
  fi
}

step_create_app() {
  step "Create Next.js app"
  # --skip-install: the install would run on the global pnpm and leave a lockfile
  # the pinned pnpm rejects. The first `pnpm add` installs everything instead.
  run_cmd pnpm create next-app "$APP_NAME" \
    --typescript \
    --eslint \
    --tailwind \
    --app \
    --turbopack \
    --no-import-alias \
    --no-react-compiler \
    --no-src-dir \
    --use-pnpm \
    --skip-install
}

step_install_dev_deps() {
  step "Install dev dependencies"
  local deps=(concurrently rimraf)
  case "$PROVIDER" in
    kysely)
      deps+=(graphile-migrate kysely-codegen @types/pg)
      ;;
    prisma)
      # The `prisma` CLI's latest dist-tag is an 8.0.0 RC while @prisma/client's
      # is 7.x; pin the toolchain to 7 so the CLI and the client stay one major.
      deps+=(prisma@^7 @types/pg)
      ;;
    drizzle)
      deps+=(drizzle-kit @types/pg)
      ;;
  esac
  run_cmd pnpm add -D "${deps[@]}"
}

step_install_deps() {
  step "Install dependencies"
  # Nothing here is pinned. The apiKey plugin ships as its own package
  # (@better-auth/api-key) rather than in the better-auth barrel export, so it is
  # installed alongside better-auth instead of being pulled from it.
  local deps=(
    @ai-sdk/react
    @ai-sdk/openai
    @better-fetch/fetch
    ai
    better-auth
    @better-auth/api-key
    date-fns
    dotenv
    jotai
  )
  case "$PROVIDER" in
    kysely) deps+=(kysely pg) ;;
    prisma) deps+=(@prisma/client@^7 @prisma/adapter-pg@^7 pg) ;;
    drizzle) deps+=(drizzle-orm pg) ;;
  esac
  run_cmd pnpm add "${deps[@]}"
}

step_init_shadcn() {
  step "Initialize shadcn/ui"
  # A preset carries the whole design system and can only be applied at init.
  run_cmd pnpm dlx shadcn@latest init --preset "$PRESET" --template next --pointer
  run_cmd pnpm dlx shadcn@latest add --all
}

step_create_dirs() {
  step "Create directories"
  local dirs=(docker lib)
  case "$PROVIDER" in
    kysely) dirs+=(migrations/committed) ;;
    prisma) dirs+=(prisma) ;;
  esac
  run_cmd mkdir -p "${dirs[@]}"
}

step_generate_docker_compose() {
  step "Generate docker/compose.dev.yml"
  # Compose prefixes volume names with the project name, so they stay short.
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
      - postgres-data:/var/lib/postgresql
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
      - redis-data:/data
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
  postgres-data:
  redis-data:
EOL
}

step_generate_env() {
  step "Generate .env"

  local secret password="password"
  secret=$(openssl rand -base64 32 2>/dev/null || echo "replacewithyourverysecretstring")
  # Prisma's engine resolves "localhost" to ::1 first and Postgres in Docker
  # listens on IPv4 only, so it gets the address instead of the name.
  local db_host="localhost"
  [[ "$PROVIDER" == prisma ]] && db_host="127.0.0.1"
  local pg="postgresql://postgres:$password@$db_host:5432"
  local db_extra=""
  if [[ "$PROVIDER" == kysely ]]; then
    db_extra="$(printf '\n# graphile-migrate uses a shadow DB (commit) and a root/maintenance DB (reset).\n# All three connection strings must differ, so root points at the default template1.\nSHADOW_DATABASE_URL=%s/postgres_shadow\nROOT_DATABASE_URL=%s/template1' "$pg" "$pg")"
  fi

  run_write .env <<EOL
BETTER_AUTH_TELEMETRY=0
BETTER_AUTH_SECRET=$secret
BETTER_AUTH_URL=http://localhost:3000

POSTGRES_PASSWORD=$password
DATABASE_URL=$pg/postgres$db_extra

# For mailpit
SMTP_USER="mailpit"
SMTP_PASS="topsecret"
SMTP_HOST="127.0.0.1"
SMTP_PORT="1025"
EOL
}

step_generate_db_files() {
  step "Generate database files ($PROVIDER)"

  case "$PROVIDER" in
    kysely)
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
      ;;

    prisma)
  run_write prisma/schema.prisma <<EOL
generator client {
  provider   = "prisma-client"
  engineType = "client"
  output     = "../lib/prisma/generated"
}

datasource db {
  provider = "postgresql"
}
EOL

  # Prisma 7 moved the connection URL out of the schema; the CLI reads it here.
  run_write prisma.config.ts <<EOL
import 'dotenv/config';
import { defineConfig, env } from 'prisma/config';

export default defineConfig({
  schema: 'prisma/schema.prisma',
  datasource: {
    url: env('DATABASE_URL'),
  },
});
EOL

  run_write lib/prisma.ts <<EOL
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from './prisma/generated/client';

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error('DATABASE_URL environment variable is not set');
}

const adapter = new PrismaPg({ connectionString });

const prismaClientSingleton = () => new PrismaClient({ adapter });

type PrismaClientSingleton = ReturnType<typeof prismaClientSingleton>;

declare global {
  // \`var\` is required here: let/const don't create properties on globalThis,
  // so the singleton below wouldn't survive a hot reload.
  var prisma: PrismaClientSingleton | undefined;
}

const prisma = global.prisma ?? prismaClientSingleton();

if (process.env.NODE_ENV !== 'production') {
  global.prisma = prisma;
}

export { prisma };
export type PrismaInstance = typeof prisma;
EOL

  # The generated client is build output, and the auth-code step imports it, so
  # generate it once before any typecheck runs.
  run_cmd sh -c "grep -q 'lib/prisma/generated' .gitignore || echo '**/lib/prisma/generated' >> .gitignore"
  run_cmd pnpm exec prisma generate
      ;;

    drizzle)
  run_write lib/db.ts <<EOL
import { drizzle } from 'drizzle-orm/node-postgres';
import { Pool } from 'pg';

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error('DATABASE_URL environment variable is not set');
}

declare global {
  // \`var\` is required here: let/const don't create properties on globalThis,
  // so the singleton below wouldn't survive a hot reload.
  var db: ReturnType<typeof drizzle> | undefined;
}

const db = global.db ?? drizzle(new Pool({ connectionString }));

if (process.env.NODE_ENV === 'development') {
  global.db = db;
}

export { db };
EOL

  run_write drizzle.config.ts <<EOL
import 'dotenv/config';
import { defineConfig } from 'drizzle-kit';

export default defineConfig({
  schema: './lib/auth-schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: {
    url: process.env.DATABASE_URL!,
  },
});
EOL

  # Filled by \`pnpm auth:generate\` after the database is up; the empty module
  # keeps typecheck green before that.
  run_write lib/auth-schema.ts <<EOL
// Generated by \`pnpm auth:generate\`. Extend this file with your own tables and
// keep drizzle.config.ts pointing at it.
export {};
EOL
      ;;
  esac
}

step_add_package_scripts() {
  step "Add package.json scripts"
  # Every compose call needs --env-file .env; without it POSTGRES_PASSWORD
  # silently interpolates to an empty string, so the docker:* scripts carry it.
  local compose="docker compose -f docker/compose.dev.yml --env-file .env"
  # next typegen writes the route types (LayoutProps, PageProps) into the
  # gitignored .next/, so typecheck works before the first dev/build.
  # The auth CLI pulls @prisma/client and better-sqlite3, whose build scripts the
  # generated pnpm-workspace.yaml denies; on pnpm 11+ that aborts the dlx install
  # with ERR_PNPM_IGNORED_BUILDS unless each is allowed here. The CLI bundles
  # every adapter, so the flags do not vary with --provider.
  local db_scripts=()
  case "$PROVIDER" in
    kysely)
      db_scripts=(
        "scripts.db:watch=graphile-migrate watch"
        "scripts.db:migrate=graphile-migrate migrate"
        "scripts.db:commit=graphile-migrate commit"
        "scripts.db:reset=graphile-migrate reset"
        "scripts.db:codegen=kysely-codegen --dialect postgres --exclude-pattern graphile_migrate.* --out-file lib/db-types.ts"
        "scripts.auth:generate=pnpm dlx --allow-build=@prisma/client --allow-build=better-sqlite3 @better-auth/cli@latest generate --yes --output migrations/current.sql"
      )
      ;;
    prisma)
      db_scripts=(
        "scripts.db:generate=prisma generate"
        # --name keeps it non-interactive: without it prisma prompts and hangs
        # when stdin is not a TTY (CI, agents, first run).
        "scripts.db:migrate=prisma migrate dev --name init"
        "scripts.db:deploy=prisma migrate deploy"
        "scripts.db:studio=prisma studio"
        "scripts.auth:generate=pnpm dlx --allow-build=@prisma/client --allow-build=better-sqlite3 @better-auth/cli@latest generate --yes"
      )
      ;;
    drizzle)
      db_scripts=(
        "scripts.db:generate=drizzle-kit generate"
        "scripts.db:migrate=drizzle-kit migrate"
        "scripts.db:push=drizzle-kit push"
        "scripts.db:studio=drizzle-kit studio"
        "scripts.auth:generate=pnpm dlx --allow-build=@prisma/client --allow-build=better-sqlite3 @better-auth/cli@latest generate --yes --output lib/auth-schema.ts"
      )
      ;;
  esac
  run_cmd npm pkg set \
    "scripts.typecheck=next typegen && tsc --noEmit" \
    "${db_scripts[@]}" \
    "scripts.docker=$compose up -d --wait" \
    "scripts.docker:stop=$compose stop" \
    "scripts.docker:down=$compose down" \
    "scripts.docker:ps=$compose ps -a" \
    "scripts.docker:logs=$compose logs -f"
}

step_pin_toolchain() {
  step "Pin Node $NODE_VERSION and pnpm $PNPM_VERSION"
  # pnpm reads devEngines, downloads both on first use and runs every later
  # step on them, whatever is installed globally. npm refuses to touch a
  # package.json whose devEngines.runtime doesn't match its own Node, so this
  # runs after the last `npm pkg set`. create-next-app writes its own
  # packageManager field, which Corepack prefers over devEngines, so it goes.
  # It also writes pnpm-workspace.yaml in pnpm 10's format; pnpm 11+ reads
  # build approvals from allowBuilds and fails the install on any build it
  # isn't told about. .nvmrc keeps the shell's node in step.
  run_cmd npm pkg delete packageManager
  run_cmd npm pkg set --json \
    "devEngines.runtime={\"name\":\"node\",\"version\":\"$NODE_VERSION\",\"onFail\":\"download\"}" \
    "devEngines.packageManager={\"name\":\"pnpm\",\"version\":\"$PNPM_VERSION\",\"onFail\":\"download\"}"
  run_write .nvmrc <<<"$NODE_VERSION"
  # Provider packages with build scripts have to be allowed here, or pnpm 11+
  # fails the install. sharp/unrs-resolver stay denied because Next.js does not
  # need their native builds for this setup.
  local allow_extra=""
  case "$PROVIDER" in
    prisma) allow_extra=$'\n  prisma: true\n  "@prisma/client": true\n  "@prisma/engines": true' ;;
    drizzle) allow_extra=$'\n  esbuild: true' ;;
  esac
  run_write pnpm-workspace.yaml <<EOL
allowBuilds:
  sharp: false
  unrs-resolver: false$allow_extra
EOL
}

step_snapshot() {
  step "Commit scaffold snapshot"
  # Commits everything the installers and templates produced, so the AI step's
  # changes show up on their own in `git diff`.
  if $DRY_RUN; then
    echo "  > git add -A && git commit -m 'chore: scaffold installs and config'"
    return
  fi
  if [[ ! -d .git ]]; then
    warn "no git repository; skipping snapshot"
    return
  fi
  git check-ignore -q .env || echo '.env*' >> .gitignore
  # Pathspec limits staging to the scaffolded app. Without it, git 2.0+ stages
  # the entire worktree, which commits unrelated changes when the script runs
  # inside an existing repository.
  git add -A .
  git commit -q -m "chore: scaffold installs and config" || warn "snapshot commit failed; continuing"
}

# Intent, not code: the model reads the installed packages to decide how.
ai_prompt() {
  cat <<'EOL'
You are wiring authentication into a freshly scaffolded Next.js project. This is
an unattended run: nobody can answer questions, so do not ask any and do not stop
to present a plan. Make the changes, verify them, and finish.

The installed package versions are the source of truth, not your memory. Library
APIs in this stack change between releases. Before writing an import, read the
installed type definitions under node_modules (better-auth, @better-auth/*, next)
and confirm the export exists. If the project has an AGENTS.md, read it first; it
points at the docs bundled with the installed Next.js.

## What to build

1. `auth.ts` at the project root (the route handler imports it as `@/auth`): a
   Better Auth server instance with
EOL
  case "$PROVIDER" in
    kysely)
      cat <<'EOL'
   - database: a `pg` Pool built from `process.env.DATABASE_URL`, passed directly
     (not the Kysely instance in `lib/db.ts`)
EOL
      ;;
    prisma)
      cat <<'EOL'
   - database: the Prisma adapter. Import the singleton from `lib/prisma.ts` (a
     client generated to `lib/prisma/generated/client`, wired with
     `@prisma/adapter-pg`) and pass it through the Prisma adapter the installed
     better-auth exports; read its types for the exact call shape. The auth
     tables land in `prisma/schema.prisma` later via `pnpm auth:generate`, so do
     not import anything that does not exist yet.
EOL
      ;;
    drizzle)
      cat <<'EOL'
   - database: the Drizzle adapter. Import `db` from `lib/db.ts` (drizzle over
     node-postgres) and the schema namespace from `lib/auth-schema.ts` (an empty
     module until `pnpm auth:generate` fills it), and pass both through the
     Drizzle adapter the installed better-auth exports; read its types for the
     exact call shape.
EOL
      ;;
  esac
  cat <<'EOL'
   - email and password sign-in enabled, with automatic sign-in after sign-up
   - plugins: admin (default role `MEMBER`), API key, anonymous. Some plugins ship
     as separate `@better-auth/<name>` packages instead of the `better-auth/plugins`
     barrel; the API key plugin is installed as `@better-auth/api-key`. Use
     whatever the installed packages actually export.
2. `lib/auth-client.ts`: a Better Auth React client whose client plugins mirror
   the server plugins exactly. Export `authClient`, and destructure and export the
   methods for sign-in, sign-up, sign-out, the session hook, requesting a password
   reset, resetting a password, and verifying an email, using the method names the
   installed client types define.
3. `app/api/auth/[...all]/route.ts`: the App Router handler exposing GET and POST
   for the auth instance.
4. `eslint.config.mjs`: `pnpm lint` must report zero errors and zero warnings.
   Fix failures in generated or vendored files with narrow per-file override
   blocks appended as the LAST entries of the config array (flat config is
   last-match-wins; an override placed before the Next presets does nothing).
   Expected cases: a CommonJS tooling config the lint rules reject (under
   graphile-migrate that is `.gmrc.js`, which must use `require()`), and shadcn
   files in `components/ui/**` and `hooks/**`, which are vendored and may trip
   react-hooks rules. Turn off only the rules that actually fire, only for
   those files.

## Do not

- Add, remove, upgrade or downgrade any package, or run `pnpm add`,
  `pnpm install`, `pnpm update` or `pnpm dlx`.
EOL
  case "$PROVIDER" in
    kysely)
      cat <<'EOL'
- Edit `components/ui/**`, `hooks/**`, `lib/db.ts`, `lib/db-types.ts`,
  `.gmrc.js`, `.env`, `docker/**` or `package.json`.
EOL
      ;;
    prisma)
      cat <<'EOL'
- Edit `components/ui/**`, `hooks/**`, `lib/prisma.ts`, `prisma/schema.prisma`,
  `prisma.config.ts`, `.env`, `docker/**` or `package.json`.
EOL
      ;;
    drizzle)
      cat <<'EOL'
- Edit `components/ui/**`, `hooks/**`, `lib/db.ts`, `drizzle.config.ts`,
  `lib/auth-schema.ts`, `.env`, `docker/**` or `package.json`.
EOL
      ;;
  esac
  cat <<'EOL'
- Disable a lint rule project-wide or add broad `ignores`.
- Start a dev server or a database.

## Done means

These pass, in this order: `pnpm typecheck`, `pnpm lint`, `pnpm build`. If one
fails, fix the cause in the files you own and re-run. End with a short list of
the files you changed.
EOL
}

step_wire_auth() {
  step "Wire Better Auth with opencode ($AI_MODEL)"

  # Deny every shell command except the checks the prompt asks for. --auto
  # approves anything not denied, so this list is the guardrail. doom_loop
  # defaults to "ask", which --auto would approve.
  local permission='{"bash":{"*":"deny","pnpm typecheck*":"allow","pnpm lint*":"allow","pnpm build*":"allow","pnpm exec *":"allow","ls*":"allow"},"external_directory":"deny","doom_loop":"deny"}'

  if $DRY_RUN; then
    echo "  > opencode run --auto -m $AI_MODEL --title 'nnx: wire $APP_NAME' <prompt>"
    return
  fi

  # OPENCODE_DISABLE_CLAUDE_CODE keeps ~/.claude/CLAUDE.md out of the run.
  OPENCODE_DISABLE_CLAUDE_CODE=1 OPENCODE_PERMISSION="$permission" \
    opencode run --auto -m "$AI_MODEL" --title "nnx: wire $APP_NAME" "$(ai_prompt)" </dev/null &
  local pid=$!

  # opencode run has no turn or spend limit, so cap the wall-clock time.
  local waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [[ $waited -ge $AI_TIMEOUT ]]; then
      warn "opencode still running after ${AI_TIMEOUT}s; stopping it"
      kill "$pid" 2>/dev/null || true
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  # opencode's exit code isn't documented; the gate below is the real check.
  wait "$pid" || true
}

step_verify() {
  step "Verify: typecheck, lint, build"
  if ! { run_cmd pnpm typecheck && run_cmd pnpm lint && run_cmd pnpm build; }; then
    die "verification failed. Review what opencode changed with: cd $APP_NAME && git diff"
  fi
}

# --- Parse arguments --------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preset)
      [[ -n "${2:-}" && "${2:-}" != --* ]] || die "--preset needs a code"
      PRESET="$2"
      shift 2
      ;;
    --preset=*)
      PRESET="${1#--preset=}"
      shift
      ;;
    --provider)
      [[ -n "${2:-}" && "${2:-}" != --* ]] || die "--provider needs a value"
      PROVIDER="$2"
      shift 2
      ;;
    --provider=*)
      PROVIDER="${1#--provider=}"
      shift
      ;;
    --no-ai)
      NO_AI=true
      shift
      ;;
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

case "$PROVIDER" in
  kysely | prisma | drizzle) ;;
  *) die "--provider must be kysely, prisma or drizzle (got '$PROVIDER')" ;;
esac

# --- Execute ----------------------------------------------------------------

check_prereqs
step_create_app

run_cmd cd "$APP_NAME" || die "Failed to cd into $APP_NAME"

step_add_package_scripts
step_pin_toolchain
step_install_dev_deps
step_install_deps
step_init_shadcn
step_create_dirs
step_generate_env
step_generate_docker_compose
step_generate_db_files
step_snapshot

if $NO_AI; then
  cat <<EOF

Skipped the opencode step (--no-ai). Still to write by hand:
  auth.ts, lib/auth-client.ts, app/api/auth/[...all]/route.ts,
  and ESLint overrides for the tooling config and the shadcn files (pnpm lint
  fails until then).
EOF
else
  step_wire_auth
  step_verify
fi

cat <<EOF

Done! Next steps:

  cd $APP_NAME

  # 1. Start Postgres, Redis, and Mailpit (waits until healthy)
  pnpm docker
EOF

if [[ "$PROVIDER" == kysely ]]; then
  cat <<'EOL'

  # 2. Generate the Better Auth schema into migrations/current.sql
  #    (needs the database running — the pg adapter introspects it)
  pnpm auth:generate

  # 3. Make it re-runnable: graphile-migrate re-executes current.sql on every
  #    change and again at commit, and plain `create table` fails the second time
  perl -i -pe 's/^create ((?:unique )?index|table) /create $1 if not exists /' migrations/current.sql

  # 4. Apply the migration, then generate Kysely types from the database
  pnpm db:watch --once
  pnpm db:codegen

  # 5. Freeze the auth schema as migration 000001, then start the dev server
  pnpm db:commit
  pnpm dev
EOL
elif [[ "$PROVIDER" == prisma ]]; then
  cat <<'EOL'

  # 2. Add the Better Auth tables to prisma/schema.prisma
  #    (needs the database running — the CLI checks the schema against it)
  pnpm auth:generate

  # 3. Create the database and apply the migration
  pnpm db:migrate

  # 4. Start the dev server
  pnpm dev
EOL
else
  cat <<'EOL'

  # 2. Generate the Better Auth drizzle schema into lib/auth-schema.ts
  pnpm auth:generate

  # 3. Generate and apply the migration
  pnpm db:generate
  pnpm db:migrate

  # 4. Start the dev server
  pnpm dev
EOL
fi

cat <<'EOL'

Other docker scripts: pnpm docker:ps, docker:logs, docker:stop, docker:down.
EOL
