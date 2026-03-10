# Enterprise Edition — Table DDLs

All EE tables live in a dedicated `ee` schema within the `ai_automation` database. This separation provides:

- Clear licensing boundary — CE deployments never create the `ee` schema
- Independent migration numbering (100+ for Phase 3, 200+ for Phase 4)
- No impact on CE tables — EE migrations are purely additive
- Simple detection — `SELECT 1 FROM pg_namespace WHERE nspname = 'ee'` tells a service whether EE is active

**Database:** `ai_automation`
**Schema:** `ee`
**PostgreSQL version:** 16+

All EE tables reference CE tables (`public.orgs`, `public.users`, `public.tasks`) via foreign keys. RLS is applied using the same `app.current_org_id` mechanism as CE tables (see `02-rls-and-multi-tenancy.md`).

---

## EE Schema Creation (Migration 100)

```sql
-- migrate:up
CREATE SCHEMA IF NOT EXISTS ee;
GRANT USAGE ON SCHEMA ee TO app_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA ee TO app_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA ee
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA ee
  GRANT USAGE ON SEQUENCES TO app_service;

-- migrate:down
DROP SCHEMA IF EXISTS ee CASCADE;
```

---

## EE Enum Types (Migration 100 — same migration as schema creation)

```sql
CREATE TYPE ee.memory_type AS ENUM (
  'preference',
  'outcome',
  'correction',
  'prompt_effectiveness'
);

CREATE TYPE ee.cloud_provider AS ENUM (
  'aws',
  'gcp',
  'azure'
);

CREATE TYPE ee.scan_status AS ENUM (
  'pending',
  'running',
  'completed',
  'failed',
  'cancelled'
);

CREATE TYPE ee.mcp_auth_type AS ENUM (
  'none',
  'api_key',
  'oauth2',
  'mtls'
);

CREATE TYPE ee.mcp_health_status AS ENUM (
  'healthy',
  'degraded',
  'unhealthy',
  'unknown'
);

CREATE TYPE ee.channel_type AS ENUM (
  'slack',
  'teams',
  'pagerduty',
  'email'
);

CREATE TYPE ee.risk_level AS ENUM (
  'low',
  'medium',
  'high',
  'critical'
);

CREATE TYPE ee.report_type AS ENUM (
  'compliance',
  'audit',
  'cost',
  'usage'
);

CREATE TYPE ee.report_format AS ENUM (
  'pdf',
  'csv',
  'json'
);

CREATE TYPE ee.schedule_frequency AS ENUM (
  'daily',
  'weekly',
  'monthly',
  'quarterly'
);

CREATE TYPE ee.license_tier AS ENUM (
  'team',
  'enterprise'
);

CREATE TYPE ee.license_status AS ENUM (
  'active',
  'expired',
  'suspended',
  'trial'
);
```

---

## Phase 3 Tables

### Table: `ee.agent_memories` (Migration 101)

Stores organizational learning for the Memory MCP. Each memory has a type, relevance score with decay, and an access counter for boosting frequently recalled memories.

