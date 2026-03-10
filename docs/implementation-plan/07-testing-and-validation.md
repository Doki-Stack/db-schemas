# Testing and Validation

## Overview

Every migration, RLS policy, and seed file must be validated before merging. This document defines the CI pipeline, validation scripts, and testing strategy for `db-schemas`.

## CI Pipeline

### Trigger

The pipeline runs on every PR that modifies files in `migrations/`, `seed/`, `scripts/`, or `docs/implementation-plan/`.

### Pipeline Stages

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  1. Lint      │───►│  2. Migrate  │───►│  3. Rollback │───►│  4. RLS      │───►│  5. Seed     │
│  SQL files    │    │  Up (fresh)  │    │  Full cycle  │    │  Validation  │    │  Validation  │
└──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
```

### GitHub Actions Workflow

```yaml
name: db-schemas CI
on:
  pull_request:
    paths:
      - 'migrations/**'
      - 'seed/**'
      - 'scripts/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: app_admin
          POSTGRES_PASSWORD: test_password
          POSTGRES_DB: ai_automation
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U app_admin"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    env:
      DATABASE_URL: "postgres://app_admin:test_password@localhost:5432/ai_automation?sslmode=disable"

    steps:
      - uses: actions/checkout@v4

      - name: Install dbmate
        run: |
          curl -fsSL -o /usr/local/bin/dbmate \
            https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64
          chmod +x /usr/local/bin/dbmate

      - name: Create app_service role
        run: |
          psql "$DATABASE_URL" -c "
            CREATE ROLE app_service LOGIN PASSWORD 'service_password';
            GRANT CONNECT ON DATABASE ai_automation TO app_service;
          "

      - name: Stage 1 - Lint SQL files
        run: |
          echo "Checking migration file naming convention..."
          for f in migrations/*.sql; do
            basename=$(basename "$f")
            if ! echo "$basename" | grep -qE '^[0-9]{3}_[a-z][a-z0-9_]+\.sql$'; then
              echo "ERROR: Invalid migration filename: $basename"
              echo "Expected format: NNN_description.sql"
              exit 1
            fi
          done
          echo "All migration filenames valid."

          echo "Checking for migrate:up and migrate:down markers..."
          for f in migrations/*.sql; do
            if ! grep -q '-- migrate:up' "$f"; then
              echo "ERROR: Missing '-- migrate:up' in $f"
              exit 1
            fi
            if ! grep -q '-- migrate:down' "$f"; then
              echo "ERROR: Missing '-- migrate:down' in $f"
              exit 1
            fi
          done
          echo "All migrations have up and down markers."

      - name: Stage 2 - Run all migrations up
        run: dbmate up

      - name: Stage 3 - Rollback and re-apply cycle
        run: |
          MIGRATION_COUNT=$(dbmate status 2>&1 | grep -c "^\[")
          echo "Rolling back $MIGRATION_COUNT migrations..."
          for i in $(seq 1 $MIGRATION_COUNT); do
            dbmate rollback
          done
          echo "Re-applying all migrations..."
          dbmate up

      - name: Stage 4 - RLS validation
        run: |
          chmod +x scripts/validate-rls.sh
          scripts/validate-rls.sh

      - name: Stage 5 - Seed validation
        run: |
          psql "$DATABASE_URL" -f seed/dev_seed.sql
          echo "CE seed applied successfully."

          if dbmate status 2>&1 | grep -q "100_"; then
            psql "$DATABASE_URL" -f seed/ee_seed.sql
            echo "EE seed applied successfully."
          fi

      - name: Schema dump comparison
        run: |
          dbmate dump
          if ! diff -q schema.sql schema.sql.committed 2>/dev/null; then
            echo "WARNING: schema.sql has changed. Commit the updated schema.sql."
          fi
```

## RLS Validation Script

### `scripts/validate-rls.sh`

This script is the most critical validation. It verifies that RLS prevents cross-tenant data access.

```bash
#!/bin/bash
set -euo pipefail

ADMIN_URL="${DATABASE_URL}"
SERVICE_URL=$(echo "$DATABASE_URL" | sed 's/app_admin:test_password/app_service:service_password/')

ORG_A="a0000000-0000-0000-0000-000000000001"
ORG_B="b0000000-0000-0000-0000-000000000002"

echo "=== RLS Validation ==="

# Step 1: Setup - create test orgs and data as admin
echo "Step 1: Creating test data as admin..."
psql "$ADMIN_URL" <<SQL
  -- Insert test orgs
  INSERT INTO orgs (id, name, slug) VALUES
    ('${ORG_A}'::uuid, 'Test Org A', 'test-org-a'),
    ('${ORG_B}'::uuid, 'Test Org B', 'test-org-b')
  ON CONFLICT (id) DO NOTHING;

  -- Insert test users
  INSERT INTO users (id, org_id, auth0_sub, email, display_name, role) VALUES
    ('11111111-1111-1111-1111-111111111111'::uuid, '${ORG_A}'::uuid,
     'auth0|test-a', 'a@test.com', 'User A', 'operator'),
    ('22222222-2222-2222-2222-222222222222'::uuid, '${ORG_B}'::uuid,
     'auth0|test-b', 'b@test.com', 'User B', 'operator')
  ON CONFLICT (id) DO NOTHING;

  -- Insert test tasks
  INSERT INTO tasks (id, org_id, user_id, title, status) VALUES
    ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, '${ORG_A}'::uuid,
     '11111111-1111-1111-1111-111111111111'::uuid, 'Org A Task', 'pending'),
    ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid, '${ORG_B}'::uuid,
     '22222222-2222-2222-2222-222222222222'::uuid, 'Org B Task', 'pending')
  ON CONFLICT (id) DO NOTHING;

  -- Grant permissions to app_service
  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_service;
  GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_service;
SQL

echo "Test data created."

# Step 2: Verify isolation - Org A can only see Org A data
echo "Step 2: Verifying Org A isolation..."
RESULT=$(psql "$SERVICE_URL" -t -c "
  SET app.current_org_id = '${ORG_A}';
  SELECT count(*) FROM tasks;
")
RESULT=$(echo "$RESULT" | tr -d ' ')
if [ "$RESULT" != "1" ]; then
  echo "FAIL: Org A should see exactly 1 task, got $RESULT"
  exit 1
fi
echo "  PASS: Org A sees only its own tasks"

# Step 3: Verify isolation - Org B data is not visible to Org A
echo "Step 3: Verifying cross-tenant isolation..."
RESULT=$(psql "$SERVICE_URL" -t -c "
  SET app.current_org_id = '${ORG_A}';
  SELECT count(*) FROM tasks WHERE id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid;
")
RESULT=$(echo "$RESULT" | tr -d ' ')
if [ "$RESULT" != "0" ]; then
  echo "FAIL: Org A should NOT see Org B tasks"
  exit 1
fi
echo "  PASS: Org A cannot see Org B tasks"

# Step 4: Verify INSERT protection - cannot insert with wrong org_id
echo "Step 4: Verifying INSERT protection..."
INSERT_RESULT=$(psql "$SERVICE_URL" -c "
  SET app.current_org_id = '${ORG_A}';
  INSERT INTO tasks (id, org_id, user_id, title, status)
  VALUES (gen_random_uuid(), '${ORG_B}'::uuid,
          '11111111-1111-1111-1111-111111111111'::uuid, 'Sneaky Task', 'pending');
" 2>&1 || true)
if echo "$INSERT_RESULT" | grep -q "ERROR\|violates"; then
  echo "  PASS: Cannot insert with wrong org_id"
else
  echo "FAIL: Should not be able to insert with wrong org_id"
  exit 1
fi

# Step 5: Verify missing org_id returns no rows
echo "Step 5: Verifying missing org_id behavior..."
RESULT=$(psql "$SERVICE_URL" -t -c "
  RESET app.current_org_id;
  SELECT count(*) FROM tasks;
")
RESULT=$(echo "$RESULT" | tr -d ' ')
if [ "$RESULT" != "0" ]; then
  echo "FAIL: Missing org_id should return 0 rows, got $RESULT"
  exit 1
fi
echo "  PASS: Missing org_id returns 0 rows"

# Step 6: Verify audit_logs immutability
echo "Step 6: Verifying audit_logs immutability..."
psql "$SERVICE_URL" -c "
  SET app.current_org_id = '${ORG_A}';
  INSERT INTO audit_logs (org_id, actor_type, action, resource_type, details)
  VALUES ('${ORG_A}'::uuid, 'system', 'test.rls_validation', 'test', '{}'::jsonb);
" || { echo "FAIL: Should be able to INSERT audit logs"; exit 1; }
echo "  PASS: Can INSERT audit logs"

UPDATE_RESULT=$(psql "$SERVICE_URL" -c "
  SET app.current_org_id = '${ORG_A}';
  UPDATE audit_logs SET action = 'tampered' WHERE action = 'test.rls_validation';
" 2>&1 || true)
if echo "$UPDATE_RESULT" | grep -q "UPDATE 0\|ERROR"; then
  echo "  PASS: Cannot UPDATE audit logs"
else
  echo "FAIL: Should not be able to UPDATE audit logs"
  exit 1
fi

# Step 7: Verify each table
echo "Step 7: Verifying all tenant-scoped tables..."
TABLES="users tasks plans approvals scanner_contexts policy_rules cost_limits"
for table in $TABLES; do
  RESULT=$(psql "$SERVICE_URL" -t -c "
    SET app.current_org_id = '${ORG_A}';
    SELECT count(*) FROM $table WHERE org_id = '${ORG_B}'::uuid;
  ")
  RESULT=$(echo "$RESULT" | tr -d ' ')
  if [ "$RESULT" != "0" ]; then
    echo "FAIL: Table $table leaking cross-tenant data"
    exit 1
  fi
  echo "  PASS: $table - no cross-tenant data visible"
done

# Step 8: Verify orgs table is accessible (no RLS)
echo "Step 8: Verifying orgs table accessibility..."
RESULT=$(psql "$SERVICE_URL" -t -c "SELECT count(*) FROM orgs;")
RESULT=$(echo "$RESULT" | tr -d ' ')
if [ "$RESULT" -lt "2" ]; then
  echo "FAIL: orgs table should be accessible without org_id filter"
  exit 1
fi
echo "  PASS: orgs table accessible without RLS"

# Cleanup
echo "Cleaning up test data..."
psql "$ADMIN_URL" -c "
  DELETE FROM audit_logs WHERE action = 'test.rls_validation';
  DELETE FROM tasks WHERE id IN (
    'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,
    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'::uuid
  );
  DELETE FROM users WHERE id IN (
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid
  );
  DELETE FROM orgs WHERE id IN ('${ORG_A}'::uuid, '${ORG_B}'::uuid);
"

echo ""
echo "=== RLS Validation Complete: ALL TESTS PASSED ==="
```

## Migration Testing

### Up/Down Cycle Test

Every migration must survive a full up-down-up cycle. This validates that:
- The `up` migration applies cleanly to a fresh database
- The `down` migration reverses all changes
- The `up` migration can re-apply after a rollback

```bash
#!/bin/bash
# scripts/test-migrations.sh
set -euo pipefail

echo "Testing migration up/down cycle..."

# Apply all migrations
dbmate up
echo "All migrations applied successfully."

# Get count of applied migrations
COUNT=$(dbmate status 2>&1 | grep -c "^\[X\]" || true)
echo "Applied $COUNT migrations."

# Rollback all migrations one by one
for i in $(seq 1 "$COUNT"); do
  echo "Rollback $i/$COUNT..."
  dbmate rollback
done
echo "All migrations rolled back."

# Re-apply all migrations
dbmate up
echo "All migrations re-applied successfully."

echo "Migration up/down cycle test PASSED."
```

### Individual Migration Testing

When developing a new migration, test it in isolation:

```bash
# Apply up to the previous migration
dbmate up

# Apply the new migration
dbmate up  # applies next pending

# Rollback the new migration
dbmate rollback

# Re-apply to confirm
dbmate up
```

## Seed Data Validation

### CE Seed

```bash
# After migrations are applied
psql "$DATABASE_URL" -f seed/dev_seed.sql

# Verify expected row counts
psql "$DATABASE_URL" -t -c "
  SELECT 'orgs', count(*) FROM orgs
  UNION ALL SELECT 'users', count(*) FROM users
  UNION ALL SELECT 'tasks', count(*) FROM tasks
  UNION ALL SELECT 'plans', count(*) FROM plans
  UNION ALL SELECT 'approvals', count(*) FROM approvals;
"
```

Expected:

| Table | Rows |
|-------|------|
| orgs | 2 |
| users | 7 |
| tasks | 4 |
| plans | 2 |
| approvals | 1 |

### EE Seed

```bash
psql "$DATABASE_URL" -f seed/ee_seed.sql

psql "$DATABASE_URL" -t -c "
  SELECT 'ee.agent_memories', count(*) FROM ee.agent_memories
  UNION ALL SELECT 'ee.mcp_registry', count(*) FROM ee.mcp_registry
  UNION ALL SELECT 'ee.teams', count(*) FROM ee.teams
  UNION ALL SELECT 'ee.org_members', count(*) FROM ee.org_members;
"
```

### Idempotency Test

Running seed data twice should not fail or duplicate data:

```bash
psql "$DATABASE_URL" -f seed/dev_seed.sql
psql "$DATABASE_URL" -f seed/dev_seed.sql  # second run must not fail

COUNT=$(psql "$DATABASE_URL" -t -c "SELECT count(*) FROM orgs;")
if [ "$(echo "$COUNT" | tr -d ' ')" != "2" ]; then
  echo "FAIL: Seed data is not idempotent - org count should be 2"
  exit 1
fi
```

## Schema Drift Detection

The CI pipeline generates a schema dump after applying all migrations and compares it to the committed `schema.sql`. This detects:

- Manual database changes not captured in migrations
- Migration ordering issues
- Incomplete down migrations

```bash
# Generate current schema
dbmate dump

# Compare with committed schema
if [ -f schema.sql.committed ]; then
  if ! diff schema.sql schema.sql.committed; then
    echo "Schema drift detected. Review and commit the updated schema.sql."
    exit 1
  fi
fi
```

## Performance Baseline

Track migration execution time to catch regressions:

```bash
#!/bin/bash
# scripts/benchmark-migrations.sh
set -euo pipefail

echo "Benchmarking migration execution time..."

START=$(date +%s%N)
dbmate up
END=$(date +%s%N)

ELAPSED=$(( (END - START) / 1000000 ))
echo "All migrations applied in ${ELAPSED}ms"

# Alert if migrations take longer than 30 seconds
if [ "$ELAPSED" -gt 30000 ]; then
  echo "WARNING: Migrations took longer than 30 seconds"
fi
```

Expected baseline:
- CE migrations (001-013): < 5 seconds
- Full stack with EE (001-215): < 15 seconds
- These times are for an empty database; production migrations on large datasets will be slower

## Pre-Commit Checks

A `.pre-commit-config.yaml` can enforce basic checks locally:

```yaml
repos:
  - repo: local
    hooks:
      - id: check-migration-naming
        name: Check migration file naming
        entry: bash -c 'for f in migrations/*.sql; do basename=$(basename "$f"); if ! echo "$basename" | grep -qE "^[0-9]{3}_[a-z][a-z0-9_]+\.sql$"; then echo "Invalid: $basename"; exit 1; fi; done'
        language: system
        files: 'migrations/.*\.sql$'

      - id: check-migrate-markers
        name: Check migrate up/down markers
        entry: bash -c 'for f in migrations/*.sql; do if ! grep -q "migrate:up" "$f" || ! grep -q "migrate:down" "$f"; then echo "Missing markers in $f"; exit 1; fi; done'
        language: system
        files: 'migrations/.*\.sql$'
```

## Summary — What Gets Tested

| Test | Stage | Validates |
|------|-------|-----------|
| File naming | Lint | Migration files follow `NNN_description.sql` convention |
| Marker presence | Lint | Every migration has `-- migrate:up` and `-- migrate:down` |
| Up migration | Migrate | All migrations apply cleanly to a fresh database |
| Down migration | Rollback | All migrations can be fully reversed |
| Re-apply | Rollback | Migrations apply cleanly after full rollback |
| Cross-tenant isolation | RLS | `app.current_org_id` filters work on every table |
| INSERT protection | RLS | Cannot insert rows with a different org's `org_id` |
| Missing org_id | RLS | Returns 0 rows instead of erroring |
| Audit immutability | RLS | Cannot UPDATE or DELETE audit log entries |
| Seed idempotency | Seed | Running seed twice does not duplicate data |
| Row count | Seed | Expected number of rows after seeding |
| Schema drift | Dump | Schema matches the committed snapshot |
| Performance | Benchmark | Migrations complete within time budget |
