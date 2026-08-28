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

**Re-checked 28.08 against the live database, not the application repository.** The
central claim holds: a real dump of `public.books` contains no `FOREIGN KEY` and no
`REFERENCES` at all, so cutting at `books` still leaves nothing dangling. Two
corrections to the detail above, though:

- the column list was incomplete. The table also has `created_by uuid DEFAULT
  auth.uid()`. It is not a foreign key, so the conclusion stands, but the default
  calls a Supabase function that a plain Postgres does not have — which is a restore
  problem, not a scope problem, and is tracked in the specification;
- the dump is not only structure and data. It also carries row-level security with
  two policies and grants to `anon`, `authenticated` and `service_role`. That is
  desirable — restoring reinstates the access rules along with the catalogue — but
  it is what makes restoring into a bare Postgres more than a one-liner.

Dump size at 27 books: 9.7 KB, which keeps the 30-day retention decision's "disk
space is not the reason" argument comfortably true.

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

## 2026-08-28 · `pg_dump` gets into the image by copying, not by installing

The n8n image (2.36.8) turned out to be a **Docker Hardened Image**: it is Alpine,
but the package manager has been stripped out of it deliberately. There is no `apk`
inside and no `apt-get` either, so `apk add postgresql-client` cannot work in that
image in any form — not with a different version number, not with a different
package name.

**How it is done instead:** a multi-stage build. A throwaway stage on `alpine:3.24`
— the same Alpine version the n8n image is built on — installs
`postgresql17-client`, and the final stage copies two files across: the `pg_dump`
binary and `libpq.so.5`. The other five libraries `pg_dump` links against
(`libssl`, `libcrypto`, `libz`, `liblz4`, `libzstd`) are already inside the n8n
image in the same versions, precisely because the Alpine version matches. Nothing
n8n itself relies on is overwritten.

**Verified 28.08 in the built image:** `pg_dump (PostgreSQL) 17.11` runs, as the
unprivileged user `node`, and n8n itself still starts.

**Does not revoke the 28.08 decision "the dump is taken by `pg_dump` in a custom
image":** that stands in full. Only the mechanism of getting the client inside
changed, and the alternative — abandoning the real `pg_dump` — was never on the
table for the reason given there.

**New constraint this creates:** the Alpine version in the builder stage is now tied
to the Alpine version of the n8n image. Raising the pinned n8n version means
checking that its `/etc/os-release` still says 3.24. If it does not, the five shared
libraries stop matching, and that breaks at run time with a library error rather
than at build time — which is the more expensive way to find out.

**Rejected — an older n8n version that still had `apk`:** it would keep the
`Dockerfile` shorter by four lines, at the price of pinning the project to an
outdated n8n from day one. The reason for pinning a version is to control *when* an
update happens, not to avoid updating at all.

## 2026-08-28 · Edition — Community, self-hosted, with the free lifetime key

n8n runs as **Community Edition** in our own Docker container. The account created
at <http://localhost:5678> lives in n8n's database inside the `n8n_data` volume, not
on n8n's servers: nothing is registered with anyone, and no company account exists.
Community Edition is free with no time limit.

**Why not n8n Cloud:** the hosting question was already settled on 26.08, but Cloud
also fails on a harder point. **The Execute Command node does not exist on n8n
Cloud** — the documentation states plainly, "This node isn't available on n8n
Cloud." Since the 28.08 decision "n8n orchestrates, the shell does the work" builds
every step of workflow A on that node, Cloud would not merely be a paid alternative;
it would require redesigning the workflow from scratch.

**Free activation key — taken 28.08.** n8n offers Community users a lifetime key
unlocking three features: advanced debugging of failed executions, search and
tagging over execution history, and folders. It is not a trial and does not expire —
a separate offer, the enterprise trial key, is the one with an end date, and that
one was declined.

**Why it was taken:** advanced debugging is needed immediately. The definition of
done requires deliberately breaking the password to prove the Telegram branch fires;
re-running a failed execution from the failed step is exactly that job.

**Where the key lives, and the limit of that:** in the same `n8n_data` volume as the
account and the workflows. `docker compose down -v` destroys all three at once, and
the key is then re-activated from the same email. Nothing about the backup depends
on it: all three features are editor conveniences, not runtime requirements. The
project still reproduces from `docker compose up` on a machine with no key — only
the comfort of debugging differs.

**Rejected — the enterprise trial key:** it expires, and it unlocks SSO, LDAP and
log streaming, none of which this project has any use for. A dependency with an end
date, inside something meant to keep running unattended.

## 2026-08-28 · The Execute Command node has to be unblocked explicitly

`NODES_EXCLUDE` is set in `docker-compose.yml` to `["n8n-nodes-base.localFileTrigger"]`.

**Why:** from n8n 2.0 the Execute Command node is blocked by default. The built-in
default, read out of the image itself, is
`['n8n-nodes-base.executeCommand', 'n8n-nodes-base.localFileTrigger']`. Every step
of workflow A is an Execute Command node, so without this setting the node would
simply not appear in the editor — and it would have been found the slow way, half
way through assembling the workflow.

**Why the list is restated rather than emptied to `[]`:** `[]` would unblock
everything n8n blocks by default, including `localFileTrigger`, which nothing here
needs. The node was blocked for a security reason, and turning off a protection
wholesale to get at one node next to it is a wider change than the problem asks for.

**Accepted trade-off:** the protection removed from `executeCommand` is real — the
node runs shell commands inside the container. It is accepted knowingly: this is a
single-user instance on a personal laptop, and the commands in it are written by
the owner. In a shared or public deployment this line would need re-arguing.

---

# Status as of 2026-08-28 and start plan

Verified today:

- the repository `E:/Study/TrainingProjects/bookwish-automation` exists, git is
  initialised, `origin` points at GitHub;
- **Docker works.** Hyper-V and Containers were enabled in Windows features; after
  the reboot the engine answers. The first calls after a start return `500` for a
  minute or so while the engine boots — that is not a fault;
- **the image is built and n8n is running:** <http://localhost:5678> answers, the
  `n8n_data` volume and the `../bookwish-backups` mount are in place, and writing
  and deleting inside `/backups` as user `node` both work;
- **the owner account exists** and the free Community key has been activated;
- **Execute Command is unblocked** via `NODES_EXCLUDE`, and the container was
  recreated with it — the account and the key survived, because they live in the
  volume rather than in the container.

Order of work:

1. Install Docker Desktop. — **done**
2. `git init` + first commit + push to GitHub. — **done**
3. Bring up n8n in a container with a named volume so workflows survive restarts.
   — **done**
4. Custom `Dockerfile`: n8n image + `postgresql-client`. — **done**, by copying
   rather than installing (see the decision above).
5. Owner account in the n8n UI. — **done**
6. `SUPABASE_DB_URL` filled into `.env`. — *the owner's step; blocks everything
   below.*
7. Workflow A: Schedule 21:00 → `pg_dump` → file in a folder on disk →
   **failure-notification branch** (the condition from the 26.08 decision; without
   it the workflow does not count as finished).
8. Only once A works and is pushed — workflow B.
9. As a separate task at the end — uploading the dump to Google Drive
   (28.08 decision).

BookWish side (separate repository, not this one): search redesign merged (PR #25),
wishlist cleanup merged (PR #26). Next there — validation for manually adding a
book, then the error block.
