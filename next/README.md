# new-next.sh — Next.js Scaffolding Script

Scaffolds a Next.js project with App Router, TypeScript, Tailwind, shadcn/ui, Better Auth, the Vercel AI SDK, and Jotai — plus a local Docker stack (Postgres, Redis, Mailpit). Four choices shape the project — ORM (Kysely + graphile-migrate, Prisma or Drizzle), the AI client that writes the auth code (opencode, Claude Code or Codex), linter (Biome or ESLint) and shadcn preset — and are saved once in a [config file](#config-file). `--auth-saas` swaps the default auth plugins for a multi-tenant SaaS set.

> Installation and symlink setup live in the [root README](../README.md#installation).

## Usage

```bash
./new-next.sh [flags] <app-name>   # from this directory
nnx [flags] <app-name>             # from anywhere, if symlinked
nnx --setup                        # answer the config questions again
```

The script creates the project as a subdirectory of your **current working
directory**, not of the repo — so `cd` to wherever you want the project to live
first. Help and version output adapt to the name you invoked it under.

### Config file

`${XDG_CONFIG_HOME:-~/.config}/new/config.yaml` holds your defaults:

```yaml
orm: kysely             # kysely | prisma | drizzle
ai-client: opencode     # opencode | claude | codex
linter: biome           # biome | eslint
shadcn-preset: b0       # shadcn preset code
```

- **First run:** if the file is missing and the script runs in a terminal, it
  asks the four questions, saves the answers and carries on. The preset question
  takes a bare code or a pasted `--preset <code>`; Enter keeps `b0` (shadcn's
  stock `base-nova` / `neutral`).
- **Later runs:** the file is read and nothing is asked. Edit it, or run
  `--setup`, to change it.
- **No terminal** (piped, CI) **or `--dry-run`:** nothing is asked or written;
  the built-in defaults above apply.

Each value is picked as: flag, else config file, else built-in default. Flags
apply to one run and never change the file. A bad value or unknown key stops the
script with the file and line number. The keys `provider`, `ai` and `preset`
stop it with the new name to use (`orm`, `ai-client`, `shadcn-preset`).

### Flags

| Flag                     | Description                                         |
| ------------------------ | --------------------------------------------------- |
| `--orm <name>`           | Database/auth layer: `kysely`, `prisma`, `drizzle`  |
| `--ai-client <cli>`      | AI CLI: `opencode`, `claude`, `codex`               |
| `--linter <name>`        | `biome` or `eslint`                                 |
| `--shadcn-preset <code>` | shadcn preset code from the theme builder           |
| `--auth-saas`            | Multi-tenant auth plugins; see Authentication       |
| `--setup`                | Ask the config questions again and rewrite the file |
| `--no-ai`                | Skip the AI step that writes the auth code          |
| `--dry-run`              | Print what would be executed without running        |
| `-v`, `--version`        | Show version                                        |
| `--help`                 | Show help message                                   |

`--auth-saas` is a switch for one run, not a config key. The old flags
`--provider`, `--ai` and `--preset` stop the script with the new name.

| Env var          | Default       | Purpose                             |
| ---------------- | ------------- | ----------------------------------- |
| `NNX_MODEL`      | the CLI's own | Model for the AI CLI                |
| `NNX_AI_TIMEOUT` | `1000`        | Seconds before the AI CLI is killed |
| `NNX_NODE`       | `lts`         | Node line: `lts` or `latest`        |

`NNX_MODEL` defaults to `openrouter/deepseek/deepseek-v4-pro` for opencode (needs
an OpenRouter key in `opencode auth`) and to the CLI's own default for `claude`
and `codex`. The same model on the OpenCode Go route
(`opencode-go/deepseek-v4-pro`) kept stopping runs with "blocked by the
provider's content filter". The
chosen CLI must be installed and logged in; if `<cli> --version` fails, the
script warns and continues as `--no-ai`.

### Examples

```bash
./new-next.sh my-nextjs-app
./new-next.sh --orm prisma --ai-client claude my-nextjs-app
./new-next.sh --auth-saas my-nextjs-app
./new-next.sh --shadcn-preset b1f3nwcmmG my-nextjs-app
./new-next.sh --dry-run my-nextjs-app
```

## Setup Process Overview

### Step 1: Creates Next.js App

Scaffolds a new Next.js project with:

- TypeScript enabled
- Biome or ESLint, from `linter` (`--biome` / `--eslint`)
- Tailwind CSS included
- App Router (not Pages Router)
- Turbopack enabled
- No import alias
- No React Compiler
- No src directory
- Uses pnpm as package manager
- Skips its own install (`--skip-install`; see Step 1b)

Whatever version `create-next-app` installs is kept as-is. The script used to pin
Next backwards afterwards; see the note under Core Dependencies for why it no
longer does.

### Step 1b: Pins Node and pnpm

Before installing anything else, the script looks up the newest Node release on
the `NNX_NODE` line (`lts` by default, or `latest`) and the newest pnpm, and
writes both into `package.json`:

```json
"devEngines": {
  "runtime":        { "name": "node", "version": "<x.y.z>", "onFail": "download" },
  "packageManager": { "name": "pnpm", "version": "<x.y.z>", "onFail": "download" }
}
```

pnpm downloads both on first use and runs every later step, and every `pnpm`
command in the project, on them, whatever Node and pnpm are installed globally.
Only `create-next-app` itself runs on your global versions, which is why it skips
its install: a lockfile resolved by an older pnpm fails a newer one's checks.

The step also removes the `packageManager` field `create-next-app` writes
(Corepack would follow it instead of `devEngines`) and rewrites
`pnpm-workspace.yaml` in pnpm 11+'s format. pnpm 11+ fails the install on any
dependency build script it hasn't been told to allow or deny in `allowBuilds`,
and skips releases younger than a day (`minimumReleaseAge`). The same Node version
goes into `.nvmrc`, so a shell hook that reads it (nvm's, or fnm's
`--use-on-cd`) switches the shell's `node` to match.

The versions are fixed once the project exists. To move a project forward, edit
`devEngines` and `.nvmrc`.

> [!NOTE]
> npm checks `devEngines.runtime` against its own Node and refuses to run
> (`EBADDEVENGINES`) on a mismatch, so `npm pkg set` and other npm commands in
> the project only work with the matching Node active. Use `pnpm pkg set`.

### Step 2: Installs Dependencies

**Dev Dependencies:**

```bash
concurrently      # Run multiple commands concurrently
rimraf            # Cross-platform rm -rf
@types/pg         # TypeScript types for the pg driver
```

Plus the migration tooling the chosen `--orm` needs: `graphile-migrate`
and `kysely-codegen` (kysely), `prisma@^7` (prisma) or `drizzle-kit` (drizzle).
The Prisma toolchain is pinned to major 7 because the `prisma` CLI's `latest`
dist-tag is currently an 8.0.0 RC while `@prisma/client`'s is 7.x, and a
mismatched CLI and client cannot work together.

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
> Nothing but the Prisma toolchain (above) is pinned. The old `next` pin was added when `latest`
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
>
> `--auth-saas` installs nothing extra: organization, two-factor and
> multi-session ship inside `better-auth`. The script owns every install; the AI
> step only writes files.

### Step 3: Initializes shadcn/ui

- Runs `shadcn init --preset <preset> --template next --pointer` with the
  configured preset (`b0` by default). A preset carries the whole design system
  and can only be applied at `init`
- Installs **all** available shadcn/ui components

### Step 4: Sets Up Project Structure

Creates necessary directories:

- `docker/`
- `lib/`
- `migrations/committed/` (kysely) or `prisma/` (prisma)

### Step 5: Configures Environment Variables

Creates `.env` with:

- Better Auth configuration (secret, URL, telemetry settings)
- PostgreSQL database URL (the Prisma ORM option uses `127.0.0.1` instead of
  `localhost`, because Prisma's engine resolves `localhost` to `::1` first and
  the Postgres container listens on IPv4 only)
- `SHADOW_DATABASE_URL` and `ROOT_DATABASE_URL` for graphile-migrate (kysely only)
- SMTP settings for Mailpit (local email testing)

### Step 6: Configures the Database (depends on `--orm`)

**kysely (default)** creates `lib/db.ts` with:

- Kysely client using the `pg` `PostgresDialect`
- Global instance (development-optimized)
- Connection string validation

Creates `lib/db-types.ts` with:

- A placeholder `DB` type so the project type-checks before the first codegen run
- Overwritten by `pnpm db:codegen` once migrations are applied

Creates `.gmrc.js` (graphile-migrate config) that:

- Loads `.env` via `require('dotenv/config')` (graphile-migrate does not auto-load it)
- Reads `DATABASE_URL`, `SHADOW_DATABASE_URL`, and `ROOT_DATABASE_URL` from the environment

**prisma** creates:

- `prisma/schema.prisma` with the `prisma-client` generator (client engine,
  output `lib/prisma/generated`) and a datasource with no `url`: Prisma 7 moved
  the connection string out of the schema
- `prisma.config.ts` that reads `DATABASE_URL` through `prisma/config`'s `env()`
- `lib/prisma.ts`, a `PrismaClient` singleton wired through `@prisma/adapter-pg`
- `**/lib/prisma/generated` in `.gitignore`, and one `prisma generate` run so the
  client exists before the auth step type-checks against it

**drizzle** creates:

- `lib/db.ts`, a `drizzle()` client over a `pg` `Pool` (global instance)
- `drizzle.config.ts` pointing at the generated auth schema, migrations in `./drizzle`
- `lib/auth-schema.ts` as an empty module, overwritten by `pnpm auth:generate`

### Step 7: Adds package.json Scripts

Adds via `npm pkg set`. This runs right after `create-next-app`, before the pin
in Step 1b, because npm refuses to edit the file once `devEngines.runtime` names
a Node it isn't running on.

- `typecheck` (`next typegen && tsc --noEmit`; `next typegen` writes the
  `LayoutProps`/`PageProps` route types into the gitignored `.next/`)
- `db:*` scripts for the chosen ORM: `db:watch` / `db:migrate` / `db:commit` /
  `db:reset` / `db:codegen` (kysely), `db:generate` / `db:migrate` / `db:deploy` /
  `db:studio` (prisma), `db:generate` / `db:migrate` / `db:push` / `db:studio` (drizzle)
- `auth:generate` (the Better Auth CLI; it installs `@prisma/client` and
  `better-sqlite3` whatever the ORM is, so its command carries
  `--allow-build` for both — see Troubleshooting)
- `docker`, `docker:stop`, `docker:down`, `docker:ps`, `docker:logs`. Every
  compose call needs `--env-file .env`; without it `POSTGRES_PASSWORD` silently
  becomes empty, so these scripts carry the flag

### Step 8: Configures Biome (`linter: biome` only)

- Turns the linter off for `components/ui/**` in `biome.json` (formatting stays
  on). shadcn's vendored components trip recommended rules — a11y,
  `noArrayIndexKey`, `useExhaustiveDependencies` — and that list changes with
  every shadcn and Biome release
- Runs `biome check --write` once. `pnpm lint` is `biome check`, which also
  fails on formatting: shadcn writes no semicolons and the script's templates use
  single quotes

The Biome version is whatever `create-next-app` installs. Don't bump it to
`latest` on its own: Biome 2.5 also lints SVGs and fails on the stock
`public/*.svg` files.

### Step 9: Commits a Snapshot

Commits everything so far, so the next step's changes show up on their own in
`git diff`. Makes sure `.env` is git-ignored first.

### Step 10: Wires Better Auth with the AI CLI

Runs the configured CLI headlessly with a prompt that describes **what** to
build, not the code. The model reads the installed packages' types, so the code
follows whatever versions got installed instead of a template that goes stale.
It writes:

- `auth.ts`: Better Auth on the ORM's adapter, email/password with auto
  sign-in, admin (Better Auth's default `user`/`admin` roles), API key and
  anonymous plugins. With `--auth-saas`: organization (teams on, invite links
  logged to the console), admin, API keys owned by the organization, two-factor
  and multi-session, and no anonymous
- `lib/auth-client.ts`: React client with matching plugins and exported hooks
  (plus the active-organization hook under `--auth-saas`)
- `app/api/auth/[...all]/route.ts`: the route handler
- ESLint only: override blocks for `.gmrc.js` and the vendored shadcn files

Each CLI gets the narrowest guardrail it supports, and every run is killed after
`NNX_AI_TIMEOUT` seconds:

- **opencode** (`opencode run --auto`): `OPENCODE_PERMISSION` allows the shell
  but denies changing packages (`pnpm add`/`install`/`update`/`remove`/`dlx`,
  `npm`, `npx`, `yarn`) and `git`, and any path outside the project. An allowlist
  cost the model a turn on every `cat`/`echo`/`python` read it tried.
  `~/.claude/CLAUDE.md` is not loaded
- **claude** (`claude -p --permission-mode dontAsk`): every tool not in
  `--allowedTools` is denied — file read/edit/write plus the same `pnpm`
  commands; `--setting-sources project` keeps your `~/.claude` settings and
  `CLAUDE.md` out
- **codex** (`codex exec --sandbox workspace-write`): **weaker** — codex has no
  command allowlist, so it can run any shell command. The sandbox keeps writes
  inside the project; network is on because `pnpm build` downloads the
  `next/font` files. `--ignore-user-config` keeps `~/.codex/config.toml` out

### Step 11: Verifies

Fails if `auth.ts`, `lib/auth-client.ts` or `app/api/auth/[...all]/route.ts` is
missing (typecheck alone passes without them, since nothing imports them yet),
then runs `pnpm typecheck && pnpm lint && pnpm build`. Under Biome it formats
the model's files first.

If any check fails, the AI CLI gets **one** more run with the failing output
appended to the prompt, then the checks run again. A second failure exits
non-zero; review what the model changed with `git diff`.

> Neither the Better Auth schema nor the Kysely types are generated at scaffold time — both need a **live database** (the Better Auth `pg` adapter introspects the DB to diff the schema, and `kysely-codegen` reads it). They run as post-setup steps once Postgres is up (`pnpm auth:generate`, then `pnpm db:codegen`).

## Post-Setup Steps

The script prints the exact sequence for the ORM it scaffolded. After the
script completes:

1. **Start the local services** (Postgres, Redis, Mailpit). This blocks until healthy

   ```bash
   cd <app-name>
   pnpm docker
   ```

Then, **kysely** (default):

2. `pnpm auth:generate` — writes the Better Auth schema to `migrations/current.sql`
3. `perl -i -pe 's/^create ((?:unique )?index|table) /create $1 if not exists /' migrations/current.sql`
   — graphile-migrate re-executes `current.sql` on every change and again at
   commit, and the CLI's plain `create table` fails the second time with `42P07`
4. `pnpm db:watch --once` then `pnpm db:codegen` — apply the migration and read
   the Kysely types back out of the database
5. `pnpm db:commit` — freeze the auth schema as `migrations/committed/000001.sql`.
   Apply committed migrations elsewhere with `pnpm db:migrate`

**prisma**:

2. `pnpm auth:generate` — adds the Better Auth models to `prisma/schema.prisma`
3. `pnpm db:migrate` — creates the database, writes the first migration and
   applies it (`--name init` keeps it non-interactive)
4. `pnpm db:deploy` applies migrations in other environments

**drizzle**:

2. `pnpm auth:generate` — writes the auth tables to `lib/auth-schema.ts`
3. `pnpm db:generate` then `pnpm db:migrate` — write and apply the migration
4. `pnpm db:push` syncs the schema without a migration file when you iterate

Under `--auth-saas`, `auth:generate` also writes `organization`, `member`,
`invitation`, `team`, `teamMember` and `twoFactor`. A missing one means the
Better Auth CLI is behind the runtime; use `@better-auth/cli@beta` in the
`auth:generate` script.

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
- ✅ **Biome** (default) or **ESLint** - Linting; Biome also formats

### Styling & UI

- ✅ **Tailwind CSS** - Utility-first CSS framework
- ✅ **shadcn/ui** - All components pre-installed
  - Accordion, Alert, Avatar, Badge, Button, Calendar, Card, Checkbox, Collapsible, Command, Context Menu, Dialog, Drawer, Dropdown Menu, Form, Input, Label, Menubar, Navigation Menu, Pagination, Popover, Progress, Radio Group, Scroll Area, Select, Separator, Sheet, Skeleton, Slider, Switch, Table, Tabs, Textarea, Toast, Toggle, Tooltip, and more

### Database & Migrations (chosen with `--orm`)

Default, **kysely**:

- ✅ **Kysely** - Type-safe SQL query builder
- ✅ **PostgreSQL** - Database client (pg)
- ✅ **kysely-codegen** - Generates `DB` types from the live database
- ✅ **graphile-migrate** - SQL-first migrations (`.gmrc.js`, `migrations/`)
- ✅ Pre-configured Kysely client with a development-optimized global instance

`--orm prisma`:

- ✅ **Prisma 7** - `prisma-client` generator with the client engine
- ✅ **@prisma/adapter-pg** - driver adapter, so no bundled engine binary
- ✅ `prisma.config.ts` - Prisma 7 reads the connection URL here, not from the schema
- ✅ Pre-configured client singleton in `lib/prisma.ts`

`--orm drizzle`:

- ✅ **drizzle-orm** with the node-postgres driver
- ✅ **drizzle-kit** - `generate`, `migrate`, `push`, `studio`
- ✅ `drizzle.config.ts` pointing at `lib/auth-schema.ts`

### Authentication

- ✅ **Better Auth** - Complete auth solution
  - Email/password authentication
  - Admin plugin (role-based access)
  - API key authentication
  - Anonymous authentication
  - Auto sign-in after registration
- ✅ **`--auth-saas`** - Multi-tenant set instead of the above plugins
  - Organizations with teams, members and invitations
  - Admin plugin
  - API keys owned by the organization
  - Two-factor (TOTP and backup codes)
  - Multi-session (several accounts in one browser)
  - No anonymous users
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
<app-name>/                      # kysely (default); see --orm for the others
├── app/
│   └── api/
│       └── auth/
│           └── [...all]/
│               └── route.ts       # Auth API handler
├── docker/
│   └── compose.dev.yml            # Docker Compose (Postgres, Redis, Mailpit)
├── lib/
│   ├── db.ts                      # Kysely client (drizzle: db client)
│   ├── db-types.ts                # Generated Kysely types (kysely-codegen)
│   └── auth-client.ts             # Auth client hooks
├── migrations/
│   ├── current.sql                # Active migration (Better Auth schema)
│   └── committed/                 # Committed migrations
├── auth.ts                        # Auth server config (pg Pool / adapter)
├── .gmrc.js                       # graphile-migrate config
├── .nvmrc                         # Node version (same as devEngines.runtime)
└── .env                           # Environment variables

# prisma instead of migrations/ and .gmrc.js:
├── prisma/schema.prisma           # Generator, datasource, Better Auth models
├── prisma.config.ts               # Connection URL for the CLI
└── lib/prisma.ts                  # PrismaClient singleton over @prisma/adapter-pg

# drizzle instead of migrations/ and .gmrc.js:
├── drizzle.config.ts              # schema, out dir, connection
└── lib/auth-schema.ts             # Generated by pnpm auth:generate
```

## Customization

- **Preview without creating anything**: `./new-next.sh --dry-run my-app`

To modify the default setup, edit the script:

- **Change the defaults**: `--setup`, or edit `~/.config/new/config.yaml`
- **Change the shadcn design system for one project**: pass `--shadcn-preset <code>`
- **Skip specific shadcn components**: Replace `--all` with specific component names in `step_init_shadcn`
- **Add/remove dependencies**: Edit the `pnpm add` lists in `step_install_deps` / `step_install_dev_deps`
- **Customize Better Auth**: Edit the `ai_prompt` heredoc in the script (describe what you want, not the code), or edit the generated `auth.ts` and `lib/auth-client.ts` afterwards
- **Change the database schema**: Edit `migrations/current.sql`, run `pnpm db:watch`, then `pnpm db:codegen`
- **Pin a version**: There are no version variables any more. Prefer not to add one — the last set of pins caused more breakage than they prevented (see the note in Step 2). If a `latest` genuinely breaks, verify it against the registry rather than assuming, and pin the narrowest thing that fixes it

## Troubleshooting

- **AI step wrote nothing / `response was blocked by the provider's content filter`**:
  the model's provider stopped the run. Verify catches the missing auth files
  and retries once; if it fails again, rerun with another CLI or model
  (`--ai-client claude`, or `NNX_MODEL=...`)
- **Error naming `config.yaml:<line>`**: a value or key in the config file is
  wrong. Fix the line, or delete the file and answer the questions again
- **`pnpm lint` fails on formatting after `shadcn add`** (Biome): new components
  arrive unformatted. Run `pnpm format`
- **shadcn init fails**: Ensure you have a compatible Node.js version
- **`pnpm db:codegen` fails**: Ensure Postgres is running and migrations are applied (`docker compose ... up -d`, then `pnpm db:watch --once`); `kysely-codegen` needs a live database
- **Prisma: `P1001 Can't reach database server`**: the generated `.env` uses `127.0.0.1`, not `localhost`; Prisma's engine resolves `localhost` to `::1` first and the Postgres container publishes IPv4 only. If you switch hosts and hit this, keep the address
- **Prisma: the CLI installs an 8.0.0 RC**: the `prisma` package's `latest` dist-tag points at a release candidate while `@prisma/client`'s is still 7.x. The scaffold pins `prisma@^7`; a mismatched CLI and client cannot work
- **Prisma: `prisma migrate dev` hangs**: it prompts for a migration name when stdin is not a TTY. `pnpm db:migrate` passes `--name init` for that reason
- **`pnpm auth:generate` fails with `ERR_PNPM_IGNORED_BUILDS`**: the Better Auth CLI
  install pulls `@prisma/client` and `better-sqlite3`, and the generated
  `pnpm-workspace.yaml` denies build scripts it was not told about, which pnpm 11+ treats
  as an install error. The generated `auth:generate` script passes
  `--allow-build=@prisma/client --allow-build=better-sqlite3`; if the CLI ever adds
  another native dependency, allow it there too.
- **graphile-migrate can't connect**: Check `DATABASE_URL` / `SHADOW_DATABASE_URL` / `ROOT_DATABASE_URL` in `.env` — all three must be **distinct** or graphile-migrate refuses to start
- **`pnpm build` fails in `components/ui/calendar.tsx`**: `shadcn add --all` can pull a `react-day-picker` major (v10) the generated component isn't written for. Unrelated to the DB/auth setup — SWC compilation itself succeeds

See the [root README](../README.md#troubleshooting) for issues common to both scripts.
