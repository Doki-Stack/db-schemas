-- migrate:up
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

-- migrate:down
DROP TRIGGER IF EXISTS trg_ee_governance_policies_updated_at ON ee.governance_policies;
DROP TABLE IF EXISTS ee.governance_policies;
