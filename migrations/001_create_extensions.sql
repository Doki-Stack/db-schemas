-- migrate:up
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE SCHEMA IF NOT EXISTS langgraph;
GRANT ALL ON SCHEMA langgraph TO app_service;

-- migrate:down
DROP SCHEMA IF EXISTS langgraph CASCADE;
DROP EXTENSION IF EXISTS "pgcrypto";
