# new

Two shell scripts that scaffold new projects with opinionated defaults — pnpm, PostgreSQL, and Better Auth, wired up and ready to run.

| Script                                 | Scaffolds                                                                   | Database layer                | Docs                             |
| -------------------------------------- | --------------------------------------------------------------------------- | ----------------------------- | -------------------------------- |
| [`next/new-next.sh`](next/new-next.sh) | Next.js (App Router, TypeScript, Tailwind, shadcn/ui, Vercel AI SDK, Jotai) | Kysely + graphile-migrate     | [next/README.md](next/README.md) |
| [`nest/new-nest.sh`](nest/new-nest.sh) | NestJS (TypeScript, `@thallesp/nestjs-better-auth`)                         | Prisma + `@prisma/adapter-pg` | [nest/README.md](nest/README.md) |

Both produce projects using **pnpm**, **PostgreSQL**, and **Better Auth** with the admin / apiKey / anonymous plugins enabled. They differ in the database layer, and only the Next.js script generates a Docker Compose stack.

## Repository Layout

```text
new/
├── next/
│   ├── new-next.sh    # Next.js scaffolding script
│   └── README.md      # Full Next.js documentation
├── nest/
│   ├── new-nest.sh    # NestJS scaffolding script
│   └── README.md      # Full NestJS documentation
└── README.md          # You are here
```

## Prerequisites

- Node.js installed
- pnpm installed
- Docker (for the Next.js script's local Postgres / Redis / Mailpit stack)
- openssl (optional, for generating a random Better Auth secret)

## Installation

1. **Clone the repository**

   ```bash
   git clone <repo-url> ~/Projects/new
   cd ~/Projects/new
   ```

2. **Make the scripts executable**

   ```bash
   chmod +x next/new-next.sh nest/new-nest.sh
   ```

3. **(Optional) Add to PATH for global access**

   Symlinking is preferred over moving the files — the scripts stay in the repo, so `git pull` keeps them up to date:

   ```bash
   ln -s ~/Projects/new/next/new-next.sh ~/.local/bin/nnx
   ln -s ~/Projects/new/nest/new-nest.sh ~/.local/bin/nns
   ```

   Then run them from anywhere:

   ```bash
   nnx awesome-next-project
   nns awesome-nest-project
   ```

   > [!TIP]
   > Make sure `~/.local/bin` is on your `PATH`. If it isn't, add
   > `export PATH="$HOME/.local/bin:$PATH"` to your `~/.zshrc`.

   > [!IMPORTANT]
   > Use `ln -sf` to **re-point** these symlinks whenever a script moves within the
   > repo. A symlink to a moved file dangles silently — you get
   > `no such file or directory`, not a helpful error.

   If you'd rather copy the scripts into a system directory instead of symlinking,
   note that they'll no longer track the repo and you'll need to re-copy after updates:

   ```bash
   sudo cp next/new-next.sh /usr/local/bin/new-next
   sudo cp nest/new-nest.sh /usr/local/bin/new-nest
   ```

## Quick Start

Run a script from its own directory, or via the symlink from anywhere:

```bash
# Next.js — supports --dry-run to preview without creating anything
cd next && ./new-next.sh my-nextjs-app
./new-next.sh --dry-run my-nextjs-app

# NestJS — no flags, runs straight through
cd nest && ./new-nest.sh my-nestjs-app
```

The scripts create the new project as a subdirectory of wherever you run them, so `cd` to the parent directory you want the project to live in first (or use the symlinks).

Each script prints its own post-setup steps when it finishes. Full details:

- **[Next.js documentation →](next/README.md)** — flags, all 8 setup steps, version pinning rationale, post-setup DB flow, feature list
- **[NestJS documentation →](nest/README.md)** — setup steps, Prisma configuration, post-setup migrations, feature list

## Troubleshooting

Issues common to both scripts:

- **Permission denied**: Run `chmod +x next/new-next.sh nest/new-nest.sh`
- **Command not found after symlinking**: Confirm `~/.local/bin` is on your `PATH`
- **Broken symlink**: If you moved or renamed the repo, recreate the symlinks with the new paths
- **pnpm not found**: Install pnpm globally with `npm install -g pnpm`
- **Script fails mid-way**: The scripts are not idempotent — they don't roll back. Delete the partially created project directory and re-run rather than resuming
- **A freshly scaffolded project won't build**: Usually an upstream package publishing a breaking `latest`. The Next.js script pins `next`, `better-auth`, and `kysely` for exactly this reason — see the [version pinning note](next/README.md#step-2-installs-dependencies)

Script-specific issues are covered in [next/README.md](next/README.md#troubleshooting) and [nest/README.md](nest/README.md#troubleshooting).
