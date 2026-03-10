-- migrate:up
ALTER TABLE ee.agent_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.agent_memories FORCE ROW LEVEL SECURITY;
CREATE POLICY agent_memories_org_isolation ON ee.agent_memories
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.discovery_scans ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.discovery_scans FORCE ROW LEVEL SECURITY;
CREATE POLICY discovery_scans_org_isolation ON ee.discovery_scans
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.mcp_registry ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.mcp_registry FORCE ROW LEVEL SECURITY;
CREATE POLICY mcp_registry_org_isolation ON ee.mcp_registry
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.organizations FORCE ROW LEVEL SECURITY;
CREATE POLICY organizations_org_isolation ON ee.organizations
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.teams FORCE ROW LEVEL SECURITY;
CREATE POLICY teams_org_isolation ON ee.teams
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.org_quotas ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.org_quotas FORCE ROW LEVEL SECURITY;
CREATE POLICY org_quotas_org_isolation ON ee.org_quotas
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.org_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.org_members FORCE ROW LEVEL SECURITY;
CREATE POLICY org_members_org_isolation ON ee.org_members
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.notification_preferences FORCE ROW LEVEL SECURITY;
CREATE POLICY notification_preferences_org_isolation ON ee.notification_preferences
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.channel_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.channel_configs FORCE ROW LEVEL SECURITY;
CREATE POLICY channel_configs_org_isolation ON ee.channel_configs
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.governance_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.governance_policies FORCE ROW LEVEL SECURITY;
CREATE POLICY governance_policies_org_isolation ON ee.governance_policies
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.approval_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.approval_rules FORCE ROW LEVEL SECURITY;
CREATE POLICY approval_rules_org_isolation ON ee.approval_rules
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.dashboard_aggregates ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.dashboard_aggregates FORCE ROW LEVEL SECURITY;
CREATE POLICY dashboard_aggregates_org_isolation ON ee.dashboard_aggregates
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.reports FORCE ROW LEVEL SECURITY;
CREATE POLICY reports_org_isolation ON ee.reports
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.report_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.report_schedules FORCE ROW LEVEL SECURITY;
CREATE POLICY report_schedules_org_isolation ON ee.report_schedules
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.attestations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.attestations FORCE ROW LEVEL SECURITY;
CREATE POLICY attestations_org_isolation ON ee.attestations
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.licenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.licenses FORCE ROW LEVEL SECURITY;
CREATE POLICY licenses_org_isolation ON ee.licenses
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

ALTER TABLE ee.license_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE ee.license_usage FORCE ROW LEVEL SECURITY;
CREATE POLICY license_usage_org_isolation ON ee.license_usage
  FOR ALL
  USING (org_id = current_setting('app.current_org_id', true)::uuid)
  WITH CHECK (org_id = current_setting('app.current_org_id', true)::uuid);

-- migrate:down
DROP POLICY IF EXISTS license_usage_org_isolation ON ee.license_usage;
ALTER TABLE ee.license_usage DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS licenses_org_isolation ON ee.licenses;
ALTER TABLE ee.licenses DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS attestations_org_isolation ON ee.attestations;
ALTER TABLE ee.attestations DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS report_schedules_org_isolation ON ee.report_schedules;
ALTER TABLE ee.report_schedules DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS reports_org_isolation ON ee.reports;
ALTER TABLE ee.reports DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS dashboard_aggregates_org_isolation ON ee.dashboard_aggregates;
ALTER TABLE ee.dashboard_aggregates DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS approval_rules_org_isolation ON ee.approval_rules;
ALTER TABLE ee.approval_rules DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS governance_policies_org_isolation ON ee.governance_policies;
ALTER TABLE ee.governance_policies DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS channel_configs_org_isolation ON ee.channel_configs;
ALTER TABLE ee.channel_configs DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notification_preferences_org_isolation ON ee.notification_preferences;
ALTER TABLE ee.notification_preferences DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS org_members_org_isolation ON ee.org_members;
ALTER TABLE ee.org_members DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS org_quotas_org_isolation ON ee.org_quotas;
ALTER TABLE ee.org_quotas DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS teams_org_isolation ON ee.teams;
ALTER TABLE ee.teams DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS organizations_org_isolation ON ee.organizations;
ALTER TABLE ee.organizations DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mcp_registry_org_isolation ON ee.mcp_registry;
ALTER TABLE ee.mcp_registry DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS discovery_scans_org_isolation ON ee.discovery_scans;
ALTER TABLE ee.discovery_scans DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS agent_memories_org_isolation ON ee.agent_memories;
ALTER TABLE ee.agent_memories DISABLE ROW LEVEL SECURITY;
