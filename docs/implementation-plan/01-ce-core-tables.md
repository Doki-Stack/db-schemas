# Community Edition — Core Table DDLs

All CE tables live in the `public` schema of the `ai_automation` database. Every table with tenant data includes `org_id` as a foreign key to `orgs` and participates in Row-Level Security (see `02-rls-and-multi-tenancy.md`).

**Database:** `ai_automation`
**Schema:** `public`
**PostgreSQL version:** 16+

---

## Prerequisites (Migration 001)

```sql
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
```

`gen_random_uuid()` is built into PostgreSQL 13+ and does not require an extension. `pgcrypto` is included for `crypt()` and `gen_random_bytes()` if needed by future migrations.

---

## Enum Types (Migration 002)

All enum types are created in a single migration to avoid circular dependencies.

```sql
CREATE TYPE user_role AS ENUM (
  'viewer',
  'operator',
  'approver',
  'admin',
  'platform_owner'
);

CREATE TYPE task_status AS ENUM (
  'pending',
  'running',
  'completed',
  'failed',
  'cancelled'
);

CREATE TYPE plan_type AS ENUM (
  'terraform',
  'ansible'
);

CREATE TYPE plan_status AS ENUM (
  'draft',
  'pending_approval',
  'approved',
  'rejected',
  'expired',
  'applied',
  'failed'
);

CREATE TYPE approval_status AS ENUM (
  'pending',
  'approved',
  'rejected',
  'expired'
);

CREATE TYPE actor_type AS ENUM (
  'user',
  'agent',
  'system'
);

CREATE TYPE severity_level AS ENUM (
  'low',
  'medium',
  'high',
  'critical'
);

CREATE TYPE budget_period AS ENUM (
  'daily',
  'weekly',
  'monthly'
);
```

---

## Table: `orgs` (Migration 003)

Organization records. Top-level tenant entity — all other tables reference this via `org_id`.

```sql
CREATE TABLE orgs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL,
  slug        TEXT NOT NULL UNIQUE,
  settings    JSONB NOT NULL DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orgs_slug ON orgs (slug);
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT gen_random_uuid() | |
| `name` | TEXT | NOT NULL | Display name |
| `slug` | TEXT | NOT NULL, UNIQUE | URL-safe identifier |
| `settings` | JSONB | NOT NULL, DEFAULT '{}' | Org-level configuration |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

**RLS:** Exempt — `orgs` is the top-level entity. Access control is handled at the application layer. Services query `orgs` by `id` after extracting `org_id` from the JWT/header.

---

## Table: `users` (Migration 004)

User records synced from Auth0. Each user belongs to exactly one org.

```sql
CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  auth0_sub     TEXT NOT NULL UNIQUE,
  email         TEXT NOT NULL,
  display_name  TEXT NOT NULL,
  role          user_role NOT NULL DEFAULT 'viewer',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_org_id ON users (org_id);
CREATE INDEX idx_users_email ON users (email);
CREATE UNIQUE INDEX idx_users_org_id_email ON users (org_id, email);
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT gen_random_uuid() | |
| `org_id` | UUID | NOT NULL, FK → orgs(id) ON DELETE CASCADE | Tenant key |
| `auth0_sub` | TEXT | NOT NULL, UNIQUE | Auth0 subject identifier |
| `email` | TEXT | NOT NULL | |
| `display_name` | TEXT | NOT NULL | |
| `role` | user_role | NOT NULL, DEFAULT 'viewer' | Platform role |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

---

## Table: `tasks` (Migration 005)

User-initiated tasks. Each task may spawn a LangGraph thread for agent execution.

