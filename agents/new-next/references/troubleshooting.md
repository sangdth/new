# Troubleshooting

Failures that actually happen with this stack, and what each one really means.
Several have a correct answer that looks wrong at first — check here before
improvising, because the obvious fix for a few of these makes things worse.

## Contents

- [`better-auth/plugins` has no export named `apiKey`](#better-authplugins-has-no-export-named-apikey)
- [`migrations/current.sql` is missing a plugin table](#migrationscurrentsql-is-missing-a-plugin-table)
- [`forgetPassword` does not exist on the auth client](#forgetpassword-does-not-exist-on-the-auth-client)
- [ESLint can't resolve `eslint-config-next`](#eslint-cant-resolve-eslint-config-next)
- [`pnpm lint` fails on a freshly scaffolded project](#pnpm-lint-fails-on-a-freshly-scaffolded-project)
- [Peer dependency warning about `@better-fetch/fetch`](#peer-dependency-warning-about-better-fetchfetch)
- [graphile-migrate refuses to start](#graphile-migrate-refuses-to-start)
- [Every `db:*` script fails to connect](#every-db-script-fails-to-connect)
- [`pnpm auth:generate` can't reach the database](#pnpm-authgenerate-cant-reach-the-database)
- [`db:watch` or `db:commit` fails with `42P07` relation already exists](#dbwatch-or-dbcommit-fails-with-42p07-relation-already-exists)
- [`pnpm db:codegen` produces an empty DB type](#pnpm-dbcodegen-produces-an-empty-db-type)
- [The `DB` type contains `GraphileMigrate*` tables](#the-db-type-contains-graphilemigrate-tables)
- [`pnpm db:watch` never exits](#pnpm-dbwatch-never-exits)
- [Build fails in `components/ui/calendar.tsx`](#build-fails-in-componentsuicalendartsx)
- [Port 5432 already in use](#port-5432-already-in-use)
- [Postgres data disappears after a rebuild](#postgres-data-disappears-after-a-rebuild)
- [`shadcn init` fails](#shadcn-init-fails)

---

## `better-auth/plugins` has no export named `apiKey`

**Cause.** The plugin was extracted into its own package. It wasn't deleted and
it wasn't renamed — `better-auth/plugins` simply no longer re-exports it.

**Fix.** Install `@better-auth/api-key` and import from it directly:

```ts
import { apiKey } from '@better-auth/api-key';          // server, in auth.ts
import { apiKeyClient } from '@better-auth/api-key/client';  // client
```

`admin` and `anonymous` still come from `better-auth/plugins` and
`better-auth/client/plugins`.

Do **not** resolve this by downgrading `better-auth` to a version where the
barrel still had `apiKey`. That trades a one-line import fix for a stale runtime.
If another plugin goes missing later, check for its package the same way:

```bash
npm view @better-auth/<plugin-name> version
```

---

## `migrations/current.sql` is missing a plugin table

**Symptom.** `pnpm auth:generate` succeeds, but the generated SQL has no table
for a plugin you configured — typically `apikey`.

**Cause.** `@better-auth/cli` releases behind `better-auth`. Usually that gap is
harmless, but a CLI old enough to predate a plugin can't emit that plugin's
schema, and it reports success anyway.

**Fix.** Check what you actually got before applying it:

```bash
test -s migrations/current.sql && grep -oE 'create table "[a-z]+"' migrations/current.sql
```

You want `user`, `session`, `account`, `verification`, and `apikey`. If one is
missing, try `pnpm dlx @better-auth/cli@beta generate --yes --output migrations/current.sql`.
Don't hand-write the missing table — the schema has to match what the runtime
adapter expects, and guessing at column names produces failures at sign-in time
rather than at migration time.

---

## `forgetPassword` does not exist on the auth client

**Cause.** The method is `requestPasswordReset`. The old name was removed.

**Fix.** Rename it in `lib/auth-client.ts`.

Worth knowing why this one hides: the auth client is a runtime `Proxy`, so
`Object.keys()` on it returns nothing and a bad method name looks fine until
something calls it. The type checker is what catches this, which is why the
verify step runs `pnpm typecheck` instead of trusting a 200 from the dev server.

---

## ESLint can't resolve `eslint-config-next`

**Symptom.** Something like `Cannot find module '.../eslint-config-next/core-web-vitals'
imported from eslint.config.mjs`, with a hint about adding `.js`.

**Cause.** Almost always a Next version mismatch: `create-next-app` generated a
flat config for the version it installed, and something then changed the Next
version underneath it. Older `eslint-config-next` is CommonJS with no `exports`
map, so the extensionless subpath import can't resolve — and its configs are
legacy eslintrc objects that can't be spread into a flat config either.

**Fix.** Get `next` and `eslint-config-next` back onto the same version, and
prefer doing that by scaffolding at the version you want rather than by
downgrading afterwards. If you genuinely must run an older Next, the matching
config uses `FlatCompat` from `@eslint/eslintrc` instead of direct imports.

Don't expect `pnpm build` to reveal this. Recent Next majors dropped linting from
`next build` entirely, so a broken ESLint config never surfaces there — `pnpm
lint` is the only thing that shows it. (Older majors printed the error mid-build
and then continued to a successful-looking summary, which was its own trap.)
Either way, a green build tells you nothing about lint.

---

## `pnpm lint` fails on a freshly scaffolded project

**Symptom.** A scaffold nobody has written code in yet reports ESLint errors.
Typically some combination of:

- `.gmrc.js` — `A require() style import is forbidden` (`@typescript-eslint/no-require-imports`)
- `components/ui/carousel.tsx`, `hooks/use-mobile.ts` — `Calling setState
  synchronously within an effect` (`react-hooks/set-state-in-effect`)
- `lib/db.ts` — `Unused eslint-disable directive`

**Cause.** All three are generated code meeting rules written for hand-authored
code. `.gmrc.js` genuinely must use `require()` — graphile-migrate loads it as
CommonJS. The shadcn components are vendored upstream. And the `eslint-disable`
in older copies of the `lib/db.ts` template refers to rules the current Next
config doesn't even enable, so the directive itself warns.

**Fix.** Step 6 adds the two narrow override blocks that cover the first two, and
the current `lib/db.ts` template no longer carries the stale directive. If you're
looking at a project scaffolded before those changes, add the overrides and drop
the directive.

**If you already added the overrides and lint still fails, check where they are.**
They have to be the *last* entries in the exported array. ESLint flat config is
last-match-wins, so anything above `...nextVitals` / `...nextTs` gets overridden
straight back by them — the config reads correctly and does nothing. Moving the
identical blocks from the top of the array to the bottom is the whole fix.

Resist widening this into blanket rule-disabling or an `ignores` on
`components/**`. The user is about to write code in this project, and rules
switched off to quiet generated files stay off for everything they write next.

---

## Peer dependency warning about `@better-fetch/fetch`

**Symptom.** pnpm warns that `@better-auth/core` wants an exact
`@better-fetch/fetch` version but found a newer one.

**Cause.** better-auth pins its peer tightly; pnpm hoists a newer release.

**Fix.** Nothing. This is cosmetic — the scaffold type-checks, builds, and serves
auth requests through it. Don't downgrade to silence it.

---

## graphile-migrate refuses to start

**Symptom.** It exits complaining that connection strings must differ.

**Cause.** `DATABASE_URL`, `SHADOW_DATABASE_URL`, and `ROOT_DATABASE_URL` are
not all distinct. graphile-migrate drops and recreates the shadow database, so
overlapping strings risk destroying the real one — the refusal is a safety
check, not a bug.

**Fix.** In `.env`, keep three distinct targets: `postgres` for the app,
`postgres_shadow` for the shadow, and `template1` for root/maintenance.

---

## Every `db:*` script fails to connect

**Symptom.** Connection errors that read as though no database exists, even
though Docker reports the container healthy.

**Cause.** Usually `.gmrc.js` is missing its first line. graphile-migrate does
not load `.env` on its own, so without `require('dotenv/config')` every
connection string is `undefined`.

**Fix.** Confirm `.gmrc.js` starts with `require('dotenv/config');`, and that
`dotenv` is in `dependencies`.

---

## `pnpm auth:generate` can't reach the database

**Cause.** Postgres isn't up yet, or came up after the command started. Better
Auth's `pg` adapter introspects the live database to diff the schema — there's
no offline mode with this adapter.

**Fix.** The stack needs to be up and healthy before this can work. Starting it
is the user's step, so ask rather than running it yourself:

```bash
pnpm docker
```

Then confirm what's actually running before retrying:

```bash
pnpm docker:ps
```

The script carries `-a`, so a stopped stack shows as `Exited (0)` rather than
an empty table — that state means "started earlier, stopped since", and the fix
is just `pnpm docker` again (restarting the same containers is idempotent). An
empty table means the stack was never created.

Use the scripts rather than a raw `docker compose`. Every compose call for this
project needs `--env-file .env` or `${POSTGRES_PASSWORD}` interpolates to an
empty string; the `docker:*` scripts carry the flag so it can't be dropped. If
you do invoke compose directly, pass it yourself.

---

## `db:watch` or `db:commit` fails with `42P07` relation already exists

**Symptom.** `pnpm db:watch --once` or `pnpm db:commit` dies with SQL error
`42P07`. The output echoes the whole migration body before the error, so the
last SQL line shown (often an index) is usually *not* the failing statement —
the first `create table` is.

**Cause.** `current.sql` isn't idempotent, and graphile-migrate's execution
model assumes it is. Two paths trigger it, both observed live:

- **Any byte change** to an applied `current.sql` — even whitespace — makes
  `watch` re-run the *entire file*, not a diff. Plain `create table` then fails
  on the first table that already exists. The run is transactional, so the
  user's newly added statements roll back too.
- **`db:commit` re-executes the migration against the real database by design**
  (the log shows `Running migration '000001.sql'` for both shadow and real).
  So even a byte-identical, never-edited `current.sql` fails at commit time if
  its DDL isn't re-runnable.

This is why step 8b exists: the Better Auth CLI emits plain
`create table` / `create index`, which violates graphile-migrate's documented
contract that `current.sql` be re-runnable.

**Worse state.** A *failed* commit rolls back the migration but deletes
graphile-migrate's `graphile_migrate.current` bookkeeping row (the file itself
is restored). After that, even the unchanged file counts as "changed" and both
`watch` and `commit` fail every time. Diagnose with:

```bash
docker exec <app-name>-postgres psql -U postgres -d postgres -tA \
  -c "select count(*) from graphile_migrate.current"
```

**Fix.** Make the file idempotent and re-run — this is also the full recovery
from the stranded state, verified live:

```bash
perl -i -pe 's/^create ((?:unique )?index|table) /create $1 if not exists /' migrations/current.sql
pnpm db:watch --once   # every statement no-ops against existing tables
pnpm db:commit         # now passes shadow + real, freezes 000001.sql
```

Do **not** recover by re-running `pnpm auth:generate`: it diffs against the
live database, so with all tables present it emits an empty file — commit would
then freeze an *empty* migration and the auth schema would never reach
`migrations/committed/`, breaking `db:reset` and `db:migrate` on every other
environment.

And going forward, the same contract applies to SQL the user writes: additions
to `current.sql` must be idempotent (`create table if not exists`,
`create or replace function`) until they're frozen by `db:commit`.

---

## `pnpm db:codegen` produces an empty DB type

**Cause.** Codegen reads whatever is actually in the database. If migrations
haven't been applied, there are no tables to read, so an empty type is the
correct output for the current state.

**Fix.** Run the steps in order — `pnpm auth:generate`, the step 8b idempotency
transform, `pnpm db:watch --once`, then `pnpm db:codegen`. Confirm
`migrations/current.sql` is non-empty before applying it.

---

## The `DB` type contains `GraphileMigrate*` tables

**Symptom.** `lib/db-types.ts` has seven interfaces instead of five —
`GraphileMigrateCurrent` and `GraphileMigrateMigrations` alongside the auth
tables.

**Cause.** kysely-codegen reads every schema in the database, and once
migrations have run, graphile-migrate's bookkeeping tables exist. Harmless but
noisy, and it invites queries against tables the app has no business touching.

**Fix.** The `db:codegen` script carries
`--exclude-pattern graphile_migrate.*` to prevent this. If you're seeing the
extra interfaces, the script predates that flag — add it and re-run
`pnpm db:codegen`.

---

## `pnpm db:watch` never exits

**Cause.** `db:watch` is a foreground watcher by design.

**Fix.** Use `pnpm db:watch --once` to apply and exit. Bare `db:watch` is for
interactive schema iteration, where it re-applies `current.sql` on every save —
useful for a human, a hang for an agent.

---

## Build fails in `components/ui/calendar.tsx`

**Symptom.** `pnpm build` type-checks fine everywhere else but errors inside the
generated calendar component.

**Cause.** `shadcn add --all` can pull a `react-day-picker` major whose API the
generated component isn't written against. This is an upstream mismatch between
two third-party packages — nothing about the scaffold caused it, and compilation
itself succeeds.

This did not reproduce on the last verification run, so treat it as intermittent
and version-dependent rather than expected.

**Fix.** Report it rather than silently patching. Options, in rough order of
preference: delete `components/ui/calendar.tsx` if the project doesn't need a
calendar; pin `react-day-picker` to the line the component expects; or update the
component to the newer API. Don't let this one failure convince you the whole
scaffold is broken — check whether anything else fails first.

---

## Port 5432 already in use

**Cause.** Another Postgres — a different project's container, or a system
install — already holds the port.

**Fix.** Ask before touching the other service. Remapping this project is
usually right: change the host side of the mapping in `docker/compose.dev.yml`
(e.g. `"5433:5432"`) and update the port in all three connection strings in
`.env`. Stopping the user's other container is a side effect they didn't ask
for.

Note that this also makes parallel scaffolds impossible on one machine — every
project in this stack claims 5432, 6379, 1025, and 8025. Run them one at a time,
or remap before starting the second.

---

## Postgres data disappears after a rebuild

**Cause.** The volume is mounted at the wrong path. Postgres 18 stores data in a
version-numbered subdirectory, so mounting `/var/lib/postgresql/data` — correct
for older images — persists the wrong directory.

**Fix.** Mount the parent: `postgres-data:/var/lib/postgresql`.

---

## `shadcn init` fails

**Cause.** Usually an incompatible Node version, occasionally a `components.json`
left over from a partial run.

**Fix.** Check `node --version` against the shadcn requirement, remove any
partial `components.json`, and re-run. If `add --all` fails partway, it's safe to
re-run — it skips components already present.
