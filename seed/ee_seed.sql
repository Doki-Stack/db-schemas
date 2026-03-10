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

INSERT INTO ee.teams (id, org_id, name, description) VALUES
  ('ab000000-0000-0000-0000-000000000001'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'Platform Engineering', 'Core platform team'),
  ('ab000000-0000-0000-0000-000000000002'::uuid,
   'a0000000-0000-0000-0000-000000000001'::uuid,
   'Security', 'Security and compliance team')
ON CONFLICT (id) DO NOTHING;

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
