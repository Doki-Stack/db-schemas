-- migrate:up
CREATE TABLE ee.reports (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id        UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  report_type   TEXT NOT NULL,
  format        TEXT NOT NULL DEFAULT 'pdf',
  parameters    JSONB NOT NULL DEFAULT '{}',
  generated_at  TIMESTAMPTZ,
  artifact_path TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_reports_org_id ON ee.reports (org_id);
CREATE INDEX idx_ee_reports_org_type ON ee.reports (org_id, report_type);

CREATE TRIGGER trg_ee_reports_updated_at
  BEFORE UPDATE ON ee.reports
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- migrate:down
DROP TRIGGER IF EXISTS trg_ee_reports_updated_at ON ee.reports;
DROP TABLE IF EXISTS ee.reports;
