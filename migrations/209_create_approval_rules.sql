-- migrate:up
CREATE TABLE ee.approval_rules (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id             UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  name               TEXT NOT NULL,
  risk_level         TEXT NOT NULL,
  required_approvers INTEGER NOT NULL DEFAULT 1,
  conditions         JSONB NOT NULL DEFAULT '{}',
  enabled            BOOLEAN NOT NULL DEFAULT true,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_approval_rules_org_id ON ee.approval_rules (org_id);
CREATE UNIQUE INDEX idx_ee_approval_rules_org_name ON ee.approval_rules (org_id, name);

CREATE TRIGGER trg_ee_approval_rules_updated_at
  BEFORE UPDATE ON ee.approval_rules
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- migrate:down
DROP TRIGGER IF EXISTS trg_ee_approval_rules_updated_at ON ee.approval_rules;
DROP TABLE IF EXISTS ee.approval_rules;
