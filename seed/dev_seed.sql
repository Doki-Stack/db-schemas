INSERT INTO orgs (id, name, slug, settings)
VALUES (
  'a0000000-0000-0000-0000-000000000001'::uuid,
  'Acme Corp',
  'acme',
  '{"timezone": "America/New_York", "default_plan_expiry_hours": 24}'::jsonb
) ON CONFLICT (id) DO NOTHING;

INSERT INTO orgs (id, name, slug, settings)
VALUES (
  'b0000000-0000-0000-0000-000000000002'::uuid,
  'Globex Inc',
  'globex',
  '{"timezone": "Europe/London", "default_plan_expiry_hours": 48}'::jsonb
) ON CONFLICT (id) DO NOTHING;

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

INSERT INTO users (id, org_id, auth0_sub, email, display_name, role) VALUES
  ('b1000000-0000-0000-0000-000000000001'::uuid, 'b0000000-0000-0000-0000-000000000002'::uuid,
   'auth0|globex-owner', 'owner@globex.example', 'Frank Owner', 'platform_owner'),
  ('b1000000-0000-0000-0000-000000000002'::uuid, 'b0000000-0000-0000-0000-000000000002'::uuid,
   'auth0|globex-operator', 'operator@globex.example', 'Grace Operator', 'operator')
ON CONFLICT (id) DO NOTHING;

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

INSERT INTO tasks (id, org_id, user_id, title, description, status) VALUES
  ('b2000000-0000-0000-0000-000000000001'::uuid,
   'b0000000-0000-0000-0000-000000000002'::uuid,
   'b1000000-0000-0000-0000-000000000002'::uuid,
   'Set up monitoring stack',
   'Deploy Prometheus and Grafana in monitoring namespace',
   'pending')
ON CONFLICT (id) DO NOTHING;

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

INSERT INTO approvals (id, org_id, plan_id, approver_id, status, comment, decided_at) VALUES
  ('a4000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'a3000000-0000-0000-0000-000000000001'::uuid,
   'a1000000-0000-0000-0000-000000000003'::uuid,
   'approved',
   'Reviewed resource changes. LGTM.',
   now() - interval '2 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO audit_logs (id, org_id, user_id, actor_type, action, resource_type, resource_id, details, created_at)
SELECT * FROM (VALUES
  ('a5000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'a1000000-0000-0000-0000-000000000004'::uuid,
   'user'::actor_type, 'task.created', 'task',
   'a2000000-0000-0000-0000-000000000001'::uuid,
   '{"title": "Deploy staging Redis cluster"}'::jsonb,
   '2026-03-01T10:00:00Z'::timestamptz),
  ('a5000000-0000-0000-0000-000000000002'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   NULL::uuid,
   'agent'::actor_type, 'plan.generated', 'plan',
   'a3000000-0000-0000-0000-000000000001'::uuid,
   '{"plan_type": "terraform", "resource_count": 1}'::jsonb,
   '2026-03-01T10:05:00Z'::timestamptz),
  ('a5000000-0000-0000-0000-000000000003'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'a1000000-0000-0000-0000-000000000003'::uuid,
   'user'::actor_type, 'approval.approved', 'approval',
   'a4000000-0000-0000-0000-000000000001'::uuid,
   '{"comment": "Reviewed resource changes. LGTM."}'::jsonb,
   '2026-03-01T10:10:00Z'::timestamptz)
) AS v(id, org_id, user_id, actor_type, action, resource_type, resource_id, details, created_at)
WHERE NOT EXISTS (SELECT 1 FROM audit_logs WHERE audit_logs.id = v.id AND audit_logs.created_at = v.created_at);

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
