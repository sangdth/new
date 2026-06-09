# Project Scaffolding Scripts

Two convenience scripts to quickly scaffold new projects with common dependencies and configurations:

- **new-next.sh** - Scaffold a new Next.js project
- **new-nest.sh** - Scaffold a new NestJS project

## Prerequisites

- Node.js installed
- pnpm installed
- Docker (for the local Postgres / Redis / Mailpit stack)
- openssl (optional, for generating a random Better Auth secret)

## Installation

1. **Download or clone the scripts**

   Save the scripts to your desired location (e.g., `~/Projects/` or `~/scripts/`)

2. **Make the scripts executable**

   ```bash
   chmod +x new-next.sh new-nest.sh
   ```

3. **(Optional) Add to PATH for global access**

   ```bash
   # Move to a directory in your PATH
   sudo mv new-next.sh /usr/local/bin/new-next
   sudo mv new-nest.sh /usr/local/bin/new-nest

   # Now you can run them from anywhere
   new-next my-nextjs-app
   new-nest my-nestjs-app
   ```

> [!TIP]
> After running chmod, I prefer to use the symlink way:
>
> `ln -s ~/Projects/new/new-next.sh ~/.local/bin/nnx`
>
> `ln -s ~/Projects/new/new-nest.sh ~/.local/bin/nns`
>
> Then I can use like `nnx awesome-next-project`
>
> or `nns awesome-nest-project`

## Usage

### Next.js Project

```bash
./new-next.sh [flags] <app-name>
```

#### Flags

| Flag | Description |
|------|-------------|
| `--dry-run` | Print what would be executed without running anything |
| `-v`, `--version` | Show version |
| `--help` | Show help message |

#### Examples

```bash
./new-next.sh my-nextjs-app
./new-next.sh --dry-run my-nextjs-app
```

### NestJS Project

```bash
./new-nest.sh <app-name>
```

Example:

```bash
./new-nest.sh my-nestjs-app
```

---

## Next.js Script (new-next.sh)

### Setup Process Overview

The script automates the following setup:

#### Step 1: Creates Next.js App

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

