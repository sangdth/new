# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A collection of shell scripts that scaffold new projects with opinionated defaults. Not a runnable application — the scripts generate applications.

- `new-next.sh` — scaffolds a Next.js project (App Router, TypeScript, Tailwind, shadcn/ui, Prisma, Better Auth, Vercel AI SDK, Jotai)
- `new-nest.sh` — scaffolds a NestJS project (TypeScript, Prisma, Better Auth, `@thallesp/nestjs-better-auth`)

## Tech Stack of Generated Projects

Both scripts produce projects using **pnpm**, **PostgreSQL** via `@prisma/adapter-pg`, **Prisma** with client output in a `generated/` directory, and **Better Auth** with admin/apiKey/anonymous plugins.

- **Next.js stack**: App Router (no Pages Router, no src dir), Turbopack, shadcn/ui (all components), Jotai, Vercel AI SDK, `@better-fetch/fetch`
- **NestJS stack**: `@nestjs/config` (global), `@thallesp/nestjs-better-auth`, body parser disabled in `main.ts`, default port 3001

## Testing Changes to Scripts

There are no automated tests. To verify a script change:

```bash
# Next.js script
./new-next.sh test-app && cd test-app && pnpm prisma generate && pnpm build

# NestJS script
./new-nest.sh test-app && cd test-app && pnpm prisma generate && pnpm build
```

Clean up test output with `rm -rf test-app`.

## Key Patterns in the Scripts

- Docker Compose config is generated into `docker/compose.dev.yml` (Next.js only) with Postgres, Redis, and Mailpit
- `BETTER_AUTH_SECRET` is auto-generated via `openssl rand -base64 32` with a fallback string
- Prisma uses a custom output path (`./generated` for Next.js, `../src/prisma/generated` for NestJS) — both add this to `.gitignore`
- Next.js Prisma config uses `prisma.config.ts` with `dotenv/config` for env loading
- NestJS Prisma uses `env("DATABASE_URL")` directly in `schema.prisma`
- Better Auth schema is generated via `pnpm dlx @better-auth/cli@latest generate --yes`

## When Editing Scripts

- The scripts use heredocs (`cat > file <<EOL ... EOL`) to generate files. Watch for shell variable expansion — `$` characters intended for the generated code must be escaped as `\$`.
- Generated file paths differ between Next.js (root-level `lib/`, `auth.ts`) and NestJS (`src/` directory structure).
- After modifying dependencies, keep the README.md feature lists in sync.
