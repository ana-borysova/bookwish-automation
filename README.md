# bookwish-automation

Operational automation for the BookWish application — a daily backup of the book
catalogue from Supabase, built with n8n running in Docker.

The repository is deliberately separate from the application: this is
infrastructure, not product code.

## What it does

Every day at 21:00 (Europe/Kyiv) n8n takes a `pg_dump` of the `books` table from
the Supabase database, writes the file to a folder on disk, and deletes copies
older than 30 days. If anything fails, it sends a message to Telegram.

The daily schedule serves a second purpose: the Supabase free tier pauses a project
after 7 days of inactivity, and the backup is itself that activity.

## Requirements

- Docker Desktop
- A Supabase project with a `books` table
- A Telegram bot (for failure notifications)

## Getting it running

```bash
cp .env.example .env
# open .env and paste the Supabase connection string
docker compose up -d --build
```

n8n is then available at <http://localhost:5678>.

Dumps are written to `../bookwish-backups` — a folder next to the repository,
outside git.

## Restoring from a dump

The dump is plain SQL including the table structure, so restoring is a single
command:

```bash
psql "$SUPABASE_DB_URL" -f bookwish-backups/books-2026-08-28-2100.sql
```

Restoring back into Supabase is that one command.

Restoring into a **plain Postgres** instance needs a preparation step first,
because the dump carries Supabase's own furniture along with the table: grants to
the `anon`, `authenticated` and `service_role` roles, row-level security with two
policies, and a `created_by` column that defaults to `auth.uid()`. Without the
preparation the restore fails on `CREATE TABLE`, before any data is reached:

```
ERROR:  schema "auth" does not exist
LINE 11:     created_by uuid DEFAULT auth.uid()
```

Run this against the empty database first:

```sql
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;

CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$ SELECT NULL::uuid $$;
```

The `auth.uid()` stub can return `NULL`: it is never evaluated during a restore,
because `COPY` supplies every `created_by` value explicitly. It only has to exist so
that Postgres can parse the table definition and the two policies.

**Verified 2026-08-28** against a throwaway `postgres:17-alpine` container: 27 books
restored, both policies present, row-level security on, grants intact.


## Secrets

`.env` never reaches git — see `.gitignore`. The Telegram bot token does not live
here either; it lives in n8n's own Credentials store.

In the Execute Command node the connection string is written as
`"$SUPABASE_DB_URL"`: the shell inside the container expands it, not an n8n
expression, so the password never lands in workflow execution logs.

The exported workflow JSON under `workflows/` carries no secrets either: the
Telegram credential appears there as a reference — an id and a name — never as a
token. The chat ID is replaced with a placeholder before committing. It is not a
credential, and on its own it lets nobody message you, but it is a stable personal
identifier and the repository has no use for it.

## Layout

```
Dockerfile           n8n image + pg_dump copied in from an Alpine builder stage
docker-compose.yml   service, named volume, backup folder mount
.env.example         variable template
docs/decisions.md    decision log: what was decided, why, what was rejected
docs/                workflow specification
workflows/           exported n8n workflow JSON
```

n8n workflows live in n8n's internal database inside the Docker volume. They reach
the repository only by exporting them to JSON by hand — otherwise the repository
shows the infrastructure but not the automation itself.
