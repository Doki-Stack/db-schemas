# Seed Data Strategy

## Overview

Seed data provides a consistent starting point for development and testing. Two seed files are maintained:

| File | Purpose | Phase |
|------|---------|-------|
| `seed/dev_seed.sql` | CE development data — orgs, users, tasks, plans, approvals | Phase 0 |
| `seed/ee_seed.sql` | EE development data — memories, MCP registry, teams, governance | Phase 3+ |

Seed data is **not** applied in production. It is used for:
- Local development setup
- CI testing
- RLS validation (two-org fixture)
- Demo environments

## Idempotency

All seed statements use `INSERT ... ON CONFLICT DO NOTHING` so they can be re-run safely without duplicating data.

```sql
INSERT INTO orgs (id, name, slug)
VALUES ('...'::uuid, 'Acme Corp', 'acme')
ON CONFLICT (id) DO NOTHING;
```

## dev_seed.sql — CE Seed Data

### Organizations

Two orgs are created to support RLS validation:

```sql
-- Org A: primary development org
INSERT INTO orgs (id, name, slug, settings)
VALUES (
  'a0000000-0000-0000-0000-000000000001'::uuid,
  'Acme Corp',
  'acme',
  '{"timezone": "America/New_York", "default_plan_expiry_hours": 24}'::jsonb
) ON CONFLICT (id) DO NOTHING;

-- Org B: secondary org for RLS testing
INSERT INTO orgs (id, name, slug, settings)
VALUES (
  'b0000000-0000-0000-0000-000000000002'::uuid,
  'Globex Inc',
  'globex',
  '{"timezone": "Europe/London", "default_plan_expiry_hours": 48}'::jsonb
) ON CONFLICT (id) DO NOTHING;
```

### Users

One user per role in each org:

```sql
-- Org A users
INSERT INTO users (id, org_id, auth0_sub, email, display_name, role) VALUES
  ('a1000000-0000-0000-0000-000000000001'::uuid, 'a0000000-0000-0000-0000-000000000001'::uuid,
   'auth0|acme-owner', 'owner@acme.example', 'Alice Owner', 'platform_owner'),
  ('a1000000-0000-0000-0000-000000000002'::uuid, 'a0000000-0000-0000-0000-000000000001'::uuid,
   'auth0|acme-admin', 'admin@acme.example', 'Bob Admin', 'admin'),
  ('a1000000-0000-0000-0000-000000000003'::uuid, 'a0000000-0000-0000-0000-000000000001'::uuid,
   'auth0|acme-approver', 'approver@acme.example', 'Carol Approver', 'approver'),
  ('a1000000-0000-0000-0000-000000000004'::uuid, 'a0000000-0000-0000-0000-000000000001'::uuid,
   'auth0|acme-operator', 'operator@acme.example', 'Dave Operator', 'operator'),
  ('a1000000-0000-0000-0000-000000000005'::uuid, 'a0000000-0000-0000-0000-000000000001'::uuid,
   'auth0|acme-viewer', 'viewer@acme.example', 'Eve Viewer', 'viewer')
ON CONFLICT (id) DO NOTHING;

-- Org B users (minimal set for RLS testing)
INSERT INTO users (id, org_id, auth0_sub, email, display_name, role) VALUES
  ('b1000000-0000-0000-0000-000000000001'::uuid, 'b0000000-0000-0000-0000-000000000002'::uuid,
   'auth0|globex-owner', 'owner@globex.example', 'Frank Owner', 'platform_owner'),
  ('b1000000-0000-0000-0000-000000000002'::uuid, 'b0000000-0000-0000-0000-000000000002'::uuid,
   'auth0|globex-operator', 'operator@globex.example', 'Grace Operator', 'operator')
ON CONFLICT (id) DO NOTHING;
```

### Tasks

Sample tasks in various states:

