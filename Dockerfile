# The official n8n image does not ship pg_dump, and without it there is no backup.
# Hence a custom image: n8n plus the Postgres client.
#
# VERSION: currently latest, because the image has never been built yet.
# Right after the first successful build this line is replaced with a concrete
# version number, so that an n8n update cannot break a working workflow unannounced.
FROM docker.n8n.io/n8nio/n8n:latest

# apk needs root; the image runs as the unprivileged user "node".
USER root

# pg_dump must not be OLDER than the Postgres server in Supabase, or it will refuse
# to take the dump. If the first run complains about the version, change the
# package name here (postgresql16-client / postgresql17-client and so on).
RUN apk add --no-cache postgresql17-client

# Back to the unprivileged user: n8n has no business running as root.
USER node
