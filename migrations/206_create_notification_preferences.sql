-- migrate:up
CREATE TABLE ee.notification_preferences (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id      UUID NOT NULL REFERENCES public.orgs(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  event_types TEXT[] NOT NULL DEFAULT '{}',
  channels    JSONB NOT NULL DEFAULT '{}',
  enabled     BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_ee_notification_prefs_org_user ON ee.notification_preferences (org_id, user_id);

CREATE TRIGGER trg_ee_notification_prefs_updated_at
  BEFORE UPDATE ON ee.notification_preferences
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- migrate:down
DROP TRIGGER IF EXISTS trg_ee_notification_prefs_updated_at ON ee.notification_preferences;
DROP TABLE IF EXISTS ee.notification_preferences;
