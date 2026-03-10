-- migrate:up
CREATE TABLE ee.org_members (
  org_id    UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  user_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  team_id   UUID REFERENCES ee.teams(id) ON DELETE SET NULL,
  role      TEXT NOT NULL DEFAULT 'member',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (org_id, user_id)
);

CREATE INDEX idx_ee_org_members_team_id ON ee.org_members (team_id) WHERE team_id IS NOT NULL;
CREATE INDEX idx_ee_org_members_user_id ON ee.org_members (user_id);

-- migrate:down
DROP TABLE IF EXISTS ee.org_members;
