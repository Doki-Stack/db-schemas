-- migrate:up
CREATE TABLE scanner_contexts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          UUID NOT NULL REFERENCES orgs(id) ON DELETE CASCADE,
  repo            TEXT NOT NULL,
  branch          TEXT NOT NULL,
  commit_sha      TEXT NOT NULL,
  artifact_paths  TEXT[] NOT NULL DEFAULT '{}',
  scanned_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_scanner_contexts_org_id_created_at ON scanner_contexts (org_id, created_at DESC);
CREATE INDEX idx_scanner_contexts_repo ON scanner_contexts (org_id, repo, branch);
CREATE UNIQUE INDEX idx_scanner_contexts_org_repo_commit ON scanner_contexts (org_id, repo, commit_sha);

-- migrate:down
DROP TABLE IF EXISTS scanner_contexts CASCADE;
