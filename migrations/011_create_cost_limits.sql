-- migrate:up
CREATE TABLE cost_limits (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id           UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  resource_type    TEXT NOT NULL,
  limit_amount     NUMERIC(12,2) NOT NULL,
  remaining_budget  NUMERIC(12,2) NOT NULL,
  period           budget_period NOT NULL DEFAULT 'monthly',
  reset_at         TIMESTAMPTZ NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_cost_limits_positive CHECK (limit_amount > 0),
  CONSTRAINT chk_cost_limits_remaining CHECK (remaining_budget >= 0)
);

CREATE INDEX idx_cost_limits_org_id ON cost_limits (org_id);
CREATE UNIQUE INDEX idx_cost_limits_org_resource ON cost_limits (org_id, resource_type);

CREATE TRIGGER trg_cost_limits_updated_at
  BEFORE UPDATE ON cost_limits
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- migrate:down
DROP TRIGGER IF EXISTS trg_cost_limits_updated_at ON cost_limits;
DROP TABLE IF EXISTS cost_limits CASCADE;
