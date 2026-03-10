-- migrate:up
CREATE SCHEMA IF NOT EXISTS ee;

-- migrate:down
DROP SCHEMA IF EXISTS ee CASCADE;
