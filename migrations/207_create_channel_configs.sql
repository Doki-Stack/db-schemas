-- migrate:up
CREATE TABLE ee.channel_configs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  channel_type    ee.channel_type NOT NULL,
  name            TEXT NOT NULL,
  config          JSONB NOT NULL DEFAULT '{}',
  credentials_ref TEXT,
  enabled         BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_channel_configs_org_id ON ee.channel_configs (org_id);
CREATE UNIQUE INDEX idx_ee_channel_configs_org_name ON ee.channel_configs (org_id, name);

CREATE TRIGGER trg_ee_channel_configs_updated_at
  BEFORE UPDATE ON ee.channel_configs
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- migrate:down
DROP TRIGGER IF EXISTS trg_ee_channel_configs_updated_at ON ee.channel_configs;
DROP TABLE IF EXISTS ee.channel_configs;
