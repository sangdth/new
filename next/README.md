# new-next.sh — Next.js Scaffolding Script

Scaffolds a Next.js project with App Router, TypeScript, Tailwind, shadcn/ui, Kysely + graphile-migrate, Better Auth, the Vercel AI SDK, and Jotai — plus a local Docker stack (Postgres, Redis, Mailpit).

> Installation and symlink setup live in the [root README](../README.md#installation).

## Usage

```bash
./new-next.sh [flags] <app-name>   # from this directory
nnx [flags] <app-name>             # from anywhere, if symlinked
```

The script creates the project as a subdirectory of your **current working
directory**, not of the repo — so `cd` to wherever you want the project to live
first. Help and version output adapt to the name you invoked it under.

### Flags

| Flag              | Description                                                      |
| ----------------- | ---------------------------------------------------------------- |
| `--preset <code>` | shadcn preset code from the theme builder (default: `b1oVxsfY`)  |
| `--no-ai`         | Skip the opencode step that writes the auth code                 |
| `--dry-run`       | Print what would be executed without running anything            |
| `-v`, `--version` | Show version                                                     |
| `--help`          | Show help message                                                |

| Env var          | Default                        | Purpose                           |
| ---------------- | ------------------------------ | --------------------------------- |
| `NNX_MODEL`      | `opencode-go/deepseek-v4-pro`  | Model for the opencode step       |
| `NNX_AI_TIMEOUT` | `900`                          | Seconds before opencode is killed |

The opencode step needs a working [opencode](https://opencode.ai) install and a
provider for `NNX_MODEL` (the default uses an OpenCode Go subscription). If
`opencode --version` fails, the script warns and continues as `--no-ai`.

### Examples

```bash
./new-next.sh my-nextjs-app
./new-next.sh --preset b1f3nwcmmG my-nextjs-app
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

Whatever version `create-next-app` installs is kept as-is. The script used to pin
Next backwards afterwards; see the note under Core Dependencies for why it no
longer does.

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
better-auth           # Authentication library
@better-auth/api-key  # apiKey plugin (ships separately from the barrel)
date-fns              # Date utility library
dotenv                # Loads .env (used by .gmrc.js)
jotai                 # State management
kysely                # Type-safe SQL query builder
pg                    # PostgreSQL client
```

> [!NOTE]
> Nothing is pinned as of v3.0.0. The old `next` pin was added when `latest`
> briefly resolved to a preview whose SWC binary was unpublished; that stopped
> being true, but the pin stayed, and because it downgraded Next *after*
> `create-next-app` had generated config for a newer major, it silently broke
> `eslint.config.mjs` and dropped `--turbopack` from the `dev` script. Prefer
> `pnpm create next-app@<version>` if you ever need a specific major, so the
> generated config matches what is installed.
>
> The `apiKey` plugin is not in the `better-auth/plugins` barrel — it ships as
> `@better-auth/api-key`, imported from that package on the server and from
> `@better-auth/api-key/client` on the client. `@better-auth/cli` releases behind
> the runtime; that gap is normal and works. What matters is that
> `migrations/current.sql` ends up with a `create table` for every configured
> plugin.

### Step 3: Initializes shadcn/ui

- Runs `shadcn init --preset b1oVxsfY --template next --pointer` (`--preset`
  swaps the code). A preset carries the whole design system and can only be
  applied at `init`
- Installs **all** available shadcn/ui components

### Step 4: Sets Up Project Structure

Creates necessary directories:

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

### Step 7: Adds package.json Scripts

Adds via `npm pkg set`:

- `typecheck`
- `db:watch`, `db:migrate`, `db:commit`, `db:reset`
- `db:codegen` (excludes graphile-migrate's own tables from the `DB` type)
- `auth:generate`
- `docker`, `docker:stop`, `docker:down`, `docker:ps`, `docker:logs`. Every
  compose call needs `--env-file .env`; without it `POSTGRES_PASSWORD` silently
  becomes empty, so these scripts carry the flag

### Step 8: Commits a Snapshot

Commits everything so far, so the next step's changes show up on their own in
`git diff`. Makes sure `.env` is git-ignored first.

### Step 9: Wires Better Auth with opencode

Runs `opencode run --auto` headlessly with a prompt that describes **what** to
build, not the code. The model reads the installed packages' types, so the code
follows whatever versions got installed instead of a template that goes stale.
It writes:

- `auth.ts`: Better Auth on a raw `pg.Pool`, email/password with auto sign-in,
  admin (default role `MEMBER`), API key and anonymous plugins
- `lib/auth-client.ts`: React client with matching plugins and exported hooks
- `app/api/auth/[...all]/route.ts`: the route handler
- ESLint override blocks for `.gmrc.js` and the vendored shadcn files

Guardrails: all shell commands except `pnpm typecheck`/`lint`/`build`/`exec`
and `ls` are denied, `~/.claude/CLAUDE.md` is not loaded, and the run is killed
after `NNX_AI_TIMEOUT` seconds.

### Step 10: Verifies

Runs `pnpm typecheck && pnpm lint && pnpm build` itself and exits non-zero if any
fail. Review what opencode changed with `git diff`.

> Neither the Better Auth schema nor the Kysely types are generated at scaffold time — both need a **live database** (the Better Auth `pg` adapter introspects the DB to diff the schema, and `kysely-codegen` reads it). They run as post-setup steps once Postgres is up (`pnpm auth:generate`, then `pnpm db:codegen`).

## Post-Setup Steps

After the script completes:

1. **Start the local services** (Postgres, Redis, Mailpit). This blocks until healthy

   ```bash
   cd <app-name>
   pnpm docker
   ```

2. **Generate the Better Auth schema** into `migrations/current.sql` (needs the DB running)

   ```bash
   pnpm auth:generate
   ```

3. **Make the migration re-runnable**. graphile-migrate re-executes
   `current.sql` on every change and again at commit, and the CLI's plain
   `create table` fails the second time with `42P07`

   ```bash
   perl -i -pe 's/^create ((?:unique )?index|table) /create $1 if not exists /' migrations/current.sql
   ```

4. **Apply the migration** and **generate Kysely types** from the database

   ```bash
   pnpm db:watch --once
   pnpm db:codegen
   ```

5. **Freeze the auth schema** as `migrations/committed/000001.sql`. Apply committed
   migrations in other environments with `pnpm db:migrate`

   ```bash
   pnpm db:commit
   ```

6. **Update environment variables** (if needed)
   - Add an OpenAI API key if using AI features
   - Update database credentials if not using the defaults

7. **Start the development server**

   ```bash
   pnpm dev
   ```

## Feature List

After running the script, your project includes:

### Core Framework

- ✅ **Next.js** (whatever `create-next-app` installs) - React framework with App Router
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

- **Change the shadcn design system**: pass `--preset <code>`
- **Skip specific shadcn components**: Replace `--all` with specific component names in `step_init_shadcn`
- **Add/remove dependencies**: Edit the `pnpm add` lists in `step_install_deps` / `step_install_dev_deps`
- **Customize Better Auth**: Edit the `ai_prompt` heredoc in the script (describe what you want, not the code), or edit the generated `auth.ts` and `lib/auth-client.ts` afterwards
- **Change the database schema**: Edit `migrations/current.sql`, run `pnpm db:watch`, then `pnpm db:codegen`
- **Pin a version**: There are no version variables any more. Prefer not to add one — the last set of pins caused more breakage than they prevented (see the note in Step 2). If a `latest` genuinely breaks, verify it against the registry rather than assuming, and pin the narrowest thing that fixes it

## Troubleshooting

- **shadcn init fails**: Ensure you have a compatible Node.js version
- **`pnpm db:codegen` fails**: Ensure Postgres is running and migrations are applied (`docker compose ... up -d`, then `pnpm db:watch --once`); `kysely-codegen` needs a live database
- **graphile-migrate can't connect**: Check `DATABASE_URL` / `SHADOW_DATABASE_URL` / `ROOT_DATABASE_URL` in `.env` — all three must be **distinct** or graphile-migrate refuses to start
- **`pnpm build` fails in `components/ui/calendar.tsx`**: `shadcn add --all` can pull a `react-day-picker` major (v10) the generated component isn't written for. Unrelated to the DB/auth setup — SWC compilation itself succeeds

See the [root README](../README.md#troubleshooting) for issues common to both scripts.
