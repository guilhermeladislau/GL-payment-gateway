#!/bin/bash
set -e

until pg_isready -h pg-primary -p 5432 -U postgres; do
  echo "Waiting for primary..."
  sleep 2
done

if [ ! -f "$PGDATA/standby.signal" ]; then
  rm -rf "$PGDATA"/*

  PGPASSWORD=replicator_pass pg_basebackup -h pg-primary -D "$PGDATA" -U replicator -Fp -Xs -P -R

  cat >> "$PGDATA/postgresql.conf" <<CONF
hot_standby = on
CONF

  # Override the auto-generated primary_conninfo with application_name
  # This is required for synchronous replication to identify this replica
  cat > "$PGDATA/postgresql.auto.conf" <<CONF
primary_conninfo = 'host=pg-primary port=5432 user=replicator password=replicator_pass application_name=pg-replica'
CONF

  chown -R postgres:postgres "$PGDATA"
  chmod 0700 "$PGDATA"
fi

exec gosu postgres postgres
