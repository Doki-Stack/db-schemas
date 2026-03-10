-- migrate:up
CREATE TABLE ee.report_schedules (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  report_id       UUID NOT NULL REFERENCES ee.reports(id) ON DELETE CASCADE,
  cron_expression TEXT NOT NULL,
  enabled         BOOLEAN NOT NULL DEFAULT true,
  last_run_at     TIMESTAMPTZ,
  next_run_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_report_schedules_org_id ON ee.report_schedules (org_id);
CREATE INDEX idx_ee_report_schedules_report_id ON ee.report_schedules (report_id);

CREATE TRIGGER trg_ee_report_schedules_updated_at
  BEFORE UPDATE ON ee.report_schedules
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- migrate:down
DROP TRIGGER IF EXISTS trg_ee_report_schedules_updated_at ON ee.report_schedules;
DROP TABLE IF EXISTS ee.report_schedules;
