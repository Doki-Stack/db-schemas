-- migrate:up
CREATE TABLE approvals (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  plan_id     UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
  approver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status      approval_status NOT NULL DEFAULT 'pending',
  comment     TEXT,
  decided_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_approvals_org_id_created_at ON approvals (org_id, created_at DESC);
CREATE INDEX idx_approvals_plan_id ON approvals (plan_id);
CREATE INDEX idx_approvals_approver_id ON approvals (approver_id);
CREATE INDEX idx_approvals_org_id_status ON approvals (org_id, status);

-- migrate:down
DROP TABLE IF EXISTS approvals;
