#!/bin/bash
set -euo pipefail

if [ -z "${DATABASE_URL:-}" ]; then
  echo "ERROR: DATABASE_URL is not set"
  exit 1
fi

STEPS="${1:-1}"
echo "Rolling back $STEPS migration(s)..."
echo "Current status:"
dbmate status

read -p "Continue? (y/N) " confirm
if [ "$confirm" != "y" ]; then
  echo "Aborted."
  exit 0
fi

for i in $(seq 1 "$STEPS"); do
  echo "Rollback step $i/$STEPS..."
  dbmate rollback
done

echo "Final status:"
dbmate status
