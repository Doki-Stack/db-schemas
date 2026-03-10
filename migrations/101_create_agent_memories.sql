-- migrate:up
CREATE TYPE ee.memory_type AS ENUM (
  'preference',
  'outcome',
  'correction',
  'prompt_effectiveness'
);

CREATE TABLE ee.agent_memories (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id          UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  memory_type     ee.memory_type NOT NULL,
  key             TEXT NOT NULL,
  value           JSONB NOT NULL,
  source_task_id  UUID REFERENCES public.tasks(id) ON DELETE SET NULL,
  relevance_score NUMERIC(5,4) NOT NULL DEFAULT 1.0,
  decay_factor    NUMERIC(5,4) NOT NULL DEFAULT 0.95,
  access_count    INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_agent_memories_relevance CHECK (relevance_score >= 0 AND relevance_score <= 1),
  CONSTRAINT chk_agent_memories_decay CHECK (decay_factor > 0 AND decay_factor <= 1)
);

CREATE INDEX idx_agent_memories_org_id_type ON ee.agent_memories (org_id, memory_type);
CREATE INDEX idx_agent_memories_org_id_created_at ON ee.agent_memories (org_id, created_at DESC);
CREATE INDEX idx_agent_memories_org_id_relevance ON ee.agent_memories (org_id, relevance_score DESC);
CREATE INDEX idx_agent_memories_source_task ON ee.agent_memories (source_task_id) WHERE source_task_id IS NOT NULL;
CREATE INDEX idx_agent_memories_gin_value ON ee.agent_memories USING GIN (value);
CREATE UNIQUE INDEX idx_agent_memories_org_key ON ee.agent_memories (org_id, key);

CREATE TRIGGER trg_agent_memories_updated_at
  BEFORE UPDATE ON ee.agent_memories
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- migrate:down
DROP TRIGGER IF EXISTS trg_agent_memories_updated_at ON ee.agent_memories;
DROP TABLE IF EXISTS ee.agent_memories;
DROP TYPE IF EXISTS ee.memory_type;
