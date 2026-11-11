#!/usr/bin/env bash
# setup.sh — one-time Codespaces setup for MIT 8103 portfolio
# Installs PostgreSQL 16 and MongoDB 8, creates DBs, installs extensions and Python deps.
#
# Codespaces rules followed:
#  - `sudo runuser -u postgres -- ...` (not `sudo -u postgres`)
#  - PostgreSQL config dir /etc/postgresql/16/main/
#  - pg_ctl at /usr/lib/postgresql/16/bin/pg_ctl
#  - Connect via Unix socket /var/run/postgresql (no TCP password needed)
#  - Remove /etc/apt/sources.list.d/yarn.list before apt-get update
#  - No postgres_fdw used anywhere in the portfolio

set -euo pipefail

echo "==> [1/8] Removing yarn.list (Codespaces quirk that breaks apt-get update)"
if [ -f /etc/apt/sources.list.d/yarn.list ]; then
  sudo rm -f /etc/apt/sources.list.d/yarn.list
fi

echo "==> [2/8] apt-get update + install PostgreSQL 16 and MongoDB 8"
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates gnupg postgresql-16 postgresql-client-16 \
                       python3 python3-pip python3-venv libpq-dev build-essential

# Install MongoDB 8 (community) following the official Ubuntu 24.04 (noble) repo
if ! command -v mongod >/dev/null 2>&1; then
  curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
    sudo gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor
  echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" | \
    sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list
  sudo apt-get update -y
  sudo apt-get install -y mongodb-org
fi

echo "==> [3/8] Start PostgreSQL 16 (already clustered by apt on Ubuntu)"
sudo pg_ctlcluster 16 main start || true
# Wait for ready
for i in $(seq 1 15); do
  if sudo runuser -u postgres -- psql -h /var/run/postgresql -c "SELECT 1" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "==> [4/8] Create splashpoint PostgreSQL database + btree_gist extension"
sudo runuser -u postgres -- psql -h /var/run/postgresql -c "DROP DATABASE IF EXISTS splashpoint;"
sudo runuser -u postgres -- psql -h /var/run/postgresql -c "CREATE DATABASE splashpoint;"
sudo runuser -u postgres -- psql -h /var/run/postgresql -d splashpoint -c "CREATE EXTENSION IF NOT EXISTS btree_gist;"
sudo runuser -u postgres -- psql -h /var/run/postgresql -c "ALTER DATABASE splashpoint SET timezone TO 'Africa/Lagos';"

# Create a convenience role so the codespace user can connect over the Unix socket
# without a password (peer auth). The default 'postgres' user already works via sudo runuser.
echo "==> [5/8] Ensure the codespace user can connect via Unix socket"
CODESPACE_USER="$(whoami)"
sudo runuser -u postgres -- psql -h /var/run/postgresql <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${CODESPACE_USER}') THEN
    CREATE ROLE "${CODESPACE_USER}" WITH LOGIN SUPERUSER;
  END IF;
END
\$\$;
SQL

echo "==> [6/8] Start MongoDB 8 (mongod)"
sudo mkdir -p /data/db
sudo chown -R mongodb:mongodb /data/db 2>/dev/null || true
# Try systemd first; if it is not available (Codespaces), start mongod directly.
if ! sudo systemctl start mongod 2>/dev/null; then
  if ! pgrep -x mongod >/dev/null; then
    sudo mongod --fork --logpath /var/log/mongod.log --dbpath /data/db --bind_ip 127.0.0.1
  fi
fi
# Wait for MongoDB
for i in $(seq 1 20); do
  if mongosh --quiet --eval "db.runCommand({ping:1})" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "==> [7/8] Create splashpoint MongoDB database (created implicitly on first write)"
mongosh --quiet --eval "use splashpoint" >/dev/null || true
mongosh --quiet splashpoint --eval "db.init.insertOne({ok:1, at: new Date()})" >/dev/null

echo "==> [8/8] Install Python deps (psycopg2-binary, pymongo)"
python3 -m pip install --user --upgrade pip 2>/dev/null || true
python3 -m pip install --user --break-system-packages psycopg2-binary pymongo numpy 2>/dev/null || \
  python3 -m pip install --user psycopg2-binary pymongo numpy

echo
echo "==================================================="
echo "SETUP COMPLETE."
echo "  PostgreSQL 16: socket /var/run/postgresql, db 'splashpoint'"
echo "  MongoDB 8:     127.0.0.1:27017, db 'splashpoint'"
echo "  Connect psql:   psql -h /var/run/postgresql -d splashpoint"
echo "  Connect mongo:  mongosh splashpoint"
echo "==================================================="