```sql
-- Org A tasks
INSERT INTO tasks (id, org_id, user_id, title, description, status) VALUES
  ('a2000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'a1000000-0000-0000-0000-000000000004'::uuid,
   'Deploy staging Redis cluster',
   'Set up a 3-node Redis cluster in the staging namespace',
   'completed'),
  ('a2000000-0000-0000-0000-000000000002'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'a1000000-0000-0000-0000-000000000004'::uuid,
   'Upgrade production PostgreSQL to 16',
   'Rolling upgrade of the production database cluster',
   'pending'),
  ('a2000000-0000-0000-0000-000000000003'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'a1000000-0000-0000-0000-000000000002'::uuid,
   'Configure network policies for data namespace',
   'Apply Cilium network policies to restrict cross-namespace traffic',
   'running')
ON CONFLICT (id) DO NOTHING;

-- Org B task (for RLS testing)
INSERT INTO tasks (id, org_id, user_id, title, description, status) VALUES
  ('b2000000-0000-0000-0000-000000000001'::uuid,
   'b0000000-0000-0000-0000-000000000002'::uuid,
   'b1000000-0000-0000-0000-000000000002'::uuid,
   'Set up monitoring stack',
   'Deploy Prometheus and Grafana in monitoring namespace',
   'pending')
ON CONFLICT (id) DO NOTHING;
```

### Plans

```sql
INSERT INTO plans (id, org_id, task_id, plan_type, resource_changes, status, artifact_path) VALUES
  ('a3000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'a2000000-0000-0000-0000-000000000001'::uuid,
   'terraform',
   '[{"action": "create", "resource": "aws_elasticache_replication_group", "name": "staging-redis"}]'::jsonb,
   'applied',
   'org_id=a0000000-0000-0000-0000-000000000001/plans/a3000000-0000-0000-0000-000000000001/plan.json'),
  ('a3000000-0000-0000-0000-000000000002'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'a2000000-0000-0000-0000-000000000002'::uuid,
   'terraform',
   '[{"action": "update", "resource": "aws_rds_cluster", "name": "prod-postgres", "changes": ["engine_version"]}]'::jsonb,
   'pending_approval',
   'org_id=a0000000-0000-0000-0000-000000000001/plans/a3000000-0000-0000-0000-000000000002/plan.json')
ON CONFLICT (id) DO NOTHING;
```

### Approvals

```sql
INSERT INTO approvals (id, org_id, plan_id, approver_id, status, comment, decided_at) VALUES
  ('a4000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'a3000000-0000-0000-0000-000000000001'::uuid,
   'a1000000-0000-0000-0000-000000000003'::uuid,
   'approved',
   'Reviewed resource changes. LGTM.',
   now() - interval '2 days')
ON CONFLICT (id) DO NOTHING;
```

### Audit Logs

```sql
INSERT INTO audit_logs (id, org_id, user_id, actor_type, action, resource_type, resource_id, details) VALUES
  ('a5000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'a1000000-0000-0000-0000-000000000004'::uuid,
   'user', 'task.created', 'task',
   'a2000000-0000-0000-0000-000000000001'::uuid,
   '{"title": "Deploy staging Redis cluster"}'::jsonb),
  ('a5000000-0000-0000-0000-000000000002'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   NULL,
   'agent', 'plan.generated', 'plan',
   'a3000000-0000-0000-0000-000000000001'::uuid,
   '{"plan_type": "terraform", "resource_count": 1}'::jsonb),
  ('a5000000-0000-0000-0000-000000000003'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'a1000000-0000-0000-0000-000000000003'::uuid,
   'user', 'approval.approved', 'approval',
   'a4000000-0000-0000-0000-000000000001'::uuid,
   '{"comment": "Reviewed resource changes. LGTM."}'::jsonb)
ON CONFLICT DO NOTHING;
```

### Scanner Contexts

