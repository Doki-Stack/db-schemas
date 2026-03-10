-- migrate:up
CREATE TABLE ee.organizations (
  org_id          UUID PRIMARY KEY REFERENCES public.orgs(id) ON DELETE CASCADE,
  billing_email   TEXT,
  billing_plan    TEXT,
  sso_provider    TEXT,
  sso_config      JSONB NOT NULL DEFAULT '{}',
  feature_flags   JSONB NOT NULL DEFAULT '{}',
  max_users       INTEGER,
  max_teams       INTEGER,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_ee_organizations_updated_at
  BEFORE UPDATE ON ee.organizations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- migrate:down
DROP TRIGGER IF EXISTS trg_ee_organizations_updated_at ON ee.organizations;
DROP TABLE IF EXISTS ee.organizations;
