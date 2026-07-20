# new-next.sh — Next.js Scaffolding Script

Scaffolds a Next.js project with App Router, TypeScript, Tailwind, shadcn/ui, Kysely + graphile-migrate, Better Auth, the Vercel AI SDK, and Jotai — plus a local Docker stack (Postgres, Redis, Mailpit).

> Installation and symlink setup live in the [root README](../README.md#installation).

## Usage

```bash
./new-next.sh [flags] <app-name>
```

### Flags

| Flag | Description |
|------|-------------|
| `--dry-run` | Print what would be executed without running anything |
| `-v`, `--version` | Show version |
| `--help` | Show help message |

### Examples

```bash
./new-next.sh my-nextjs-app
./new-next.sh --dry-run my-nextjs-app
```

## Setup Process Overview

### Step 1: Creates Next.js App

Scaffolds a new Next.js project with:

- TypeScript enabled
- ESLint configured
- Tailwind CSS included
- App Router (not Pages Router)
- Turbopack enabled
- No import alias
- No React Compiler
- No src directory
- Uses pnpm as package manager

Then **pins Next.js to a stable release** (`next` + `eslint-config-next` to `15.5.19`). `create-next-app` installs `next@latest`, which currently resolves to a preview build (e.g. `16.3.0-preview.0`) whose native SWC binary is not published — so `pnpm dev`/`build` fail trying to download it (404). The pin avoids that until Next 16 is GA.

### Step 2: Installs Dependencies

**Dev Dependencies:**

```bash
concurrently      # Run multiple commands concurrently
rimraf            # Cross-platform rm -rf
graphile-migrate  # SQL migration tool
kysely-codegen    # Generate Kysely types from the database
@types/pg         # TypeScript types for the pg driver
```

**Core Dependencies:**

```bash
@ai-sdk/react         # AI SDK for React
@ai-sdk/openai        # OpenAI provider for AI SDK
@better-fetch/fetch   # Enhanced fetch utility
ai                    # Vercel AI SDK
better-auth@1.4.22    # Authentication library (pinned: see note below)
date-fns              # Date utility library
dotenv                # Loads .env (used by .gmrc.js)
jotai                 # State management
kysely@^0.28.5        # Type-safe SQL query builder (pinned to better-auth's peer)
pg                    # PostgreSQL client
```

> [!NOTE]
> `better-auth` is pinned to the `1.4` line. Its `latest` (`1.6.x`) dropped the
> `apiKey` plugin from the barrel export and has no matching `@better-auth/cli`
> release yet, which breaks `auth.ts` and schema generation. `kysely` is held on
> `0.28.x` to satisfy better-auth 1.4's peer range (`^0.28.5`).

### Step 3: Initializes shadcn/ui

- Runs `shadcn init` with default configuration (neutral base color)
- Installs **all** available shadcn/ui components

### Step 4: Sets Up Project Structure

Creates necessary directories:

- `app/api/auth/[...all]/`
- `migrations/committed/` (graphile-migrate)
- `docker/`
- `lib/`

### Step 5: Configures Environment Variables

Creates `.env` with:

- Better Auth configuration (secret, URL, telemetry settings)
- PostgreSQL database URL, plus `SHADOW_DATABASE_URL` and `ROOT_DATABASE_URL` for graphile-migrate
- SMTP settings for Mailpit (local email testing)

### Step 6: Configures the Database (Kysely + graphile-migrate)

Creates `lib/db.ts` with:

- Kysely client using the `pg` `PostgresDialect`
- Global instance (development-optimized)
- Connection string validation

Creates `lib/db-types.ts` with:

- A placeholder `DB` type so the project type-checks before the first codegen run
- Overwritten by `pnpm db:codegen` once migrations are applied

Creates `.gmrc.js` (graphile-migrate config) that:

- Loads `.env` via `require('dotenv/config')` (graphile-migrate does not auto-load it)
- Reads `DATABASE_URL`, `SHADOW_DATABASE_URL`, and `ROOT_DATABASE_URL` from the environment

### Step 7: Configures Better Auth

Creates `lib/auth-client.ts` with:

- Client-side auth hooks (signIn, signUp, signOut, etc.)
- Admin, API key, and anonymous plugins enabled

Creates `auth.ts` with:

- Server-side auth configuration
- Connects to PostgreSQL via a raw `pg.Pool` (Better Auth uses Kysely internally)
- Email/password authentication enabled
- Auto sign-in after registration
- Admin, API key, and anonymous plugins

Creates `api/auth/[...all]/route.ts`:

- Next.js API route handler for Better Auth

### Step 8: Adds package.json Scripts

- Adds `db:watch`, `db:migrate`, `db:commit`, `db:reset`, `db:codegen`, and `auth:generate` scripts to `package.json` via `npm pkg set`

> Neither the Better Auth schema nor the Kysely types are generated at scaffold time — both need a **live database** (the Better Auth `pg` adapter introspects the DB to diff the schema, and `kysely-codegen` reads it). They run as post-setup steps once Postgres is up (`pnpm auth:generate`, then `pnpm db:codegen`).

## Post-Setup Steps

After the script completes:

1. **Start the local services** (Postgres, Redis, Mailpit) — `--wait` blocks until healthy

   ```bash
   cd <app-name>
   docker compose -f docker/compose.dev.yml --env-file .env up -d --wait
   ```

2. **Generate the Better Auth schema** into `migrations/current.sql` (needs the DB running)

   ```bash
   pnpm auth:generate
   ```

3. **Apply the migration** to your dev database

   ```bash
   pnpm db:watch --once
   ```

   When the schema is stable, freeze it as a committed migration with `pnpm db:commit`,
   then apply committed migrations in other environments with `pnpm db:migrate`.

4. **Generate Kysely types** from the database

   ```bash
   pnpm db:codegen
   ```

5. **Update environment variables** (if needed)
   - Add an OpenAI API key if using AI features
   - Update database credentials if not using the defaults

6. **Start the development server**

   ```bash
   pnpm dev
   ```

## Feature List

After running the script, your project includes:

### Core Framework

- ✅ **Next.js** (`15.5.x`, pinned stable) - React framework with App Router
- ✅ **TypeScript** - Type-safe development
- ✅ **Turbopack** - Fast bundler
- ✅ **ESLint** - Code linting

### Styling & UI

- ✅ **Tailwind CSS** - Utility-first CSS framework
- ✅ **shadcn/ui** - All components pre-installed
  - Accordion, Alert, Avatar, Badge, Button, Calendar, Card, Checkbox, Collapsible, Command, Context Menu, Dialog, Drawer, Dropdown Menu, Form, Input, Label, Menubar, Navigation Menu, Pagination, Popover, Progress, Radio Group, Scroll Area, Select, Separator, Sheet, Skeleton, Slider, Switch, Table, Tabs, Textarea, Toast, Toggle, Tooltip, and more

### Database & Migrations

- ✅ **Kysely** - Type-safe SQL query builder
- ✅ **PostgreSQL** - Database client (pg)
- ✅ **kysely-codegen** - Generates `DB` types from the live database
- ✅ **graphile-migrate** - SQL-first migrations (`.gmrc.js`, `migrations/`)
- ✅ Pre-configured Kysely client with a development-optimized global instance

### Authentication

- ✅ **Better Auth** - Complete auth solution
  - Email/password authentication
  - Admin plugin (role-based access)
  - API key authentication
  - Anonymous authentication
  - Auto sign-in after registration
- ✅ Pre-configured client and server setup
- ✅ Next.js API routes ready

### AI & LLM

- ✅ **Vercel AI SDK** - AI/LLM integration
- ✅ **@ai-sdk/react** - React hooks for AI
- ✅ **@ai-sdk/openai** - OpenAI provider

### State Management & Utilities

- ✅ **Jotai** - Atomic state management
- ✅ **date-fns** - Date manipulation
- ✅ **@better-fetch/fetch** - Enhanced fetch utility

### Developer Tools

- ✅ **concurrently** - Run multiple scripts
- ✅ **rimraf** - Cross-platform file deletion
- ✅ Pre-configured environment variables
- ✅ SMTP config for local email testing (Mailpit)

## Generated Project Structure

```text
<app-name>/
├── app/
│   └── api/
│       └── auth/
│           └── [...all]/
│               └── route.ts       # Auth API handler
├── docker/
│   └── compose.dev.yml            # Docker Compose (Postgres, Redis, Mailpit)
├── lib/
│   ├── db.ts                      # Kysely client
│   ├── db-types.ts                # Generated Kysely types (kysely-codegen)
│   └── auth-client.ts             # Auth client hooks
├── migrations/
│   ├── current.sql                # Active migration (Better Auth schema)
│   └── committed/                 # Committed migrations
├── auth.ts                        # Auth server config (pg Pool)
├── .gmrc.js                       # graphile-migrate config
└── .env                           # Environment variables
```

## Customization

- **Preview without creating anything**: `./new-next.sh --dry-run my-app`

To modify the default setup, edit the script:

- **Change shadcn base color**: Edit the `step_init_shadcn` function to add `--base-color` flag
- **Skip specific shadcn components**: Replace `--all` with specific component names in `step_init_shadcn`
- **Add/remove dependencies**: Edit the `pnpm add` lists in `step_install_deps` / `step_install_dev_deps`
- **Customize Better Auth**: Edit the generated `auth.ts` and `lib/auth-client.ts` files
- **Change the database schema**: Edit `migrations/current.sql`, run `pnpm db:watch`, then `pnpm db:codegen`
- **Change pinned versions**: Edit `NEXT_VERSION` / `BETTER_AUTH_VERSION` at the top of the script (check the upstream changelog first — see the note in Step 2)

## Troubleshooting

- **shadcn init fails**: Ensure you have a compatible Node.js version
- **`pnpm db:codegen` fails**: Ensure Postgres is running and migrations are applied (`docker compose ... up -d`, then `pnpm db:watch --once`); `kysely-codegen` needs a live database
- **graphile-migrate can't connect**: Check `DATABASE_URL` / `SHADOW_DATABASE_URL` / `ROOT_DATABASE_URL` in `.env` — all three must be **distinct** or graphile-migrate refuses to start
- **`pnpm build` fails in `components/ui/calendar.tsx`**: `shadcn add --all` can pull a `react-day-picker` major (v10) the generated component isn't written for. Unrelated to the DB/auth setup — SWC compilation itself succeeds

See the [root README](../README.md#troubleshooting) for issues common to both scripts.
