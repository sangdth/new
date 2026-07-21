# Provenance and verification record

Read this before re-adding a version pin, before trusting a claim in `SKILL.md`
that a step has been verified, or when trying to work out why the scaffold is
shaped the way it is.

## Contents

- [Self-contained by design](#self-contained-by-design)
- [Why nothing is pinned](#why-nothing-is-pinned)
- [Verification record](#verification-record)

---

## Self-contained by design

Everything this skill needs is in `SKILL.md` and `references/`. It shells out
only to `pnpm`, `docker`, and the public npm registry, and reads no other
scaffolding tool, script, or repository. There is no companion artifact to keep
in sync — if something here is wrong, fix it here.

This wasn't always true. An earlier version mirrored a shell script and told
readers that when the two disagreed, the script was authoritative. They drifted,
the skill became the more correct of the two, and that instruction started
pointing at the worse artifact. Hence: one source, no mirror.

---

## Why nothing is pinned

Worth remembering, because the instinct to re-add pins comes back.

An earlier version froze `next`, `better-auth`, and `kysely`.

**The `next` pin** was added when `latest` briefly resolved to a preview whose
SWC binary was never published, so `dev` and `build` died fetching it. That
stopped being true — the tag moved on to a stable release with published
binaries — but the pin stayed. And because it downgraded Next *after*
`create-next-app` had already generated config for a newer major, it produced a
broken `eslint.config.mjs` and silently dropped `--turbopack` from the `dev`
script. **The pin outlasted the bug it was defending against and became the
bug.**

**The `better-auth` pin** was aimed at `apiKey` vanishing from the
`better-auth/plugins` barrel export. But the plugin had been extracted into its
own `@better-auth/api-key` package, not removed — a one-line import change
misdiagnosed as a version problem, and "fixed" by holding the whole auth library
two minors back.

**The `kysely` pin** existed only to satisfy the older better-auth's peer range.
It had no independent reason at all, and became moot the moment the first pin
went.

The lesson generalizes past this stack: **a pinned version is a fact with an
expiry date.** A pin whose reason isn't written down outlives the problem it was
solving, and the workarounds built around it accumulate into worse damage than
the original bug. When `latest` really does break something, check the registry
rather than reasoning from memory — `npm view <pkg> dist-tags` and
`npm view <pkg>@<ver> version` settle most of these in seconds, and questions
like "is the platform binary actually published?" are directly checkable.

If you do pin, write down what would make the pin removable.

---

## Verification record

Keeping this honest matters more here than it looks, given everything above. A
stale claim about what has been tested rots exactly like a stale pin.

### 2026-07-20 run

Everything in this section on **2026-07-20**, against Next 16.2.10, better-auth
1.6.23, `@better-auth/api-key` 1.6.23, and kysely 0.29.4.

**Steps 1-6 and 8-11 — verified end to end.** All five auth tables generated
(`user`, `session`, `account`, `verification`, `apikey`), and a live
`POST /api/auth/sign-up/email` returned 200 with the expected `role` and
`isAnonymous` fields. So the CLI-lagging-the-runtime gap is confirmed harmless by
an actual write, not merely by a generate that didn't error.

**Step 6's ESLint overrides — verified as an instruction, not just as a fix.** An
agent with no prior knowledge of this stack followed step 6 from a fresh scaffold
and produced a working config on the first attempt, with `pnpm lint` coming back
silent. The counterfactual was measured on that same project: the pre-edit config
produced exactly three errors, the post-edit config zero. The overrides are doing
the work rather than decorating a config that was already clean.

Placement remains load-bearing — the identical blocks moved to the top of the
array reinstate all three errors, because flat config resolves last-match-wins.

**Step 7's handoff — exercised.** An agent with no user available correctly wrote
the full handoff rather than asking a question and ending its turn, and confirmed
the claim that stopping there is a legitimate finishing point: `tsc`, `lint`, and
`build` all pass with no database, against the placeholder `DB` type.

### 2026-07-21 run (test-nn-6, resumed across turns)

Same versions as above (Next 16.2.10, better-auth 1.6.23), full sequence
including a genuine turn boundary: Phase 1 in one turn, the user ran
`pnpm docker` themselves, work resumed at step 7 in a later turn.

**The resumption path — now walked, and it found a bug.** The stack had been
started and then stopped between turns. Bare `compose ps` printed an empty
table — byte-identical to "never started" — while `ps -a` showed all three
containers `Exited (0)`. That ambiguity is why `docker:ps` now carries `-a`
and why step 7 spells out the three states. Re-running `pnpm docker` restarted
the same containers (`Started`, not `Created`) to healthy in ~10s.

**The idempotency contract — discovered, confirmed, fixed, verified.** The
reason step 8b exists:

- Unchanged `current.sql` re-run: skipped via hash
  (`current.sql unchanged, skipping migration`).
- Any edit to an applied `current.sql`: graphile-migrate re-runs the whole
  file; the CLI's plain `create table` DDL fails `42P07`, and the transaction
  rollback takes the user's own addition with it.
- `db:commit` re-executes the migration against the **real** database by
  design (`Running migration '000001.sql'` logged for shadow and real) — so
  even the pristine, never-edited generated file cannot survive commit.
- A failed commit deletes the `graphile_migrate.current` row while restoring
  the file, stranding the project (watch *and* commit then always fail).
- The step 8b transform recovered that exact stranded state live: watch
  no-opped, commit passed shadow + real, `000001.sql` frozen, template
  `current.sql` written.

**`docker:down` volume safety — observed, no longer the weakest claim.** With a
real row in `user` (live sign-up), `pnpm docker:down` removed containers and
network, left both named volumes, and after `pnpm docker` the row and the
`graphile_migrate.migrations` record were intact. Data survives a full
down → up cycle.

**Also observed on this run:** sibling argument pass-through
(`pnpm docker:ps -a` before the flag was baked in); `db:codegen` including the
two `graphile_migrate` bookkeeping tables without `--exclude-pattern` and
exactly the five auth interfaces with it; the full verify suite green (tsc,
silent lint, build, homepage and `get-session` 200); and a live
`POST /api/auth/sign-up/email` returning 200 with `role: "MEMBER"` and
`isAnonymous: false`.

### 2026-07-21 run (test-nn-7, straight-through)

Same versions again (Next 16.2.10, better-auth 1.6.23, `@better-auth/api-key`
1.6.23, kysely 0.29.4, kysely-codegen 0.20.0, graphile-migrate 1.4.1), executed
as a single uninterrupted sequence with zero failures and zero deviations from
the skill as written.

**The happy-path ordering of 8b → 9 → 12 — now verified directly.** The
test-nn-6 run had only exercised the idempotency transform in recovery order
(after a `42P07`). Here the transform ran before first apply, as the skill
prescribes: 11/11 statements caught, `pnpm db:watch --once` applied clean,
`pnpm db:commit` passed shadow + real on the first attempt and froze
`000001.sql`, leaving the empty-template `current.sql`. The gap flagged in the
previous record is closed.

**Agent-run `pnpm docker` — the "run it yourself when asked" path walked.** The
user asked for the full sequence, the agent started the stack itself, and
`--wait` returned with all three services healthy in ~15s. A `docker ps -a`
pre-check first confirmed the previous scaffold's stack was stopped — the check
that motivated step 7's pre-flight sentence, since every project in this stack
claims the same four host ports.

**Also observed:** `shadcn add --all` produced 60 components with no
`calendar.tsx` build failure (react-day-picker 10 paired fine with the
generated component); step 3's claim that `init` adds `@base-ui/react`,
`@shadcn/react`, and `shadcn` to dependencies confirmed against the final
`package.json`; no `@better-fetch/fetch` peer warning on this version pair;
lint silent on the first attempt after the step 6 overrides; full verify green
(tsc, silent lint, build, homepage and `get-session` 200, and a live sign-up
200 with `role: "MEMBER"` and `isAnonymous: false`).

### Still unobserved

`pnpm db:reset`; `pnpm db:migrate` applying committed migrations on a second
environment; `docker:logs` pass-through specifically (`docker:ps` pass-through
was seen, and the mechanism is the same); a genuine port-conflict remap; and
the `openssl`-missing fallback.