#### Step 2: Installs Dependencies

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
date-fns              # Date utility library
dotenv                # Loads .env (used by .gmrc.js)
jotai                 # State management
kysely                # Type-safe SQL query builder
pg                    # PostgreSQL client
```

#### Step 3: Initializes shadcn/ui

- Runs `shadcn init` with default configuration (neutral base color)
- Installs **all** available shadcn/ui components

#### Step 4: Sets Up Project Structure

Creates necessary directories:

- `app/api/auth/[...all]/`
- `migrations/committed/` (graphile-migrate)
- `docker/`
- `lib/`

#### Step 5: Configures Environment Variables

Creates `.env` with:

- Better Auth configuration (secret, URL, telemetry settings)
- PostgreSQL database URL, plus `SHADOW_DATABASE_URL` and `ROOT_DATABASE_URL` for graphile-migrate
- SMTP settings for Mailpit (local email testing)

#### Step 6: Configures the Database (Kysely + graphile-migrate)

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

#### Step 7: Configures Better Auth

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

#### Step 8: Generates Code & Scripts

- Runs `pnpm dlx @better-auth/cli@latest generate --yes --output migrations/current.sql` to write the Better Auth SQL schema into graphile-migrate's current migration
- Adds `db:watch`, `db:migrate`, `db:commit`, `db:reset`, `db:codegen`, and `auth:generate` scripts to `package.json` via `npm pkg set`

> Kysely types are **not** generated here — `kysely-codegen` introspects a live database, so it runs as a post-setup step once Postgres is up and migrations are applied.

### Next.js Post-Setup Steps

After the script completes:

1. **Start the local services** (Postgres, Redis, Mailpit)

   ```bash
   cd <app-name>
   docker compose -f docker/compose.dev.yml --env-file .env up -d
   ```

2. **Apply the Better Auth migration** to your dev database

   ```bash
   pnpm db:watch --once
   ```

   When the schema is stable, freeze it as a committed migration with `pnpm db:commit`,
   then apply committed migrations in other environments with `pnpm db:migrate`.

3. **Generate Kysely types** from the database

   ```bash
   pnpm db:codegen
   ```

4. **Update environment variables** (if needed)
   - Add an OpenAI API key if using AI features
   - Update database credentials if not using the defaults

5. **Start the development server**

   ```bash
   pnpm dev
   ```

### Next.js Feature List

After running the script, your project includes:

#### Next.js Core Framework

- ✅ **Next.js** (latest) - React framework with App Router
- ✅ **TypeScript** - Type-safe development
- ✅ **Turbopack** - Fast bundler
- ✅ **ESLint** - Code linting

#### Next.js Styling & UI

- ✅ **Tailwind CSS** - Utility-first CSS framework
- ✅ **shadcn/ui** - All components pre-installed
  - Accordion, Alert, Avatar, Badge, Button, Calendar, Card, Checkbox, Collapsible, Command, Context Menu, Dialog, Drawer, Dropdown Menu, Form, Input, Label, Menubar, Navigation Menu, Pagination, Popover, Progress, Radio Group, Scroll Area, Select, Separator, Sheet, Skeleton, Slider, Switch, Table, Tabs, Textarea, Toast, Toggle, Tooltip, and more

#### Next.js Database & Migrations

- ✅ **Kysely** - Type-safe SQL query builder
- ✅ **PostgreSQL** - Database client (pg)
- ✅ **kysely-codegen** - Generates `DB` types from the live database
- ✅ **graphile-migrate** - SQL-first migrations (`.gmrc.js`, `migrations/`)
- ✅ Pre-configured Kysely client with a development-optimized global instance

#### Next.js Authentication

- ✅ **Better Auth** - Complete auth solution
  - Email/password authentication
  - Admin plugin (role-based access)
  - API key authentication
  - Anonymous authentication
  - Auto sign-in after registration
- ✅ Pre-configured client and server setup
- ✅ Next.js API routes ready

#### Next.js AI & LLM

- ✅ **Vercel AI SDK** - AI/LLM integration
- ✅ **@ai-sdk/react** - React hooks for AI
- ✅ **@ai-sdk/openai** - OpenAI provider

#### Next.js State Management & Utilities

- ✅ **Jotai** - Atomic state management
- ✅ **date-fns** - Date manipulation
- ✅ **@better-fetch/fetch** - Enhanced fetch utility

#### Next.js Developer Tools

- ✅ **concurrently** - Run multiple scripts
- ✅ **rimraf** - Cross-platform file deletion
- ✅ Pre-configured environment variables
- ✅ SMTP config for local email testing (Mailpit)

#### Next.js Project Structure

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

### Next.js Customization

- **Preview without creating anything**: `./new-next.sh --dry-run my-app`

To modify the default setup, edit the script:

- **Change shadcn base color**: Edit the `step_init_shadcn` function to add `--base-color` flag
- **Skip specific shadcn components**: Replace `--all` with specific component names in `step_init_shadcn`
- **Add/remove dependencies**: Edit the `pnpm add` lists in `step_install_deps` / `step_install_dev_deps`
- **Customize Better Auth**: Edit the generated `auth.ts` and `lib/auth-client.ts` files
- **Change the database schema**: Edit `migrations/current.sql`, run `pnpm db:watch`, then `pnpm db:codegen`

---

## NestJS Script (new-nest.sh)

### NestJS Setup Process Overview

The script automates the following setup process for NestJS:

#### NestJS Step 1: Creates NestJS App

Scaffolds a new NestJS project using the official CLI with:

- TypeScript enabled
- ESLint configured
- Uses pnpm as package manager

#### NestJS Step 2: Installs Dependencies

**Dev Dependencies:**

```bash
prisma        # Prisma CLI
rimraf        # Cross-platform rm -rf
```

**Core Dependencies:**

```bash
@nestjs/config           # Configuration module for NestJS
@prisma/adapter-pg       # PostgreSQL adapter for Prisma
@prisma/client           # Prisma ORM client
@thallesp/nestjs-better-auth  # Better Auth integration for NestJS
better-auth              # Authentication library
date-fns                 # Date utility library
pg                       # PostgreSQL client
```

#### NestJS Step 3: Generates NestJS Resources

- Creates Prisma module using NestJS CLI
- Creates Prisma service using NestJS CLI

#### NestJS Step 4: Sets Up Project Structure

Creates necessary directories and files:

- `prisma/` - Database schema
- `src/prisma/` - Prisma module, service, and instance
- `src/auth.ts` - Better Auth configuration

#### NestJS Step 5: Configures Environment Variables

Creates `.env` with:

- Better Auth configuration (secret, URL, telemetry settings)
- PostgreSQL database URL
- SMTP settings for Mailpit (local email testing)

#### NestJS Step 6: Configures Prisma

Creates `prisma/schema.prisma` with:

- PostgreSQL datasource
- Prisma client generator with custom output path

Creates `src/prisma/prisma.instance.ts` with:

- PrismaPg adapter setup
- Global Prisma client (development-optimized)
- Connection string validation

Creates `src/prisma/prisma.service.ts` with:

- NestJS service extending PrismaClient
- Module lifecycle hooks (onModuleInit, onModuleDestroy)

#### NestJS Step 7: Configures Better Auth

Creates `src/auth.ts` with:

- Server-side auth configuration
- Prisma adapter integration
- Email/password authentication enabled
- Auto sign-in after registration
- Admin, API key, and anonymous plugins

Updates `src/app.module.ts`:

- Imports ConfigModule (global)
- Imports AuthModule with Better Auth configuration
- Registers PrismaService

Updates `src/main.ts`:

- Disables body parser (required for Better Auth)
- Sets default port to 3001

#### NestJS Step 8: Generates Code

- Runs `pnpm dlx prisma generate` to generate Prisma client
- Runs `pnpm dlx @better-auth/cli@latest generate --yes --config src/auth.ts` to generate Better Auth schema

### NestJS Post-Setup Steps

After the script completes, you need to:

1. **Run Prisma migrations**

   ```bash
   cd <app-name>
   pnpm prisma migrate dev --name init
   ```

2. **Update environment variables** (if needed)
   - Modify `.env` for your specific setup
   - Update database credentials if not using default

3. **Start the development server**

   ```bash
   pnpm run start:dev
   ```

### NestJS Feature List

After running the script, your NestJS project includes:

#### NestJS Core Framework

- ✅ **NestJS** (latest) - Progressive Node.js framework
- ✅ **TypeScript** - Type-safe development
- ✅ **ESLint** - Code linting

#### NestJS Database & ORM

- ✅ **Prisma** - Type-safe ORM with PostgreSQL adapter
- ✅ **PostgreSQL** - Database client (pg)
- ✅ **@prisma/adapter-pg** - Direct PostgreSQL connection
- ✅ Pre-configured Prisma client with custom output path
- ✅ Development-optimized global instance
- ✅ NestJS Prisma service with lifecycle hooks

#### NestJS Authentication

- ✅ **Better Auth** - Complete auth solution
  - Email/password authentication
  - Admin plugin (role-based access)
  - API key authentication
  - Anonymous authentication
  - Auto sign-in after registration
- ✅ **@thallesp/nestjs-better-auth** - NestJS integration
- ✅ Pre-configured server setup

#### NestJS Configuration & Utilities

- ✅ **@nestjs/config** - Environment configuration
- ✅ **date-fns** - Date manipulation

#### NestJS Developer Tools

- ✅ **rimraf** - Cross-platform file deletion
- ✅ Pre-configured environment variables
- ✅ SMTP config for local email testing (Mailpit)

#### NestJS Project Structure

```text
<app-name>/
├── src/
│   ├── prisma/
│   │   ├── prisma.instance.ts    # Prisma client instance
│   │   ├── prisma.service.ts     # NestJS Prisma service
│   │   └── prisma.module.ts      # Prisma module
│   ├── auth.ts                   # Auth server config
│   ├── app.module.ts             # App module with imports
│   └── main.ts                   # Entry point with config
├── prisma/
│   ├── schema.prisma             # Database schema
│   └── generated/                # Generated Prisma client
└── .env                          # Environment variables
```

### NestJS Customization

To modify the default setup, edit the script:

- **Add/remove dependencies**: Modify lines 14-24
- **Customize Better Auth**: Edit the generated `src/auth.ts` file
- **Modify Prisma schema**: Edit `prisma/schema.prisma` after generation
- **Change default port**: Edit `src/main.ts` after generation

---

## Troubleshooting

### Common Issues

- **Permission denied**: Run `chmod +x new-next.sh new-nest.sh` to make the scripts executable
- **pnpm not found**: Install pnpm globally with `npm install -g pnpm`
- **Script fails mid-way**: Check error messages and manually run remaining commands

### Script-Specific Issues

**Next.js (new-next.sh)**:

- **shadcn init fails**: Ensure you have a compatible Node.js version
- **`pnpm db:codegen` fails**: Ensure Postgres is running and migrations are applied (`docker compose ... up -d`, then `pnpm db:watch --once`); `kysely-codegen` needs a live database
- **graphile-migrate can't connect**: Check `DATABASE_URL` / `SHADOW_DATABASE_URL` / `ROOT_DATABASE_URL` in `.env`

**NestJS (new-nest.sh)**:

- **NestJS CLI fails**: Ensure `@nestjs/cli` can be accessed via pnpm dlx
- **Better Auth generation fails**: Verify the `--config src/auth.ts` path is correct
