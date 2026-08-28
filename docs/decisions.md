# Decision log — bookwish-automation

Format: date · decision · why · what was rejected.

---

## 2026-08-25 · Separate repository

The automation lives in its own repository, not inside the BookWish application.

**Why:** the goal is a portfolio and CV piece, not utility for the app. A separate
repository reads as a self-contained case study and keeps operational scripts out
of the product code.

## 2026-08-25 · Scope: two workflows, A before B

- **A** — daily Supabase backup at 21:00.
- **B** — email notification when a book is reserved.

A must be finished and pushed before B starts.

**Why:** A removes a real risk (data loss), B is an experience improvement.
Risk first, comfort second.

## 2026-08-25 · Rejected: n8n for book search

**Why:** n8n is an orchestrator, not a search engine. Search problems are fixed by
editing `src/services/booksApi.ts` in the application. A workflow sitting on the
user's critical path would add latency and make debugging harder.

## 2026-08-25 · Rejected: cover enrichment by ISBN

**Why:** `src/lib/coverUrl.ts` already builds Open Library links at render time.
Database state as of 2026-08-25: 26 books, of which 0 have neither a cover nor an
ISBN. The problem such a workflow would solve does not exist.

## 2026-08-26 · Hosting: locally in Docker

n8n stays in Docker on the working laptop.

**Why:** the laptop is on almost all the time, the project is a learning exercise,
and paying for cloud or a VPS makes no sense right now.

**Accepted trade-off:** while the laptop is off, no backups happen. These gaps are
accepted deliberately. A spare machine with Docker is a manual failover for the
future, not for now.

**Future constraint:** never run two instances at once — they would produce two
dumps and fight over one filename. Hence manual failover, and backup filenames
carry a date and time.

## 2026-08-26 · Backup frequency is daily, and it doubles as keep-alive

No separate keep-alive job for Supabase.

**Why:** the Supabase free tier pauses a project after 7 days of inactivity. A
daily backup is itself that activity, so it keeps the database alive with six days
to spare. A second "every 5 days" process would duplicate a guarantee we already
have and leave only two days of slack if something fails.

**Important:** if the backup frequency ever changes, this decision breaks in two
places at once. Daily is not only about the freshness of the copy.

**Constraint:** the workflow must have a failure-notification branch. A silent
error costs both the backup and the live database.

## 2026-08-28 · The dump is taken by `pg_dump` in a custom image

The backup is taken with the real `pg_dump`, not by a node reading tables out.

**How:** a custom `Dockerfile` based on the official n8n image with
`postgresql-client` added. The official image does not ship `pg_dump`.

**Why:** a dump that cannot be restored with a single command is an export, not a
backup. On top of that, a custom `Dockerfile` is something concrete to discuss in
an interview.

**Rejected:** a Postgres node reads the tables and writes JSON. Simpler on day one,
but restoring then needs a separate script, which also has to be written and tested.

## 2026-08-28 · The copy goes to Google Drive, not just the laptop disk

The finished dump is uploaded by a Google Drive node.

**Why:** a backup sitting on the same laptop as the Docker host running n8n does
not protect against that disk dying. That is a single copy, not a backup copy.
The node is free.

**Still in force:** filenames carry date and time — the 26.08 decision about two
instances has not gone anywhere.

## 2026-08-28 · Part one — no Google Drive, copy on the laptop disk only

In its first iteration workflow A finishes with a ready dump in a folder on the
laptop. The Google Drive upload moves to a separate task at the end of the queue.

**Why:** the goal of part one is to learn n8n, not to build reliable storage.
Google Drive adds an OAuth connection and an external dependency that teach nothing
about n8n, while adding places where things break before the first successful dump.

**Relation to the 28.08 decision "The copy goes to Google Drive":** this does not
revoke it, it defers it. That decision's argument stands in full: a copy on the
same disk as the Docker host running n8n does not protect against disk failure.

**Accepted trade-off:** until Drive is connected this is not a backup in the full
sense — it is one copy sitting next to the original working environment.
Deliberately accepted for the duration of the learning phase.

**Closing condition:** Google Drive returns as a separate task once workflow A runs
reliably.

## 2026-08-28 · Failure notification — Telegram bot

The notification branch required by the 26.08 decision is implemented as a separate
utility workflow with an Error Trigger node that sends a message to Telegram.

**Why:** this is a real push to a phone, so the condition "no notification, no
finished workflow" is met in substance rather than on paper. It costs one secret
(the bot token) and a few minutes in BotFather. It also walks through the basic n8n
path of "create a credential → wire it into a node".

