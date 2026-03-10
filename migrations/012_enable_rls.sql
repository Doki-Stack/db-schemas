-- migrate:up
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;
CREATE POLICY users_org_isolation ON users
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks FORCE ROW LEVEL SECURITY;
CREATE POLICY tasks_org_isolation ON tasks
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE plans FORCE ROW LEVEL SECURITY;
CREATE POLICY plans_org_isolation ON plans
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE approvals FORCE ROW LEVEL SECURITY;
CREATE POLICY approvals_org_isolation ON approvals
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs FORCE ROW LEVEL SECURITY;
CREATE POLICY audit_logs_insert ON audit_logs
  FOR INSERT
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);
CREATE POLICY audit_logs_select ON audit_logs
  FOR SELECT
  USING (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE scanner_contexts ENABLE ROW LEVEL SECURITY;
ALTER TABLE scanner_contexts FORCE ROW LEVEL SECURITY;
CREATE POLICY scanner_contexts_org_isolation ON scanner_contexts
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE policy_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE policy_rules FORCE ROW LEVEL SECURITY;
CREATE POLICY policy_rules_org_isolation ON policy_rules
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE cost_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE cost_limits FORCE ROW LEVEL SECURITY;
CREATE POLICY cost_limits_org_isolation ON cost_limits
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- migrate:down
DROP POLICY IF EXISTS cost_limits_org_isolation ON cost_limits;
ALTER TABLE cost_limits DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS policy_rules_org_isolation ON policy_rules;
ALTER TABLE policy_rules DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS scanner_contexts_org_isolation ON scanner_contexts;
ALTER TABLE scanner_contexts DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS audit_logs_select ON audit_logs;
DROP POLICY IF EXISTS audit_logs_insert ON audit_logs;
ALTER TABLE audit_logs DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS approvals_org_isolation ON approvals;
ALTER TABLE approvals DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS plans_org_isolation ON plans;
ALTER TABLE plans DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tasks_org_isolation ON tasks;
ALTER TABLE tasks DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS users_org_isolation ON users;
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
