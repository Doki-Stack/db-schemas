-- migrate:up
CREATE TABLE ee.teams (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_teams_org_id ON ee.teams (org_id);
CREATE UNIQUE INDEX idx_ee_teams_org_name ON ee.teams (org_id, name);

CREATE TRIGGER trg_ee_teams_updated_at
  BEFORE UPDATE ON ee.teams
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- migrate:down
DROP TRIGGER IF EXISTS trg_ee_teams_updated_at ON ee.teams;
DROP TABLE IF EXISTS ee.teams;
