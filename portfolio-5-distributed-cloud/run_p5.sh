#!/usr/bin/env bash
# run_p5.sh — Portfolio 5 end-to-end runner.
# 1. Monthly range partitioning of lesson_session + pruning + integrity checks.
# 2. Streaming read replica on port 5433 (replica_setup.sh).
# 3. One-script replica demo (replica_demo.sh) -> replication_output.log
set -euo pipefail
cd "$(dirname "$0")"

echo "==> [1/3] Convert lesson_session into a monthly range-partitioned table"
sudo runuser -u postgres -- psql -h /var/run/postgresql -p 5432 -d splashpoint -v ON_ERROR_STOP=1 -f partition.sql

echo ""
echo "==> [2/3] Set up the streaming read replica (port 5433)"
bash replica_setup.sh

echo ""
echo "==> [3/3] Replica demo -> replication_output.log"
bash replica_demo.sh 2>&1 | tee replication_output.log

echo ""
echo "P5 DONE. Evidence: this output (p5_output.log) and replication_output.log"
echo "Cloud architecture, CAP and NDPA notes: cloud_architecture.md"
