-- migrate:up
CREATE TABLE ee.dashboard_aggregates (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id       UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  metric_name  TEXT NOT NULL,
  metric_value NUMERIC NOT NULL,
  dimensions   JSONB NOT NULL DEFAULT '{}',
  period_start TIMESTAMPTZ NOT NULL,
  period_end   TIMESTAMPTZ NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_dashboard_aggregates_org_id ON ee.dashboard_aggregates (org_id);
CREATE INDEX idx_ee_dashboard_aggregates_org_metric_period ON ee.dashboard_aggregates (org_id, metric_name, period_start);

-- migrate:down
DROP TABLE IF EXISTS ee.dashboard_aggregates;
