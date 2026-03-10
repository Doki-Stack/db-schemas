-- migrate:up
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

-- migrate:down
DROP TRIGGER IF EXISTS trg_ee_org_quotas_updated_at ON ee.org_quotas;
DROP TABLE IF EXISTS ee.org_quotas;