```sql
INSERT INTO scanner_contexts (id, org_id, repo, branch, commit_sha, artifact_paths) VALUES
  ('a6000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'https://github.com/acme/infra',
   'main',
   'abc123def456',
   ARRAY[
     'org_id=a0000000-0000-0000-0000-000000000001/acme/infra/abc123def456/skill.md',
     'org_id=a0000000-0000-0000-0000-000000000001/acme/infra/abc123def456/instructions.md'
   ])
ON CONFLICT (id) DO NOTHING;
```

### Policy Rules

```sql
INSERT INTO policy_rules (id, org_id, name, description, rule_type, rule_config, severity, enabled) VALUES
  ('a7000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'max-resource-count',
   'Reject plans that create more than 50 resources at once',
   'blast_radius',
   '{"max_resources": 50}'::jsonb,
   'high', true),
  ('a7000000-0000-0000-0000-000000000002'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'no-public-s3',
   'Block creation of publicly accessible S3 buckets',
   'resource_whitelist',
   '{"deny_patterns": ["aws_s3_bucket.*.acl=public-read"]}'::jsonb,
   'critical', true)
ON CONFLICT (id) DO NOTHING;
```

### Cost Limits

```sql
INSERT INTO cost_limits (id, org_id, resource_type, limit_amount, remaining_budget, period, reset_at) VALUES
  ('a8000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'compute',
   5000.00, 4200.00, 'monthly',
   date_trunc('month', now()) + interval '1 month'),
  ('a8000000-0000-0000-0000-000000000002'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'storage',
   1000.00, 980.50, 'monthly',
   date_trunc('month', now()) + interval '1 month')
ON CONFLICT (id) DO NOTHING;
```

---

## ee_seed.sql — Enterprise Edition Seed Data

Only applied when EE migrations have been run. Depends on `dev_seed.sql` being applied first.

### Agent Memories

```sql
INSERT INTO ee.agent_memories (id, org_id, memory_type, key, value, source_task_id, relevance_score) VALUES
  ('a9000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'preference',
   'terraform-provider-version',
   '{"provider": "aws", "preferred_version": "~> 5.0", "reason": "Org policy requires AWS provider 5.x"}'::jsonb,
   NULL, 0.95),
  ('a9000000-0000-0000-0000-000000000002'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'outcome',
   'redis-cluster-deploy-success',
   '{"task": "Deploy staging Redis cluster", "result": "success", "duration_seconds": 180, "notes": "3-node cluster with TLS"}'::jsonb,
   'a2000000-0000-0000-0000-000000000001'::uuid, 0.90),
  ('a9000000-0000-0000-0000-000000000003'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'correction',
   'use-gp3-not-gp2',
   '{"original": "aws_ebs_volume.type = gp2", "corrected": "aws_ebs_volume.type = gp3", "reason": "gp3 is cheaper and faster than gp2"}'::jsonb,
   NULL, 0.85)
ON CONFLICT (id) DO NOTHING;
```

### MCP Registry

```sql
INSERT INTO ee.mcp_registry (id, org_id, name, description, endpoint_url, auth_type, tool_manifest, health_status) VALUES
  ('aa000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'custom-compliance-checker',
   'Internal compliance policy checker for SOC2 requirements',
   'http://compliance-mcp.internal:8080',
   'api_key',
   '{"tools": [{"name": "check-compliance", "description": "Evaluate plan against SOC2 controls"}]}'::jsonb,
   'healthy')
ON CONFLICT (id) DO NOTHING;
```

### Teams

```sql
INSERT INTO ee.teams (id, org_id, name, description) VALUES
  ('ab000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'Platform Engineering', 'Core platform team'),
  ('ab000000-0000-0000-0000-000000000002'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'Security', 'Security and compliance team')
ON CONFLICT (id) DO NOTHING;
```

### Org Members

