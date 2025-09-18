#!/bin/bash

# PostgreSQL Slave Initialization Script
# Kong APIM Platform - Slave Database Setup

set -e

# Environment variables
PGDATA=/var/lib/postgresql/data
POSTGRES_MASTER_SERVICE=${POSTGRES_MASTER_SERVICE:-kong-database-master}
POSTGRES_REPLICATION_USER=${POSTGRES_REPLICATION_USER:-replicator}
POSTGRES_REPLICATION_PASSWORD=${POSTGRES_REPLICATION_PASSWORD}

echo "Starting PostgreSQL slave initialization..."

# Check if PGDATA is empty or needs initialization
if [ -z "$(ls -A $PGDATA 2>/dev/null)" ] || [ ! -f "${PGDATA}/PG_VERSION" ]; then
    echo "PGDATA is empty or invalid. Starting replication setup..."

    # Remove any existing data
    rm -rf ${PGDATA}/*

    # Use pg_basebackup to copy data from master
    echo "Running pg_basebackup from master..."
    PGPASSWORD=${POSTGRES_REPLICATION_PASSWORD} pg_basebackup \
        -h ${POSTGRES_MASTER_SERVICE} \
        -p 5432 \
        -U ${POSTGRES_REPLICATION_USER} \
        -D ${PGDATA} \
        -Fp \
        -Xs \
        -P \
        -R \
        -v

    # Create standby.signal file (for PostgreSQL 12+)
    touch ${PGDATA}/standby.signal

    # Configure postgresql.auto.conf for replication
    cat >> ${PGDATA}/postgresql.auto.conf <<EOF
# Replication settings
primary_conninfo = 'host=${POSTGRES_MASTER_SERVICE} port=5432 user=${POSTGRES_REPLICATION_USER} password=${POSTGRES_REPLICATION_PASSWORD} application_name=slave1'
primary_slot_name = 'slave1_slot'
restore_command = 'cp /var/lib/postgresql/wal_archive/%f %p'
EOF

    # Set proper permissions
    chown -R postgres:postgres ${PGDATA}
    chmod 700 ${PGDATA}

    echo "Slave initialization completed successfully!"
else
    echo "PGDATA exists. Checking for standby.signal..."
    if [ ! -f "${PGDATA}/standby.signal" ]; then
        touch ${PGDATA}/standby.signal
        chown postgres:postgres ${PGDATA}/standby.signal
    fi
fi

# Switch to postgres user and start PostgreSQL
exec gosu postgres postgres -c config_file=/etc/postgresql/postgresql.conf -c hba_file=/etc/postgresql/pg_hba.conf