#!/usr/bin/env bash
set -euo pipefail

SQL_FILE="${1:?SQL file is required}"
LOG_FILE="${2:?LOG file is required}"

PGPASSWORD=lab5_admin_pass psql \
  -h 127.0.0.1 \
  -p 25432 \
  -U lab5_admin \
  -d subd_lab5 \
  -v ON_ERROR_STOP=1 \
  -f "$SQL_FILE" \
  2>&1 | tee "$LOG_FILE"
