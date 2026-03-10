#!/bin/bash
set -euo pipefail

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: DATABASE_URL is not set"
  exit 1
fi

echo "Running migrations..."
dbmate status
dbmate up
echo "Migrations complete."
dbmate status
