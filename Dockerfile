# The official n8n image does not ship pg_dump, and without it there is no backup.
# Hence a custom image: n8n plus the Postgres client.
#
# The n8n image is a Docker Hardened Image. It is Alpine, but the package manager
# has been removed from it deliberately: there is no apk inside, and no apt-get
# either. So "apk add postgresql-client" cannot work in it at all — not with a
# different version number, not in any form. The client is instead built in a
# throwaway stage on the SAME Alpine version and the files that matter are copied
# across.
FROM alpine:3.24 AS pgclient

# pg_dump must not be OLDER than the Postgres server in Supabase, or it will refuse
# to take the dump. If the first run complains about the version, change the
# package name here (postgresql16-client / postgresql18-client and so on).
RUN apk add --no-cache postgresql17-client

# VERSION: pinned deliberately, so that an n8n update cannot break a working
# workflow unannounced. Raising it is a conscious act: change the number, rebuild,
# check that the workflow still runs.
FROM docker.n8n.io/n8nio/n8n:2.36.8

# pg_dump needs six shared libraries. Five of them — libssl, libcrypto, libz,
# liblz4, libzstd — are already inside the n8n image, in the same versions, because
# both images are Alpine 3.24. Only libpq is missing, so only libpq is copied:
# nothing that n8n itself relies on gets overwritten.
COPY --from=pgclient /usr/bin/pg_dump   /usr/bin/pg_dump
COPY --from=pgclient /usr/lib/libpq.so.5 /usr/lib/libpq.so.5

# No USER switching here on purpose. COPY runs with the builder's own privileges
# and writes the files as root, while the base image already runs as the
# unprivileged user "node" — which is exactly what we want to keep.
