# db-schemas — Implementation Overview

## Purpose

`db-schemas` is the single source of truth for all PostgreSQL schemas in the Doki Stack platform. It contains language-agnostic SQL migrations consumed by every service regardless of language runtime:

| Runtime | Driver | Services |
|---------|--------|----------|
| Go | pgx / sqlc | api-server, mcp-policy, mcp-memory (EE) |
| Rust | sqlx | mcp-scanner, mcp-execution |
| Python | psycopg | agent-orchestrator, agent-automation, agent-review |
| LangGraph | langgraph-checkpoint-postgres | agent-orchestrator (own `langgraph` schema, not managed here) |

This repo does **not** contain Drizzle ORM schemas. ADR-008 established Drizzle for TypeScript services (`packages/db` in the monorepo), but `db-schemas` supersedes that for Go, Rust, and Python consumers. The raw SQL here is the canonical DDL.

## Relationship to Implementation Phases

| Phase | Tables | Milestone |
|-------|--------|-----------|
| **Phase 0** (Weeks 1–6) | Extensions, enums, `orgs`, `users`, `tasks`, `plans`, `approvals`, `audit_logs`, `scanner_contexts`, `policy_rules`, `cost_limits`, RLS policies, indexes | Foundation — migrations run before any service starts |
| **Phase 1** (Weeks 7–16) | No new tables — services consume Phase 0 schemas | MCP servers + core UI |
| **Phase 2** (Weeks 17–26) | No new tables — LangGraph manages its own `langgraph` schema | Agents + HITL = MVP |
| **Phase 3** (Weeks 27–36) | `ee.agent_memories`, `ee.discovery_scans` | Safety + Memory + AWS Discovery |
| **Phase 4** (Weeks 37–48) | `ee.mcp_registry`, `ee.organizations`, `ee.teams`, `ee.org_quotas`, `ee.org_members`, `ee.notification_preferences`, `ee.channel_configs`, `ee.governance_policies`, `ee.approval_rules`, `ee.dashboard_aggregates`, `ee.reports`, `ee.report_schedules`, `ee.attestations`, `ee.licenses`, `ee.license_usage` | Scale + Registry + Multi-Cloud |

## Migration Tooling

**Tool:** dbmate

dbmate is chosen over golang-migrate for its simpler CLI, `DATABASE_URL`-based configuration, and no Go dependency requirement for non-Go developers. It supports up/down migrations, status checking, and can be installed as a standalone binary.

```bash
# Install
curl -fsSL -o /usr/local/bin/dbmate https://github.com/amacneil/dbmate/releases/latest/download/dbmate-linux-amd64
chmod +x /usr/local/bin/dbmate

# Usage
export DATABASE_URL="postgres://user:pass@host:5432/ai_automation?sslmode=disable"
dbmate up        # Run pending migrations
dbmate rollback  # Rollback last migration
dbmate status    # Show migration status
```

## Naming Conventions

- Migration files: `NNN_description.sql` (dbmate default, single file with `-- migrate:up` / `-- migrate:down` markers)
- CE migrations: `001`–`099`
- EE Phase 3 migrations: `100`–`199`
- EE Phase 4 migrations: `200`–`299`
- All table names: `snake_case`, plural nouns
- All column names: `snake_case`
- All enum types: `snake_case` with descriptive suffix (e.g., `task_status`, `plan_type`)
- Foreign keys: `{referenced_table_singular}_id` (e.g., `org_id`, `user_id`, `task_id`)
- Indexes: `idx_{table}_{columns}` (e.g., `idx_tasks_org_id_created_at`)

## Target Directory Structure

```
db-schemas/
├── migrations/
│   ├── 001_create_extensions.sql
│   ├── 002_create_enums.sql
│   ├── 003_create_orgs.sql
│   ├── 004_create_users.sql
│   ├── 005_create_tasks.sql
│   ├── 006_create_plans.sql
│   ├── 007_create_approvals.sql
│   ├── 008_create_audit_logs.sql
│   ├── 009_create_scanner_contexts.sql
│   ├── 010_create_policy_rules.sql
│   ├── 011_create_cost_limits.sql
│   ├── 012_enable_rls.sql
│   ├── 013_create_indexes.sql
│   ├── 100_create_ee_schema.sql
│   ├── 101_create_agent_memories.sql
│   ├── 102_create_discovery_scans.sql
│   ├── 200_create_mcp_registry.sql
│   ├── 201_create_ee_organizations.sql
│   ├── 202_create_ee_teams.sql
│   ├── 203_create_ee_org_quotas.sql
│   ├── 204_create_ee_org_members.sql
│   ├── 205_create_ee_notification_preferences.sql
│   ├── 206_create_ee_channel_configs.sql
│   ├── 207_create_ee_governance_policies.sql
│   ├── 208_create_ee_approval_rules.sql
│   ├── 209_create_ee_dashboard_aggregates.sql
│   ├── 210_create_ee_reports.sql
│   ├── 211_create_ee_report_schedules.sql
│   ├── 212_create_ee_attestations.sql
│   ├── 213_create_ee_licenses.sql
│   ├── 214_create_ee_license_usage.sql
│   └── 215_enable_ee_rls.sql
├── seed/
│   ├── dev_seed.sql
│   └── ee_seed.sql
├── scripts/
│   ├── migrate.sh
│   ├── rollback.sh
│   └── validate-rls.sh
├── docs/
│   ├── design.md
│   └── implementation-plan/
│       ├── 00-overview.md          (this file)
│       ├── 01-ce-core-tables.md
│       ├── 02-rls-and-multi-tenancy.md
│       ├── 03-ee-tables.md
│       ├── 04-migration-strategy.md
│       ├── 05-seed-data.md
│       ├── 06-non-pg-data-stores.md
│       └── 07-testing-and-validation.md
├── .gitignore
├── LICENSE
└── README.md
```