```sql
CREATE TABLE tasks (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  description TEXT,
  status      task_status NOT NULL DEFAULT 'pending',
  thread_id   UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_tasks_org_id_created_at ON tasks (org_id, created_at DESC);
CREATE INDEX idx_tasks_org_id_status ON tasks (org_id, status);
CREATE INDEX idx_tasks_user_id ON tasks (user_id);
CREATE INDEX idx_tasks_thread_id ON tasks (thread_id) WHERE thread_id IS NOT NULL;
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT gen_random_uuid() | |
| `org_id` | UUID | NOT NULL, FK → orgs(id) ON DELETE CASCADE | Tenant key |
| `user_id` | UUID | NOT NULL, FK → users(id) ON DELETE CASCADE | Task creator |
| `title` | TEXT | NOT NULL | |
| `description` | TEXT | Nullable | |
| `status` | task_status | NOT NULL, DEFAULT 'pending' | |
| `thread_id` | UUID | Nullable | LangGraph thread_id, set when agent starts |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

---

## Table: `plans` (Migration 006)

Generated Terraform/Ansible plans linked to a task. Contains metadata; the full plan artifact is stored in MinIO.

```sql
CREATE TABLE plans (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id            UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  task_id           UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  plan_type         plan_type NOT NULL,
  resource_changes  JSONB NOT NULL DEFAULT '[]',
  status            plan_status NOT NULL DEFAULT 'draft',
  artifact_path     TEXT,
  expires_at        TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_plans_org_id_created_at ON plans (org_id, created_at DESC);
CREATE INDEX idx_plans_task_id ON plans (task_id);
CREATE INDEX idx_plans_org_id_status ON plans (org_id, status);
CREATE INDEX idx_plans_gin_resource_changes ON plans USING GIN (resource_changes);
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT gen_random_uuid() | |
| `org_id` | UUID | NOT NULL, FK → orgs(id) ON DELETE CASCADE | Tenant key |
| `task_id` | UUID | NOT NULL, FK → tasks(id) ON DELETE CASCADE | Parent task |
| `plan_type` | plan_type | NOT NULL | terraform or ansible |
| `resource_changes` | JSONB | NOT NULL, DEFAULT '[]' | Structured diff of planned changes |
| `status` | plan_status | NOT NULL, DEFAULT 'draft' | Lifecycle status |
| `artifact_path` | TEXT | Nullable | MinIO path: `org_id={org_id}/plans/{plan_id}/plan.json` |
| `expires_at` | TIMESTAMPTZ | Nullable | Plans expire if not approved within window |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

---

## Table: `approvals` (Migration 007)

HITL approval records. Each plan requires at least one approval before it can be applied.

```sql
CREATE TABLE approvals (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  plan_id     UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
  approver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status      approval_status NOT NULL DEFAULT 'pending',
  comment     TEXT,
  decided_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_approvals_org_id_created_at ON approvals (org_id, created_at DESC);
CREATE INDEX idx_approvals_plan_id ON approvals (plan_id);
CREATE INDEX idx_approvals_approver_id ON approvals (approver_id);
CREATE INDEX idx_approvals_org_id_status ON approvals (org_id, status);
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT gen_random_uuid() | |
| `org_id` | UUID | NOT NULL, FK → orgs(id) ON DELETE CASCADE | Tenant key |
| `plan_id` | UUID | NOT NULL, FK → plans(id) ON DELETE CASCADE | Plan being approved |
| `approver_id` | UUID | NOT NULL, FK → users(id) ON DELETE CASCADE | Human approver |
| `status` | approval_status | NOT NULL, DEFAULT 'pending' | |
| `comment` | TEXT | Nullable | Approver's rationale |
| `decided_at` | TIMESTAMPTZ | Nullable | When decision was made |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

---

## Table: `audit_logs` (Migration 008)

Immutable audit trail. Partitioned by month on `created_at` for performance and lifecycle management. Records are append-only — no UPDATE or DELETE.

```sql
CREATE TABLE audit_logs (
  id            UUID NOT NULL DEFAULT gen_random_uuid(),
  org_id        UUID NOT NULL,
  user_id       UUID,
  actor_type    actor_type NOT NULL,
  action        TEXT NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id   UUID,
  details       JSONB NOT NULL DEFAULT '{}',
  ip_address    INET,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- Initial partitions (script generates monthly partitions)
CREATE TABLE audit_logs_y2026m01 PARTITION OF audit_logs
  FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE audit_logs_y2026m02 PARTITION OF audit_logs
  FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE audit_logs_y2026m03 PARTITION OF audit_logs
  FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE audit_logs_y2026m04 PARTITION OF audit_logs
  FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE audit_logs_y2026m05 PARTITION OF audit_logs
  FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE audit_logs_y2026m06 PARTITION OF audit_logs
  FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit_logs_y2026m07 PARTITION OF audit_logs
  FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE audit_logs_y2026m08 PARTITION OF audit_logs
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE audit_logs_y2026m09 PARTITION OF audit_logs
  FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE audit_logs_y2026m10 PARTITION OF audit_logs
  FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE audit_logs_y2026m11 PARTITION OF audit_logs
  FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE audit_logs_y2026m12 PARTITION OF audit_logs
  FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

CREATE INDEX idx_audit_logs_org_id_created_at ON audit_logs (org_id, created_at DESC);
CREATE INDEX idx_audit_logs_resource ON audit_logs (resource_type, resource_id);
CREATE INDEX idx_audit_logs_actor ON audit_logs (actor_type, user_id);
CREATE INDEX idx_audit_logs_gin_details ON audit_logs USING GIN (details);
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | NOT NULL, DEFAULT gen_random_uuid() | Part of composite PK with created_at |
| `org_id` | UUID | NOT NULL | Tenant key (no FK — audit logs must survive org deletion) |
| `user_id` | UUID | Nullable | Null for agent/system actions |
| `actor_type` | actor_type | NOT NULL | user, agent, or system |
| `action` | TEXT | NOT NULL | e.g., "plan.created", "approval.approved" |
| `resource_type` | TEXT | NOT NULL | e.g., "task", "plan", "approval" |
| `resource_id` | UUID | Nullable | ID of the affected resource |
| `details` | JSONB | NOT NULL, DEFAULT '{}' | Action-specific metadata (inputs redacted) |
| `ip_address` | INET | Nullable | Client IP when available |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | Partition key |

**Partitioning:** Range partitioned by month on `created_at`. A cron job or pg_partman creates future partitions. Partitions older than 12 months are detached and archived to MinIO.

**No foreign keys:** `org_id` and `user_id` are not foreign keys intentionally — audit logs must be retained even if the referenced org or user is deleted.

---

## Table: `scanner_contexts` (Migration 009)

Repository scan result index. The actual scan artifacts (skill.md, instructions.md) are stored in MinIO; this table holds metadata.

```sql
CREATE TABLE scanner_contexts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  repo            TEXT NOT NULL,
  branch          TEXT NOT NULL,
  commit_sha      TEXT NOT NULL,
  artifact_paths  TEXT[] NOT NULL DEFAULT '{}',
  scanned_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_scanner_contexts_org_id_created_at ON scanner_contexts (org_id, created_at DESC);
CREATE INDEX idx_scanner_contexts_repo ON scanner_contexts (org_id, repo, branch);
CREATE UNIQUE INDEX idx_scanner_contexts_org_repo_commit ON scanner_contexts (org_id, repo, commit_sha);
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT gen_random_uuid() | |
| `org_id` | UUID | NOT NULL, FK → orgs(id) ON DELETE CASCADE | Tenant key |
| `repo` | TEXT | NOT NULL | Repository URL or path |
| `branch` | TEXT | NOT NULL | Branch name |
| `commit_sha` | TEXT | NOT NULL | Git commit SHA |
| `artifact_paths` | TEXT[] | NOT NULL, DEFAULT '{}' | MinIO paths to scan artifacts |
| `scanned_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | When scan completed |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

**Unique constraint:** `(org_id, repo, commit_sha)` — a commit is scanned once per org.

---

## Table: `policy_rules` (Migration 010)

Policy metadata for the Policy MCP. Rules are evaluated against plans before approval. The full policy text may also be embedded in Qdrant for semantic retrieval.

```sql
CREATE TABLE policy_rules (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  description TEXT,
  rule_type   TEXT NOT NULL,
  rule_config JSONB NOT NULL DEFAULT '{}',
  severity    severity_level NOT NULL DEFAULT 'medium',
  enabled     BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_policy_rules_org_id ON policy_rules (org_id);
CREATE INDEX idx_policy_rules_org_id_enabled ON policy_rules (org_id) WHERE enabled = true;
CREATE UNIQUE INDEX idx_policy_rules_org_id_name ON policy_rules (org_id, name);
CREATE INDEX idx_policy_rules_gin_config ON policy_rules USING GIN (rule_config);
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT gen_random_uuid() | |
| `org_id` | UUID | NOT NULL, FK → orgs(id) ON DELETE CASCADE | Tenant key |
| `name` | TEXT | NOT NULL | Rule name, unique per org |
| `description` | TEXT | Nullable | |
| `rule_type` | TEXT | NOT NULL | e.g., "cost_guard", "blast_radius", "resource_whitelist" |
| `rule_config` | JSONB | NOT NULL, DEFAULT '{}' | Rule parameters |
| `severity` | severity_level | NOT NULL, DEFAULT 'medium' | |
| `enabled` | BOOLEAN | NOT NULL, DEFAULT true | Soft disable without deletion |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

---

## Table: `cost_limits` (Migration 011)

Per-org cost guard limits used by the Policy MCP to enforce budget constraints.

```sql
CREATE TABLE cost_limits (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id           UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  resource_type    TEXT NOT NULL,
  limit_amount     NUMERIC(12,2) NOT NULL,
  remaining_budget NUMERIC(12,2) NOT NULL,
  period           budget_period NOT NULL DEFAULT 'monthly',
  reset_at         TIMESTAMPTZ NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_cost_limits_positive CHECK (limit_amount > 0),
  CONSTRAINT chk_cost_limits_remaining CHECK (remaining_budget >= 0)
);

CREATE INDEX idx_cost_limits_org_id ON cost_limits (org_id);
CREATE UNIQUE INDEX idx_cost_limits_org_resource ON cost_limits (org_id, resource_type);
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT gen_random_uuid() | |
| `org_id` | UUID | NOT NULL, FK → orgs(id) ON DELETE CASCADE | Tenant key |
| `resource_type` | TEXT | NOT NULL | e.g., "compute", "storage", "network" |
| `limit_amount` | NUMERIC(12,2) | NOT NULL, CHECK > 0 | Budget ceiling |
| `remaining_budget` | NUMERIC(12,2) | NOT NULL, CHECK >= 0 | Remaining budget in current period |
| `period` | budget_period | NOT NULL, DEFAULT 'monthly' | Reset frequency |
| `reset_at` | TIMESTAMPTZ | NOT NULL | Next budget reset timestamp |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

**Unique constraint:** `(org_id, resource_type)` — one limit per resource type per org.

---

## Updated-At Trigger

All tables with `updated_at` columns use a shared trigger function to auto-update the timestamp.

```sql
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Applied to each table:
CREATE TRIGGER trg_orgs_updated_at
  BEFORE UPDATE ON orgs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ... repeated for tasks, plans, policy_rules, cost_limits
```

---

## Summary

| Migration | Table | Depends On | Phase |
|-----------|-------|------------|-------|
| 001 | Extensions (pgcrypto) | — | 0 |
| 002 | Enum types | — | 0 |
| 003 | `orgs` | 001 | 0 |
| 004 | `users` | 003 | 0 |
| 005 | `tasks` | 003, 004 | 0 |
| 006 | `plans` | 003, 005 | 0 |
| 007 | `approvals` | 003, 004, 006 | 0 |
| 008 | `audit_logs` | — | 0 |
| 009 | `scanner_contexts` | 003 | 0 |
| 010 | `policy_rules` | 003 | 0 |
| 011 | `cost_limits` | 003 | 0 |
| 012 | RLS policies | All above | 0 |
| 013 | Additional indexes | All above | 0 |
