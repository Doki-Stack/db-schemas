-- migrate:up
CREATE TYPE ee.cloud_provider AS ENUM (
  'aws',
  'gcp',
  'azure'
);

CREATE TYPE ee.scan_status AS ENUM (
  'pending',
  'running',
  'completed',
  'failed',
  'cancelled'
);

CREATE TABLE ee.discovery_scans (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id              UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  provider            ee.cloud_provider NOT NULL,
  regions             TEXT[] NOT NULL DEFAULT '{}',
  resource_types      TEXT[] NOT NULL DEFAULT '{}',
  exclusion_patterns  TEXT[] NOT NULL DEFAULT '{}',
  status              ee.scan_status NOT NULL DEFAULT 'pending',
  error_message       TEXT,
  started_at          TIMESTAMPTZ,
  completed_at        TIMESTAMPTZ,
  result_path         TEXT,
  resource_count      INTEGER,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_discovery_scans_org_id_created_at ON ee.discovery_scans (org_id, created_at DESC);
CREATE INDEX idx_discovery_scans_org_id_status ON ee.discovery_scans (org_id, status);
CREATE INDEX idx_discovery_scans_org_id_provider ON ee.discovery_scans (org_id, provider);

-- migrate:down
DROP TABLE IF EXISTS ee.discovery_scans;
DROP TYPE IF EXISTS ee.scan_status;
DROP TYPE IF EXISTS ee.cloud_provider;