```sql
INSERT INTO ee.org_members (org_id, user_id, team_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001'::uuid,
   'a1000000-0000-0000-0000-000000000001'::uuid,
   NULL, 'admin'),
  ('a0000000-0000-0000-0000-000000000001'::uuid,
   'a1000000-0000-0000-0000-000000000004'::uuid,
   'ab000000-0000-0000-0000-000000000001'::uuid, 'member'),
  ('a0000000-0000-0000-0000-000000000001'::uuid,
   'a1000000-0000-0000-0000-000000000003'::uuid,
   'ab000000-0000-0000-0000-000000000002'::uuid, 'member')
ON CONFLICT (org_id, user_id) DO NOTHING;
```

### Governance Policies

```sql
INSERT INTO ee.governance_policies (id, org_id, policy_type, name, description, config, enabled) VALUES
  ('ac000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'cost_guard',
   'Monthly cost ceiling',
   'Reject plans exceeding monthly cost limits',
   '{"enforce": true, "alert_threshold_percent": 80}'::jsonb,
   true),
  ('ac000000-0000-0000-0000-000000000002'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'blast_radius',
   'Max simultaneous destroys',
   'Limit destructive operations to 10 resources per plan',
   '{"max_destroys": 10, "require_approval_above": 5}'::jsonb,
   true)
ON CONFLICT (id) DO NOTHING;
```

### Approval Rules

```sql
INSERT INTO ee.approval_rules (id, org_id, name, risk_level, required_approvers, conditions, enabled) VALUES
  ('ad000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'Critical changes need 2 approvers',
   'critical', 2,
   '{"resource_types": ["aws_rds_cluster", "aws_eks_cluster"], "actions": ["destroy", "update"]}'::jsonb,
   true),
  ('ad000000-0000-0000-0000-000000000002'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'High-risk needs 1 approver',
   'high', 1,
   '{"resource_types": ["aws_security_group", "aws_iam_role"]}'::jsonb,
   true)
ON CONFLICT (id) DO NOTHING;
```

---

## Running Seed Data

### Local Development

```bash
# Apply CE seed
dbmate -d ./seed -e DATABASE_URL up  # if using dbmate seed support
# or directly:
psql "$DATABASE_URL" -f seed/dev_seed.sql

# Apply EE seed (only after EE migrations)
psql "$DATABASE_URL" -f seed/ee_seed.sql
```

### CI Pipeline

```bash
# In CI, seed is applied after migrations for testing
dbmate up
psql "$DATABASE_URL" -f seed/dev_seed.sql
# Run tests...
```

### Kubernetes (dev/staging only)

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-seed
  namespace: data
spec:
  template:
    spec:
      containers:
        - name: seed
          image: postgres:16
          command: ["psql", "$(DATABASE_URL)", "-f", "/seed/dev_seed.sql"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: postgres-credentials
                  key: admin-url
          volumeMounts:
            - name: seed-data
              mountPath: /seed
      volumes:
        - name: seed-data
          configMap:
            name: db-seed-data
      restartPolicy: Never
```

## UUID Convention

All seed UUIDs follow a readable pattern for easy identification during development:

| Prefix | Entity |
|--------|--------|
| `a0...001` | Org A |
| `b0...002` | Org B |
| `a1...NNN` | Org A users |
| `b1...NNN` | Org B users |
| `a2...NNN` | Org A tasks |
| `a3...NNN` | Org A plans |
| `a4...NNN` | Org A approvals |
| `a5...NNN` | Org A audit logs |
| `a6...NNN` | Org A scanner contexts |
| `a7...NNN` | Org A policy rules |
| `a8...NNN` | Org A cost limits |
| `a9...NNN` | Org A agent memories (EE) |
| `aa...NNN` | Org A MCP registry (EE) |
| `ab...NNN` | Org A teams (EE) |
| `ac...NNN` | Org A governance policies (EE) |
| `ad...NNN` | Org A approval rules (EE) |

This convention makes it trivial to identify which org owns a record during debugging.