**Rejected — reading execution logs in n8n manually:** zero setup, but it is not a
notification. Forget to look, and the error is silent again — exactly what the
26.08 decision was written against.

**Rejected — email over SMTP:** working with the email node is the learning content
of workflow B. Spending it here means arriving at B with no new material. On top of
that, Gmail would require an app password — another secret.

**Coverage limit, accepted deliberately:** the branch only catches "it ran and it
broke". It cannot catch "it never ran because the laptop was off" — there was
nothing to fail. This is the same gap accepted in the 26.08 hosting decision.

## 2026-08-28 · Dump scope — the `books` table only

The backup takes a single table from the `public` schema: `books`. Not
`wishlist_item`, not `profiles`, and none of the Supabase system schemas
(`auth`, `storage`).

**Why (business):** the value of the project is the book catalogue. A wishlist
without profiles is meaningless, and profiles without users equally so, so "a
little more data" turns immediately into "pull the whole database including
accounts". At the learning stage that is unnecessary complexity.

**Why (technical, verified 28.08 in the application repository):** `public` holds
three tables — `books`, `wishlist_item`, `profiles`. Dependencies run one way:
`wishlist_item` → `books` and `wishlist_item` → `profiles`. The `books` table
references nothing: `id`, `google_books_id`, `title`, `authors`, `thumbnail`,
`year`, `publisher`, `page_count`, `isbn`. Cutting at `books` therefore leaves no
dangling references — the dump is self-contained and restores cleanly.

**Consequence, accepted deliberately:** restoring from such a backup does not bring
back wishlists or profiles. It brings back the book catalogue in full.

## 2026-08-28 · Retention — keep 30 days

Dumps older than 30 days are deleted automatically by a step in the workflow.

**Why:** the rollback window has to cover more than "the database vanished
yesterday". It has to cover slow data corruption, which is not noticed right away.
A month is a realistic period in which to spot that something is wrong with the
catalogue in a learning application that is not opened every day.

**Why not "keep everything":** rotation is what separates a backup from a pile of
files in a folder, and it costs exactly one step in the workflow.

**What is NOT the reason:** disk space. A dump of the `books` table is 10–30 KB, and
a year of daily copies comes to roughly 10 MB. The "do not fill up the disk"
argument does not apply at this scale, and this decision must not be revisited on
that basis.

**Format and location (implementer's technical call):** plain SQL including the
table structure, not data only, so that restoring into an empty project is a single
command. The dump folder lives outside the repository so copies cannot reach git.

## 2026-08-28 · Division of logic — n8n orchestrates, the shell does the work

Workflow A consists of a schedule, a `pg_dump` step, a step that clears out old
files, and a notification branch. Each step is a short shell command in an Execute
Command node. Rotation is not assembled out of n8n nodes, nor extracted into a
separate script.

**Why:** n8n is learned where it actually is an orchestrator — scheduling,
sequencing, error handling. Complexity should appear where it buys something.

**Rejected — rotation built from n8n nodes (`ls` → Code → loop → delete):** a wider
slice of n8n, but a one-line shell task stretched across five nodes. That teaches
fighting n8n rather than using it. The Code node will be genuinely needed in
workflow B, where the email body has to be assembled from data.

**Rejected — all logic in `backup.sh`, with n8n only triggering it:** the script
would sit better in git, but n8n degrades into cron and never gets learned. Also,
on screen a BA would see a single "run the script" node — the picture stops being
readable.

**Consequence:** the workflow lives in n8n's internal database inside the Docker
volume, not in the repository. Getting it into git requires exporting it to JSON by
hand (Download in the workflow menu) and committing the file. Without that the
repository shows the infrastructure but not the automation itself.

---

# Status as of 2026-08-28 and start plan

Verified today:

- the repository `E:/Study/TrainingProjects/bookwish-automation` exists; **git is
  not initialised** and there is no remote;
- **Docker Desktop is installed** (4.88.1, CLI 29.7.2), but the application has not
  been started yet — the engine does not answer.

Order of work:

1. Install Docker Desktop. — **done**
2. `git init` + first commit + push to GitHub.
3. Bring up n8n in a container with a named volume so workflows survive restarts.
4. Custom `Dockerfile`: n8n image + `postgresql-client`.
5. Workflow A: Schedule 21:00 → `pg_dump` → file in a folder on disk →
   **failure-notification branch** (the condition from the 26.08 decision; without
   it the workflow does not count as finished).
6. Only once A works and is pushed — workflow B.
7. As a separate task at the end — uploading the dump to Google Drive
   (28.08 decision).

BookWish side (separate repository, not this one): search redesign merged (PR #25),
wishlist cleanup merged (PR #26). Next there — validation for manually adding a
book, then the error block.
