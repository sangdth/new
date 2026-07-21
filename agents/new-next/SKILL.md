---
name: new-next
description: Scaffold a new Next.js project with the house stack — App Router + TypeScript + Tailwind, all of shadcn/ui, Kysely + graphile-migrate on Postgres, Better Auth (admin/apiKey/anonymous), the Vercel AI SDK, and Jotai — plus a local Docker stack (Postgres, Redis, Mailpit). Generates the whole project, then once the user starts the database, generates the auth schema and Kysely types and verifies the app builds and serves. Use this whenever the user wants to start, create, bootstrap, or scaffold a new Next.js app, web app, or frontend project, mentions `new-next`, or asks for a Next.js starter with auth and a database — even when they don't name the individual libraries. Also use it when someone asks what the standard Next.js setup here looks like.
---

# new-next

Scaffold a Next.js project with an opinionated, known-working stack, then — once
the user has started the local database — take it to a verified, working app.
The last mile is why this is a skill: Better Auth's `pg` adapter and
`kysely-codegen` both **introspect a live database**, so the auth schema and
types can only be generated after Postgres is up, and that stretch involves
reacting to failures and knowing which errors are expected. Starting the
database itself is the user's step — see step 7.

## Before you start

Confirm the app name and target directory, and resolve them into one
**absolute path** before running anything. If the user hasn't said where, ask
rather than guessing.

Check prerequisites early:

```bash
node --version && pnpm --version && docker --version && docker info --format 'daemon {{.ServerVersion}}'
```

`docker info` is the real check — `docker --version` only reads the CLI binary
and exits 0 with the daemon stopped, a failure that otherwise stays hidden
until step 7. Report a dead daemon now, next to its fix (start Docker Desktop).
If `pnpm` is missing, stop and tell the user (`npm i -g pnpm` or
`corepack enable`). If Docker is missing you can still scaffold all of
Phase 1 — say so plainly now rather than letting them discover it at step 7.

## Versions: install everything at `latest`

This scaffold deliberately pins nothing — an earlier version's pins outlived
their reasons and became the bugs they were defending against. Read
`references/provenance.md` before re-adding any pin. Three version facts
replace the pins:

- **Better Auth splits plugins into separate packages.** `apiKey` is not in
  the `better-auth/plugins` barrel — it imports from `@better-auth/api-key`
  (server) and `@better-auth/api-key/client` (client). `admin` and `anonymous`
  are still in the main barrels. If a plugin import resolves to `undefined`,
  assume extraction, not deletion: check `npm view @better-auth/<plugin-name>
  version` before rewriting anything.
- **The Better Auth CLI lags the runtime.** A CLI a minor behind is normal;
  don't force versions to match. Judge the *output* instead:
  `migrations/current.sql` must contain a `create table` per configured
  plugin. A missing table means the CLI is too old for that plugin — try
  `@better-auth/cli@beta`. And don't trust `@better-auth/cli --version`; it
  reports `0.1.0` regardless. `npm view @better-auth/cli version` tells the
  truth.
- **Never downgrade Next after scaffolding.** `create-next-app` writes
  `eslint.config.mjs` and the `dev` script for the version it installed;
  pinning backwards leaves a broken ESLint config and a silently dropped
  `--turbopack` flag. If you need a specific major, get it at creation time:
  `pnpm create next-app@<version>`.

## Phase 1 — Scaffold

Run in order. Every command below either takes an absolute path or is prefixed
with `cd <abs-path> &&` in the same invocation — a standalone `cd` doesn't
reliably carry over to the next command in an agent session, and most of these
commands succeed silently in the wrong directory.

### 1. Create the Next.js app

```bash
pnpm create next-app /absolute/path/to/<app-name> \
  --typescript --eslint --tailwind --app --turbopack \
  --no-import-alias --no-react-compiler --no-src-dir --use-pnpm
```

Pass an **absolute path**, not a bare app name, then confirm where it landed:

```bash
ls /absolute/path/to/<app-name>/package.json
```

