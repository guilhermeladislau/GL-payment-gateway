#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator_pass';
EOSQL

echo "host replication replicator 0.0.0.0/0 md5" >> "$PGDATA/pg_hba.conf"

cat >> "$PGDATA/postgresql.conf" <<EOF
wal_level = replica
max_wal_senders = 3
wal_keep_size = 64
hot_standby = on
synchronous_commit = on
synchronous_standby_names = '"pg-replica"'
EOF
