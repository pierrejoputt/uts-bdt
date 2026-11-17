#!/bin/bash
# Entrypoint replica: clone dari primary (pg_basebackup) saat data kosong, lalu jalan sebagai standby.
set -e
PGDATA="${PGDATA:-/var/lib/postgresql/data}"
mkdir -p "$PGDATA"
if [ -z "$(ls -A "$PGDATA" 2>/dev/null)" ]; then
  until pg_isready -h db-primary -U postgres; do sleep 2; done
  chown postgres:postgres "$PGDATA"
  # -R otomatis membuat standby.signal dan primary_conninfo
  PGPASSWORD="$REPL_PASSWORD" gosu postgres pg_basebackup -h db-primary -U replicator \
    -D "$PGDATA" -Fp -Xs -P -R
  chmod 700 "$PGDATA"
fi
exec docker-entrypoint.sh postgres
