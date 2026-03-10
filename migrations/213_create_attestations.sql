-- migrate:up
CREATE TABLE ee.attestations (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  plan_id         UUID NOT NULL REFERENCES public.plans(id) ON DELETE CASCADE,
  attester_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  attestation_type TEXT NOT NULL,
  evidence        JSONB NOT NULL DEFAULT '{}',
  attested_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ee_attestations_org_id ON ee.attestations (org_id);
CREATE INDEX idx_ee_attestations_plan_id ON ee.attestations (plan_id);
CREATE INDEX idx_ee_attestations_attester_id ON ee.attestations (attester_id);

-- migrate:down
DROP TABLE IF EXISTS ee.attestations;
