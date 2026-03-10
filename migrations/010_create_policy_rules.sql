-- migrate:up
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

CREATE TRIGGER trg_policy_rules_updated_at
  BEFORE UPDATE ON policy_rules
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- migrate:down
DROP TRIGGER IF EXISTS trg_policy_rules_updated_at ON policy_rules;
DROP TABLE IF EXISTS policy_rules CASCADE;