## Consumer Matrix

Which service reads/writes which tables:

| Table | api-server (Go) | mcp-scanner (Rust) | mcp-execution (Rust) | mcp-policy (Go) | agent-orchestrator (Python) | agent-automation (Python) | agent-review (Python) |
|-------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| `orgs` | RW | R | R | R | R | — | — |
| `users` | RW | — | — | — | R | — | — |
| `tasks` | RW | — | — | — | R | R | R |
| `plans` | RW | — | RW | — | R | R | R |
| `approvals` | RW | — | R | — | R | — | — |
| `audit_logs` | RW | W | W | W | W | W | W |
| `scanner_contexts` | R | RW | — | — | — | R | — |
| `policy_rules` | RW | — | — | RW | — | — | R |
| `cost_limits` | RW | — | — | RW | — | — | — |

**EE tables** (consumed by EE services only):

| Table | mcp-memory (Go) | agent-discovery (Go) | ee-multi-tenancy | ee-notifications | ee-compliance | ee-governance | ee-dashboards | ee-license-server |
|-------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| `ee.agent_memories` | RW | — | — | — | — | — | — | — |
| `ee.discovery_scans` | — | RW | — | — | — | — | — | — |
| `ee.mcp_registry` | — | — | — | — | — | — | — | — |
| `ee.organizations` | — | — | RW | — | — | — | R | — |
| `ee.teams` | — | — | RW | — | — | — | — | — |
| `ee.org_quotas` | — | — | RW | — | — | — | R | — |
| `ee.org_members` | — | — | RW | — | — | — | — | — |
| `ee.notification_preferences` | — | — | — | RW | — | — | — | — |
| `ee.channel_configs` | — | — | — | RW | — | — | — | — |
| `ee.governance_policies` | — | — | — | — | — | RW | — | — |
| `ee.approval_rules` | — | — | — | — | — | RW | — | — |
| `ee.dashboard_aggregates` | — | — | — | — | — | — | RW | — |
| `ee.reports` | — | — | — | — | RW | — | — | — |
| `ee.report_schedules` | — | — | — | — | RW | — | — | — |
| `ee.attestations` | — | — | — | — | RW | — | — | — |
| `ee.licenses` | — | — | — | — | — | — | — | RW |
| `ee.license_usage` | — | — | — | — | — | — | — | RW |

## Document Dependencies

```
00-overview.md (this file)
├── 01-ce-core-tables.md      ← defines CE table DDLs
├── 02-rls-and-multi-tenancy.md ← depends on 01 (tables must exist before RLS)
├── 03-ee-tables.md            ← defines EE table DDLs, references CE FKs
├── 04-migration-strategy.md   ← references 01, 02, 03 for ordering
├── 05-seed-data.md            ← references 01, 03 for table shapes
├── 06-non-pg-data-stores.md   ← standalone reference doc
└── 07-testing-and-validation.md ← references 02, 04 for test strategy
```

## Key Architecture Decisions

| ADR | Relevance to db-schemas |
|-----|------------------------|
| ADR-003 | LangGraph checkpoints use their own `langgraph` schema — not managed by db-schemas |
| ADR-005 | Policy MCP fail-closed — `policy_rules` and `cost_limits` tables must always be available |
| ADR-008 | Drizzle for TS services; db-schemas uses raw SQL for Go/Rust/Python |
| ADR-010 | TS + Python split at HTTP boundary — db-schemas serves the non-TS side |
| ADR-011 | Memory MCP stores in PG + Qdrant + Dragonfly — `ee.agent_memories` table defined here |
| ADR-012 | MCP Registry metadata in PG — `ee.mcp_registry` table defined here |
