# db-schemas — High-Level Design

## Overview

`db-schemas` contains all PostgreSQL migrations as plain SQL files. It is consumed by every service that needs database access, regardless of language.

## Architecture

```
db-schemas/
├── migrations/
│   ├── 001_create_orgs.up.sql
│   ├── 001_create_orgs.down.sql
│   ├── 002_create_users.up.sql
│   ├── 002_create_users.down.sql
│   ├── 003_create_tasks.up.sql
│   ├── 003_create_tasks.down.sql
│   ├── 004_create_plans.up.sql
│   ├── 005_create_approvals.up.sql
│   ├── 006_create_audit_logs.up.sql
│   ├── 007_create_scanner_contexts.up.sql
│   ├── 008_create_policy_rules.up.sql
│   ├── 009_enable_rls.up.sql
│   └── ...
├── seed/
│   └── dev_seed.sql           # Development seed data
├── scripts/
│   ├── migrate.sh             # Run migrations
│   └── rollback.sh            # Rollback last migration
└── README.md
```

## RLS Strategy

Every table with tenant data has RLS enabled:

```sql
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY tasks_org_isolation ON tasks
  USING (org_id = current_setting('app.current_org_id')::uuid);
```

Services set `app.current_org_id` on each connection before executing queries.

## Consumers

| Service | Driver |
|---------|--------|
| Go services (api-server, mcp-policy, etc.) | pgx |
| Rust services (mcp-scanner, mcp-execution) | sqlx |
| Python agents (orchestrator, automation, review) | psycopg |
| LangGraph checkpointing | langgraph-checkpoint-postgres |
