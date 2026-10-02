# new-next.sh — Next.js Scaffolding Script

Scaffolds a Next.js project with App Router, TypeScript, Tailwind, shadcn/ui, Better Auth, the Vercel AI SDK, and Jotai — plus a local Docker stack (Postgres, Redis, Mailpit). The database layer is chosen with `--provider`: Kysely + graphile-migrate (default), Prisma, or Drizzle.

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
| `--provider <db>` | Database/auth layer: `kysely` (default), `prisma` or `drizzle`    |
| `--no-ai`         | Skip the opencode step that writes the auth code                 |
| `--dry-run`       | Print what would be executed without running anything            |
| `-v`, `--version` | Show version                                                     |
| `--help`          | Show help message                                                |

| Env var          | Default                        | Purpose                           |
| ---------------- | ------------------------------ | --------------------------------- |
| `NNX_MODEL`      | `opencode-go/deepseek-v4-pro`  | Model for the opencode step       |
| `NNX_AI_TIMEOUT` | `1000`                         | Seconds before opencode is killed |
| `NNX_NODE`       | `lts`                          | Node line: `lts` or `latest`      |

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

Plus the migration tooling the chosen `--provider` needs: `graphile-migrate`
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

- `docker/`
- `lib/`
- `migrations/committed/` (kysely) or `prisma/` (prisma)

### Step 5: Configures Environment Variables

Creates `.env` with:

- Better Auth configuration (secret, URL, telemetry settings)
- PostgreSQL database URL (the Prisma provider uses `127.0.0.1` instead of
  `localhost`, because Prisma's engine resolves `localhost` to `::1` first and
  the Postgres container listens on IPv4 only)
- `SHADOW_DATABASE_URL` and `ROOT_DATABASE_URL` for graphile-migrate (kysely only)
- SMTP settings for Mailpit (local email testing)

### Step 6: Configures the Database (depends on `--provider`)

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
- `db:*` scripts for the chosen provider: `db:watch` / `db:migrate` / `db:commit` /
  `db:reset` / `db:codegen` (kysely), `db:generate` / `db:migrate` / `db:deploy` /
  `db:studio` (prisma), `db:generate` / `db:migrate` / `db:push` / `db:studio` (drizzle)
- `auth:generate` (the Better Auth CLI; it installs `@prisma/client` and
  `better-sqlite3` whatever the provider is, so its command carries
  `--allow-build` for both — see Troubleshooting)
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

The script prints the exact sequence for the provider it scaffolded. After the
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

### Database & Migrations (chosen with `--provider`)

Default, **kysely**:

- ✅ **Kysely** - Type-safe SQL query builder
- ✅ **PostgreSQL** - Database client (pg)
- ✅ **kysely-codegen** - Generates `DB` types from the live database
- ✅ **graphile-migrate** - SQL-first migrations (`.gmrc.js`, `migrations/`)
- ✅ Pre-configured Kysely client with a development-optimized global instance

`--provider prisma`:

- ✅ **Prisma 7** - `prisma-client` generator with the client engine
- ✅ **@prisma/adapter-pg** - driver adapter, so no bundled engine binary
- ✅ `prisma.config.ts` - Prisma 7 reads the connection URL here, not from the schema
- ✅ Pre-configured client singleton in `lib/prisma.ts`

`--provider drizzle`:

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
<app-name>/                      # kysely (default); see --provider for the others
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

- **Change the shadcn design system**: pass `--preset <code>`
- **Skip specific shadcn components**: Replace `--all` with specific component names in `step_init_shadcn`
- **Add/remove dependencies**: Edit the `pnpm add` lists in `step_install_deps` / `step_install_dev_deps`
- **Customize Better Auth**: Edit the `ai_prompt` heredoc in the script (describe what you want, not the code), or edit the generated `auth.ts` and `lib/auth-client.ts` afterwards
- **Change the database schema**: Edit `migrations/current.sql`, run `pnpm db:watch`, then `pnpm db:codegen`
- **Pin a version**: There are no version variables any more. Prefer not to add one — the last set of pins caused more breakage than they prevented (see the note in Step 2). If a `latest` genuinely breaks, verify it against the registry rather than assuming, and pin the narrowest thing that fixes it

## Troubleshooting

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
