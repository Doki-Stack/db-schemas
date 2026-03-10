-- migrate:up
CREATE TABLE plans (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id            UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  task_id           UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  plan_type         plan_type NOT NULL,
  resource_changes  JSONB NOT NULL DEFAULT '[]',
  status            plan_status NOT NULL DEFAULT 'draft',
  artifact_path     TEXT,
  expires_at        TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_plans_org_id_created_at ON plans (org_id, created_at DESC);
CREATE INDEX idx_plans_task_id ON plans (task_id);
CREATE INDEX idx_plans_org_id_status ON plans (org_id, status);
CREATE INDEX idx_plans_gin_resource_changes ON plans USING GIN (resource_changes);

CREATE TRIGGER trg_plans_updated_at
  BEFORE UPDATE ON plans
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- migrate:down
DROP TRIGGER IF EXISTS trg_plans_updated_at ON plans;
DROP TABLE IF EXISTS plans;
