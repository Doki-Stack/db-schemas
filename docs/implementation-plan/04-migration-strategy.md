# Migration Strategy

## Tooling

### dbmate

**Decision:** Use [dbmate](https://github.com/amacneil/dbmate) as the migration runner.

**Rationale:**
- Single static binary — no Go toolchain required for non-Go developers
- `DATABASE_URL`-based configuration — works with any CI environment
- Built-in `up`, `rollback`, `status`, `new`, `dump` commands
- Supports `-- migrate:up` / `-- migrate:down` markers in a single file (simpler than separate `.up.sql` / `.down.sql` files)
- Creates a `schema_migrations` table to track applied migrations
- Supports multiple databases (useful for `ai_automation` and `terraform_states` if needed)

**Alternatives considered:**
- golang-migrate: requires Go toolchain, separate up/down files (more files to manage)
- Flyway: Java dependency, heavier for a lightweight migration repo
- Prisma Migrate: TypeScript-centric, doesn't serve Go/Rust/Python consumers well

### Installation

```bash
# Linux (amd64)
curl -fsSL -o /usr/local/bin/dbmate \
  https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64
chmod +x /usr/local/bin/dbmate

# macOS (Apple Silicon)
brew install dbmate

# Docker
docker run --rm -v "$(pwd)/migrations:/db/migrations" \
  --network host \
  ghcr.io/amacneil/dbmate:2 up
```

### Configuration

dbmate reads `DATABASE_URL` from the environment. A `.env.example` is provided:

```bash
# .env.example
DATABASE_URL="postgres://app_admin:password@localhost:5432/ai_automation?sslmode=disable"
```

The `dbmate.toml` configuration file (optional, in repo root):

```toml
[dbmate]
migrations-dir = "./migrations"
schema-file = "./schema.sql"
no-dump-schema = false
```

## Migration File Format

Each migration is a single `.sql` file with `-- migrate:up` and `-- migrate:down` markers:

```sql
-- migrate:up
CREATE TABLE example (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL
);

-- migrate:down
DROP TABLE IF EXISTS example;
```

### Naming Convention

```
{NNN}_{description}.sql
```

- `NNN`: Zero-padded 3-digit sequential number
- `description`: Snake_case description of what the migration does
- CE migrations: `001`–`099`
- EE Phase 3 migrations: `100`–`199`
- EE Phase 4 migrations: `200`–`299`

This numbering scheme leaves room for CE patch migrations (e.g., `014_add_column_to_tasks.sql`) without conflicting with EE migrations.

**dbmate default behavior:** `dbmate new` generates files with timestamp prefixes (e.g., `20260310143000_description.sql`), not sequential numbers. To use our `NNN_` convention, create migration files manually or rename after generation:

```bash
# Option A: create files manually
touch migrations/014_add_status_to_tasks.sql

# Option B: generate and rename
dbmate new add_status_to_tasks
mv migrations/20260310*_add_status_to_tasks.sql migrations/014_add_status_to_tasks.sql
```

dbmate sorts migration files lexicographically, so our zero-padded `NNN_` convention maintains correct ordering.

## Migration Ordering and Dependencies

### CE Migrations (Phase 0)

```
001_create_extensions.sql
 └── pgcrypto extension

002_create_enums.sql
 └── all CE enum types (task_status, plan_type, plan_status, etc.)

003_create_orgs.sql
 └── orgs table (no dependencies)
 └── updated_at trigger function

004_create_users.sql
 └── depends on: 003 (FK → orgs)

005_create_tasks.sql
 └── depends on: 003, 004 (FK → orgs, users)

006_create_plans.sql
 └── depends on: 003, 005 (FK → orgs, tasks)

007_create_approvals.sql
 └── depends on: 003, 004, 006 (FK → orgs, users, plans)

008_create_audit_logs.sql
 └── no FK dependencies (intentional)
 └── partitioned by month on created_at

009_create_scanner_contexts.sql
 └── depends on: 003 (FK → orgs)

010_create_policy_rules.sql
 └── depends on: 003 (FK → orgs)

011_create_cost_limits.sql
 └── depends on: 003 (FK → orgs)

012_enable_rls.sql
 └── depends on: all CE tables (004–011)

013_create_indexes.sql
 └── depends on: all CE tables (003–011)
 └── additional composite/partial indexes not created with tables
```

### EE Phase 3 Migrations

```
100_create_ee_schema.sql
 └── ee schema, ee enum types, grants

101_create_agent_memories.sql
 └── depends on: 100, 003, 005 (FK → orgs, tasks)

102_create_discovery_scans.sql
 └── depends on: 100, 003 (FK → orgs)
```

### EE Phase 4 Migrations

```
200_create_mcp_registry.sql
 └── depends on: 100, 003 (FK → orgs)

201_create_ee_organizations.sql
 └── depends on: 100, 003 (FK → orgs, 1:1 extension)

202_create_ee_teams.sql
 └── depends on: 100, 003 (FK → orgs)

203_create_ee_org_quotas.sql
 └── depends on: 100, 003 (FK → orgs)

204_create_ee_org_members.sql
 └── depends on: 100, 003, 004, 202 (FK → orgs, users, teams)

205_create_ee_notification_preferences.sql
 └── depends on: 100, 003, 004 (FK → orgs, users)

206_create_ee_channel_configs.sql
 └── depends on: 100, 003 (FK → orgs)

207_create_ee_governance_policies.sql
 └── depends on: 100, 003 (FK → orgs)

208_create_ee_approval_rules.sql
 └── depends on: 100, 003 (FK → orgs)

209_create_ee_dashboard_aggregates.sql
 └── depends on: 100, 003 (FK → orgs)

210_create_ee_reports.sql
 └── depends on: 100, 003, 004 (FK → orgs, users)

211_create_ee_report_schedules.sql
 └── depends on: 100, 003 (FK → orgs)

212_create_ee_attestations.sql
 └── depends on: 100, 003, 004, 210 (FK → orgs, users, reports)

213_create_ee_licenses.sql
 └── depends on: 100, 003 (FK → orgs)

214_create_ee_license_usage.sql
 └── depends on: 100, 003, 213 (FK → orgs, licenses)

215_enable_ee_rls.sql
 └── depends on: all EE tables (101–214)
```

### Dependency Diagram

```mermaid
graph TD
    M001[001 extensions] --> M002[002 enums]
    M002 --> M003[003 orgs]
    M003 --> M004[004 users]
    M003 --> M005[005 tasks]
    M004 --> M005
    M003 --> M006[006 plans]
    M005 --> M006
    M003 --> M007[007 approvals]
    M004 --> M007
    M006 --> M007
    M008[008 audit_logs]
    M003 --> M009[009 scanner_contexts]
    M003 --> M010[010 policy_rules]
    M003 --> M011[011 cost_limits]
    M004 --> M012[012 RLS]
    M005 --> M012
    M006 --> M012
    M007 --> M012
    M008 --> M012
    M009 --> M012
    M010 --> M012
    M011 --> M012
    M012 --> M013[013 indexes]

    M003 --> M100[100 ee schema]
    M100 --> M101[101 agent_memories]
    M005 --> M101
    M100 --> M102[102 discovery_scans]

    M100 --> M200[200 mcp_registry]
    M100 --> M201[201 ee.organizations]
    M100 --> M202[202 ee.teams]
    M100 --> M203[203 ee.org_quotas]
    M004 --> M204[204 ee.org_members]
    M202 --> M204
    M004 --> M205[205 ee.notification_prefs]
    M100 --> M206[206 ee.channel_configs]
    M100 --> M207[207 ee.governance]
    M100 --> M208[208 ee.approval_rules]
    M100 --> M209[209 ee.dashboard_agg]
    M004 --> M210[210 ee.reports]
    M100 --> M211[211 ee.report_schedules]
    M210 --> M212[212 ee.attestations]
    M100 --> M213[213 ee.licenses]
    M213 --> M214[214 ee.license_usage]

    M101 --> M215[215 ee RLS]
    M102 --> M215
    M200 --> M215
    M201 --> M215
    M202 --> M215
    M203 --> M215
    M204 --> M215
    M205 --> M215
    M206 --> M215
    M207 --> M215
    M208 --> M215
    M209 --> M215
    M210 --> M215
    M211 --> M215
    M212 --> M215
    M213 --> M215
    M214 --> M215
```

## Down Migrations

Every `-- migrate:up` block must have a corresponding `-- migrate:down` block. Down migrations:

- Drop tables with `CASCADE` to handle dependent objects
- Drop enum types
- Drop indexes (dropped automatically with table CASCADE, but explicit if created separately)
- Reverse RLS policies (disable RLS, drop policies)

### Down Migration Rules

1. Down migrations are executed in reverse order automatically by dbmate
2. Use `DROP TABLE IF EXISTS ... CASCADE` to handle foreign keys
3. Use `DROP TYPE IF EXISTS ... CASCADE` for enum types
4. Down migrations must be idempotent (`IF EXISTS`)

Example:

```sql
-- migrate:up
CREATE TABLE tasks ( ... );

-- migrate:down
DROP TABLE IF EXISTS tasks CASCADE;
```

## Rollback Procedure

### Single Migration Rollback

```bash
# Check current status
dbmate status

# Rollback the most recent migration
dbmate rollback
```

### Multi-Step Rollback

dbmate only rolls back one migration at a time. For multi-step rollbacks:

```bash
# Rollback N migrations
for i in $(seq 1 $N); do
  dbmate rollback
done
```

### Emergency Rollback Script

`scripts/rollback.sh` provides a safe wrapper:

```bash
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
```

## LangGraph Checkpoints

**Not managed by db-schemas.** The `langgraph-checkpoint-postgres` library creates and manages its own schema (`langgraph`) with tables for thread state, checkpoints, and metadata. The agent-orchestrator service handles this at startup.

The only requirement from db-schemas is that the `langgraph` schema exists. This is handled in migration 001 (`001_create_extensions.sql`):

```sql
CREATE SCHEMA IF NOT EXISTS langgraph;
GRANT ALL ON SCHEMA langgraph TO app_service;
```

## CI Integration

Migrations are validated in CI on every PR:

1. Start a PostgreSQL container (Docker)
2. Run `dbmate up` — all migrations must apply cleanly
3. Run `dbmate rollback` for each migration — verify all down migrations work
4. Run `dbmate up` again — verify re-application works
5. Run `scripts/validate-rls.sh` — verify tenant isolation
6. Run seed data — verify dev_seed.sql applies cleanly

See `07-testing-and-validation.md` for the full CI pipeline specification.

## Migration Scripts

### `scripts/migrate.sh`

```bash
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
```

### Usage in Kubernetes

Migrations run as a Kubernetes Job or init container before application pods start:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate
  namespace: data
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: ghcr.io/amacneil/dbmate:2
          command: ["dbmate", "up"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: admin-url
          volumeMounts:
            - name: migrations
              mountPath: /db/migrations
      volumes:
        - name: migrations
          configMap:
            name: db-migrations
      restartPolicy: Never
  backoffLimit: 3
```

## Schema Dump

dbmate can dump the current schema for reference:

```bash
dbmate dump  # creates schema.sql
```

The `schema.sql` file is committed to the repo as a reference snapshot. It is regenerated on every CI run and compared to the committed version to detect drift.
