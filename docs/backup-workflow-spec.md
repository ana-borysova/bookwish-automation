# Specification: workflow A — daily backup of the book catalogue

Date: 2026-08-28. Status: approved, in implementation.

The reasoning behind these choices is not repeated here — it lives in
[`decisions.md`](decisions.md). This document describes **what is being built**,
not why it was chosen.

---

## 1. Purpose

Take a daily copy of the `books` table from the Supabase database of the BookWish
project, store it on the laptop disk, keep the last 30 days of copies, and notify
the owner when it fails.

A secondary but mandatory function: the daily hit against the database keeps the
free Supabase project active (it is paused after 7 days of inactivity).

## 2. Scope

**In scope:** the `public.books` table — structure and data.

**Out of scope:** `wishlist_item`, `profiles`, Supabase system schemas (`auth`,
`storage`, `realtime`). Uploading the copy to cloud storage. Automated
restore-verification.

**Consequence:** restoring from this backup brings the book catalogue back in full;
wishlists and profiles do not come back.

## 3. Infrastructure

| Component | Decision |
|---|---|
| Orchestrator | n8n in Docker, locally on the laptop |
| Image | custom: n8n `2.36.8` + `pg_dump` copied in from an `alpine:3.24` builder stage |
| n8n state | named volume `n8n_data` mounted at `/home/node/.n8n` |
| Dump folder | `../bookwish-backups` on the host → `/backups` in the container |
| Time zone | `Europe/Kyiv` (`TZ` and `GENERIC_TIMEZONE`) |
| Restart policy | `unless-stopped` |
| Blocked nodes | `NODES_EXCLUDE` restated as `["n8n-nodes-base.localFileTrigger"]` — Execute Command is blocked by default from n8n 2.0 |
| Access | <http://localhost:5678> |

The dump folder sits outside the repository. Copies never reach git.

## 4. Secrets

| Secret | Where it lives | Who enters it |
|---|---|---|
| `SUPABASE_DB_URL` | `.env` on disk, excluded from git | the owner |
| Telegram bot token | Credentials inside n8n | the owner |

The connection string comes from the Supabase **Session pooler**. The Transaction
pooler (port 6543) is not suitable: `pg_dump` needs a stable session. The direct
connection is not suitable either — verified 28.08, `db.<project-ref>.supabase.co`
has an AAAA record and no A record, so it is reachable only over IPv6, which the
container does not have.

In the Execute Command node the variable is written as `"$SUPABASE_DB_URL"` — the
shell inside the container expands it, not n8n. The value never appears in
execution logs.

## 5. Workflow A — steps

1. **Schedule Trigger** — daily at 21:00.
2. **Execute Command — dump.** `pg_dump` of `public.books` as plain SQL, including
   the table structure rather than data only.
   It writes to a temporary file and renames it to `.sql` only after a successful
   finish. Otherwise a dump interrupted midway would leave a file in the folder
   that looks like a backup but is not one.
3. **Execute Command — rotation.** Delete `books-*.sql` older than 30 days.
4. **Failure branch** — see section 6.

**Filename:** `books-YYYY-MM-DD-HHMM.sql`, for example `books-2026-08-28-2100.sql`.
Date and time in the name are mandatory: two n8n instances must not overwrite each
other.

## 6. Failure notification

A separate utility workflow: **Error Trigger** → **Telegram**. It is assigned as
the Error Workflow in workflow A's settings, after which n8n runs it automatically
on failure.

**Coverage limit:** this catches "it ran and it broke". It cannot catch "it never
ran because the laptop was off" — there is nothing to fail. That gap is accepted
deliberately (see `decisions.md`, 26.08).

## 7. Definition of done

The workflow counts as finished when **all three** conditions hold:

1. It ran on schedule with no manual trigger, and the file is in the folder.
2. A deliberately broken password produced a Telegram message.
3. The dump has **actually been restored**: `psql -f` executed against a throwaway
   container running clean Postgres, books present, container torn down.

The third condition is not a formality: by the 28.08 decision, a dump that cannot
be restored with a single command is an export, not a backup.

**Status as of 28.08:**

| # | Condition | State |
|---|---|---|
| 1 | Ran on schedule, no manual trigger | workflow published and active, `triggerAtHour: 21` — waiting for the first unattended run |
| 2 | Broken password produced a Telegram message | not started — the bot comes after the dump works |
| 3 | The dump has actually been restored | **met.** Restored into a throwaway `postgres:17-alpine`: 27 books, both policies, RLS on, grants intact, container torn down |

Manual run on 28.08 produced `books-2026-08-28-1735.sql`, 9748 bytes, 27 rows,
byte-identical to a dump taken by hand apart from the two random `\restrict`
tokens.

## 8. Open questions

These are not gaps in the design — they are things more honestly verified than
guessed. Closed ones keep their answer here instead of disappearing.

- **`pg_dump` version** — **closed 28.08.** The header of a real dump reads
  "Dumped from database version 17.6 / Dumped by pg_dump version 17.11". The client
  is newer than the server, which is the condition `pg_dump` imposes. The
  `Dockerfile` needs no change.
- **Write permissions on the dump folder** — **closed 28.08.** A container from the
  built image, with the same mount, created and then deleted a file in `/backups`
  as user `node`. The Windows bind mount permits writes.
- **Whether the Execute Command node treats a non-zero exit code as a failure** —
  open. If it does not, the workflow would finish "successfully" with a broken
  backup, and a node performing an explicit exit-code check has to be added.
  Verified with a deliberately broken password.
- **Restoring into clean Postgres** — **closed 28.08, proven both ways.** Without
  preparation the restore fails at `CREATE TABLE`, before a single row:
  `ERROR: schema "auth" does not exist`. With three empty roles and an `auth` schema
  holding an `auth.uid()` stub, it restores with exit code 0 and no errors: 27
  books, both policies, row-level security on, grants intact. The stub may return
  `NULL` — it is never evaluated, because `COPY` supplies every `created_by` value.
  The procedure is in the README.

## 9. What goes into the repository

`Dockerfile`, `docker-compose.yml`, `.env.example`, `.gitignore`, `README.md`,
`docs/`, and — once the workflow is assembled — exported JSON under `workflows/`.

Exporting is manual: n8n keeps workflows in its own database inside the volume and
never puts anything into git by itself.
