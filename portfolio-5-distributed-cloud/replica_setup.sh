#!/usr/bin/env bash
# replica_setup.sh — set up a PostgreSQL 16 streaming read replica in Codespaces.
# SplashPoint Swim School (Portfolio 5, MIT 8103)
#
# Codespaces rules followed:
#  - sudo runuser -u postgres -- ... (not sudo -u postgres)
#  - PostgreSQL config dir /etc/postgresql/16/main/
#  - pg_ctl at /usr/lib/postgresql/16/bin/pg_ctl
#  - pg_hba.conf trust lines at the top of the file (so the replica can connect
#    to the primary via Unix socket without a password)
#  - Connect via Unix socket /var/run/postgresql (no TCP password needed)
#  - No postgres_fdw used
#
# Result:
#  - Primary:    already running on port 5432 (Unix socket /var/run/postgresql)
#  - Replica:    new cluster running on port 5433 (Unix socket /var/run/postgresql),
#                in hot standby mode, streaming WAL from the primary.

set -euo pipefail

PRIMARY_PORT=5432
REPLICA_PORT=5433
REPLICA_DATA=/var/lib/postgresql/16/replica
PG_CTL=/usr/lib/postgresql/16/bin/pg_ctl
PG_BASEBACKUP=/usr/lib/postgresql/16/bin/pg_basebackup

echo "==> [1/8] Stop any existing replica"
sudo runuser -u postgres -- $PG_CTL -D $REPLICA_DATA stop -m fast 2>/dev/null || true
sudo rm -rf $REPLICA_DATA
sudo mkdir -p $REPLICA_DATA
sudo chown postgres:postgres $REPLICA_DATA
sudo chmod 700 $REPLICA_DATA

echo "==> [2/8] Create replication role on the primary"
sudo runuser -u postgres -- psql -h /var/run/postgresql -p $PRIMARY_PORT -c \
  "DO \$\$ BEGIN
     IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='replicator') THEN
       CREATE ROLE replicator WITH REPLICATION LOGIN;
     END IF;
   END \$\$;"

echo "==> [3/8] Add a trust line for local replication at the TOP of pg_hba.conf"
# Codespaces rule: trust lines must be at the top of pg_hba.conf
PG_HBA=/etc/postgresql/16/main/pg_hba.conf
if sudo grep -q "local replication trust for Portfolio 5" $PG_HBA; then
  echo "    (already added on an earlier run)"
else
sudo cp $PG_HBA ${PG_HBA}.bak
( echo "# local replication trust for Portfolio 5 demo (Codespaces only)";
  echo "local   replication     all                                     trust";
  echo "host    replication     all             127.0.0.1/32            trust";
  echo "host    replication     all             ::1/128                 trust";
  echo "# --- original pg_hba.conf below ---";
  sudo cat ${PG_HBA}.bak ) | sudo tee $PG_HBA > /dev/null
fi

echo "==> [4/8] Enable WAL level = replica and wal_log_hints on the primary"
PRIMARY_CONF=/etc/postgresql/16/main/postgresql.conf
sudo sed -i 's/^#*wal_level.*/wal_level = replica/' $PRIMARY_CONF
sudo sed -i 's/^#*max_wal_senders.*/max_wal_senders = 10/' $PRIMARY_CONF
sudo sed -i 's/^#*max_replication_slots.*/max_replication_slots = 10/' $PRIMARY_CONF
sudo sed -i 's/^#*wal_log_hints.*/wal_log_hints = on/' $PRIMARY_CONF
sudo sed -i 's/^#*hot_standby.*/hot_standby = on/' $PRIMARY_CONF
# listen on Unix socket (default) AND localhost so pg_basebackup can connect over TCP if needed
sudo grep -q "^listen_addresses = 'localhost'" $PRIMARY_CONF || \
  echo "listen_addresses = 'localhost'" | sudo tee -a $PRIMARY_CONF > /dev/null

echo "==> [5/8] Restart primary to apply settings"
sudo pg_ctlcluster 16 main restart
for i in $(seq 1 15); do
  if sudo runuser -u postgres -- psql -h /var/run/postgresql -p $PRIMARY_PORT -c "SELECT 1" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "==> [6/8] pg_basebackup — clone the primary into the replica data dir"
sudo runuser -u postgres -- $PG_BASEBACKUP \
  -h 127.0.0.1 -p $PRIMARY_PORT -U replicator -D $REPLICA_DATA \
  -Fp -Xs -R -w      # -w: never prompt for a password (trust line above)
# -R writes standby.signal and a primary_conninfo into the replica

echo "==> [7/8] Configure the replica's postgresql.conf (separate file, per Codespaces rule)"
REPLICA_CONF=$REPLICA_DATA/postgresql.conf
sudo runuser -u postgres -- bash -c "cat > $REPLICA_CONF <<'EOF'
# Replica-specific config (Portfolio 5)
listen_addresses = 'localhost'
port = 5433
unix_socket_directories = '/var/run/postgresql'
hot_standby = on
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_log_hints = on
shared_buffers = 128MB
work_mem = 4MB
EOF"

# pg_hba.conf for the replica (allow local connections for SELECT demos)
sudo runuser -u postgres -- bash -c "cat > $REPLICA_DATA/pg_hba.conf <<'EOF'
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
EOF"

# Ubuntu keeps pg_ident.conf in /etc too, so the cloned data dir has none: copy it
sudo cp /etc/postgresql/16/main/pg_ident.conf $REPLICA_DATA/pg_ident.conf
sudo chown postgres:postgres $REPLICA_DATA/pg_ident.conf $REPLICA_DATA/pg_hba.conf $REPLICA_CONF
sudo chmod 700 $REPLICA_DATA

# Make sure standby.signal exists (pg_basebackup -R creates it)
sudo runuser -u postgres -- touch $REPLICA_DATA/standby.signal

echo "==> [8/8] Start the replica"
sudo runuser -u postgres -- $PG_CTL -D $REPLICA_DATA -l /var/log/postgresql/replica.log start
# Wait for ready
for i in $(seq 1 20); do
  if sudo runuser -u postgres -- psql -h /var/run/postgresql -p $REPLICA_PORT -c "SELECT 1" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo ""
echo "===================================================================="
echo "REPLICA IS UP. Verify:"
echo "  Primary:  sudo runuser -u postgres -- psql -h /var/run/postgresql -p 5432 -d splashpoint"
echo "  Replica:  sudo runuser -u postgres -- psql -h /var/run/postgresql -p 5433 -d splashpoint"
echo ""
echo "Check streaming is working:"
sudo runuser -u postgres -- psql -h /var/run/postgresql -p $PRIMARY_PORT -d splashpoint -c \
  "SELECT application_name, state, sync_state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"

echo ""
echo "Check replica is in recovery (read-only):"
sudo runuser -u postgres -- psql -h /var/run/postgresql -p $REPLICA_PORT -d splashpoint -c \
  "SELECT pg_is_in_recovery() AS in_recovery, now() AS replica_now;"
echo ""
echo "Next: replica_demo.sh shows the read-only replica, a row arriving and the lag."
