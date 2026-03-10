-- migrate:up
CREATE TABLE ee.mcp_registry (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id            UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  name              TEXT NOT NULL,
  description       TEXT,
  endpoint_url      TEXT NOT NULL,
  auth_type         ee.mcp_auth_type NOT NULL DEFAULT 'none',
  credentials_ref   TEXT,
  tool_manifest     JSONB NOT NULL DEFAULT '{}',
  health_status     ee.mcp_health_status NOT NULL DEFAULT 'unknown',
  last_validated_at TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_mcp_registry_org_id ON ee.mcp_registry (org_id);
CREATE UNIQUE INDEX idx_mcp_registry_org_name ON ee.mcp_registry (org_id, name);
CREATE INDEX idx_mcp_registry_health ON ee.mcp_registry (org_id, health_status);
CREATE INDEX idx_mcp_registry_gin_manifest ON ee.mcp_registry USING GIN (tool_manifest);

CREATE TRIGGER trg_mcp_registry_updated_at
  BEFORE UPDATE ON ee.mcp_registry
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- migrate:down
DROP TRIGGER IF EXISTS trg_mcp_registry_updated_at ON ee.mcp_registry;
DROP TABLE IF EXISTS ee.mcp_registry;