`--no-import-alias` only skips the prompt — the default `@/*` mapping is still
in `tsconfig.json`, and the generated files rely on it. Leave whatever version
this installs alone; recent Next majors make Turbopack the default and omit
the flag from the `dev` script — expected, not a problem to fix.

### 2. Install dependencies

```bash
cd /absolute/path/to/<app-name> && pnpm add -D concurrently rimraf graphile-migrate kysely-codegen @types/pg

cd /absolute/path/to/<app-name> && pnpm add @ai-sdk/react @ai-sdk/openai @better-fetch/fetch ai \
  better-auth @better-auth/api-key date-fns dotenv jotai kysely pg
```

`dotenv` is a runtime dependency — `.gmrc.js` requires it. `concurrently` and
`rimraf` have no consumer in the scaffold, and the compose stack's Redis and
Mailpit (plus the `SMTP_*` values in `.env`) are wired to nothing — all of
these are pre-provisioned for what this stack usually grows next. Don't go
hunting for their wiring. A pnpm peer warning about `@better-fetch/fetch` is
cosmetic when it appears — the scaffold builds and runs through it.

### 3. Initialize shadcn/ui

```bash
cd /absolute/path/to/<app-name> && pnpm dlx shadcn@latest init --defaults
cd /absolute/path/to/<app-name> && pnpm dlx shadcn@latest add --all
```

