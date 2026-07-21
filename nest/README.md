# new-nest.sh — NestJS Scaffolding Script

Scaffolds a NestJS project with TypeScript, Prisma (via `@prisma/adapter-pg`), and Better Auth wired through `@thallesp/nestjs-better-auth`.

> Installation and symlink setup live in the [root README](../README.md#installation).

## Usage

```bash
./new-nest.sh <app-name>   # from this directory
nns <app-name>             # from anywhere, if symlinked
```

Example:

```bash
./new-nest.sh my-nestjs-app
nns my-nestjs-app
```

The script creates the project as a subdirectory of your **current working
directory**, not of the repo — so `cd` to wherever you want the project to live first.

> [!NOTE]
> Unlike `new-next.sh`, this script takes no flags — no `--dry-run`, no `--version`.
> It runs straight through. Passing a flag is treated as the app name.

## Setup Process Overview

### Step 1: Creates NestJS App

Scaffolds a new NestJS project using the official CLI with:

- TypeScript enabled
- ESLint configured
- Uses pnpm as package manager

### Step 2: Installs Dependencies

**Dev Dependencies:**

```bash
prisma        # Prisma CLI
rimraf        # Cross-platform rm -rf
```

**Core Dependencies:**

```bash
@nestjs/config                # Configuration module for NestJS
@prisma/adapter-pg            # PostgreSQL adapter for Prisma
@prisma/client                # Prisma ORM client
@thallesp/nestjs-better-auth  # Better Auth integration for NestJS
better-auth                   # Authentication library
date-fns                      # Date utility library
pg                            # PostgreSQL client
```

> [!NOTE]
> Nothing here is version-pinned — `better-auth` installs at `latest`. (Neither
> does the Next.js script any more, as of `new-next.sh` v3.0.0.)
>
> The `apiKey` plugin is no longer exported from `better-auth/plugins`; it ships
> as its own package, `@better-auth/api-key`. `src/auth.ts` generated here still
> imports it from the barrel, so a fresh scaffold is expected to fail on that
> import until the script is updated to add `@better-auth/api-key` to the
> `pnpm add` list and import `apiKey` from it. Pinning `better-auth` back to
> `1.4.22` also silences it, but that trades a one-line import fix for a stale
> runtime. **This path has not been re-verified since the Next.js script was
> updated — the NestJS scaffold needs its own end-to-end run.**

### Step 3: Generates NestJS Resources

- Creates Prisma module using NestJS CLI
- Creates Prisma service using NestJS CLI

### Step 4: Sets Up Project Structure

Creates necessary directories and files:

- `prisma/` - Database schema
- `src/prisma/` - Prisma module, service, and instance
- `src/auth.ts` - Better Auth configuration

Also appends `**/prisma/generated` to `.gitignore`.

### Step 5: Configures Environment Variables

Creates `.env` with:

- Better Auth configuration (secret, URL, telemetry settings) — `BETTER_AUTH_SECRET` is generated with `openssl rand -base64 32`, falling back to a placeholder string if openssl is unavailable
- PostgreSQL database URL
- SMTP settings for Mailpit (local email testing)

> [!IMPORTANT]
> This script does **not** generate a Docker Compose file — only `new-next.sh` does.
> You need a PostgreSQL instance reachable at the `DATABASE_URL` in `.env`
> (defaults to `postgresql://postgres:password@localhost:5432/postgres`) before
> running migrations. Reuse the Next.js stack's `docker/compose.dev.yml`, or point
> `DATABASE_URL` at any Postgres you already have.

### Step 6: Configures Prisma

Creates `prisma/schema.prisma` with:

- PostgreSQL datasource using `env("DATABASE_URL")`
- Prisma client generator with custom output path (`../src/prisma/generated`)

Creates `src/prisma/prisma.instance.ts` with:

- PrismaPg adapter setup
- Global Prisma client (development-optimized)
- Connection string validation

Creates `src/prisma/prisma.service.ts` with:

- NestJS service extending PrismaClient
- Module lifecycle hooks (onModuleInit, onModuleDestroy)

### Step 7: Configures Better Auth

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
- Sets default port 3001 (override with `SERVER_PORT`)

### Step 8: Generates Code

- Runs `pnpm dlx prisma generate` to generate the Prisma client
- Runs `pnpm dlx @better-auth/cli@latest generate --yes --config src/auth.ts` to generate the Better Auth schema

Unlike the Next.js script, both of these run **at scaffold time** — the Prisma adapter lets Better Auth generate its schema offline, without a live database.

## Post-Setup Steps

After the script completes:

1. **Run Prisma migrations** (needs a reachable Postgres — see Step 5)

   ```bash
   cd <app-name>
   pnpm prisma migrate dev --name init
   ```

2. **Update environment variables** (if needed)
   - Modify `.env` for your specific setup
   - Update database credentials if not using the defaults

3. **Start the development server**

   ```bash
   pnpm run start:dev
   ```

## Feature List

After running the script, your NestJS project includes:

### Core Framework

- ✅ **NestJS** (latest) - Progressive Node.js framework
- ✅ **TypeScript** - Type-safe development
- ✅ **ESLint** - Code linting

### Database & ORM

- ✅ **Prisma** - Type-safe ORM with PostgreSQL adapter
- ✅ **PostgreSQL** - Database client (pg)
- ✅ **@prisma/adapter-pg** - Direct PostgreSQL connection
- ✅ Pre-configured Prisma client with custom output path
- ✅ Development-optimized global instance
- ✅ NestJS Prisma service with lifecycle hooks

### Authentication

- ✅ **Better Auth** - Complete auth solution
  - Email/password authentication
  - Admin plugin (role-based access)
  - API key authentication
  - Anonymous authentication
  - Auto sign-in after registration
- ✅ **@thallesp/nestjs-better-auth** - NestJS integration
- ✅ Pre-configured server setup

### Configuration & Utilities

- ✅ **@nestjs/config** - Environment configuration
- ✅ **date-fns** - Date manipulation

### Developer Tools

- ✅ **rimraf** - Cross-platform file deletion
- ✅ Pre-configured environment variables
- ✅ SMTP config for local email testing (Mailpit)

## Generated Project Structure

```text
<app-name>/
├── src/
│   ├── prisma/
│   │   ├── prisma.instance.ts    # Prisma client instance
│   │   ├── prisma.service.ts     # NestJS Prisma service
│   │   ├── prisma.module.ts      # Prisma module
│   │   └── generated/            # Generated Prisma client (gitignored)
│   ├── auth.ts                   # Auth server config
│   ├── app.module.ts             # App module with imports
│   └── main.ts                   # Entry point with config
├── prisma/
│   └── schema.prisma             # Database schema
└── .env                          # Environment variables
```

## Customization

To modify the default setup, edit the script:

- **Add/remove dependencies**: Modify the `pnpm add` lists near the top of the script
- **Customize Better Auth**: Edit the generated `src/auth.ts` file
- **Modify Prisma schema**: Edit `prisma/schema.prisma` after generation
- **Change default port**: Edit `src/main.ts` after generation, or set `SERVER_PORT` in `.env`

## Troubleshooting

- **NestJS CLI fails**: Ensure `@nestjs/cli` can be accessed via pnpm dlx
- **Better Auth generation fails**: Verify the `--config src/auth.ts` path is correct. If it fails on the `apiKey` import, the plugin has moved to `@better-auth/api-key` — install that package and import `apiKey` from it rather than from `better-auth/plugins` (see the note in Step 2)
- **`prisma migrate` can't connect**: This script generates no Docker stack — confirm Postgres is actually running at your `DATABASE_URL`

See the [root README](../README.md#troubleshooting) for issues common to both scripts.
