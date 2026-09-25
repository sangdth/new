#!/bin/bash

# ============================================================================
# new-next.sh — Scaffold a new Next.js project with opinionated defaults
# ============================================================================

set -euo pipefail

# --- Defaults ---------------------------------------------------------------

VERSION="4.0.0"
APP_NAME=""
PRESET="b1oVxsfY"
DRY_RUN=false
NO_AI=false
STEP_NUM=0

# Headless opencode run that writes the version-sensitive auth code.
AI_MODEL="${NNX_MODEL:-opencode-go/deepseek-v4-pro}"
AI_TIMEOUT="${NNX_AI_TIMEOUT:-1000}"

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
  --preset <code>  shadcn preset code from the theme builder (default: $PRESET)
  --no-ai          Skip the opencode step that writes the auth code
  --dry-run        Print what would be executed without running anything
  -v, --version    Show version
  --help           Show this help message

Environment:
  NNX_MODEL        opencode model (default: $AI_MODEL)
  NNX_AI_TIMEOUT   Seconds before the opencode step is killed (default: $AI_TIMEOUT)

Examples:
  $PROG my-app
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

check_prereqs() {
  command -v pnpm >/dev/null 2>&1 || die "pnpm not found (npm i -g pnpm, or corepack enable)"
  command -v docker >/dev/null 2>&1 || warn "docker not found; you'll need it for the post-setup steps"

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
  # A preset carries the whole design system and can only be applied at init.
  run_cmd pnpm dlx shadcn@latest init --preset "$PRESET" --template next --pointer
  run_cmd pnpm dlx shadcn@latest add --all
}

step_create_dirs() {
  step "Create directories"
  run_cmd mkdir -p \
    migrations/committed \
    docker \
    lib
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

step_add_package_scripts() {
  step "Add package.json scripts"
  # Every compose call needs --env-file .env; without it POSTGRES_PASSWORD
  # silently interpolates to an empty string, so the docker:* scripts carry it.
  run_cmd npm pkg set \
    "scripts.typecheck=tsc --noEmit" \
    "scripts.db:watch=graphile-migrate watch" \
    "scripts.db:migrate=graphile-migrate migrate" \
    "scripts.db:commit=graphile-migrate commit" \
    "scripts.db:reset=graphile-migrate reset" \
    "scripts.db:codegen=kysely-codegen --dialect postgres --exclude-pattern graphile_migrate.* --out-file lib/db-types.ts" \
    "scripts.auth:generate=pnpm dlx @better-auth/cli@latest generate --yes --output migrations/current.sql" \
    "scripts.docker=docker compose -f docker/compose.dev.yml --env-file .env up -d --wait" \
    "scripts.docker:stop=docker compose -f docker/compose.dev.yml --env-file .env stop" \
    "scripts.docker:down=docker compose -f docker/compose.dev.yml --env-file .env down" \
    "scripts.docker:ps=docker compose -f docker/compose.dev.yml --env-file .env ps -a" \
    "scripts.docker:logs=docker compose -f docker/compose.dev.yml --env-file .env logs -f"
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
  git add -A
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
   - database: a `pg` Pool built from `process.env.DATABASE_URL`, passed directly
     (not the Kysely instance in `lib/db.ts`)
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
   Expected cases: `.gmrc.js` must use `require()` because graphile-migrate loads
   it as CommonJS; shadcn files in `components/ui/**` and `hooks/**` are vendored
   and may trip react-hooks rules. Turn off only the rules that actually fire,
   only for those files.

## Do not

- Add, remove, upgrade or downgrade any package, or run `pnpm add`,
  `pnpm install`, `pnpm update` or `pnpm dlx`.
- Edit `components/ui/**`, `hooks/**`, `lib/db.ts`, `lib/db-types.ts`,
  `.gmrc.js`, `.env`, `docker/**` or `package.json`.
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
    sleep 5
    waited=$((waited + 5))
  done
  # opencode's exit code isn't documented; the gate below is the real check.
  wait "$pid" || true
}

step_verify() {
  step "Verify: typecheck, lint, build"
  if $DRY_RUN; then
    echo "  > pnpm typecheck && pnpm lint && pnpm build"
    return
  fi
  if ! { pnpm typecheck && pnpm lint && pnpm build; }; then
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

# --- Execute ----------------------------------------------------------------

check_prereqs
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
step_add_package_scripts
step_snapshot

if $NO_AI; then
  cat <<EOF

Skipped the opencode step (--no-ai). Still to write by hand:
  auth.ts, lib/auth-client.ts, app/api/auth/[...all]/route.ts,
  and ESLint overrides for .gmrc.js and the shadcn files (pnpm lint fails until then).
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

  # 2. Generate the Better Auth schema into migrations/current.sql
  #    (needs the database running — the pg adapter introspects it)
  pnpm auth:generate

  # 3. Make it re-runnable: graphile-migrate re-executes current.sql on every
  #    change and again at commit, and plain \`create table\` fails the second time
  perl -i -pe 's/^create ((?:unique )?index|table) /create \$1 if not exists /' migrations/current.sql

  # 4. Apply the migration, then generate Kysely types from the database
  pnpm db:watch --once
  pnpm db:codegen

  # 5. Freeze the auth schema as migration 000001, then start the dev server
  pnpm db:commit
  pnpm dev

Other docker scripts: pnpm docker:ps, docker:logs, docker:stop, docker:down.
EOF