```sql
CREATE TABLE ee.agent_memories (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  memory_type     ee.memory_type NOT NULL,
  key             TEXT NOT NULL,
  value           JSONB NOT NULL,
  source_task_id  UUID REFERENCES public.tasks(id) ON DELETE SET NULL,
  relevance_score NUMERIC(5,4) NOT NULL DEFAULT 1.0,
  decay_factor    NUMERIC(5,4) NOT NULL DEFAULT 0.95,
  access_count    INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_agent_memories_relevance CHECK (relevance_score >= 0 AND relevance_score <= 1),
  CONSTRAINT chk_agent_memories_decay CHECK (decay_factor > 0 AND decay_factor <= 1)
);

CREATE INDEX idx_agent_memories_org_id_type ON ee.agent_memories (org_id, memory_type);
CREATE INDEX idx_agent_memories_org_id_created_at ON ee.agent_memories (org_id, created_at DESC);
CREATE INDEX idx_agent_memories_org_id_relevance ON ee.agent_memories (org_id, relevance_score DESC);
CREATE INDEX idx_agent_memories_source_task ON ee.agent_memories (source_task_id) WHERE source_task_id IS NOT NULL;
CREATE INDEX idx_agent_memories_gin_value ON ee.agent_memories USING GIN (value);
CREATE UNIQUE INDEX idx_agent_memories_org_key ON ee.agent_memories (org_id, key);

CREATE TRIGGER trg_agent_memories_updated_at
  BEFORE UPDATE ON ee.agent_memories
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT gen_random_uuid() | |
| `org_id` | UUID | NOT NULL, FK → public.orgs(id) ON DELETE CASCADE | Tenant key |
| `memory_type` | ee.memory_type | NOT NULL | preference, outcome, correction, prompt_effectiveness |
| `key` | TEXT | NOT NULL | Unique per org — the memory identifier |
| `value` | JSONB | NOT NULL | Memory content |
| `source_task_id` | UUID | FK → public.tasks(id) ON DELETE SET NULL | Task that produced this memory |
| `relevance_score` | NUMERIC(5,4) | NOT NULL, DEFAULT 1.0, CHECK [0,1] | Decays over time, boosted on access |
| `decay_factor` | NUMERIC(5,4) | NOT NULL, DEFAULT 0.95, CHECK (0,1] | Half-life multiplier applied periodically |
| `access_count` | INTEGER | NOT NULL, DEFAULT 0 | Incremented on recall |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

**Semantic retrieval:** Qdrant `agent_memories` collection (768 dims, cosine) stores embeddings with `org_id` metadata filter. The PG table stores structured data; Qdrant handles similarity search.

**Memory decay:** A periodic job multiplies `relevance_score` by `decay_factor`. Memories with `relevance_score` below a threshold (e.g., 0.01) can be archived or deleted. `access_count` provides a boost signal.

---

### Table: `ee.discovery_scans` (Migration 102)

Tracks AWS/GCP/Azure infrastructure discovery scans. The actual scan results are stored in MinIO as structured JSON.

```sql
CREATE TABLE ee.discovery_scans (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id              UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  provider            ee.cloud_provider NOT NULL,
  regions             TEXT[] NOT NULL DEFAULT '{}',
  resource_types      TEXT[] NOT NULL DEFAULT '{}',
  exclusion_patterns  TEXT[] NOT NULL DEFAULT '{}',
  status              ee.scan_status NOT NULL DEFAULT 'pending',
  error_message       TEXT,
  started_at          TIMESTAMPTZ,
  completed_at        TIMESTAMPTZ,
  result_path         TEXT,
  resource_count      INTEGER,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_discovery_scans_org_id_created_at ON ee.discovery_scans (org_id, created_at DESC);
CREATE INDEX idx_discovery_scans_org_id_status ON ee.discovery_scans (org_id, status);
CREATE INDEX idx_discovery_scans_org_id_provider ON ee.discovery_scans (org_id, provider);
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT gen_random_uuid() | |
| `org_id` | UUID | NOT NULL, FK → public.orgs(id) ON DELETE CASCADE | Tenant key |
| `provider` | ee.cloud_provider | NOT NULL | aws, gcp, or azure |
| `regions` | TEXT[] | NOT NULL, DEFAULT '{}' | Regions to scan |
| `resource_types` | TEXT[] | NOT NULL, DEFAULT '{}' | Resource types to discover |
| `exclusion_patterns` | TEXT[] | NOT NULL, DEFAULT '{}' | Patterns to exclude |
| `status` | ee.scan_status | NOT NULL, DEFAULT 'pending' | Scan lifecycle |
| `error_message` | TEXT | Nullable | Error details on failure |
| `started_at` | TIMESTAMPTZ | Nullable | When scan started |
| `completed_at` | TIMESTAMPTZ | Nullable | When scan finished |
| `result_path` | TEXT | Nullable | MinIO path to scan results |
| `resource_count` | INTEGER | Nullable | Number of resources discovered |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

---

## Phase 4 Tables

### Table: `ee.mcp_registry` (Migration 200)

Registry of custom MCP servers per org. Credentials are stored in Vault; only the Vault path reference is stored here.

```sql
CREATE TABLE ee.mcp_registry (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id            UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  name              TEXT NOT NULL,
  description       TEXT,
  endpoint_url      TEXT NOT NULL,
  auth_type         ee.mcp_auth_type NOT NULL DEFAULT 'none',
  credentials_ref   TEXT,
  tool_manifest     JSONB NOT NULL DEFAULT '{}',
  health_status     ee.mcp_health_status NOT NULL DEFAULT 'unknown',
  last_validated_at TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_mcp_registry_org_id ON ee.mcp_registry (org_id);
CREATE UNIQUE INDEX idx_mcp_registry_org_name ON ee.mcp_registry (org_id, name);
CREATE INDEX idx_mcp_registry_health ON ee.mcp_registry (org_id, health_status);
CREATE INDEX idx_mcp_registry_gin_manifest ON ee.mcp_registry USING GIN (tool_manifest);

CREATE TRIGGER trg_mcp_registry_updated_at
  BEFORE UPDATE ON ee.mcp_registry
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT gen_random_uuid() | |
| `org_id` | UUID | NOT NULL, FK → public.orgs(id) ON DELETE CASCADE | Tenant key |
| `name` | TEXT | NOT NULL | MCP name, unique per org |
| `description` | TEXT | Nullable | |
| `endpoint_url` | TEXT | NOT NULL | MCP server URL |
| `auth_type` | ee.mcp_auth_type | NOT NULL, DEFAULT 'none' | |
| `credentials_ref` | TEXT | Nullable | Vault path: `secret/data/orgs/{org_id}/mcps/{mcp_id}` |
| `tool_manifest` | JSONB | NOT NULL, DEFAULT '{}' | Available tools and their schemas |
| `health_status` | ee.mcp_health_status | NOT NULL, DEFAULT 'unknown' | |
| `last_validated_at` | TIMESTAMPTZ | Nullable | |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

---

### Table: `ee.organizations` (Migration 201)

Extends CE `orgs` with enterprise features: billing, SSO configuration, feature flags.

```sql
CREATE TABLE ee.organizations (
  org_id          UUID PRIMARY KEY REFERENCES public.orgs(id) ON DELETE CASCADE,
  billing_email   TEXT,
  billing_plan    TEXT,
  sso_provider    TEXT,
  sso_config      JSONB NOT NULL DEFAULT '{}',
  feature_flags   JSONB NOT NULL DEFAULT '{}',
  max_users       INTEGER,
  max_teams       INTEGER,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_ee_organizations_updated_at
  BEFORE UPDATE ON ee.organizations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `org_id` | UUID | PK, FK → public.orgs(id) ON DELETE CASCADE | 1:1 extension of CE orgs |
| `billing_email` | TEXT | Nullable | |
| `billing_plan` | TEXT | Nullable | |
| `sso_provider` | TEXT | Nullable | e.g., "okta", "azure_ad" |
| `sso_config` | JSONB | NOT NULL, DEFAULT '{}' | SSO configuration |
| `feature_flags` | JSONB | NOT NULL, DEFAULT '{}' | Per-org feature toggles |
| `max_users` | INTEGER | Nullable | License-enforced limit |
| `max_teams` | INTEGER | Nullable | License-enforced limit |
| `created_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |
| `updated_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

---

### Table: `ee.teams` (Migration 202)

Teams within organizations for sub-org scoping and access control.

```sql
CREATE TABLE ee.teams (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_teams_org_id ON ee.teams (org_id);
CREATE UNIQUE INDEX idx_ee_teams_org_name ON ee.teams (org_id, name);

CREATE TRIGGER trg_ee_teams_updated_at
  BEFORE UPDATE ON ee.teams
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

---

### Table: `ee.org_quotas` (Migration 203)

Resource quotas per org. Enforced by Kyverno policies and application-level checks.

```sql
CREATE TABLE ee.org_quotas (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  resource_type TEXT NOT NULL,
  limit_value   INTEGER NOT NULL,
  current_usage INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_org_quotas_limit CHECK (limit_value > 0),
  CONSTRAINT chk_org_quotas_usage CHECK (current_usage >= 0)
);

CREATE UNIQUE INDEX idx_ee_org_quotas_org_resource ON ee.org_quotas (org_id, resource_type);

CREATE TRIGGER trg_ee_org_quotas_updated_at
  BEFORE UPDATE ON ee.org_quotas
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

---

### Table: `ee.org_members` (Migration 204)

Organization membership with optional team assignment.

```sql
CREATE TABLE ee.org_members (
  org_id    UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  user_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  team_id   UUID REFERENCES ee.teams(id) ON DELETE SET NULL,
  role      TEXT NOT NULL DEFAULT 'member',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (org_id, user_id)
);

CREATE INDEX idx_ee_org_members_team_id ON ee.org_members (team_id) WHERE team_id IS NOT NULL;
CREATE INDEX idx_ee_org_members_user_id ON ee.org_members (user_id);
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `org_id` | UUID | NOT NULL, FK → public.orgs(id) ON DELETE CASCADE | Composite PK part 1 |
| `user_id` | UUID | NOT NULL, FK → public.users(id) ON DELETE CASCADE | Composite PK part 2 |
| `team_id` | UUID | FK → ee.teams(id) ON DELETE SET NULL | Optional team membership |
| `role` | TEXT | NOT NULL, DEFAULT 'member' | e.g., "member", "team_lead", "admin" |
| `joined_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

---

### Table: `ee.notification_preferences` (Migration 205)

Per-user notification preferences specifying which events to receive and through which channels.

```sql
CREATE TABLE ee.notification_preferences (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  event_types TEXT[] NOT NULL DEFAULT '{}',
  channels    JSONB NOT NULL DEFAULT '{}',
  enabled     BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_ee_notification_prefs_org_user ON ee.notification_preferences (org_id, user_id);

CREATE TRIGGER trg_ee_notification_prefs_updated_at
  BEFORE UPDATE ON ee.notification_preferences
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

---

### Table: `ee.channel_configs` (Migration 206)

Organization-level notification channel configurations (Slack, Teams, PagerDuty, Email).

```sql
CREATE TABLE ee.channel_configs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  channel_type    ee.channel_type NOT NULL,
  name            TEXT NOT NULL,
  config          JSONB NOT NULL DEFAULT '{}',
  credentials_ref TEXT,
  enabled         BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_channel_configs_org_id ON ee.channel_configs (org_id);
CREATE UNIQUE INDEX idx_ee_channel_configs_org_name ON ee.channel_configs (org_id, name);

CREATE TRIGGER trg_ee_channel_configs_updated_at
  BEFORE UPDATE ON ee.channel_configs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

---

### Table: `ee.governance_policies` (Migration 207)

Organization-level governance configuration: cost guards, blast-radius limits, token budgets, destructive-operation patterns.

```sql
CREATE TABLE ee.governance_policies (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  policy_type TEXT NOT NULL,
  name        TEXT NOT NULL,
  description TEXT,
  config      JSONB NOT NULL DEFAULT '{}',
  enabled     BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_governance_policies_org_id ON ee.governance_policies (org_id);
CREATE INDEX idx_ee_governance_policies_org_enabled ON ee.governance_policies (org_id) WHERE enabled = true;
CREATE UNIQUE INDEX idx_ee_governance_policies_org_name ON ee.governance_policies (org_id, name);

CREATE TRIGGER trg_ee_governance_policies_updated_at
  BEFORE UPDATE ON ee.governance_policies
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

---

### Table: `ee.approval_rules` (Migration 208)

Multi-approver rules. Governance can require 2+ approvers for high-risk operations.

```sql
CREATE TABLE ee.approval_rules (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id             UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  name               TEXT NOT NULL,
  risk_level         ee.risk_level NOT NULL,
  required_approvers INTEGER NOT NULL DEFAULT 1,
  conditions         JSONB NOT NULL DEFAULT '{}',
  enabled            BOOLEAN NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_approval_rules_approvers CHECK (required_approvers >= 1)
);

CREATE INDEX idx_ee_approval_rules_org_id ON ee.approval_rules (org_id);
CREATE INDEX idx_ee_approval_rules_org_risk ON ee.approval_rules (org_id, risk_level);
CREATE UNIQUE INDEX idx_ee_approval_rules_org_name ON ee.approval_rules (org_id, name);

CREATE TRIGGER trg_ee_approval_rules_updated_at
  BEFORE UPDATE ON ee.approval_rules
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

---

### Table: `ee.dashboard_aggregates` (Migration 209)

Pre-computed dashboard metrics. Populated by a periodic aggregation job that reads CE tables (`tasks`, `plans`, `approvals`) and Prometheus/OpenCost metrics.

```sql
CREATE TABLE ee.dashboard_aggregates (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  metric_type TEXT NOT NULL,
  period      TEXT NOT NULL,
  period_start TIMESTAMPTZ NOT NULL,
  value       JSONB NOT NULL DEFAULT '{}',
  computed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_dashboard_agg_org_metric ON ee.dashboard_aggregates (org_id, metric_type, period_start DESC);
CREATE UNIQUE INDEX idx_ee_dashboard_agg_org_metric_period ON ee.dashboard_aggregates (org_id, metric_type, period, period_start);
```

---

### Table: `ee.reports` (Migration 210)

Generated compliance reports. The report file is stored in MinIO; this table holds metadata.

```sql
CREATE TABLE ee.reports (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  report_type   ee.report_type NOT NULL,
  title         TEXT NOT NULL,
  format        ee.report_format NOT NULL DEFAULT 'pdf',
  artifact_path TEXT,
  parameters    JSONB NOT NULL DEFAULT '{}',
  generated_by  UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_reports_org_id_created_at ON ee.reports (org_id, created_at DESC);
CREATE INDEX idx_ee_reports_org_type ON ee.reports (org_id, report_type);
```

---

### Table: `ee.report_schedules` (Migration 211)

Scheduled report generation configuration.

```sql
CREATE TABLE ee.report_schedules (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  report_type   ee.report_type NOT NULL,
  frequency     ee.schedule_frequency NOT NULL,
  parameters    JSONB NOT NULL DEFAULT '{}',
  recipients    TEXT[] NOT NULL DEFAULT '{}',
  enabled       BOOLEAN NOT NULL DEFAULT true,
  last_run_at   TIMESTAMPTZ,
  next_run_at   TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_report_schedules_org_id ON ee.report_schedules (org_id);
CREATE INDEX idx_ee_report_schedules_next_run ON ee.report_schedules (next_run_at) WHERE enabled = true;

CREATE TRIGGER trg_ee_report_schedules_updated_at
  BEFORE UPDATE ON ee.report_schedules
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

---

### Table: `ee.attestations` (Migration 212)

Compliance attestation sign-offs. Records who reviewed and signed off on a report.

```sql
CREATE TABLE ee.attestations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  report_id   UUID NOT NULL REFERENCES ee.reports(id) ON DELETE CASCADE,
  attester_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  comment     TEXT,
  attested_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_attestations_org_id ON ee.attestations (org_id);
CREATE INDEX idx_ee_attestations_report_id ON ee.attestations (report_id);
```

---

### Table: `ee.licenses` (Migration 213)

License records for the EE license server.

```sql
CREATE TABLE ee.licenses (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  license_key   TEXT NOT NULL UNIQUE,
  tier          ee.license_tier NOT NULL,
  status        ee.license_status NOT NULL DEFAULT 'active',
  features      TEXT[] NOT NULL DEFAULT '{}',
  max_users     INTEGER,
  starts_at     TIMESTAMPTZ NOT NULL,
  expires_at    TIMESTAMPTZ NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_license_dates CHECK (expires_at > starts_at)
);

CREATE INDEX idx_ee_licenses_org_id ON ee.licenses (org_id);
CREATE INDEX idx_ee_licenses_status ON ee.licenses (status) WHERE status = 'active';

CREATE TRIGGER trg_ee_licenses_updated_at
  BEFORE UPDATE ON ee.licenses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();
```

---

### Table: `ee.license_usage` (Migration 214)

Tracks usage metrics per org for license compliance auditing.

```sql
CREATE TABLE ee.license_usage (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id       UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  license_id   UUID NOT NULL REFERENCES ee.licenses(id) ON DELETE CASCADE,
  metric_type  TEXT NOT NULL,
  metric_value INTEGER NOT NULL DEFAULT 0,
  recorded_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_license_usage_org_license ON ee.license_usage (org_id, license_id, recorded_at DESC);
CREATE INDEX idx_ee_license_usage_metric ON ee.license_usage (org_id, metric_type, recorded_at DESC);
```

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | UUID | PK, DEFAULT gen_random_uuid() | |
| `org_id` | UUID | NOT NULL, FK → public.orgs(id) ON DELETE CASCADE | Tenant key |
| `license_id` | UUID | NOT NULL, FK → ee.licenses(id) ON DELETE CASCADE | |
| `metric_type` | TEXT | NOT NULL | e.g., "active_users", "plans_created", "scans_run" |
| `metric_value` | INTEGER | NOT NULL, DEFAULT 0 | Metric value at point in time |
| `recorded_at` | TIMESTAMPTZ | NOT NULL, DEFAULT now() | |

---

## EE RLS (Migration 215)

All EE tables with `org_id` get the standard RLS policy:

```sql
-- migrate:up

-- Agent Memories
ALTER TABLE ee.agent_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.agent_memories FORCE ROW LEVEL SECURITY;
CREATE POLICY agent_memories_org_isolation ON ee.agent_memories
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Discovery Scans
ALTER TABLE ee.discovery_scans ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.discovery_scans FORCE ROW LEVEL SECURITY;
CREATE POLICY discovery_scans_org_isolation ON ee.discovery_scans
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- MCP Registry
ALTER TABLE ee.mcp_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.mcp_registry FORCE ROW LEVEL SECURITY;
CREATE POLICY mcp_registry_org_isolation ON ee.mcp_registry
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Organizations (org_id is the PK here, same pattern)
ALTER TABLE ee.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.organizations FORCE ROW LEVEL SECURITY;
CREATE POLICY organizations_org_isolation ON ee.organizations
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Teams
ALTER TABLE ee.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.teams FORCE ROW LEVEL SECURITY;
CREATE POLICY teams_org_isolation ON ee.teams
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Org Quotas
ALTER TABLE ee.org_quotas ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.org_quotas FORCE ROW LEVEL SECURITY;
CREATE POLICY org_quotas_org_isolation ON ee.org_quotas
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Org Members
ALTER TABLE ee.org_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.org_members FORCE ROW LEVEL SECURITY;
CREATE POLICY org_members_org_isolation ON ee.org_members
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Notification Preferences
ALTER TABLE ee.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.notification_preferences FORCE ROW LEVEL SECURITY;
CREATE POLICY notification_preferences_org_isolation ON ee.notification_preferences
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Channel Configs
ALTER TABLE ee.channel_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.channel_configs FORCE ROW LEVEL SECURITY;
CREATE POLICY channel_configs_org_isolation ON ee.channel_configs
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Governance Policies
ALTER TABLE ee.governance_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.governance_policies FORCE ROW LEVEL SECURITY;
CREATE POLICY governance_policies_org_isolation ON ee.governance_policies
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Approval Rules
ALTER TABLE ee.approval_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.approval_rules FORCE ROW LEVEL SECURITY;
CREATE POLICY approval_rules_org_isolation ON ee.approval_rules
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Dashboard Aggregates
ALTER TABLE ee.dashboard_aggregates ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.dashboard_aggregates FORCE ROW LEVEL SECURITY;
CREATE POLICY dashboard_aggregates_org_isolation ON ee.dashboard_aggregates
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Reports
ALTER TABLE ee.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.reports FORCE ROW LEVEL SECURITY;
CREATE POLICY reports_org_isolation ON ee.reports
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Report Schedules
ALTER TABLE ee.report_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.report_schedules FORCE ROW LEVEL SECURITY;
CREATE POLICY report_schedules_org_isolation ON ee.report_schedules
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Attestations
ALTER TABLE ee.attestations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.attestations FORCE ROW LEVEL SECURITY;
CREATE POLICY attestations_org_isolation ON ee.attestations
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- Licenses
ALTER TABLE ee.licenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.licenses FORCE ROW LEVEL SECURITY;
CREATE POLICY licenses_org_isolation ON ee.licenses
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- License Usage
ALTER TABLE ee.license_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.license_usage FORCE ROW LEVEL SECURITY;
CREATE POLICY license_usage_org_isolation ON ee.license_usage
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- migrate:down
-- (reverse order: drop policies and disable RLS for each table)
```

---

## Summary

| Migration | Table | Schema | Phase |
|-----------|-------|--------|-------|
| 100 | `ee` schema + enums | ee | 3 |
| 101 | `ee.agent_memories` | ee | 3 |
| 102 | `ee.discovery_scans` | ee | 3 |
| 200 | `ee.mcp_registry` | ee | 4 |
| 201 | `ee.organizations` | ee | 4 |
| 202 | `ee.teams` | ee | 4 |
| 203 | `ee.org_quotas` | ee | 4 |
| 204 | `ee.org_members` | ee | 4 |
| 205 | `ee.notification_preferences` | ee | 4 |
| 206 | `ee.channel_configs` | ee | 4 |
| 207 | `ee.governance_policies` | ee | 4 |
| 208 | `ee.approval_rules` | ee | 4 |
| 209 | `ee.dashboard_aggregates` | ee | 4 |
| 210 | `ee.reports` | ee | 4 |
| 211 | `ee.report_schedules` | ee | 4 |
| 212 | `ee.attestations` | ee | 4 |
| 213 | `ee.licenses` | ee | 4 |
| 214 | `ee.license_usage` | ee | 4 |
| 215 | EE RLS policies | ee | 4 |

## CE-to-EE Migration Path

1. EE migrations are purely additive — no CE tables are modified
2. CE deployments skip migrations 100+
3. A fresh EE install runs all migrations (001–215)
4. An existing CE install upgrades to EE by running migrations 100+ on top of existing data
5. The `ee` schema can be dropped entirely to revert to CE-only (Migration 100 down)