Must be `cd <abs-path> && pnpm dlx …` (or shadcn's own `--cwd` flag) —
`pnpm --dir <path> dlx` does **not** set the directory for the dlx'd binary,
and shadcn, not finding a project in the shell's cwd, starts prompting for a
new one. `--all` installs ~60 components; chatty and slow on a cold cache is
normal. If the user wants a lean install, name the components instead.

`init` also adds `@base-ui/react`, `@shadcn/react`, and `shadcn` itself as
dependencies — that's the Radix → Base UI migration, not a failure worth
investigating.

### 4. Create directories

```bash
cd /absolute/path/to/<app-name> && mkdir -p 'app/api/auth/[...all]' migrations/committed docker lib
```

Quote the `[...all]` path — unquoted brackets are a shell glob.

### 5. Write the project files

Read `references/templates.md` and write each file exactly as given, using
absolute path prefixes:

| File | Purpose |
|---|---|
| `.env` | Secrets and connection strings (generate the auth secret — see below) |
| `docker/compose.dev.yml` | Postgres 18, Redis 7, Mailpit |
| `lib/db.ts` | Kysely client, dev-global singleton |
| `lib/db-types.ts` | Placeholder `DB` type so the project type-checks pre-codegen |
| `.gmrc.js` | graphile-migrate config |
| `migrations/committed/.gitkeep` | Empty file, keeps the dir in git |
| `lib/auth-client.ts` | Better Auth React client + exported hooks |
| `auth.ts` | Better Auth server config on a raw `pg.Pool` |
| `app/api/auth/[...all]/route.ts` | Auth route handler |

For `.env`, generate a fresh secret:

```bash
openssl rand -base64 32
```

Substitute it as `BETTER_AUTH_SECRET`, unquoted — base64's alphabet
(`A-Za-z0-9+/=`) is inert for both parsers that read this file (dotenv and
`docker compose --env-file`). If `openssl` isn't available, fall back to
`replacewithyourverysecretstring` and tell the user to replace it before
deploying anywhere real.

### 6. Add package.json scripts and ESLint overrides

```bash
cd /absolute/path/to/<app-name> && npm pkg set \
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
```

Flags that are observations, not style: `db:codegen`'s `--exclude-pattern`
keeps graphile-migrate's two bookkeeping tables out of the generated `DB`
type, and `docker:ps`'s `-a` makes a stopped stack (`Exited (0)`) visible —
bare `ps` prints the same empty table for "stopped" and "never started". The
`docker:*` scripts exist because **every** compose call for this project needs
`--env-file .env` — omitting it doesn't error, it interpolates
`${POSTGRES_PASSWORD}` to an empty string — so the flag is encapsulated
instead of remembered. `pnpm docker` has `up -d --wait` baked in; the siblings
forward trailing args (`pnpm docker:logs postgres`). No script wraps
`down -v` — that's the one that deletes data; `docker:down` leaves the named
volumes intact.

Then add two override blocks to `eslint.config.mjs`, **as the last entries in
the array passed to `defineConfig(...)`** — after the Next spreads *and* the
`globalIgnores(...)` entry `create-next-app` puts at the end:

```js
  {
    // graphile-migrate loads .gmrc.js as CommonJS, and its `require('dotenv/config')`
    // is what supplies the connection strings — the TS-oriented rule doesn't apply.
    files: ['.gmrc.js'],
    rules: { '@typescript-eslint/no-require-imports': 'off' },
  },
  {
    // shadcn components and hooks are vendored generated code. Their effect
    // patterns trip newer react-hooks rules; rewriting them diverges from
    // upstream for no benefit.
    files: ['components/ui/**', 'hooks/**'],
    rules: { 'react-hooks/set-state-in-effect': 'off' },
  },
```

Placement is load-bearing: flat config resolves last-match-wins, so a block
above `...nextVitals` / `...nextTs` gets its rules switched straight back on
and the override silently does nothing (verified both ways). Edit the
generated file rather than replacing it, and keep the overrides this narrow —
the point is to excuse generated code, not to disable rules for the code the
user is about to write.

Confirm with `pnpm lint` before moving on — it must exit silent. That check is
what distinguishes a real fix from a no-op, and it's the only signal if a rule
name ever rots upstream (ESLint silently ignores unknown rules set to `off`).

## Phase 2 — Post-setup

Needs a live database. Order matters — check each step's result before the
next instead of firing them all and hoping.

### 7. Ask the user to start the services

This is the only step with consequences outside the project directory: it
binds host ports 5432, 6379, 1025, 8025, creates named volumes, and leaves
three services running. Plenty of machines already have a Postgres on 5432,
and nobody asking for a scaffold asked you to reshape what's listening on
their ports. So hand them the command rather than running it:

```bash
pnpm docker
```

Tell them alongside it: `--wait` blocks until the healthchecks pass, so a
clean exit means Postgres is genuinely accepting connections. If they hit a
port conflict, the fix is to remap the host side in `docker/compose.dev.yml`
(e.g. `"5433:5432"`) and update the port in all three connection strings in
`.env` — not to stop whatever else is running.

Give them that command **and** the whole remaining sequence in the same
message — see [Handing off](#handing-off). There's no "they didn't reply"
event: if nobody's there your turn simply ends, and a question without the
handoff leaves them half an instruction. Stopping here is a legitimate
finishing point, not a failure — the project is complete and type-checks
against the placeholder `DB` type.

If the user asks you to run it yourself, run it — the point is that it's their
decision, not that you refuse. First glance at `docker ps` for containers
already bound to 5432, 6379, 1025, or 8025: every project in this stack claims
the same four host ports, so an earlier scaffold still running fails this
one's `up` mid-sequence.

**Before continuing, confirm Postgres is actually reachable:**

```bash
pnpm docker:ps
```

The `-a` makes three states distinguishable:

- `Up … (healthy)` — continue to step 8.
- `Exited (0)` — started earlier, stopped since (the likeliest state when
  resuming in a later turn). Run `pnpm docker` again — restarting the same
  containers against the same volumes is idempotent.
- Empty table — never created; hand the user `pnpm docker` as above.

**Postgres must report `healthy`** before you continue. Mailpit may report
plain `Up` on older images — nothing downstream touches it, don't stall on
it. If Postgres isn't healthy, say what you actually see rather than pressing
on into a failure that will look like a config error.

### 8. Generate the Better Auth schema

```bash
pnpm auth:generate
```

Writes `migrations/current.sql` by introspecting the running database — which
is why it couldn't happen in Phase 1. Expect noise and don't chase it:
`pnpm dlx` pulls the CLI into a throwaway tree bundling every adapter, so
deprecation warnings and ignored build scripts (`prisma`, `better-sqlite3`)
are about that tree, not your project.

Verify before moving on:

```bash
test -s migrations/current.sql && grep -oE 'create table "[a-z]+"' migrations/current.sql
```

Expect `user`, `session`, `account`, `verification`, and `apikey`. The
`test -s` comes first because `grep` prints nothing whether the file is
missing or merely lacks matches — two different problems that otherwise look
identical. A missing `apikey` means the CLI is too old for the extracted
plugin — see [Versions](#versions-install-everything-at-latest).

### 8b. Make the generated SQL idempotent

```bash
cd /absolute/path/to/<app-name> && perl -i -pe 's/^create ((?:unique )?index|table) /create $1 if not exists /' migrations/current.sql
```

Load-bearing, not defensive: graphile-migrate's contract is that `current.sql`
can be re-executed at any time — `watch` re-runs the **whole file** on any
change, and `commit` re-executes it against the real database by design. The
CLI's plain `create table` output survives exactly one apply, then fails with
`42P07`, and a failed commit strands the project in a state where watch *and*
commit both fail (recovery: the `42P07` entry in
`references/troubleshooting.md`). Confirm the transform caught everything:

```bash
grep -c 'if not exists' migrations/current.sql
```

Expect the count to match the `create` statements — 11 with the default
plugin set (5 tables + 6 indexes).

### 9. Apply the migration

```bash
pnpm db:watch --once
```

`--once` applies and exits; without it, `db:watch` stays in the foreground and
hangs the session. Running it twice is safe — graphile-migrate skips an
unchanged file by hash, and after 8b every statement no-ops anyway.

### 10. Generate Kysely types

```bash
pnpm db:codegen
```

Overwrites the `lib/db-types.ts` placeholder with exactly five interfaces
(`User`, `Session`, `Account`, `Verification`, `Apikey`). If
`GraphileMigrate*` interfaces appear too, the script lost its
`--exclude-pattern` (step 6).

### 11. Verify

Run all four. A scaffold can serve a perfectly good homepage while carrying a
broken ESLint config and a type error in the auth client — a real run hit
exactly that, and each failure was visible to exactly one of these commands:

```bash
pnpm typecheck   # type errors in the generated files
pnpm lint        # zero lint errors — not merely a config that resolves
pnpm build       # production build succeeds
pnpm dev         # serves for real
```

`pnpm lint` must come back completely silent — step 6 exists so it can; treat
any output as a real finding. And don't infer lint health from the build:
recent Next majors dropped linting from `next build` entirely, so a green
build says nothing about ESLint.

For `pnpm dev`: start it in the background, confirm the homepage and
`/api/auth/get-session` both return 200, then stop it. The strongest check is
a real write — it exercises the route handler, auth config, schema, and
database in one request:

```bash
curl -s -X POST http://localhost:3000/api/auth/sign-up/email \
  -H 'Content-Type: application/json' \
  -d '{"name":"Probe User","email":"probe@example.com","password":"probe-password-123"}'
```

Expect 200 with a `user` carrying `"role": "MEMBER"` (the admin plugin's
`defaultRole` working) and `"isAnonymous": false`. The row it leaves is
harmless in dev, and doubles as proof later that data survives container
restarts.

### 12. Freeze the auth schema

```bash
pnpm db:commit
```

Only after step 11 passes. Validates the migration against the shadow
database, re-executes it against the real one (a no-op thanks to 8b), writes
`migrations/committed/000001.sql`, and resets `current.sql` to an empty
template. The auth schema is stable from birth, so freezing it now gives the
user a clean `current.sql` for their own first migration.

Report honestly what passed. If something fails, check
`references/troubleshooting.md` before improvising — several of these
failures have a correct answer that looks wrong at first — and if it's an
undocumented version interaction, say so plainly rather than papering over it.

## Handing off

### If you stopped at step 7

The project is finished and consistent — it just has no database yet. Give
them the whole remaining sequence in order, since the ordering isn't
guessable:

```bash
# 1. Start Postgres, Redis and Mailpit (blocks until healthy)
pnpm docker

# 2. Generate the Better Auth schema (introspects the live database)
pnpm auth:generate

# 3. Make it re-runnable — graphile-migrate re-executes current.sql on every
#    change and again at commit; plain `create table` output fails that
perl -i -pe 's/^create ((?:unique )?index|table) /create $1 if not exists /' migrations/current.sql

# 4. Apply it
pnpm db:watch --once

# 5. Generate Kysely types from the database
pnpm db:codegen

# 6. Check it holds together, then freeze the auth schema as migration 000001
pnpm typecheck && pnpm lint && pnpm build
pnpm db:commit
pnpm dev
```

Include two non-guessable facts about that first command: the `docker:*`
scripts exist because every compose call needs `--env-file .env` (`ps` and
`stop` included) — reaching past them for raw `docker compose` silently
interpolates `${POSTGRES_PASSWORD}` to an empty string; and a port conflict
means remapping the host side in `docker/compose.dev.yml` plus updating all
three connection strings in `.env`, not stopping whatever else is running.
List the sibling scripts too — `pnpm docker:ps`, `docker:logs`, `docker:stop`,
`docker:down` — so they don't fall back to raw compose. Offer to pick up from
step 2 once they've started the stack — that's the part where the failures
are non-obvious.

### If you ran the full sequence

Tell the user what's running and what to do next:

- Dev server: `pnpm dev` → http://localhost:3000
- Mailpit inbox: http://localhost:8025
- The three containers are still running; `pnpm docker:stop` when done
  (`docker:ps` to check, `docker:logs <service>` to follow one).
  `pnpm docker:down` removes containers but leaves the named volumes — data
  survives a full down → up cycle (verified with a real row)
- Schema changes: write **idempotent** SQL in `migrations/current.sql`
  (`create table if not exists …`, `create or replace function …`) →
  `pnpm db:watch --once` → `pnpm db:codegen`. Idempotent is a requirement,
  not a courtesy — graphile-migrate re-runs the whole file on every change,
  and `db:commit` re-executes it once more; plain `create table` fails both
  with `42P07`
- The auth schema is already frozen as `migrations/committed/000001.sql`.
  When their own schema work stabilizes: `pnpm db:commit` freezes it;
  `pnpm db:migrate` applies committed migrations elsewhere
- Add an OpenAI API key to `.env` before using the AI SDK features

### Either way

- `BETTER_AUTH_SECRET` was generated fresh, and `.env` is covered by the
  generated `.gitignore`'s `.env*` pattern — actually run
  `git check-ignore .env` rather than asserting it; a leaked secret here is a
  full auth bypass.
- `create-next-app` may leave an `AGENTS.md` warning about breaking changes
  plus a `CLAUDE.md` pointing at it. Mention both — they're aimed at future
  agents, and a stale one is worse than none.

## When something breaks

Read `references/troubleshooting.md`. It covers the failures that actually
happen with this stack, and several have a correct answer that looks wrong at
first — check there before improvising.

## Deviating from the defaults

The stack is opinionated, not mandatory:

- **Fewer shadcn components** — name them instead of `--all`
- **A different base color** — `shadcn init --base-color <color>` instead of
  `--defaults`
- **Extra Better Auth plugins** — add to both `auth.ts` and
  `lib/auth-client.ts`, then re-run `pnpm auth:generate` (it diffs against the
  live database, so only the new plugin's tables appear), apply step 8b's
  transform to the fresh output, then `pnpm db:watch --once`,
  `pnpm db:codegen`, `pnpm db:commit`. Check whether the plugin ships in the
  barrel or as its own `@better-auth/*` package
- **A different ORM** — doable, but `auth.ts` and `lib/db.ts` both assume the
  `pg` driver, and Better Auth's adapter choice drives whether schema
  generation can run offline. Say what changes before you start

Deviations are fine. Silent deviations are not — if you change something the
user didn't ask about, tell them.

## Provenance

This skill is self-contained: everything it needs is in this file and
`references/`, and it shells out only to `pnpm`, `docker`, and the public npm
registry. If something here is wrong, fix it here — there is no companion
script. `references/provenance.md` holds **why nothing is pinned** (read it
before re-adding any pin) and the **verification record** of which steps have
actually been run end to end (read it before trusting that a step is proven).
