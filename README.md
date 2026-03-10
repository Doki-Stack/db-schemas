# db-schemas

Language-agnostic SQL migrations for the Doki Stack platform. Contains all database schemas, Row-Level Security (RLS) policies, and seed data used across Go, Rust, and Python services.

## Purpose

This repository is the single source of truth for all PostgreSQL schemas. Migrations are plain SQL files managed by [dbmate](https://github.com/amacneil/dbmate). Each service connects to PostgreSQL using its own language-native driver (pgx for Go, sqlx for Rust, psycopg for Python) but the schema is defined here.

## Technology Stack

| Component | Technology |
|-----------|-----------|
| Database | PostgreSQL 16+ |
| Migrations | dbmate |
| Schema Format | Raw SQL (no ORM dependency) |
| RLS | Row-Level Security policies per table |
| Tenant Key | `org_id` on every table |

## Directory Structure

```
db-schemas/
├── migrations/          # dbmate SQL migration files
│   ├── 001-013          # CE core tables + RLS
│   ├── 100-102          # EE Phase 3 (agent_memories, discovery_scans)
│   └── 200-215          # EE Phase 4 (registry, governance, licensing)
├── seed/                # Development seed data
│   ├── dev_seed.sql     # CE seed data
│   └── ee_seed.sql      # EE seed data
├── scripts/             # Operational scripts
│   ├── migrate.sh       # Run migrations
│   ├── rollback.sh      # N-step rollback with confirmation
│   └── validate-rls.sh  # RLS validation test suite
├── dbmate.toml          # dbmate configuration
├── .env.example         # DATABASE_URL template
└── docs/                # Design docs and implementation plan
```

## CE Tables (public schema)

| Migration | Table | Purpose |
|-----------|-------|---------|
| 003 | `orgs` | Organization records |
| 004 | `users` | User records (synced from Auth0) |
| 005 | `tasks` | User task records |
| 006 | `plans` | Generated terraform/ansible plans |
| 007 | `approvals` | HITL approval records |
| 008 | `audit_logs` | Immutable audit trail (range-partitioned) |
| 009 | `scanner_contexts` | Repository scan results index |
| 010 | `policy_rules` | Policy metadata |
| 011 | `cost_limits` | Budget controls per resource type |

## EE Tables (ee schema)

| Migration | Table | Phase |
|-----------|-------|-------|
| 101 | `ee.agent_memories` | 3 |
| 102 | `ee.discovery_scans` | 3 |
| 201 | `ee.mcp_registry` | 4 |
| 202 | `ee.organizations` | 4 |
| 203 | `ee.teams` | 4 |
| 204 | `ee.org_quotas` | 4 |
| 205 | `ee.org_members` | 4 |
| 206 | `ee.notification_preferences` | 4 |
| 207 | `ee.channel_configs` | 4 |
| 208 | `ee.governance_policies` | 4 |
| 209 | `ee.approval_rules` | 4 |
| 210 | `ee.dashboard_aggregates` | 4 |
| 211 | `ee.reports` | 4 |
| 212 | `ee.report_schedules` | 4 |
| 213 | `ee.attestations` | 4 |
| 214 | `ee.licenses` / `ee.license_usage` | 4 |

## Quick Start

```bash
# Install dbmate
curl -fsSL -o /usr/local/bin/dbmate \
  https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64
chmod +x /usr/local/bin/dbmate

# Set connection string
export DATABASE_URL="postgres://app_admin:password@localhost:5432/ai_automation?sslmode=disable"

# Run all migrations
./scripts/migrate.sh

# Load dev seed data
psql "$DATABASE_URL" -f seed/dev_seed.sql

# Validate RLS policies
./scripts/validate-rls.sh

# Rollback last migration
./scripts/rollback.sh 1
```

## Multi-Tenancy

Every tenant-scoped table enforces Row-Level Security via `current_setting('app.current_org_id')`. Applications must use `SET LOCAL app.current_org_id = '<uuid>'` within explicit transactions. See `docs/implementation-plan/02-rls-and-multi-tenancy.md` for details.

## License

Apache License 2.0 — see [LICENSE](LICENSE)
