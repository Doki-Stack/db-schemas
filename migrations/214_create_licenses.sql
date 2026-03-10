-- migrate:up
CREATE TABLE ee.licenses (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  license_key TEXT NOT NULL UNIQUE,
  license_type TEXT NOT NULL,
  max_users   INTEGER NOT NULL,
  features    JSONB NOT NULL DEFAULT '{}',
  valid_from  TIMESTAMPTZ NOT NULL,
  valid_until TIMESTAMPTZ NOT NULL,
  status      TEXT NOT NULL DEFAULT 'active',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_licenses_org_id ON ee.licenses (org_id);
CREATE UNIQUE INDEX idx_ee_licenses_license_key ON ee.licenses (license_key);

CREATE TRIGGER trg_ee_licenses_updated_at
  BEFORE UPDATE ON ee.licenses
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TABLE ee.license_usage (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  license_id   UUID NOT NULL REFERENCES ee.licenses(id) ON DELETE CASCADE,
  org_id       UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  recorded_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  active_users INTEGER NOT NULL,
  features_used JSONB NOT NULL DEFAULT '{}',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_license_usage_license_id ON ee.license_usage (license_id);
CREATE INDEX idx_ee_license_usage_org_id ON ee.license_usage (org_id);
CREATE INDEX idx_ee_license_usage_org_recorded ON ee.license_usage (org_id, recorded_at);

-- migrate:down
DROP TABLE IF EXISTS ee.license_usage;
DROP TRIGGER IF EXISTS trg_ee_licenses_updated_at ON ee.licenses;
DROP TABLE IF EXISTS ee.licenses;
